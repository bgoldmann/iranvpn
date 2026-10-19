//! C ABI for iOS/macOS XCFramework and other FFI consumers.
//!
//! String returns are heap-allocated UTF-8 C strings; caller must free with
//! [`iran_vpn_string_free`].

use crate::bootstrap::{embedded_server_list, resolve_bootstrap};
use crate::fetch::{default_config_sources, fetch_server_list};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

/// Free a string returned by this FFI.
#[no_mangle]
pub unsafe extern "C" fn iran_vpn_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    drop(CString::from_raw(s));
}

fn to_cstring(s: String) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Returns embedded bootstrap server list JSON.
#[no_mangle]
pub extern "C" fn iran_vpn_embedded_server_list() -> *mut c_char {
    let list = embedded_server_list();
    to_cstring(serde_json::to_string(&list).unwrap_or_else(|_| "{}".into()))
}

/// Bootstrap: last-good from cache_dir (nullable) → embedded.
/// `cache_dir` is a UTF-8 path or null.
#[no_mangle]
pub unsafe extern "C" fn iran_vpn_bootstrap_server_list(cache_dir: *const c_char) -> *mut c_char {
    let dir = if cache_dir.is_null() {
        None
    } else {
        CStr::from_ptr(cache_dir)
            .to_str()
            .ok()
            .map(Path::new)
    };
    let list = resolve_bootstrap(dir);
    to_cstring(serde_json::to_string(&list).unwrap_or_else(|_| "{}".into()))
}

/// Fetch server list from default sources (blocking). Prefer after tunnel is up.
#[no_mangle]
pub extern "C" fn iran_vpn_fetch_server_list() -> *mut c_char {
    let rt = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(_) => return std::ptr::null_mut(),
    };
    let sources = default_config_sources();
    match rt.block_on(fetch_server_list(&sources)) {
        Ok(list) => to_cstring(serde_json::to_string(&list).unwrap_or_else(|_| "{}".into())),
        Err(e) => {
            let escaped = e.to_string().replace('\\', "\\\\").replace('"', "\\\"");
            to_cstring(format!(r#"{{"error":"{escaped}"}}"#))
        }
    }
}

/// Probe via SOCKS. Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn iran_vpn_probe_socks(socks_port: u16) -> i32 {
    let rt = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(_) => return 0,
    };
    match rt.block_on(crate::probe::probe_default(socks_port)) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// Default race path order as JSON array.
#[no_mangle]
pub extern "C" fn iran_vpn_default_path_order() -> *mut c_char {
    to_cstring(r#"["psiphon","xray"]"#.into())
}
