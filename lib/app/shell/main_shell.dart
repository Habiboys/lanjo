import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/catat_bottom_sheet.dart';
import '../theme/app_theme.dart';

/// Five-item minimalist bottom navigation shell: Beranda, Transaksi, Catat (+), Rencana, Pengaturan.
class MainShell extends StatelessWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  int get _selectedBarIndex {
    return switch (navigationShell.currentIndex) {
      0 => 0,
      1 => 1,
      2 => 3,
      3 => 4,
      _ => 0,
    };
  }

  void _onDestinationSelected(BuildContext context, int barIndex) {
    if (barIndex == 2) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (_) => const CatatBottomSheet(),
      );
      return;
    }

    final branchIndex = switch (barIndex) {
      0 => 0,
      1 => 1,
      3 => 2,
      4 => 3,
      _ => 0,
    };
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedBarIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.lanjoCard,
          border: Border(
            top: BorderSide(color: context.lanjoBorder, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _NavTabItem(
                      icon: LucideIcons.home,
                      label: 'Beranda',
                      isSelected: selected == 0,
                      onTap: () => _onDestinationSelected(context, 0),
                    ),
                  ),
                  Expanded(
                    child: _NavTabItem(
                      icon: LucideIcons.receiptText,
                      label: 'Transaksi',
                      isSelected: selected == 1,
                      onTap: () => _onDestinationSelected(context, 1),
                    ),
                  ),
                  Expanded(
                    child: _CatatCenterAction(
                      onTap: () => _onDestinationSelected(context, 2),
                    ),
                  ),
                  Expanded(
                    child: _NavTabItem(
                      icon: LucideIcons.compass,
                      label: 'Rencana',
                      isSelected: selected == 3,
                      onTap: () => _onDestinationSelected(context, 3),
                    ),
                  ),
                  Expanded(
                    child: _NavTabItem(
                      icon: LucideIcons.settings,
                      label: 'Pengaturan',
                      isSelected: selected == 4,
                      onTap: () => _onDestinationSelected(context, 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = context.lanjoSubtle;
    final color = isSelected ? activeColor : inactiveColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: context.isDark ? 0.16 : 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ArusColors.fontFamily,
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? context.lanjoInk : inactiveColor,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatatCenterAction extends StatelessWidget {
  const _CatatCenterAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Catat',
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Semantics(
              label: 'Catat',
              button: true,
              child: Container(
                width: 48,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ArusColors.heroMid,
                      ArusColors.primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: ArusColors.primary.withValues(alpha: 0.24),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.plus,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
