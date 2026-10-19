//! JNI bridge for Android. Enable with `cargo build --features jni`.
//! Provides bootstrap, fetch, probe.

#![cfg(all(feature = "jni", target_os = "android"))]

use jni::objects::{JClass, JString};
use jni::sys::{jint, jstring};
use jni::JNIEnv;

fn jstring_from(env: &mut JNIEnv, s: &str) -> jstring {
    env.new_string(s)
        .map(|js| js.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Bootstrap server list (embedded / last-good). cacheDir may be empty.
#[no_mangle]
pub unsafe extern "C" fn Java_org_opensignalfoundation_iranvpn_Native_bootstrapServerList(
    mut env: JNIEnv,
    _class: JClass,
    cache_dir: JString,
) -> jstring {
    let dir: String = env
        .get_string(&cache_dir)
        .map(|s| s.into())
        .unwrap_or_default();
    let path = if dir.is_empty() {
        None
    } else {
        Some(std::path::Path::new(&dir))
    };
    let list = crate::bootstrap::resolve_bootstrap(path);
    let json = serde_json::to_string(&list).unwrap_or_else(|_| "{}".into());
    jstring_from(&mut env, &json)
}

/// Fetch server list. Called from Kotlin: Native.fetchServerList(sourcesJson)
#[no_mangle]
pub unsafe extern "C" fn Java_org_opensignalfoundation_iranvpn_Native_fetchServerList(
    mut env: JNIEnv,
    _class: JClass,
    sources_json: JString,
) -> jstring {
    let result = (|| {
        let s: String = env
            .get_string(&sources_json)
            .map_err(|e| e.to_string())?
            .into();
        let sources: Vec<crate::config::ConfigSource> =
            serde_json::from_str(&s).map_err(|e| e.to_string())?;
        let list = tokio::runtime::Runtime::new()
            .map_err(|e| e.to_string())?
            .block_on(crate::fetch::fetch_server_list(&sources))
            .map_err(|e| e.to_string())?;
        serde_json::to_string(&list).map_err(|e| e.to_string())
    })();
    match result {
        Ok(json) => jstring_from(&mut env, &json),
        Err(e) => {
            let _ = env.throw_new("java/lang/RuntimeException", &e);
            std::ptr::null_mut()
        }
    }
}

/// Probe through SOCKS. Returns 1 on success, 0 on failure.
#[no_mangle]
pub unsafe extern "C" fn Java_org_opensignalfoundation_iranvpn_Native_probeSocks(
    _env: JNIEnv,
    _class: JClass,
    socks_port: jint,
) -> jint {
    let port = socks_port as u16;
    let rt = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(_) => return 0,
    };
    match rt.block_on(crate::probe::probe_default(port)) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// Embedded bootstrap JSON.
#[no_mangle]
pub unsafe extern "C" fn Java_org_opensignalfoundation_iranvpn_Native_embeddedServerList(
    mut env: JNIEnv,
    _class: JClass,
) -> jstring {
    let list = crate::bootstrap::embedded_server_list();
    let json = serde_json::to_string(&list).unwrap_or_else(|_| "{}".into());
    jstring_from(&mut env, &json)
}
