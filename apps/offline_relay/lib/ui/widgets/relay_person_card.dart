import 'package:flutter/material.dart';

import 'package:relay_transport/relay_transport.dart';

import '../offline_relay_theme.dart';

class RelayPersonCard extends StatelessWidget {
  const RelayPersonCard({
    required this.peer,
    required this.onConnect,
    this.isConnecting = false,
    super.key,
  });

  final RelayPeer peer;
  final VoidCallback onConnect;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    final initial = peer.label.trim().isEmpty
        ? '?'
        : peer.label.trim().characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RelayColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RelayColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A284636),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: RelayColors.peachLight,
            foregroundColor: RelayColors.greenDark,
            child: Text(
              initial,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Nearby · Internet Helper',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: RelayColors.muted),
                ),
                const SizedBox(height: 6),
                const _AvailableLabel(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: isConnecting ? null : onConnect,
            style: FilledButton.styleFrom(
              minimumSize: const Size(78, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: RelayColors.greenLight,
              foregroundColor: RelayColors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }
}

class _AvailableLabel extends StatelessWidget {
  const _AvailableLabel();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF4EA474),
          shape: BoxShape.circle,
        ),
        child: SizedBox(width: 7, height: 7),
      ),
      SizedBox(width: 6),
      Text(
        'Available nearby',
        style: TextStyle(
          color: RelayColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
