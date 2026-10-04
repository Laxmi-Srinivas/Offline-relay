package org.continuity.p0.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.continuity.p0.core.ConnectionState
import org.continuity.p0.protocol.HelpCategory
import org.continuity.p0.protocol.HelpMessageCodec
import org.continuity.p0.protocol.Role

@Composable
fun ContinuityScreen(
    state: ConnectionState,
    start: (Role) -> Unit,
    connect: (String) -> Unit,
    confirm: (Boolean) -> Unit,
    stop: () -> Unit,
    sendRequest: (HelpCategory, String) -> Unit,
    acceptRequest: () -> Unit,
    declineRequest: () -> Unit,
    sendChat: (String) -> Unit,
    endHelp: () -> Unit,
    appSettings: () -> Unit,
    radioSettings: () -> Unit,
) {
    var category by remember { mutableStateOf(HelpCategory.FOOD) }
    var requestDetails by remember { mutableStateOf("") }
    var chatDraft by remember { mutableStateOf("") }
    var confirmEnd by remember { mutableStateOf(false) }

    BackHandler(enabled = state.phase == "CHAT") {
        confirmEnd = true
    }

    val visibleStatus = when (state.phase) {
        "CONNECTED" -> "Setting up your connection…"
        "READY" -> "Connected. You’re ready to continue."
        else -> state.status
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = "OfflineRelay",
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                text = "Offline help between nearby phones",
                style = MaterialTheme.typography.bodyLarge,
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text("Connection", style = MaterialTheme.typography.labelLarge)
                    Text(visibleStatus, style = MaterialTheme.typography.bodyMedium)
                }
            }

            if (state.phase == "IDLE" || state.phase == "ERROR") {
                Button(
                    onClick = { start(Role.REQUESTER) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("I need help")
                }

                OutlinedButton(
                    onClick = { start(Role.HELPER) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("I can help")
                }

                Text(
                    text = "Keep Wi-Fi and Bluetooth on. Mobile data and internet aren’t needed.",
                    style = MaterialTheme.typography.bodySmall,
                )
            } else {
                Text(
                    text = when (state.role) {
                        Role.HELPER -> "Offering help"
                        Role.REQUESTER -> "Requesting help"
                        null -> ""
                    },
                    style = MaterialTheme.typography.labelLarge,
                )

                if (state.phase == "DISCOVERING" && state.peers.isEmpty()) {
                    Text("Looking for a nearby helper. Choose “I can help” on the other phone.")
                }

                if (state.phase == "ADVERTISING") {
                    Text("You’re available. Keep this screen open while waiting for a request.")
                }

                state.peers.forEach { peer ->
                    OutlinedButton(
                        onClick = { connect(peer.id) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Connect to ${peer.name}")
                    }
                }

                when (state.phase) {
                    "READY" -> {
                        if (state.role == Role.REQUESTER) {
                            Text(
                                text = "What do you need help with?",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                text = "The connected helper will see these details.",
                                style = MaterialTheme.typography.bodySmall,
                            )

                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                HelpCategory.entries.forEach { option ->
                                    FilterChip(
                                        selected = category == option,
                                        onClick = { category = option },
                                        label = {
                                            Text(
                                                option.name.lowercase()
                                                    .replaceFirstChar { it.uppercase() },
                                            )
                                        },
                                    )
                                }
                            }

                            OutlinedTextField(
                                value = requestDetails,
                                onValueChange = { requestDetails = it },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("Describe the help you need") },
                                minLines = 3,
                                maxLines = 5,
                            )

                            Button(
                                onClick = {
                                    sendRequest(category, requestDetails)
                                    requestDetails = ""
                                },
                                enabled = HelpMessageCodec.validText(
                                    requestDetails.trim(),
                                    HelpMessageCodec.MAX_REQUEST_BYTES,
                                ),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("Send request")
                            }

                            Text(
                                text = "No orders or payments are made in Continuity. Don’t share passwords or card details.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        } else {
                            Text("You’re available for a nearby request.")
                        }
                    }

                    "WAITING_ACCEPT" -> {
                        Text("Request sent", style = MaterialTheme.typography.titleLarge)
                        state.request?.let {
                            RequestSummary(it.category.name, it.details)
                        }
                        Text("Waiting for the helper to respond.")
                    }

                    "REQUEST_RECEIVED" -> {
                        Text("Help request", style = MaterialTheme.typography.titleLarge)
                        state.request?.let {
                            RequestSummary(it.category.name, it.details)
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Button(
                                    onClick = acceptRequest,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("Accept")
                                }
                                OutlinedButton(
                                    onClick = declineRequest,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Text("Decline")
                                }
                            }
                        }
                    }

                    "CHAT" -> {
                        Text("Help chat", style = MaterialTheme.typography.titleLarge)
                        state.request?.let {
                            RequestSummary(it.category.name, it.details)
                        }

                        state.chat.forEach { line ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(14.dp),
                                color = if (line.sentByMe) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceVariant
                                },
                            ) {
                                Text(
                                    text = "${if (line.sentByMe) "You" else "Helper"}: ${line.text}",
                                    modifier = Modifier.padding(12.dp),
                                )
                            }
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = chatDraft,
                                onValueChange = { chatDraft = it },
                                modifier = Modifier.weight(1f),
                                label = { Text("Message") },
                                maxLines = 3,
                            )
                            Button(
                                onClick = {
                                    sendChat(chatDraft)
                                    chatDraft = ""
                                },
                                enabled = HelpMessageCodec.validText(
                                    chatDraft.trim(),
                                    HelpMessageCodec.MAX_CHAT_BYTES,
                                ),
                            ) {
                                Text("Send")
                            }
                        }

                        OutlinedButton(
                            onClick = { confirmEnd = true },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("End help")
                        }
                    }

                    "TASK_ENDED", "TASK_DECLINED", "TASK_EXPIRED" -> {
                        Text(
                            text = state.phase
                                .removePrefix("TASK_")
                                .replace('_', ' ')
                                .lowercase()
                                .replaceFirstChar { it.uppercase() },
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Text("This session is closed.")
                    }
                }

                if (state.phase !in setOf(
                        "TASK_ENDED",
                        "TASK_DECLINED",
                        "TASK_EXPIRED",
                        "CHAT",
                    )
                ) {
                    OutlinedButton(
                        onClick = stop,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Stop connection")
                    }
                } else {
                    Button(
                        onClick = stop,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Finish")
                    }
                }
            }

            if (state.phase == "ERROR") {
                OutlinedButton(onClick = appSettings) {
                    Text("App permissions")
                }
                OutlinedButton(onClick = radioSettings) {
                    Text("Phone settings")
                }
                Text(
                    text = "After fixing settings, choose a role again on both phones.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }

    if (state.phase == "VERIFYING" && state.digits != null) {
        AlertDialog(
            onDismissRequest = { confirm(false) },
            title = { Text("Verify the other phone") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(state.peerName)
                    Text(state.digits, style = MaterialTheme.typography.headlineLarge)
                    Text("Confirm only if the codes match on both phones.")
                }
            },
            confirmButton = {
                TextButton(onClick = { confirm(true) }) {
                    Text("Codes match")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirm(false) }) {
                    Text("Reject")
                }
            },
        )
    }

    if (confirmEnd) {
        AlertDialog(
            onDismissRequest = { confirmEnd = false },
            title = { Text("End this help session?") },
            text = { Text("Choose “Keep chatting” if you pressed Back by accident.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmEnd = false
                        endHelp()
                    },
                ) {
                    Text("End help")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmEnd = false }) {
                    Text("Keep chatting")
                }
            },
        )
    }
}

@Composable
private fun RequestSummary(
    category: String,
    details: String,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = category.lowercase().replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.labelLarge,
            )
            Text(details)
        }
    }
}
