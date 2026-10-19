fn main() {
    #[cfg(target_os = "windows")]
    {
        let mut res = winres::WindowsResource::new();
        res.set_icon("assets/icon.ico");
        if let Err(e) = res.compile() {
            // Non-fatal on cross-compile hosts without a Windows resource compiler
            println!("cargo:warning=winres icon embed skipped: {e}");
        }
    }
}
