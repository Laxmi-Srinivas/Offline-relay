package org.continuity.p0.ui

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import org.continuity.p0.core.ConnectionSession
import org.continuity.p0.core.ConnectionState
import org.continuity.p0.permissions.NearbyPreflight
import org.continuity.p0.protocol.HelpCategory
import org.continuity.p0.protocol.Role
import org.continuity.p0.transport.NearbyConnectionsTransport

class ConnectionViewModel(application: Application) : AndroidViewModel(application) {
    var state by mutableStateOf(ConnectionState()); private set
    var pendingRole: Role? = null
    private val handler = Handler(Looper.getMainLooper())
    private val session = ConnectionSession(
        { NearbyConnectionsTransport(application) }, System::currentTimeMillis,
        { delay, action ->
            val runnable = Runnable { action() }; handler.postDelayed(runnable, delay)
            val cancel: () -> Unit = { handler.removeCallbacks(runnable) }; cancel
        },
        { state = it },
    )
    fun start(role: Role) {
        pendingRole = null
        val problem = NearbyPreflight.problem(getApplication())
        if (problem != null) session.fail(problem) else session.start(role)
    }
    fun denied() { pendingRole = null; session.fail("PERMISSION_DENIED: open App settings, allow required permissions, then retry.") }
    fun connect(id: String) = session.connect(id)
    fun confirm(approved: Boolean) = session.confirm(approved)
    fun sendRequest(category: HelpCategory, details: String) = session.sendRequest(category, details)
    fun acceptRequest() = session.acceptRequest()
    fun declineRequest() = session.declineRequest()
    fun sendChat(text: String) = session.sendChat(text)
    fun endHelp() = session.endHelp()
    fun stop() { pendingRole = null; session.stop() }
    override fun onCleared() { session.stop(); handler.removeCallbacksAndMessages(null) }
}
