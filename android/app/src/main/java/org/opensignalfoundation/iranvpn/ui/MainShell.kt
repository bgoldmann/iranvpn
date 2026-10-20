package org.opensignalfoundation.iranvpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush

@Composable
fun MainShell(
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
    appVersion: String = "1.0.0",
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val atmosphere = Brush.verticalGradient(listOf(IranMist, IranPaleTeal, IranMist))

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                val colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = IranTeal,
                    selectedTextColor = IranTeal,
                    indicatorColor = IranPaleTeal,
                    unselectedIconColor = IranTeal.copy(alpha = 0.45f),
                    unselectedTextColor = IranTeal.copy(alpha = 0.45f),
                )
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Outlined.Wifi, contentDescription = null) },
                    label = { Text("اتصال / Connect") },
                    colors = colors,
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Outlined.AccountTree, contentDescription = null) },
                    label = { Text("مسیرها / Paths") },
                    colors = colors,
                )
                NavigationBarItem(
                    selected = tab == 2,
                    onClick = { tab = 2 },
                    icon = { Icon(Icons.Outlined.Info, contentDescription = null) },
                    label = { Text("درباره / About") },
                    colors = colors,
                )
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .background(atmosphere)
                .padding(padding),
        ) {
            when (tab) {
                0 -> ConnectTab(
                    isConnected = isConnected,
                    isConnecting = isConnecting,
                    activePath = activePath,
                    onConnect = onConnect,
                    onDisconnect = onDisconnect,
                )
                1 -> PathsTab(
                    isConnected = isConnected,
                    isConnecting = isConnecting,
                    xrayImportEnabled = xrayImportEnabled,
                    conduitCompartment = conduitCompartment,
                    onConduitCompartmentChange = onConduitCompartmentChange,
                    onImportShareLink = onImportShareLink,
                    onOpenOrbot = onOpenOrbot,
                )
                else -> AboutTab(appVersion = appVersion)
            }
        }
    }
}
