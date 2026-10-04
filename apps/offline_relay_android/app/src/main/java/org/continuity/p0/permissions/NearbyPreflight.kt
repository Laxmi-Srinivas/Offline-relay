package org.continuity.p0.permissions

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

object NearbyPreflight {
    fun permissions(): Array<String> = buildList {
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 31) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
            add(Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.NEARBY_WIFI_DEVICES)
    }.toTypedArray()
    fun granted(context: Context) = permissions().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }
    fun problem(context: Context): String? {
        if (!granted(context)) return "PERMISSION_DENIED: allow Nearby devices and, where requested, precise location in App settings."
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS)
            return "TRANSPORT_UNAVAILABLE: install or update Google Play services on this phone."
        return try {
            val bluetooth = context.getSystemService(BluetoothManager::class.java)?.adapter
                ?: return "TRANSPORT_UNAVAILABLE: Bluetooth is unavailable."
            if (!bluetooth.isEnabled) return "RADIO_DISABLED: turn on Bluetooth, then try again."
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifi?.isWifiEnabled != true) return "RADIO_DISABLED: turn on Wi-Fi. Internet access is not required."
            if (Build.VERSION.SDK_INT <= 32) {
                val location = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
                if (!LocationManagerCompat.isLocationEnabled(location))
                    return "RADIO_DISABLED: turn on Location for nearby discovery on this Android version."
            }
            null
        } catch (_: SecurityException) { "PERMISSION_DENIED: check app permissions and try again." }
    }
}
