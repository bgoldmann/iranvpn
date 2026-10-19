package org.opensignalfoundation.iranvpn.metrics

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Non-identifying local failure log: path name, error class, RTT ms.
 * Never phones home by default.
 */
object LocalFailureLog {
    private const val FILE = "local_failures.json"
    private const val MAX_ENTRIES = 100

    data class Entry(
        val path: String,
        val errorClass: String,
        val rttMs: Long,
        val ts: Long = System.currentTimeMillis(),
    )

    fun record(context: Context, path: String, errorClass: String, rttMs: Long = -1) {
        try {
            val file = File(context.noBackupFilesDir, FILE)
            val arr = if (file.exists()) JSONArray(file.readText()) else JSONArray()
            arr.put(
                JSONObject()
                    .put("path", path)
                    .put("error_class", errorClass)
                    .put("rtt_ms", rttMs)
                    .put("ts", System.currentTimeMillis())
            )
            // Trim
            while (arr.length() > MAX_ENTRIES) {
                arr.remove(0)
            }
            file.writeText(arr.toString())
        } catch (_: Exception) {}
    }

    fun readAll(context: Context): List<Entry> {
        return try {
            val file = File(context.noBackupFilesDir, FILE)
            if (!file.exists()) return emptyList()
            val arr = JSONArray(file.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Entry(
                    path = o.optString("path"),
                    errorClass = o.optString("error_class"),
                    rttMs = o.optLong("rtt_ms", -1),
                    ts = o.optLong("ts"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
