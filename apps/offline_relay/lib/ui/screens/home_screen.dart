import 'package:flutter/material.dart';

import '../offline_relay_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onFindNearby,
    required this.helperAvailable,
    super.key,
  });

  final VoidCallback onFindNearby;
  final bool helperAvailable;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
    children: [
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: RelayColors.green,
              borderRadius: BorderRadius.circular(13),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33286653),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.favorite_border, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text('OfflineRelay', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          _ModePill(
            label: helperAvailable ? 'Help Others on' : 'Nearby help',
            color: helperAvailable ? RelayColors.green : RelayColors.muted,
            dotColor: helperAvailable
                ? const Color(0xFF4EA474)
                : RelayColors.peach,
          ),
        ],
      ),
      const SizedBox(height: 28),
      const _PeopleIllustration(),
      const SizedBox(height: 22),
      const _Eyebrow('A LITTLE HELP IS CLOSE BY'),
      const SizedBox(height: 8),
      Text(
        'No internet?\nGet help nearby.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 13),
      Text(
        'Connect with someone nearby who has internet and can help you access an online service.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: onFindNearby,
        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
        label: const Text('Find People Nearby'),
      ),
      const SizedBox(height: 20),
      const Row(
        children: [
          Expanded(
            child: _Reassurance(
              icon: Icons.bluetooth,
              label: 'Nearby\nconnection',
            ),
          ),
          Expanded(
            child: _Reassurance(
              icon: Icons.chat_bubble_outline,
              label: 'Temporary\nchat',
            ),
          ),
          Expanded(
            child: _Reassurance(
              icon: Icons.verified_user_outlined,
              label: 'Not saved\nafter ending',
            ),
          ),
        ],
      ),
      if (helperAvailable) ...[
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: RelayColors.greenLight,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(Icons.favorite, color: RelayColors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You’re available to help nearby, even in another app.',
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.color,
    required this.dotColor,
  });

  final String label;
  final Color color;
  final Color dotColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.8),
      border: Border.all(color: RelayColors.border),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PeopleIllustration extends StatelessWidget {
  const _PeopleIllustration();

  @override
  Widget build(BuildContext context) => Container(
    height: 190,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          RelayColors.peachLight,
          Color(0xFFF5EEE4),
          RelayColors.sageLight,
        ],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14284636),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: -38,
          left: -24,
          child: _SoftOrb(
            size: 112,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        Positioned(
          bottom: -48,
          right: -20,
          child: _SoftOrb(
            size: 126,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          top: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x14284636), blurRadius: 12),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 15, color: RelayColors.green),
                SizedBox(width: 5),
                Text(
                  'Here to help',
                  style: TextStyle(
                    color: RelayColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 78,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 40, height: 2, color: RelayColors.sage),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bluetooth,
                  color: RelayColors.green,
                  size: 17,
                ),
              ),
              Container(width: 40, height: 2, color: RelayColors.sage),
            ],
          ),
        ),
        const Positioned(
          left: 44,
          bottom: 8,
          child: _IllustratedPerson(color: RelayColors.peach),
        ),
        const Positioned(
          right: 44,
          bottom: 8,
          child: _IllustratedPerson(color: RelayColors.sage),
        ),
      ],
    ),
  );
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _IllustratedPerson extends StatelessWidget {
  const _IllustratedPerson({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: Color(0xFF6D4536),
          shape: BoxShape.circle,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: 34,
            height: 15,
            margin: const EdgeInsets.only(top: 3),
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(20),
                bottom: Radius.circular(10),
              ),
            ),
          ),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -5),
        child: Container(
          width: 74,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(20),
            ),
          ),
          child: const Icon(
            Icons.phone_android,
            color: RelayColors.green,
            size: 24,
          ),
        ),
      ),
    ],
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Manrope',
      color: RelayColors.green,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    ),
  );
}

class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: RelayColors.green, size: 19),
      const SizedBox(height: 6),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: RelayColors.muted,
          fontSize: 11,
          height: 1.25,
        ),
      ),
    ],
  );
}
