package org.opensignalfoundation.iranvpn.ui

import android.app.Activity
import android.os.Build
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/** Brand: deep teal #0B3D3A + warm gold #C4A574 */
val IranTeal = Color(0xFF0B3D3A)
val IranGold = Color(0xFFC4A574)
val IranMist = Color(0xFFF1F4F5)
val IranPaleTeal = Color(0xFFDBEEEB)
val IranDanger = Color(0xFFBF3833)

private val LightColors = lightColorScheme(
    primary = IranTeal,
    onPrimary = Color.White,
    secondary = IranGold,
    onSecondary = IranTeal,
    tertiary = IranPaleTeal,
    background = IranMist,
    onBackground = IranTeal,
    surface = Color.White,
    onSurface = IranTeal,
    error = IranDanger,
    onError = Color.White,
)

@Composable
fun Theme(
    content: @Composable () -> Unit,
) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < 35) {
                window.statusBarColor = IranTeal.toArgb()
            }
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = false
        }
    }
    MaterialTheme(colorScheme = LightColors, content = content)
}
