import 'dart:async';

import 'package:flutter/material.dart';

import 'relay_demo_controller.dart';
import 'transport/ble_relay_transport.dart';

void main() => runApp(const OfflineRelayApp());

class OfflineRelayApp extends StatefulWidget {
  const OfflineRelayApp({super.key});

  @override
  State<OfflineRelayApp> createState() => _OfflineRelayAppState();
}

class _OfflineRelayAppState extends State<OfflineRelayApp> {
  late final RelayDemoController _controller;
  final _nameController = TextEditingController();
  final _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = RelayDemoController(BleRelayTransport());
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OfflineRelay',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final inChat = _controller.inChat;
        return Scaffold(
          appBar: AppBar(
            leading: inChat
                ? IconButton(
                    tooltip: 'Back to Nearby Users',
                    onPressed: () => _run(_controller.returnToNearby),
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            title: Text(
              inChat
                  ? 'Chat with ${_controller.remoteName ?? 'Nearby user'}'
                  : 'Nearby Users',
            ),
          ),
          body: SafeArea(
            child: inChat ? _chatScreen(context) : _nearbyScreen(),
          ),
        );
      },
    ),
  );

  Widget _nearbyScreen() {
    final c = _controller;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Connect directly with people nearby, even without mobile data.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your display name',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onChanged: (name) => c.updateProfile(name: name, role: c.role),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<RelayUserRole>(
          initialValue: c.role,
          decoration: const InputDecoration(
            labelText: 'Your role',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: RelayUserRole.offlineUser,
              child: Text('Offline User'),
            ),
            DropdownMenuItem(
              value: RelayUserRole.internetHelper,
              child: Text('Internet Helper'),
            ),
          ],
          onChanged: (role) {
            if (role == null) return;
            c.updateProfile(name: _nameController.text, role: role);
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: c.isConnecting
              ? null
              : () => _run(
                  c.role == RelayUserRole.offlineUser
                      ? c.findNearbyHelpers
                      : c.offerHelp,
                ),
          icon: Icon(
            c.role == RelayUserRole.offlineUser
                ? Icons.radar
                : Icons.volunteer_activism,
          ),
          label: Text(
            c.role == RelayUserRole.offlineUser
                ? 'Find Nearby Helpers'
                : 'Offer Help',
          ),
        ),
        const SizedBox(height: 12),
        _StatusCard(message: c.status),
        if (c.isOffering) ...[
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.bluetooth_searching),
              title: Text('Advertising for nearby users'),
              subtitle: Text('Keep this screen open to receive a request.'),
            ),
          ),
        ],
        if (c.isWaitingForAcceptance) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (c.hasIncomingRequest) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.incomingPeerName ?? 'A nearby user'} wants to connect',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _run(c.acceptIncomingRequest),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _run(c.rejectIncomingRequest),
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (c.peers.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nearby Internet Helpers',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final peer in c.peers)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(peer.label),
                subtitle: const Text('Internet Helper · Bluetooth nearby'),
                trailing: FilledButton.tonal(
                  onPressed: c.isConnecting
                      ? null
                      : () => _run(() => c.connectTo(peer)),
                  child: const Text('Connect'),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _chatScreen(BuildContext context) {
    final c = _controller;
    return Column(
      children: [
        if (c.messages.length >= RelayDemoController.maxHistoryMessages)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Showing the newest 300 messages in this conversation.'),
          ),
        Expanded(
          child: c.messages.isEmpty
              ? const Center(child: Text('Connected. Start a conversation.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: c.messages.length,
                  itemBuilder: (context, index) =>
                      _messageBubble(context, c.messages[index]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    textInputAction: TextInputAction.send,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sendChat,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageBubble(BuildContext context, RelayConversationMessage message) {
    return Align(
      alignment: message.fromLocalUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          color: message.fromLocalUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message.text),
          ),
        ),
      ),
    );
  }

  Future<void> _sendChat() async {
    final text = _chatController.text;
    if (text.trim().isEmpty) return;
    await _run(() => _controller.sendChat(text));
    _chatController.clear();
  }

}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(message),
    ),
  );
}
