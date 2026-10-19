package org.opensignalfoundation.iranvpn

/**
 * JNI bridge to iran-vpn-core (Rust).
 * Requires libiran_vpn_core.so built with `--features jni`.
 */
object Native {
    @Volatile
    private var loaded = false

    @Volatile
    private var loadError: Throwable? = null

    fun isAvailable(): Boolean {
        if (!loaded) {
            try {
                System.loadLibrary("iran_vpn_core")
                loaded = true
            } catch (e: UnsatisfiedLinkError) {
                loadError = e
                loaded = true // don't retry
            }
        }
        return loadError == null
    }

    /** Fetch server list from redundant sources. */
    external fun fetchServerList(sourcesJson: String): String

    /** Bootstrap: last-good from cacheDir or embedded. */
    external fun bootstrapServerList(cacheDir: String): String

    /** Embedded Psiphon-only bootstrap JSON. */
    external fun embeddedServerList(): String

    /** Probe via SOCKS; returns 1 on success, 0 on failure. */
    external fun probeSocks(socksPort: Int): Int
}
