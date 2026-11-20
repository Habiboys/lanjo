import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import 'lanjo_ui.dart';

/// Center `Catat (+)` action bottom sheet with Bento primary actions & grouped AI shortcuts.
class CatatBottomSheet extends ConsumerWidget {
  const CatatBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LanjoSheetHeader(
                title: 'Catat Transaksi',
                subtitle: 'Pilih cara tercepat untuk mencatat',
              ),
              const SizedBox(height: 16),
              // Primary Bento Trio
              Row(
                children: [
                  Expanded(
                    child: _PrimaryActionTile(
                      icon: LucideIcons.arrowUpRight,
                      label: 'Pengeluaran',
                      color: ArusColors.expense,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/transactions/new?type=expense');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PrimaryActionTile(
                      icon: LucideIcons.arrowDownLeft,
                      label: 'Pemasukan',
                      color: ArusColors.income,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/transactions/new?type=income');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PrimaryActionTile(
                      icon: LucideIcons.arrowLeftRight,
                      label: 'Transfer',
                      color: ArusColors.transfer,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/transactions/new?type=transfer');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  'INPUT CERDAS & FAVORIT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              LanjoSurface(
                child: Column(
                  children: [
                    _QuickRow(
                      icon: LucideIcons.sparkles,
                      color: context.lanjoPrimary,
                      title: 'Catat dengan AI',
                      subtitle: 'Ketik kalimat bebas: "Makan 25rb pakai BCA"',
                      badge: 'AI',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/ai/quick-expense');
                      },
                    ),
                    const Divider(indent: 64),
                    _QuickRow(
                      icon: LucideIcons.scanLine,
                      color: const Color(0xFF7C3AED),
                      title: 'Scan Struk',
                      subtitle: 'Ekstrak otomatis dari foto struk / bukti bayar',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/ai/receipt-scanner');
                      },
                    ),
                    const Divider(indent: 64),
                    _QuickRow(
                      icon: LucideIcons.mic,
                      color: ArusColors.primaryLight,
                      title: 'Input Suara',
                      subtitle: 'Ucapkan transaksi lalu tinjau sebelum simpan',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/ai/quick-expense?voice=1');
                      },
                    ),
                    const Divider(indent: 64),
                    _QuickRow(
                      icon: LucideIcons.zap,
                      color: ArusColors.warning,
                      title: 'Transaksi Favorit',
                      subtitle: 'Gunakan template 1-ketuk yang sudah disimpan',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/transactions/templates');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionTile extends StatelessWidget {
  const _PrimaryActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      color: color.withValues(alpha: isDark ? 0.14 : 0.07),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.25 : 0.16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 19),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            LanjoIconBox(icon: icon, color: color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        LanjoPillBadge(label: badge!, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: context.lanjoSubtle,
            ),
          ],
        ),
      ),
    );
  }
}
