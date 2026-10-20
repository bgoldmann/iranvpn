package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import java.io.File

/** Extract and locate native helper binaries from assets (xray, sing-box, tor, …). */
object AssetBinary {
    fun findOrExtract(context: Context, assetRelPaths: List<String>, outName: String): String? {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val expanded = assetRelPaths.flatMap { path ->
            listOf(path.replace("\$ABI", abi), path)
        }.distinct()
        for (rel in expanded) {
            try {
                context.assets.open(rel).use { input ->
                    val dir = File(context.noBackupFilesDir, "bin").apply { mkdirs() }
                    val out = File(dir, outName)
                    if (!out.exists() || out.length() == 0L) {
                        out.outputStream().use { input.copyTo(it) }
                        out.setExecutable(true, false)
                    }
                    if (out.canExecute() || out.exists()) return out.absolutePath
                }
            } catch (_: Exception) {
                continue
            }
        }
        // Already extracted from a previous run
        val cached = File(context.noBackupFilesDir, "bin/$outName")
        if (cached.exists()) return cached.absolutePath
        return null
    }

    fun hasAny(context: Context, assetRelPaths: List<String>): Boolean {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        return assetRelPaths.any { path ->
            val rel = path.replace("\$ABI", abi)
            try {
                context.assets.open(rel).close()
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
