package org.opensignalfoundation.iranvpn.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Back-compat entry — prefer [MainShell]. */
@Composable
fun ConnectScreen(
    isConnected: Boolean,
    activePath: String? = null,
    isConnecting: Boolean = false,
    xrayImportEnabled: Boolean = true,
    conduitCompartment: String = "",
    onConduitCompartmentChange: ((String) -> Unit)? = null,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onImportShareLink: ((String) -> Boolean)? = null,
    onOpenOrbot: (() -> Unit)? = null,
) {
    MainShell(
        isConnected = isConnected,
        activePath = activePath,
        isConnecting = isConnecting,
        xrayImportEnabled = xrayImportEnabled,
        conduitCompartment = conduitCompartment,
        onConduitCompartmentChange = onConduitCompartmentChange,
        onConnect = onConnect,
        onDisconnect = onDisconnect,
        onImportShareLink = onImportShareLink,
        onOpenOrbot = onOpenOrbot,
    )
}

@Composable
fun ConnectTab(
    isConnected: Boolean,
    isConnecting: Boolean,
    activePath: String?,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "Iran VPN",
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = IranTeal,
        )
        Text(
            text = "ایران وی‌پی‌ان",
            style = MaterialTheme.typography.titleLarge,
            color = IranGold,
        )
        Spacer(Modifier.height(28.dp))
        StatusRing(isConnected = isConnected, isConnecting = isConnecting)
        Spacer(Modifier.height(12.dp))
        if (isConnected && activePath != null) {
            Text(
                text = "via $activePath",
                color = IranGold,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(24.dp))
        when {
            isConnecting -> {
                CircularProgressIndicator(color = IranTeal, modifier = Modifier.size(36.dp))
                Spacer(Modifier.height(12.dp))
                OutlinedButton(onClick = onDisconnect) { Text("لغو / Cancel") }
            }
            isConnected -> {
                Button(
                    onClick = onDisconnect,
                    colors = ButtonDefaults.buttonColors(containerColor = IranDanger),
                    modifier = Modifier.fillMaxWidth(0.75f),
                ) {
                    Text("قطع اتصال / Disconnect", fontWeight = FontWeight.SemiBold)
                }
            }
            else -> {
                Button(
                    onClick = onConnect,
                    colors = ButtonDefaults.buttonColors(containerColor = IranTeal),
                    modifier = Modifier.fillMaxWidth(0.75f),
                ) {
                    Text("اتصال / Connect", fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Spacer(Modifier.height(32.dp))
        Text(
            text = "Default path: Psiphon · Conduit on hold",
            style = MaterialTheme.typography.bodySmall,
            color = IranTeal.copy(alpha = 0.55f),
        )
    }
}

@Composable
private fun StatusRing(isConnected: Boolean, isConnecting: Boolean) {
    val progress by animateFloatAsState(
        targetValue = when {
            isConnected -> 1f
            isConnecting -> 0.65f
            else -> 0.2f
        },
        label = "ring",
    )
    val ringColor by animateColorAsState(
        targetValue = when {
            isConnecting -> IranGold
            isConnected -> IranTeal
            else -> IranTeal.copy(alpha = 0.3f)
        },
        label = "ringColor",
    )
    val label = when {
        isConnecting -> "در حال اتصال…\nConnecting…"
        isConnected -> "متصل\nConnected"
        else -> "قطع\nDisconnected"
    }
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(160.dp)) {
        Canvas(Modifier.size(160.dp)) {
            val stroke = 10.dp.toPx()
            drawArc(
                color = ringColor.copy(alpha = 0.2f),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
                size = Size(size.width - stroke, size.height - stroke),
                topLeft = Offset(stroke / 2, stroke / 2),
            )
            drawArc(
                color = ringColor,
                startAngle = -90f,
                sweepAngle = 360f * progress,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
                size = Size(size.width - stroke, size.height - stroke),
                topLeft = Offset(stroke / 2, stroke / 2),
            )
        }
        Text(
            text = label,
            textAlign = TextAlign.Center,
            color = IranTeal,
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp,
            lineHeight = 18.sp,
        )
    }
}

@Composable
fun PathsTab(
    isConnected: Boolean,
    isConnecting: Boolean,
    xrayImportEnabled: Boolean,
    conduitCompartment: String,
    onConduitCompartmentChange: ((String) -> Unit)?,
    onImportShareLink: ((String) -> Boolean)?,
    onOpenOrbot: (() -> Unit)?,
) {
    var shareLink by remember { mutableStateOf("") }
    var importMessage by remember { mutableStateOf<String?>(null) }
    var compartmentDraft by remember(conduitCompartment) { mutableStateOf(conduitCompartment) }
    val busy = isConnected || isConnecting

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.Top,
    ) {
        Text(
            text = "مسیرها / Paths",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = IranTeal,
        )
        Spacer(Modifier.height(16.dp))
        Text("Conduit", fontWeight = FontWeight.SemiBold, color = IranTeal)
        Text(
            "Personal code for Psiphon in-proxy when distributor keys arrive.",
            style = MaterialTheme.typography.bodySmall,
            color = IranTeal.copy(alpha = 0.65f),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = compartmentDraft,
            onValueChange = { compartmentDraft = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Conduit personal code") },
            singleLine = true,
            enabled = !busy,
        )
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = {
                onConduitCompartmentChange?.invoke(compartmentDraft.trim())
                importMessage = if (compartmentDraft.isBlank()) {
                    "Conduit pairing cleared"
                } else {
                    "Conduit pairing saved — used on next Psiphon Connect"
                }
            },
            enabled = !busy && onConduitCompartmentChange != null,
            colors = ButtonDefaults.buttonColors(containerColor = IranTeal),
        ) {
            Text("Save Conduit code")
        }

        Spacer(Modifier.height(24.dp))
        Text("Providers", fontWeight = FontWeight.SemiBold, color = IranTeal)
        Text(
            "Psiphon · Xray · sing-box · Outline · Tor · AmneziaWG (Advanced stubs)",
            style = MaterialTheme.typography.bodySmall,
            color = IranTeal.copy(alpha = 0.65f),
        )
        if (onOpenOrbot != null) {
            TextButton(onClick = onOpenOrbot) { Text("Install / open Orbot (Tor)") }
        }
        if (!xrayImportEnabled) {
            Text(
                "Tip: ./scripts/fetch-sing-box-android.sh — Outline + Hy2 without Xray",
                style = MaterialTheme.typography.bodySmall,
                color = IranGold,
            )
        }
        Text(
            "vless:// · vmess:// · trojan:// · ss:// · hy2:// · sing-box JSON · Tor bridge · WG/AWG",
            style = MaterialTheme.typography.bodySmall,
        )
        if (onImportShareLink != null) {
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = shareLink,
                onValueChange = { shareLink = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Share link / config") },
                singleLine = false,
                minLines = 2,
                enabled = !busy,
            )
            Spacer(Modifier.height(8.dp))
            Button(
                onClick = {
                    val trimmed = shareLink.trim()
                    if (trimmed.isNotEmpty()) {
                        val ok = onImportShareLink(trimmed)
                        importMessage = if (ok) {
                            "Imported. Connect races Psiphon + this path when a runner is available."
                        } else {
                            "Import failed — check format"
                        }
                        if (ok) shareLink = ""
                    }
                },
                enabled = shareLink.isNotBlank() && !busy,
                colors = ButtonDefaults.buttonColors(containerColor = IranTeal),
            ) {
                Text("Import")
            }
        }
        importMessage?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = MaterialTheme.typography.bodySmall, color = IranTeal)
        }
    }
}

@Composable
fun AboutTab(appVersion: String) {
    val uriHandler = LocalUriHandler.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
    ) {
        Text(
            text = "Iran VPN",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = IranTeal,
        )
        Text("ایران وی‌پی‌ان", style = MaterialTheme.typography.titleMedium, color = IranGold)
        Spacer(Modifier.height(12.dp))
        Text(
            "Open circumvention client that races FOSS paths (Psiphon first). Research and informational use only.",
            style = MaterialTheme.typography.bodyMedium,
            color = IranTeal.copy(alpha = 0.75f),
        )
        Spacer(Modifier.height(20.dp))
        Text("Security tips", fontWeight = FontWeight.SemiBold, color = IranTeal)
        Text(
            "• Prefer tunneled DNS\n• Avoid untrusted public Wi‑Fi\n• Keep the app updated\n• Conduit / in-proxy on hold until Psiphon keys arrive",
            style = MaterialTheme.typography.bodyMedium,
            color = IranTeal.copy(alpha = 0.7f),
        )
        Spacer(Modifier.height(20.dp))
        Text(
            "Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). Users assume all legal and personal risks.",
            style = MaterialTheme.typography.bodySmall,
            color = IranTeal.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(20.dp))
        Text("Developed by Goldmann LLC", fontWeight = FontWeight.SemiBold, color = IranTeal)
        TextButton(onClick = { uriHandler.openUri("https://goldmannllc.com/websites/iranvpn") }) {
            Text("goldmannllc.com/websites/iranvpn", color = IranGold)
        }
        TextButton(onClick = { uriHandler.openUri("https://goldmannllc.com/contact") }) {
            Text("Support / پشتیبانی", color = IranGold)
        }
        Text(
            "support@goldmannllc.com",
            style = MaterialTheme.typography.bodySmall,
            color = IranTeal.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(16.dp))
        Text("Version $appVersion", style = MaterialTheme.typography.labelMedium, color = IranGold)
    }
}
