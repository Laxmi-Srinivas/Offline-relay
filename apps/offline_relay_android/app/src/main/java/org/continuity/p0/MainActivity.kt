package org.continuity.p0

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.lifecycle.ViewModelProvider
import org.continuity.p0.permissions.NearbyPreflight
import org.continuity.p0.protocol.Role
import org.continuity.p0.ui.ConnectionViewModel
import org.continuity.p0.ui.ContinuityScreen

class MainActivity : ComponentActivity() {
    private val model by lazy { ViewModelProvider(this)[ConnectionViewModel::class.java] }
    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val role = model.pendingRole
        if (role != null) {
            if (NearbyPreflight.granted(this)) model.start(role) else model.denied()
        }
    }
    private fun start(role: Role) {
        if (NearbyPreflight.granted(this)) model.start(role)
        else {
            model.pendingRole = role
            permissions.launch(NearbyPreflight.permissions())
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                ContinuityScreen(
                    state = model.state, start = ::start, connect = model::connect,
                    confirm = model::confirm, stop = model::stop,
                    sendRequest = model::sendRequest, acceptRequest = model::acceptRequest,
                    declineRequest = model::declineRequest, sendChat = model::sendChat,
                    endHelp = model::endHelp,
                    appSettings = { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"))) },
                    radioSettings = { startActivity(Intent(Settings.ACTION_SETTINGS)) },
                )
            }
        }
    }
}
