package org.opensignalfoundation.iranvpn.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * US-001: Zero-config Connect/Disconnect.
 * Advanced: paste VLESS/VMess/Trojan share link or subscription URL.
 * Persian-first status strings with English fallback labels.
 */
@Composable
fun ConnectScreen(
    isConnected: Boolean,
    activePath: String? = null,
    isConnecting: Boolean = false,
    xrayImportEnabled: Boolean = true,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onImportShareLink: ((String) -> Boolean)? = null,
) {
    var showAdvanced by remember { mutableStateOf(false) }
    var shareLink by remember { mutableStateOf("") }
    var importMessage by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = when {
                isConnecting -> "در حال اتصال… / Connecting…"
                isConnected -> if (activePath != null) {
                    "متصل از طریق $activePath / Connected via $activePath"
                } else {
                    "متصل / Connected"
                }
                else -> "قطع / Disconnected"
            },
            style = MaterialTheme.typography.headlineSmall
        )
        Spacer(Modifier.height(16.dp))
        if (isConnecting) {
            CircularProgressIndicator(Modifier.size(48.dp))
        } else {
            if (isConnected) {
                Button(onClick = onDisconnect) {
                    Text("قطع اتصال / Disconnect")
                }
            } else {
                Button(onClick = onConnect) {
                    Text("اتصال / Connect")
                }
            }
        }

        Spacer(Modifier.height(24.dp))
        TextButton(onClick = { showAdvanced = !showAdvanced }) {
            Text(if (showAdvanced) "پنهان کردن پیشرفته" else "پیشرفته / Advanced")
        }

        if (showAdvanced && onImportShareLink != null) {
            Spacer(Modifier.height(8.dp))
            if (!xrayImportEnabled) {
                Text(
                    "Xray not bundled — add assets/xray/<abi>/xray or a LibXray AAR to enable share links.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            } else {
                Text(
                    "VLESS / VMess / Trojan / subscription URL",
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = shareLink,
                    onValueChange = { shareLink = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Share link") },
                    singleLine = false,
                    minLines = 2,
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = {
                        val trimmed = shareLink.trim()
                        if (trimmed.isNotEmpty()) {
                            val ok = onImportShareLink(trimmed)
                            importMessage = if (ok) {
                                "Imported — will be tried with Connect"
                            } else {
                                "Import failed — check link format"
                            }
                            if (ok) shareLink = ""
                        }
                    },
                    enabled = shareLink.isNotBlank() && !isConnected
                ) {
                    Text("Import")
                }
                importMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
