import 'package:flutter/material.dart';

import '../../relay_demo_controller.dart';
import '../offline_relay_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.controller,
    required this.onEndChat,
    required this.onReturnToNearby,
    required this.onSubmitReport,
    super.key,
  });

  final RelayDemoController controller;
  final Future<void> Function() onEndChat;
  final Future<void> Function() onReturnToNearby;
  final Future<void> Function(String reason, String note) onSubmitReport;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.isChatTerminal || !controller.inChat) {
      _messageController.clear();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (controller.isChatTerminal) {
            widget.onReturnToNearby();
          } else {
            _confirmEndChat();
          }
        }
      },
      child: Scaffold(
        backgroundColor: RelayColors.canvas,
        appBar: AppBar(
          leading: controller.isChatTerminal
              ? null
              : IconButton(
                  tooltip: 'Chat options',
                  onPressed: _confirmEndChat,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
          titleSpacing: controller.isChatTerminal ? 22 : 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.remoteName ?? 'Nearby person',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                controller.remoteRoleLabel ?? 'Temporary chat',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: RelayColors.muted, fontSize: 11),
              ),
              if (controller.messages.length >=
                  RelayDemoController.maxHistoryMessages)
                const Text(
                  'Newest 300 messages kept in memory.',
                  style: TextStyle(fontSize: 11),
                ),
            ],
          ),
          actions: [
            if (!controller.isChatTerminal) ...[
              IconButton(
                tooltip: controller.hasSubmittedReport
                    ? 'Report submitted'
                    : 'Report this person',
                onPressed: controller.securityState == RelaySecurityState.ready
                    ? _showReportDialog
                    : null,
                icon: Icon(
                  controller.hasSubmittedReport
                      ? Icons.flag_rounded
                      : Icons.outlined_flag_rounded,
                  color: controller.hasSubmittedReport
                      ? RelayColors.coral
                      : RelayColors.text,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _confirmEndChat,
                  icon: const Icon(Icons.call_end_rounded, size: 17),
                  label: const Text('End'),
                  style: TextButton.styleFrom(
                    foregroundColor: RelayColors.coral,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(
                  onPressed: () => widget.onReturnToNearby(),
                  child: const Text('Done'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: controller.isChatTerminal
              ? _terminalState(controller)
              : controller.securityState == RelaySecurityState.exchangingKeys
              ? _securityLoading()
              : controller.securityState == RelaySecurityState.ready
              ? _activeChat(controller)
              : _securityLoading(),
        ),
      ),
    );
  }

  Widget _securityLoading() => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: RelayColors.green),
          SizedBox(height: 18),
          Text('Securing this temporary chat…'),
        ],
      ),
    ),
  );

  Widget _activeChat(RelayDemoController controller) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _TemporarySessionNote(compact: true),
      ),
      Expanded(
        child: controller.messages.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    'You’re connected. Say hello to start the conversation.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) => _messageBubble(
                  controller.messages[controller.messages.length - 1 - index],
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: !_sending,
                maxLength: 80,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  counterText: '',
                  helperText: 'Short messages only; emoji use more space.',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _messageBubble(RelayConversationMessage message) => Align(
    alignment: message.fromLocalUser
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 310),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: message.fromLocalUser ? RelayColors.green : RelayColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(message.fromLocalUser ? 18 : 5),
          bottomRight: Radius.circular(message.fromLocalUser ? 5 : 18),
        ),
        border: message.fromLocalUser
            ? null
            : Border.all(color: RelayColors.border),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: message.fromLocalUser ? Colors.white : RelayColors.text,
          height: 1.4,
        ),
      ),
    ),
  );

  Widget _terminalState(RelayDemoController controller) {
    final (icon, title, body) = switch (controller.chatEndReason!) {
      RelayChatEndReason.local => (
        Icons.check_circle_outline_rounded,
        'Chat ended',
        'You ended this temporary conversation.',
      ),
      RelayChatEndReason.remote => (
        Icons.waving_hand_outlined,
        'Chat ended by ${controller.remoteName ?? 'the other person'}',
        'The other person intentionally ended this conversation.',
      ),
      RelayChatEndReason.connectionLost => (
        Icons.bluetooth_disabled_rounded,
        'Connection lost',
        'The nearby connection ended unexpectedly. You can return to Nearby and connect again.',
      ),
      RelayChatEndReason.securityFailed => (
        Icons.gpp_bad_outlined,
        'Encrypted chat unavailable',
        'Encrypted session setup failed or timed out. Return to Nearby to start a new session.',
      ),
    };
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RelayColors.green, size: 54),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              controller.errorMessage ?? body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => widget.onReturnToNearby(),
              child: const Text('Return to Nearby'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.controller.sendChat(text);
      if (mounted) _messageController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmEndChat() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this chat?'),
        content: const Text(
          'The conversation will close for both people. Your messages are only kept for this temporary session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep chatting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: RelayColors.coral),
            child: const Text('End chat'),
          ),
        ],
      ),
    );
    if (shouldEnd == true) await widget.onEndChat();
  }

  Future<void> _showReportDialog() async {
    if (widget.controller.hasSubmittedReport) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Report noted'),
          content: const Text(
            'This report is stored only in the current app session. It was not sent to a moderation service.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    const reasons = [
      'Harassment or abuse',
      'Spam or scam',
      'Inappropriate content',
      'Other concern',
    ];
    var selectedReason = reasons.first;
    final noteController = TextEditingController();
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report this person'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('What happened?'),
                  ),
                  RadioGroup<String>(
                    groupValue: selectedReason,
                    onChanged: (value) => setDialogState(
                      () => selectedReason = value ?? reasons.first,
                    ),
                    child: Column(
                      children: [
                        for (final reason in reasons)
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: reason,
                            title: Text(reason),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    maxLength: 240,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Add a note (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This stays on this device for the current session. It will not be sent to a server.',
                    style: TextStyle(fontSize: 12, color: RelayColors.muted),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (selectedReason, noteController.text)),
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (result == null || !mounted) return;
    await widget.onSubmitReport(result.$1, result.$2);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag_outlined, color: RelayColors.green),
        title: const Text('Report noted'),
        content: const Text(
          'Your report is recorded only for this temporary session. It was not sent to a moderation service.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TemporarySessionNote extends StatelessWidget {
  const _TemporarySessionNote({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(compact ? 10 : 14),
    decoration: BoxDecoration(
      color: RelayColors.greenLight,
      borderRadius: BorderRadius.circular(compact ? 14 : 17),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          color: RelayColors.green,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Encrypted chat. Messages last for this temporary session only.',
            style: TextStyle(
              color: RelayColors.greenDark,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ),
      ],
    ),
  );
}
