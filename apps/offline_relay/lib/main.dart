import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_transport/relay_transport.dart';

import 'relay_demo_controller.dart';
import 'transport/ble_relay_transport.dart';
import 'ui/offline_relay_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/nearby_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/widgets/relay_bottom_navigation.dart';

void main() => runApp(const OfflineRelayApp());

class OfflineRelayApp extends StatefulWidget {
  const OfflineRelayApp({super.key, this.transport});

  final RelayTransport? transport;

  @override
  State<OfflineRelayApp> createState() => _OfflineRelayAppState();
}

class _OfflineRelayAppState extends State<OfflineRelayApp> {
  late final RelayDemoController _controller;
  final _nameController = TextEditingController();
  final _chatController = TextEditingController();
  RelayTab _selectedTab = RelayTab.home;
  bool _availabilityBusy = false;

  @override
  void initState() {
    super.initState();
    _controller = RelayDemoController(widget.transport ?? BleRelayTransport());
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final changedName = _nameController.text != _controller.displayName;
    if (changedName) {
      _nameController.value = TextEditingValue(
        text: _controller.displayName,
        selection: TextSelection.collapsed(
          offset: _controller.displayName.length,
        ),
      );
    }
    if (_controller.hasIncomingRequest &&
        !_controller.inChat &&
        _selectedTab != RelayTab.nearby) {
      setState(() => _selectedTab = RelayTab.nearby);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _nameController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      _controller.reportError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: RelayColors.greenDark,
        ),
      );
    }
  }

  Future<void> _findNearby() async {
    if (_controller.displayName.trim().isEmpty) {
      setState(() => _selectedTab = RelayTab.profile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add your name in Profile to get started.'),
        ),
      );
      return;
    }
    await _run(() async {
      if (_controller.isOffering) await _controller.stopOfferingHelp();
      _controller.updateProfile(
        name: _controller.displayName,
        role: RelayUserRole.offlineUser,
      );
      setState(() => _selectedTab = RelayTab.nearby);
      await _controller.findNearbyHelpers();
    });
  }

  Future<void> _setAvailability(bool enabled) async {
    if (_availabilityBusy) return;
    if (enabled && _controller.displayName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add your name before enabling Help Others.'),
        ),
      );
      return;
    }
    setState(() => _availabilityBusy = true);
    try {
      if (enabled) {
        _controller.updateProfile(
          name: _controller.displayName,
          role: RelayUserRole.internetHelper,
        );
        await _controller.offerHelp();
      } else {
        await _controller.stopOfferingHelp();
      }
      _controller.clearError();
    } catch (error) {
      _controller.reportError(error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
            backgroundColor: RelayColors.greenDark,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OfflineRelay',
    debugShowCheckedModeBanner: false,
    theme: buildOfflineRelayTheme(),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.inChat) return _chatScreen();
        return Scaffold(
          backgroundColor: RelayColors.canvas,
          body: SafeArea(child: _selectedScreen()),
          bottomNavigationBar: RelayBottomNavigation(
            selected: _selectedTab,
            onSelected: (tab) {
              _controller.clearError();
              setState(() => _selectedTab = tab);
            },
          ),
        );
      },
    ),
  );

  Widget _selectedScreen() => switch (_selectedTab) {
    RelayTab.home => HomeScreen(
      helperAvailable: _controller.isOffering,
      onFindNearby: _findNearby,
    ),
    RelayTab.nearby => NearbyScreen(
      controller: _controller,
      onSearch: () => _run(_findNearby),
      onConnect: (peer) => _run(() => _controller.connectTo(peer)),
      onAccept: () => _run(_controller.acceptIncomingRequest),
      onReject: () => _run(_controller.rejectIncomingRequest),
      onCancelRequest: () => _run(_controller.returnToNearby),
    ),
    RelayTab.profile => ProfileScreen(
      nameController: _nameController,
      isAvailable: _controller.isOffering,
      isBusy: _availabilityBusy,
      onNameChanged: (name) =>
          _controller.updateProfile(name: name, role: _controller.role),
      onAvailabilityChanged: _setAvailability,
      errorMessage: _controller.errorMessage,
    ),
  };

  Widget _chatScreen() => Scaffold(
    backgroundColor: RelayColors.canvas,
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'End chat and return to Nearby',
        onPressed: () => _run(_controller.returnToNearby),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text('Chat with ${_controller.remoteName ?? 'Nearby user'}'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _controller.messages.isEmpty
                ? const Center(child: Text('Connected. Start a conversation.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _controller.messages.length,
                    itemBuilder: (context, index) =>
                        _messageBubble(context, _controller.messages[index]),
                  ),
          ),
          Padding(
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
        ],
      ),
    ),
  );

  Widget _messageBubble(
    BuildContext context,
    RelayConversationMessage message,
  ) => Align(
    alignment: message.fromLocalUser
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Card(
        color: message.fromLocalUser
            ? RelayColors.greenLight
            : RelayColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(message.text),
        ),
      ),
    ),
  );

  Future<void> _sendChat() async {
    final text = _chatController.text;
    if (text.trim().isEmpty) return;
    await _run(() => _controller.sendChat(text));
    _chatController.clear();
  }
}
