import 'package:flutter/material.dart';
import 'package:relay_transport/relay_transport.dart';

import '../../relay_demo_controller.dart';
import '../offline_relay_theme.dart';
import '../widgets/relay_person_card.dart';

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({
    required this.controller,
    required this.onSearch,
    required this.onConnect,
    required this.onAccept,
    required this.onReject,
    required this.onCancelRequest,
    super.key,
  });

  final RelayDemoController controller;
  final VoidCallback onSearch;
  final ValueChanged<RelayPeer> onConnect;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancelRequest;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'People nearby',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            tooltip: 'Search again',
            onPressed:
                controller.isConnecting ||
                    controller.isWaitingForAcceptance ||
                    controller.hasIncomingRequest
                ? null
                : onSearch,
            icon: const Icon(Icons.refresh_rounded, color: RelayColors.green),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        'Connect with nearby people who are available to help.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (controller.errorMessage case final error?) ...[
        const SizedBox(height: 18),
        _ErrorCard(message: error, onRetry: onSearch),
      ],
      if (controller.hasIncomingRequest) ...[
        const SizedBox(height: 18),
        _IncomingRequestCard(
          name: controller.incomingPeerName ?? 'A nearby user',
          onAccept: controller.isResponding ? null : onAccept,
          onReject: controller.isResponding ? null : onReject,
        ),
      ],
      if (controller.isConnecting || controller.isWaitingForAcceptance) ...[
        const SizedBox(height: 18),
        _RequestPendingCard(
          message: controller.isConnecting
              ? 'Connecting to ${controller.remoteName ?? 'nearby helper'}…'
              : controller.status,
          onCancel: onCancelRequest,
        ),
      ] else if (controller.isDiscovering) ...[
        const SizedBox(height: 22),
        const _SearchingCard(),
        if (controller.peers.isNotEmpty) ...[
          const SizedBox(height: 22),
          _PeopleList(
            peers: controller.peers,
            onConnect: onConnect,
            isConnecting: controller.isConnecting,
          ),
        ],
      ] else if (controller.noPeopleFound) ...[
        const SizedBox(height: 24),
        _NoPeopleCard(onSearch: onSearch),
      ] else if (controller.peers.isNotEmpty) ...[
        const SizedBox(height: 22),
        _PeopleList(
          peers: controller.peers,
          onConnect: onConnect,
          isConnecting: controller.isConnecting,
        ),
        const SizedBox(height: 18),
        const _PrivacyNote(),
      ] else if (controller.errorMessage == null &&
          !controller.hasIncomingRequest &&
          !controller.isConnecting &&
          !controller.isWaitingForAcceptance) ...[
        const SizedBox(height: 24),
        _NearbyIntro(onSearch: onSearch),
      ],
      if (controller.errorMessage == null &&
          !controller.isDiscovering &&
          !controller.isConnecting &&
          !controller.isWaitingForAcceptance &&
          !controller.hasIncomingRequest &&
          controller.peers.isEmpty &&
          !controller.noPeopleFound &&
          controller.status != 'Choose your name and role to begin.') ...[
        const SizedBox(height: 18),
        _StatusCard(message: controller.status),
      ],
      if (controller.errorMessage == null &&
          !controller.isDiscovering &&
          !controller.isConnecting &&
          !controller.isWaitingForAcceptance &&
          !controller.hasIncomingRequest &&
          controller.peers.isNotEmpty &&
          (controller.status.toLowerCase().contains('declined') ||
              controller.status.toLowerCase().contains('accepted'))) ...[
        const SizedBox(height: 14),
        _StatusCard(message: controller.status),
      ],
    ],
  );
}

class _NearbyIntro extends StatelessWidget {
  const _NearbyIntro({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: RelayColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: RelayColors.border),
    ),
    child: Column(
      children: [
        const _PeopleIcon(),
        const SizedBox(height: 15),
        Text(
          'A little help is close by',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Search for people nearby who have chosen to offer help.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.people_outline),
            label: const Text('Find People Nearby'),
          ),
        ),
      ],
    ),
  );
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: RelayColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: RelayColors.border),
    ),
    child: Column(
      children: [
        SizedBox(
          width: 154,
          height: 154,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 146,
                height: 146,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RelayColors.greenLight.withValues(alpha: 0.65),
                ),
              ),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RelayColors.sage, width: 1.5),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: RelayColors.green,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 31),
              ),
              const Positioned(
                right: 12,
                top: 21,
                child: _FloatingPerson(color: RelayColors.peach),
              ),
              const Positioned(
                left: 4,
                bottom: 19,
                child: _FloatingPerson(color: RelayColors.sage),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Finding people nearby…',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Looking for people who are available to help.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 17),
        const _BluetoothPill(),
        const SizedBox(height: 18),
        const LinearProgressIndicator(
          minHeight: 3,
          borderRadius: BorderRadius.all(Radius.circular(4)),
          backgroundColor: RelayColors.greenLight,
        ),
      ],
    ),
  );
}

class _FloatingPerson extends StatelessWidget {
  const _FloatingPerson({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 18,
    backgroundColor: color,
    foregroundColor: RelayColors.greenDark,
    child: const Icon(Icons.person, size: 20),
  );
}

class _BluetoothPill extends StatelessWidget {
  const _BluetoothPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: RelayColors.greenLight,
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bluetooth, color: RelayColors.green, size: 17),
        SizedBox(width: 6),
        Text(
          'Connecting through Bluetooth',
          style: TextStyle(color: RelayColors.green, fontSize: 12),
        ),
      ],
    ),
  );
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({
    required this.peers,
    required this.onConnect,
    required this.isConnecting,
  });

  final List<RelayPeer> peers;
  final ValueChanged<RelayPeer> onConnect;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${peers.length} ${peers.length == 1 ? 'person' : 'people'} available',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 5),
      Text(
        'These nearby users have Help Others enabled.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: RelayColors.muted),
      ),
      const SizedBox(height: 14),
      for (final peer in peers) ...[
        RelayPersonCard(
          peer: peer,
          isConnecting: isConnecting,
          onConnect: () => onConnect(peer),
        ),
        if (peer != peers.last) const SizedBox(height: 11),
      ],
    ],
  );
}

class _NoPeopleCard extends StatelessWidget {
  const _NoPeopleCard({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: RelayColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: RelayColors.border),
    ),
    child: Column(
      children: [
        const _PeopleIcon(empty: true),
        const SizedBox(height: 16),
        Text(
          'No one found nearby',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        Text(
          'We couldn’t find anyone available to help right now.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        const _Suggestion(
          icon: Icons.bluetooth,
          text: 'Make sure Bluetooth is turned on.',
        ),
        const _Suggestion(
          icon: Icons.directions_walk,
          text: 'Try moving to an area with more people.',
        ),
        const _Suggestion(
          icon: Icons.access_time,
          text: 'Wait a moment and search again.',
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onSearch,
            child: const Text('Search Again'),
          ),
        ),
      ],
    ),
  );
}

class _PeopleIcon extends StatelessWidget {
  const _PeopleIcon({this.empty = false});

  final bool empty;

  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    height: 76,
    decoration: BoxDecoration(
      color: empty ? RelayColors.peachLight : RelayColors.sageLight,
      shape: BoxShape.circle,
    ),
    child: Icon(
      empty ? Icons.people_outline : Icons.people_alt_outlined,
      color: RelayColors.green,
      size: 36,
    ),
  );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: RelayColors.green, size: 17),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.name,
    required this.onAccept,
    required this.onReject,
  });

  final String name;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: RelayColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: RelayColors.sage),
      boxShadow: const [BoxShadow(color: Color(0x14284636), blurRadius: 18)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NEARBY REQUEST',
          style: TextStyle(
            color: RelayColors.green,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '$name wants to connect',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 5),
        Text(
          'They would like help accessing an online service.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 13),
        const Text(
          'A temporary chat will open after you accept.',
          style: TextStyle(fontSize: 12, color: RelayColors.greenDark),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: onAccept,
                child: const Text('Accept'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RequestPendingCard extends StatelessWidget {
  const _RequestPendingCard({required this.message, required this.onCancel});

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: RelayColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: RelayColors.border),
    ),
    child: Column(
      children: [
        const CircularProgressIndicator(color: RelayColors.green),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (controllerStatusIncludesWait(message)) ...[
          const SizedBox(height: 5),
          const Text(
            'Waiting for the helper to respond…',
            style: TextStyle(color: RelayColors.muted),
          ),
        ],
        const SizedBox(height: 10),
        TextButton(onPressed: onCancel, child: const Text('Cancel Request')),
      ],
    ),
  );
}

bool controllerStatusIncludesWait(String message) =>
    message.toLowerCase().contains('request sent');

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: RelayColors.coralLight,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, color: RelayColors.coral),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: RelayColors.text),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      ],
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.62),
      border: Border.all(color: RelayColors.border),
      borderRadius: BorderRadius.circular(17),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: RelayColors.green, size: 19),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your nearby profile shares only the name and helper role.',
            style: TextStyle(
              color: RelayColors.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: RelayColors.greenLight,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(message, style: const TextStyle(color: RelayColors.greenDark)),
  );
}
