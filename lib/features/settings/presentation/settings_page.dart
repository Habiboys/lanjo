import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Settings Hub covering all local profile, wallet, category, AI, notification,
/// appearance, security, import/export, and backup subpages.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _editProfileDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettingRecord settings,
  ) async {
    final nameCtrl = TextEditingController(text: settings.nickname ?? '');
    final salaryCtrl = TextEditingController(
      text: settings.monthlySalary?.toString() ?? '',
    );
    int? payday = settings.paydayDay;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Profil & Periode Keuangan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama panggilan'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: payday,
                  decoration: const InputDecoration(labelText: 'Tanggal gajian'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Akhir bulan kalender'),
                    ),
                    for (var d = 1; d <= 31; d++)
                      DropdownMenuItem<int?>(
                        value: d,
                        child: Text('Tanggal $d'),
                      ),
                  ],
                  onChanged: (v) => setState(() => payday = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Estimasi besar gaji bulanan (Rp)',
                    hintText: 'Contoh: 5000000',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final db = ref.read(appDatabaseProvider);
                final salaryVal = int.tryParse(salaryCtrl.text.trim());
                await (db.update(db.appSettings)
                      ..where((s) => s.id.equals('default')))
                    .write(
                  AppSettingsCompanion(
                    nickname: Value(
                      nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                    ),
                    paydayDay: Value(payday),
                    monthlySalary: Value(
                      (salaryVal != null && salaryVal > 0) ? salaryVal : null,
                    ),
                    updatedAt: Value(DateTime.now()),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final aiProvider = ref.watch(aiProviderTypeProvider).valueOrNull;
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
        children: [
          if (settings != null) ...[
            _GroupLabel('UMUM & TAMPILAN', theme),
            LanjoSurface(
              child: Column(
                children: [
                  _SettingsRow(
                    icon: LucideIcons.user,
                    color: ArusColors.primary,
                    title: 'Profil & Periode Keuangan',
                    subtitle:
                        '${settings.nickname ?? 'Pengguna Lanjo'} • Gajian: ${settings.paydayDay != null ? 'Tgl ${settings.paydayDay}' : 'Akhir bulan'}'
                        '${settings.monthlySalary != null ? ' (${MoneyFormatter.formatCompact(settings.monthlySalary!)})' : ''}',
                    onTap: () => _editProfileDialog(context, ref, settings),
                  ),
                  const Divider(indent: 66),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        LanjoIconBox(
                          icon: context.isDark ? LucideIcons.moon : LucideIcons.sun,
                          color: ArusColors.warning,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tampilan (Theme)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.lanjoSurfaceSecondary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButton<String>(
                            value: settings.themeMode,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(value: 'system', child: Text('Sistem')),
                              DropdownMenuItem(value: 'light', child: Text('Terang')),
                              DropdownMenuItem(value: 'dark', child: Text('Gelap')),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              await (db.update(db.appSettings)
                                    ..where((s) => s.id.equals('default')))
                                  .write(
                                AppSettingsCompanion(
                                  themeMode: Value(v),
                                  updatedAt: Value(DateTime.now()),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          _GroupLabel('DOMPET & KATEGORI', theme),
          LanjoSurface(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.wallet,
                  color: ArusColors.income,
                  title: 'Dompet & Rekening',
                  subtitle: 'Kelola dompet, default, dan rekonsiliasi saldo',
                  onTap: () => context.push('/settings/wallets'),
                ),
                const Divider(indent: 66),
                _SettingsRow(
                  icon: LucideIcons.shapes,
                  color: ArusColors.transfer,
                  title: 'Kategori Transaksi',
                  subtitle: 'Tambah, edit, arsip, dan gabung kategori',
                  onTap: () => context.push('/settings/categories'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _GroupLabel('KECERDASAN & KEAMANAN', theme),
          LanjoSurface(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.smartphone,
                  color: ArusColors.primaryLight,
                  title: 'Fitur Pintar Android & Widget',
                  subtitle:
                      'Home Screen Widget, Deteksi Otomatis Notifikasi Bank, Quick Tile & Share Struk',
                  onTap: () => context.push('/settings/android-native'),
                ),
                const Divider(indent: 66),
                _SettingsRow(
                  icon: LucideIcons.sparkles,
                  color: ArusColors.primary,
                  title: 'Asisten AI (Gemini / OpenCode BYOK)',
                  subtitle: settings?.aiEnabled == true
                      ? 'Aktif • ${aiProvider?.shortLabel ?? 'AI'} • ${settings?.aiModel ?? 'Model belum dipilih'}'
                      : 'Nonaktif (opsional)',
                  onTap: () => context.push('/settings/ai'),
                ),
                const Divider(indent: 66),
                _SettingsRow(
                  icon: LucideIcons.bell,
                  color: ArusColors.warning,
                  title: 'Notifikasi Lokal & FCM',
                  subtitle: 'Pengingat harian, jam tenang, push opsional',
                  onTap: () => context.push('/settings/notifications'),
                ),
                const Divider(indent: 66),
                _SettingsRow(
                  icon: LucideIcons.lock,
                  color: ArusColors.expense,
                  title: 'Keamanan & Kunci Aplikasi',
                  subtitle: 'PIN, Biometrik, dan Auto-lock',
                  onTap: () => context.push('/settings/security'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _GroupLabel('DATA & CADANGAN', theme),
          LanjoSurface(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.fileSpreadsheet,
                  color: ArusColors.transfer,
                  title: 'Import & Export (CSV / Excel / PDF)',
                  subtitle: 'Impor mutasi dengan preview & rollback',
                  onTap: () => context.push('/settings/import-export'),
                ),
                const Divider(indent: 66),
                _SettingsRow(
                  icon: LucideIcons.shieldCheck,
                  color: ArusColors.income,
                  title: 'Backup & Restore Terenkripsi',
                  subtitle: 'File .arusbackup terenkripsi tanpa API Key/PIN',
                  onTap: () => context.push('/settings/backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _GroupLabel('TENTANG APLIKASI', theme),
          LanjoSurface(
            onTap: () async {
              final check =
                  await ref.read(ledgerEngineProvider).verifyLedgerIntegrity();
              if (!context.mounted) return;
              showAboutDialog(
                context: context,
                applicationName: 'Lanjo',
                applicationVersion: '1.0.0',
                applicationIcon: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/lanjo_icon.png',
                    width: 48,
                    height: 48,
                  ),
                ),
                children: [
                  const Text(
                    'Lanjo — Personal Finance & Smart Money Assistant.\n\n'
                    'Seluruh data transaksi disimpan di SQLite lokal tanpa server cloud.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Status Ledger: ${check.isBalanced ? 'Seimbang ✅' : 'Perlu cek ⚠️'} '
                    '(${check.checkedTransactions} transaksi, ${check.checkedAccounts} akun)',
                  ),
                ],
              );
            },
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'assets/images/lanjo_icon.png',
                    width: 40,
                    height: 40,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tentang Lanjo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Versi 1.0 • Local-First, Offline-First • Ketuk untuk cek integritas ledger.',
                        style: theme.textTheme.bodySmall,
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
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, this.theme);
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
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
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
