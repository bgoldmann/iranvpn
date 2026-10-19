//! Race-and-probe engine: parallel path race (~8s), probe gate, warm spare,
//! health loop, exponential backoff after all paths fail. US-002, FR-6.

use crate::config::{PathConfig, PathKind, ServerList};
use crate::path::{PathRunner, PathStatus};
use crate::probe;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, RwLock};
use tokio::time::timeout;
use tracing::{info, warn};

/// Default race order: Psiphon (includes Conduit) then Xray. Rostam excluded.
pub const DEFAULT_PATH_ORDER: [PathKind; 2] = [PathKind::Psiphon, PathKind::Xray];

pub const RACE_BUDGET: Duration = Duration::from_secs(8);
pub const HEALTH_INTERVAL: Duration = Duration::from_secs(5);

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum FallbackEvent {
    Connecting { path_kind: PathKind, index: usize },
    Connected { path_kind: PathKind, index: usize },
    PathFailed {
        path_kind: PathKind,
        index: usize,
        error: String,
    },
    FallbackActivated { from: PathKind, to: PathKind },
    ProbeFailed { path_kind: PathKind, error: String },
    HealthFailed { path_kind: PathKind, error: String },
    AllPathsFailed,
    Backoff { duration_secs: u64 },
    SpareReady { path_kind: PathKind, index: usize },
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct FallbackState {
    pub active_path_index: Option<usize>,
    pub active_path_kind: Option<PathKind>,
    pub spare_path_index: Option<usize>,
    pub spare_path_kind: Option<PathKind>,
    pub connection_established: bool,
    pub failure_count: u32,
    pub active_socks_port: Option<u16>,
}

/// Optional socks port provider after connect (platform sets this on PathConfig race).
#[async_trait::async_trait]
pub trait SocksPortProvider: Send + Sync {
    async fn socks_port(&self, path_index: usize) -> Option<u16>;
}

/// No-op socks port provider (probe skipped if port unknown).
pub struct NoSocksPort;

#[async_trait::async_trait]
impl SocksPortProvider for NoSocksPort {
    async fn socks_port(&self, _path_index: usize) -> Option<u16> {
        None
    }
}

pub struct FallbackEngine {
    paths: Vec<PathConfig>,
    path_order: Vec<PathKind>,
    state: Arc<RwLock<FallbackState>>,
    event_tx: Option<mpsc::UnboundedSender<FallbackEvent>>,
    race_budget: Duration,
    backoff_base: Duration,
    require_probe: bool,
}

impl FallbackEngine {
    pub fn new(paths: Vec<PathConfig>) -> Self {
        Self {
            path_order: DEFAULT_PATH_ORDER.to_vec(),
            paths,
            state: Arc::new(RwLock::new(FallbackState::default())),
            event_tx: None,
            race_budget: RACE_BUDGET,
            backoff_base: Duration::from_secs(5),
            require_probe: true,
        }
    }

    pub fn with_server_list(server_list: ServerList) -> Self {
        Self::new(server_list.paths)
    }

    pub fn set_event_tx(&mut self, tx: mpsc::UnboundedSender<FallbackEvent>) {
        self.event_tx = Some(tx);
    }

    pub fn set_path_order(&mut self, order: Vec<PathKind>) {
        self.path_order = order;
    }

    pub fn set_require_probe(&mut self, require: bool) {
        self.require_probe = require;
    }

    pub fn race_budget(&self) -> Duration {
        self.race_budget
    }

    pub fn backoff_duration(&self, failure_count: u32) -> Duration {
        let secs = self.backoff_base.as_secs() * (1 << failure_count.min(6)) as u64;
        Duration::from_secs(secs.min(3600))
    }

    fn emit(&self, event: FallbackEvent) {
        if let Some(ref tx) = self.event_tx {
            let _ = tx.send(event);
        }
    }

    /// Indices eligible for the race (Psiphon/Xray by default; skip Conduit/Rostam).
    pub fn race_indices(&self) -> Vec<usize> {
        let mut indices: Vec<usize> = (0..self.paths.len())
            .filter(|&i| {
                let kind = self.paths[i].kind();
                matches!(kind, PathKind::Psiphon | PathKind::Xray | PathKind::Custom)
            })
            .collect();
        indices.sort_by_key(|&i| {
            let kind = self.paths[i].kind();
            self.path_order
                .iter()
                .position(|k| k == &kind)
                .unwrap_or(usize::MAX)
        });
        indices.truncate(3);
        indices
    }

    pub fn ordered_indices(&self) -> Vec<usize> {
        self.race_indices()
    }

    /// Race paths in parallel; first that connects (and optionally probes) wins.
    /// Keeps second-best as warm spare when available.
    pub async fn run_race<R, S>(
        &self,
        runner: &R,
        socks: &S,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
    where
        R: PathRunner,
        S: SocksPortProvider,
    {
        let indices = self.race_indices();
        if indices.is_empty() {
            self.emit(FallbackEvent::AllPathsFailed);
            return Err("no paths configured".into());
        }

        let mut handles = Vec::new();
        for &idx in &indices {
            let path = self.paths[idx].clone();
            let kind = path.kind();
            self.emit(FallbackEvent::Connecting {
                path_kind: kind.clone(),
                index: idx,
            });
            // We cannot easily clone runner; race serially with timeout per path
            // but start timer overlapping via join_all of async blocks that call runner.
            handles.push((idx, kind, path));
        }

        // Parallel race using futures — PathRunner is &self so we race with join_all
        // by connecting each with timeout sequentially in spawned tasks is hard without
        // Arc. Use sequential race with short budget each, collecting successes — OR
        // use tokio::select! style: try first two in parallel via join!.

        let mut results: Vec<(usize, PathKind, Result<(), String>, Option<u16>)> = Vec::new();

        // Race first two (or one) in parallel
        match handles.len() {
            0 => {}
            1 => {
                let (idx, kind, path) = handles.remove(0);
                let r = self.try_connect(runner, socks, idx, kind.clone(), path).await;
                results.push(r);
            }
            _ => {
                let (idx0, kind0, path0) = handles.remove(0);
                let (idx1, kind1, path1) = handles.remove(0);
                let (r0, r1) = tokio::join!(
                    self.try_connect(runner, socks, idx0, kind0, path0),
                    self.try_connect(runner, socks, idx1, kind1, path1),
                );
                results.push(r0);
                results.push(r1);
                // Optional third
                if let Some((idx, kind, path)) = handles.first().cloned() {
                    let r = self.try_connect(runner, socks, idx, kind, path).await;
                    results.push(r);
                }
            }
        }

        let mut successes: Vec<(usize, PathKind, Option<u16>)> = results
            .into_iter()
            .filter_map(|(idx, kind, res, port)| match res {
                Ok(()) => Some((idx, kind, port)),
                Err(e) => {
                    self.emit(FallbackEvent::PathFailed {
                        path_kind: kind,
                        index: idx,
                        error: e,
                    });
                    None
                }
            })
            .collect();

        if successes.is_empty() {
            let mut state = self.state.write().await;
            state.connection_established = false;
            state.failure_count += 1;
            let backoff = self.backoff_duration(state.failure_count);
            drop(state);
            self.emit(FallbackEvent::AllPathsFailed);
            self.emit(FallbackEvent::Backoff {
                duration_secs: backoff.as_secs(),
            });
            tokio::time::sleep(backoff).await;
            return Err("all paths failed".into());
        }

        // Winner = first success in race order; spare = second if any.
        // Do NOT call runner.disconnect() here: PathRunner::disconnect is global and would
        // tear down the winner when a shared runner is used (Windows). Platforms with
        // per-path runners should disconnect losers themselves after run_race returns.
        let (win_idx, win_kind, win_port) = successes.remove(0);
        let spare = successes.first().cloned();

        {
            let mut state = self.state.write().await;
            state.active_path_index = Some(win_idx);
            state.active_path_kind = Some(win_kind.clone());
            state.active_socks_port = win_port;
            state.connection_established = true;
            state.failure_count = 0;
            if let Some((si, sk, _)) = &spare {
                state.spare_path_index = Some(*si);
                state.spare_path_kind = Some(sk.clone());
                self.emit(FallbackEvent::SpareReady {
                    path_kind: sk.clone(),
                    index: *si,
                });
            }
        }
        self.emit(FallbackEvent::Connected {
            path_kind: win_kind,
            index: win_idx,
        });
        info!(index = win_idx, "race winner established");
        Ok(())
    }

    async fn try_connect<R, S>(
        &self,
        runner: &R,
        socks: &S,
        idx: usize,
        kind: PathKind,
        path: PathConfig,
    ) -> (usize, PathKind, Result<(), String>, Option<u16>)
    where
        R: PathRunner,
        S: SocksPortProvider,
    {
        let connect_result = timeout(self.race_budget, runner.connect(path)).await;
        match connect_result {
            Ok(Ok(())) => {
                let port = socks.socks_port(idx).await;
                if self.require_probe {
                    if let Some(p) = port {
                        match probe::probe_default(p).await {
                            Ok(()) => (idx, kind, Ok(()), Some(p)),
                            Err(e) => {
                                self.emit(FallbackEvent::ProbeFailed {
                                    path_kind: kind.clone(),
                                    error: e.to_string(),
                                });
                                // Do not disconnect shared runners here (would kill peers in join!)
                                (idx, kind, Err(format!("probe failed: {e}")), None)
                            }
                        }
                    } else {
                        // No socks port — accept connect without probe (platform will probe)
                        (idx, kind, Ok(()), None)
                    }
                } else {
                    (idx, kind, Ok(()), port)
                }
            }
            Ok(Err(e)) => (idx, kind, Err(e.to_string()), None),
            Err(_) => (idx, kind, Err("race budget timeout".into()), None),
        }
    }

    /// Legacy serial run (compat). Prefers [run_race].
    pub async fn run<R: PathRunner>(
        &self,
        runner: &R,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.run_race(runner, &NoSocksPort).await
    }

    pub async fn check_health<R: PathRunner>(&self, runner: &R) -> bool {
        let state = self.state.read().await;
        let idx = match state.active_path_index {
            Some(i) => i,
            None => return false,
        };
        let socks_port = state.active_socks_port;
        let kind = state.active_path_kind.clone();
        let path = match self.paths.get(idx) {
            Some(p) => p.clone(),
            None => return false,
        };
        drop(state);

        if let Some(port) = socks_port {
            if let Err(e) = probe::probe_default(port).await {
                self.emit(FallbackEvent::HealthFailed {
                    path_kind: kind.unwrap_or(path.kind()),
                    error: e.to_string(),
                });
                return false;
            }
            return true;
        }

        match runner.status(&path).await {
            PathStatus::Connected => true,
            PathStatus::Failed(e) => {
                self.emit(FallbackEvent::PathFailed {
                    path_kind: path.kind(),
                    index: idx,
                    error: e,
                });
                false
            }
            PathStatus::Disconnected => false,
        }
    }

    /// On health failure: promote spare if present.
    pub async fn promote_spare<R: PathRunner>(
        &self,
        runner: &R,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let state = self.state.read().await;
        let from = state.active_path_kind.clone();
        let spare_idx = state.spare_path_index;
        let spare_kind = state.spare_path_kind.clone();
        drop(state);

        let Some(idx) = spare_idx else {
            return Err("no spare".into());
        };
        let path = self
            .paths
            .get(idx)
            .cloned()
            .ok_or("spare index invalid")?;
        let kind = spare_kind.unwrap_or_else(|| path.kind());

        // Connect spare. Clear socks port so health does not probe the old path
        // until the platform updates it via state / SocksPortProvider.
        runner.connect(path).await?;

        {
            let mut state = self.state.write().await;
            if let Some(from_kind) = from {
                self.emit(FallbackEvent::FallbackActivated {
                    from: from_kind,
                    to: kind.clone(),
                });
            }
            state.active_path_index = Some(idx);
            state.active_path_kind = Some(kind);
            state.active_socks_port = None;
            state.spare_path_index = None;
            state.spare_path_kind = None;
            state.connection_established = true;
        }
        Ok(())
    }

    pub async fn state(&self) -> FallbackState {
        self.state.read().await.clone()
    }

    /// Health loop: probe every HEALTH_INTERVAL; promote spare or return Err.
    pub async fn run_health_loop<R: PathRunner>(
        &self,
        runner: &R,
        mut shutdown: tokio::sync::watch::Receiver<bool>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        loop {
            tokio::select! {
                _ = shutdown.changed() => {
                    if *shutdown.borrow() {
                        return Ok(());
                    }
                }
                _ = tokio::time::sleep(HEALTH_INTERVAL) => {
                    if !self.check_health(runner).await {
                        warn!("health check failed");
                        if self.promote_spare(runner).await.is_err() {
                            return Err("health failed and no spare".into());
                        }
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_duration_increases() {
        let e = FallbackEngine::new(vec![]);
        let d0 = e.backoff_duration(0);
        let d1 = e.backoff_duration(1);
        let d2 = e.backoff_duration(2);
        assert!(d1 > d0);
        assert!(d2 > d1);
    }

    #[tokio::test]
    async fn race_indices_empty() {
        let e = FallbackEngine::new(vec![]);
        assert!(e.race_indices().is_empty());
    }

    #[tokio::test]
    async fn race_indices_skips_rostam() {
        let e = FallbackEngine::new(vec![
            PathConfig::Rostam {
                wireguard_config: "x".into(),
            },
            PathConfig::Psiphon {
                server_list_url: None,
            },
        ]);
        let idx = e.race_indices();
        assert_eq!(idx.len(), 1);
        assert!(matches!(e.paths[idx[0]], PathConfig::Psiphon { .. }));
    }
}
