package org.opensignalfoundation.iranvpn

import android.content.Intent
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
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.ShareLinkParser
import org.opensignalfoundation.iranvpn.model.ServerList
import org.opensignalfoundation.iranvpn.ui.ConnectScreen
import org.opensignalfoundation.iranvpn.ui.LegalDisclaimer
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
            // Service finished attempting without success
            connectingState.value = false
        }
        if (VpnTunnelService.isConnecting) {
            connectingState.value = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                    ConnectScreen(
                        isConnected = connected,
                        isConnecting = connecting,
                        activePath = activePath,
                        onConnect = {
                            connectingState.value = true
                            prepareAndConnect()
                        },
                        onDisconnect = {
                            VpnTunnelService.disconnect(applicationContext)
                            connectionState.value = false
                            connectingState.value = false
                            activePathState.value = null
                        },
                        onImportShareLink = { link ->
                            val parsed = ShareLinkParser.parse(link)
                            if (parsed is PathConfig.XrayConfig) {
                                val list = ServerList(
                                    paths = listOf(
                                        PathConfig.PsiphonConfig(null),
                                        parsed,
                                    ),
                                    sources = emptyList(),
                                )
                                ConfigFetcher.saveLastGood(applicationContext, list)
                            }
                        }
                    )
                }
            }
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
        startService(Intent(this, VpnTunnelService::class.java).apply {
            action = VpnTunnelService.ACTION_CONNECT
        })
    }
}
