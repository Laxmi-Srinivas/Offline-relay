import 'package:flutter/material.dart';

import '../offline_relay_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.nameController,
    required this.isAvailable,
    required this.isBusy,
    required this.onNameChanged,
    required this.onAvailabilityChanged,
    required this.errorMessage,
    super.key,
  });

  final TextEditingController nameController;
  final bool isAvailable;
  final bool isBusy;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<bool> onAvailabilityChanged;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
    children: [
      Text('Your profile', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 5),
      Text(
        'Set your name and choose how you want to help.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: RelayColors.surface,
          border: Border.all(color: RelayColors.border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: RelayColors.sageLight,
              foregroundColor: RelayColors.greenDark,
              child: Text(
                nameController.text.trim().isEmpty
                    ? '?'
                    : nameController.text.trim().characters.first.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      counterText: '',
                      isDense: true,
                    ),
                    onChanged: onNameChanged,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Android phone',
                    style: TextStyle(color: RelayColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: RelayColors.greenLight,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_border, color: RelayColors.green),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available to help nearby',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: RelayColors.greenDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Allow nearby people to send you a connection request. Help Others stays on while you use another app.',
                    style: TextStyle(
                      color: RelayColors.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isBusy)
              const SizedBox(
                width: 38,
                height: 28,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Switch.adaptive(
                value: isAvailable,
                onChanged: onAvailabilityChanged,
                activeTrackColor: RelayColors.green,
              ),
          ],
        ),
      ),
      if (isAvailable) ...[
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RelayColors.surface,
            border: Border.all(color: RelayColors.border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Row(
            children: [
              Icon(Icons.bluetooth_searching, color: RelayColors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Help Others is on. Nearby requests can reach you in the background.',
                  style: TextStyle(
                    color: RelayColors.greenDark,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      if (errorMessage != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RelayColors.coralLight,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            errorMessage!,
            style: const TextStyle(color: RelayColors.text),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: RelayColors.surface,
          border: Border.all(color: RelayColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: RelayColors.green),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chats are temporary and are not saved after the connection ends.',
                style: TextStyle(
                  color: RelayColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
