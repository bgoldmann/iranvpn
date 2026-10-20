package org.opensignalfoundation.iranvpn

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import org.opensignalfoundation.iranvpn.fallback.TorPathRunner
import org.opensignalfoundation.iranvpn.fallback.XrayPathRunner
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.ServerList
import org.opensignalfoundation.iranvpn.model.ShareLinkParser
import org.opensignalfoundation.iranvpn.ui.LegalDisclaimer
import org.opensignalfoundation.iranvpn.ui.MainShell
import org.opensignalfoundation.iranvpn.ui.Theme


class MainActivity : ComponentActivity() {

    private val connectionState = mutableStateOf(false)
    private val connectingState = mutableStateOf(false)
    private val activePathState = mutableStateOf<String?>(null)
    private val statusHandler = Handler(Looper.getMainLooper())
    private val statusPoll = object : Runnable {
        override fun run() {
            syncFromService()
            statusHandler.postDelayed(this, 500)
        }
    }

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            startVpnConnection()
        } else {
            connectingState.value = false
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* FGS still starts; notification may be silent if denied */ }

    override fun onResume() {
        super.onResume()
        syncFromService()
        statusHandler.post(statusPoll)
    }

    override fun onPause() {
        statusHandler.removeCallbacks(statusPoll)
        super.onPause()
    }

    private fun syncFromService() {
        val connected = VpnTunnelService.isConnected
        connectionState.value = connected
        activePathState.value = VpnTunnelService.activePathName
        if (connected) {
            connectingState.value = false
        } else if (!VpnTunnelService.isConnecting && connectingState.value) {
            connectingState.value = false
        }
        if (VpnTunnelService.isConnecting) {
            connectingState.value = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        maybeRequestNotificationPermission()
        syncFromService()
        setContent {
            Theme {
                var acceptedDisclaimer by rememberSaveable {
                    mutableStateOf(DisclaimerPrefs(applicationContext).hasAccepted())
                }
                if (!acceptedDisclaimer) {
                    LegalDisclaimer(
                        onAccept = {
                            DisclaimerPrefs(applicationContext).setAccepted(true)
                            acceptedDisclaimer = true
                        }
                    )
                } else {
                    val connected by remember { connectionState }
                    val connecting by remember { connectingState }
                    val activePath by remember { activePathState }
                    val xrayReady = remember { XrayPathRunner.isAvailable(applicationContext) }
                    var conduitCode by remember {
                        mutableStateOf(ConduitPrefs.getPersonalCompartmentId(applicationContext).orEmpty())
                    }
                    MainShell(
                        isConnected = connected,
                        isConnecting = connecting,
                        activePath = activePath,
                        xrayImportEnabled = xrayReady,
                        conduitCompartment = conduitCode,
                        appVersion = try {
                            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0.0"
                        } catch (_: Exception) {
                            "1.0.0"
                        },
                        onConduitCompartmentChange = { code ->
                            ConduitPrefs.setPersonalCompartmentId(applicationContext, code)
                            conduitCode = code
                        },
                        onConnect = {
                            connectingState.value = true
                            prepareAndConnect()
                        },
                        onDisconnect = {
                            connectionState.value = false
                            connectingState.value = false
                            activePathState.value = null
                            VpnTunnelService.disconnect(applicationContext)
                        },
                        onImportShareLink = { link ->
                            val parsed = ShareLinkParser.parse(link) ?: return@MainShell false
                            if (parsed is PathConfig.ConduitConfig && !parsed.personalCompartmentId.isNullOrBlank()) {
                                ConduitPrefs.setPersonalCompartmentId(
                                    applicationContext,
                                    parsed.personalCompartmentId,
                                )
                                conduitCode = parsed.personalCompartmentId
                            }
                            val paths = mutableListOf<PathConfig>(
                                PathConfig.PsiphonConfig(
                                    serverListUrl = null,
                                    inproxyClientPersonalCompartmentId = ConduitPrefs
                                        .getPersonalCompartmentId(applicationContext),
                                ),
                            )
                            when (parsed) {
                                is PathConfig.PsiphonConfig, is PathConfig.ConduitConfig -> Unit
                                else -> paths.add(parsed)
                            }
                            ConfigFetcher.saveLastGood(
                                applicationContext,
                                ServerList(paths = paths, sources = emptyList()),
                            )
                            true
                        },
                        onOpenOrbot = { TorPathRunner.openOrbotPlayStore(applicationContext) },
                    )
                }
            }
        }
    }

    private fun maybeRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun prepareAndConnect() {
        val intent = android.net.VpnService.prepare(this)
        if (intent != null) {
            vpnPermissionLauncher.launch(intent)
        } else {
            startVpnConnection()
        }
    }

    private fun startVpnConnection() {
        val intent = Intent(this, VpnTunnelService::class.java).apply {
            action = VpnTunnelService.ACTION_CONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
