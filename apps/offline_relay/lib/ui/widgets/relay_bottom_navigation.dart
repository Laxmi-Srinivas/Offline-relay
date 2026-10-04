import 'package:flutter/material.dart';

import '../offline_relay_theme.dart';

enum RelayTab { home, nearby, profile }

class RelayBottomNavigation extends StatelessWidget {
  const RelayBottomNavigation({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final RelayTab selected;
  final ValueChanged<RelayTab> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
    child: Container(
      height: 76,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: RelayColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RelayColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1E4F41),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _NavigationItem(
            tab: RelayTab.home,
            selected: selected,
            icon: Icons.home_outlined,
            label: 'Home',
            onSelected: onSelected,
          ),
          _NavigationItem(
            tab: RelayTab.nearby,
            selected: selected,
            icon: Icons.people_outline,
            label: 'Nearby',
            onSelected: onSelected,
          ),
          _NavigationItem(
            tab: RelayTab.profile,
            selected: selected,
            icon: Icons.person_outline,
            label: 'Profile',
            onSelected: onSelected,
          ),
        ],
      ),
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.tab,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final RelayTab tab;
  final RelayTab selected;
  final IconData icon;
  final String label;
  final ValueChanged<RelayTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = tab == selected;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelected(tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? RelayColors.greenLight : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? RelayColors.green : RelayColors.muted,
                  size: 21,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? RelayColors.green : RelayColors.muted,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
