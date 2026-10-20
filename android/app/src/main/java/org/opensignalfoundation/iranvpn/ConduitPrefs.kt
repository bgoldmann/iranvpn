package org.opensignalfoundation.iranvpn

import android.content.Context

/** Optional Psiphon Conduit personal pairing (InproxyClientPersonalCompartmentID). */
object ConduitPrefs {
    private const val PREFS = "iranvpn_conduit"
    private const val KEY_COMPARTMENT = "inproxy_client_personal_compartment_id"

    fun getPersonalCompartmentId(context: Context): String? {
        val v = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_COMPARTMENT, null)
            ?.trim()
        return v?.takeIf { it.isNotEmpty() }
    }

    fun setPersonalCompartmentId(context: Context, value: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_COMPARTMENT, value?.trim().orEmpty())
            .apply()
    }
}
