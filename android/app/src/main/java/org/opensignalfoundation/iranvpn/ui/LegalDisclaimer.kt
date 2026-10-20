package org.opensignalfoundation.iranvpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun LegalDisclaimer(onAccept: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(IranMist, IranPaleTeal, IranMist)))
            .verticalScroll(rememberScrollState())
            .padding(28.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "Iran VPN",
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = IranTeal,
        )
        Text("ایران وی‌پی‌ان", style = MaterialTheme.typography.titleLarge, color = IranGold)
        Spacer(Modifier.height(20.dp))
        Text(
            text = "اطلاعیه قانونی / Legal Notice",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = IranTeal,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = "Unauthorized VPN use is illegal in Iran (Supreme Council of Cyberspace, Feb 2024). This app is for research and informational use only. Users assume all legal and personal risks. We do not encourage illegal activity.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = IranTeal.copy(alpha = 0.75f),
        )
        Spacer(Modifier.height(12.dp))
        Text(
            text = "Security: Prefer tunneled DNS; avoid public Wi-Fi; keep the app updated.",
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
            color = IranTeal.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(28.dp))
        Button(
            onClick = onAccept,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = IranTeal),
        ) {
            Text("می‌پذیرم / I understand and accept the risks")
        }
    }
}
