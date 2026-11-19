import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Dedicated configuration and testing hub for Android native features:
/// Home Screen Widget, Smart Notification Auto-Detector, Quick Settings Tile,
/// Launcher App Shortcuts, and Share Target.
class AndroidNativeSettingsPage extends ConsumerStatefulWidget {
  const AndroidNativeSettingsPage({super.key});

  @override
  ConsumerState<AndroidNativeSettingsPage> createState() =>
      _AndroidNativeSettingsPageState();
}

class _AndroidNativeSettingsPageState
    extends ConsumerState<AndroidNativeSettingsPage>
    with WidgetsBindingObserver {
  bool _listenerGranted = false;
  bool _autoDetectEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final bridge = ref.read(nativeBridgeServiceProvider);
    final granted = await bridge.isNotificationListenerEnabled();
    final enabled = await bridge.getAutoDetectEnabled();
    if (!mounted) return;
    setState(() {
      _listenerGranted = granted;
      _autoDetectEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _syncWidgetNow() async {
    final sts = await ref.read(safeToSpendProvider.future);
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final txs = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    var todayExp = 0;
    for (final tx in txs) {
      if (tx.occurredAt.year == now.year &&
          tx.occurredAt.month == now.month &&
          tx.occurredAt.day == now.day) {
        if (tx.type == 'expense') todayExp += tx.amount;
        if (tx.type == 'refund') todayExp -= tx.amount;
      }
    }
    if (todayExp < 0) todayExp = 0;

    await ref.read(nativeBridgeServiceProvider).syncHomeWidget(
          sts: sts,
          todayExpense: todayExp,
          privacyMode: settings?.privacyMode ?? false,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Widget Home Screen Android berhasil disinkronkan.'),
      ),
    );
  }

  Future<void> _simulateNotification({
    required String app,
    required String title,
    required String body,
  }) async {
    final item = await ref
        .read(nativeBridgeServiceProvider)
        .simulateBankNotification(app: app, title: title, body: body);
    ref.read(smartInboxRevisionProvider.notifier).state++;
    if (!mounted) return;
    if (item != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Terdeteksi: ${item.sourceApp} (${MoneyFormatter.format(item.amount)}) → Masuk ke Smart Inbox Beranda',
          ),
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => context.go('/home'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sts = ref.watch(safeToSpendProvider).valueOrNull;
    final hidden =
        ref.watch(appSettingsProvider).valueOrNull?.privacyMode ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Fitur Pintar Android & Widget')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          // 1. Home Screen Widget Preview & Sync
          Text(
            '1. HOME SCREEN WIDGET ANDROID',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ArusColors.heroDeep,
                  ArusColors.heroMid,
                  ArusColors.heroEnd,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/images/lanjo_icon.png',
                        width: 18,
                        height: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AMAN DIBELANJAKAN / HARI',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${sts?.remainingDays ?? 14} hari lagi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  MoneyFormatter.format(
                    sts?.dailySafeSpend ?? 0,
                    hidden: hidden,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kas Likuid: ${MoneyFormatter.formatCompact(sts?.spendableLiquidBalance ?? 0, hidden: hidden)} • 4 tombol pintas aktif',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LanjoSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cara Pasang Widget di Layar Utama HP',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tekan-tahan area kosong di Home Screen Android → pilih menu Widget → cari "Lanjo Safe-to-Spend" → tarik ke layar utama.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _syncWidgetNow,
                    icon: const Icon(LucideIcons.repeat, size: 16),
                    label: const Text('Sinkronkan Data Widget Sekarang'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 2. Smart Notification Auto-Detector
          Text(
            '2. DETEKSI OTOMATIS NOTIFIKASI BANK & E-WALLET',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Deteksi Otomatis Transaksi (100% Offline)',
                  ),
                  subtitle: const Text(
                    'Baca notifikasi pembayaran BCA, Livin\', BRImo, BNI, Jago, SeaBank, GoPay, OVO, DANA, ShopeePay & QRIS secara lokal di perangkat.',
                  ),
                  value: _autoDetectEnabled,
                  onChanged: (v) async {
                    setState(() => _autoDetectEnabled = v);
                    await ref
                        .read(nativeBridgeServiceProvider)
                        .setAutoDetectEnabled(v);
                  },
                ),
                const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _listenerGranted
                                ? LucideIcons.circleCheck
                                : LucideIcons.shieldAlert,
                            size: 18,
                            color: _listenerGranted
                                ? ArusColors.income
                                : ArusColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _loading
                                  ? 'Memeriksa status izin Android...'
                                  : (_listenerGranted
                                      ? 'Izin Akses Notifikasi Android: Aktif'
                                      : 'Izin Akses Notifikasi belum diaktifkan di Pengaturan Android'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: _listenerGranted
                                    ? ArusColors.income
                                    : ArusColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(nativeBridgeServiceProvider)
                                .openNotificationListenerSettings();
                          },
                          icon: const Icon(LucideIcons.shieldCheck, size: 17),
                          label: const Text(
                            'Buka Pengaturan Izin Akses Notifikasi',
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Uji Coba Simulasi Deteksi Otomatis (1-Ketuk):',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: context.lanjoInk,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _simulateNotification(
                              app: 'com.gojek.app',
                              title: 'Pembayaran QRIS GoPay Berhasil',
                              body:
                                  'Kamu berhasil membayar Rp28.500 di Kopi Kenangan menggunakan GoPay.',
                            ),
                            icon: const Icon(LucideIcons.zap, size: 15),
                            label: const Text('Simulasi QRIS Rp28,5rb'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _simulateNotification(
                              app: 'com.bca',
                              title: 'BCA mobile - Transfer Berhasil',
                              body:
                                  'Transfer Rp150.000 ke Tokopedia berhasil diproses.',
                            ),
                            icon: const Icon(LucideIcons.landmark, size: 15),
                            label: const Text('Simulasi BCA Rp150rb'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _simulateNotification(
                              app: 'id.bmri.livin',
                              title: 'Livin\' by Mandiri - Uang Masuk',
                              body:
                                  'Transfer masuk diterima sebesar Rp1.250.000 dari Klien Proyek.',
                            ),
                            icon: const Icon(
                              LucideIcons.arrowDownLeft,
                              size: 15,
                            ),
                            label: const Text('Simulasi Masuk Rp1,25jt'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 3. Share Target, Quick Settings Tile & App Shortcuts
          Text(
            '3. PINTASAN SISTEM ANDROID LAINNYA',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          const LanjoSurface(
            child: Column(
              children: [
                _FeatureGuideRow(
                  icon: LucideIcons.share2,
                  color: ArusColors.primary,
                  title: 'Share Bukti Transfer / Teks Mutasi ke Lanjo',
                  subtitle:
                      'Selesai transfer di m-Banking / e-Wallet, ketuk tombol "Bagikan (Share)" → pilih Lanjo. Gambar struk otomatis masuk ke Scanner AI, teks otomatis masuk ke Catat Cepat AI.',
                ),
                Divider(indent: 66),
                _FeatureGuideRow(
                  icon: LucideIcons.zap,
                  color: ArusColors.warning,
                  title: 'Quick Settings Tile ("Catat Lanjo")',
                  subtitle:
                      'Tarik panel notifikasi atas Android → ketuk ikon Pensil (Edit Tile) → tambahkan tombol "Catat Lanjo" di sebelah Wi-Fi/Senter untuk akses 1 detik kapan saja.',
                ),
                Divider(indent: 66),
                _FeatureGuideRow(
                  icon: LucideIcons.layers,
                  color: ArusColors.transfer,
                  title: 'Launcher Long-Press Shortcuts',
                  subtitle:
                      'Tekan-tahan ikon aplikasi Lanjo di layar HP untuk memunculkan 4 menu instan: Catat Keluar, Catat via AI, Scan Struk, dan Input Suara.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGuideRow extends StatelessWidget {
  const _FeatureGuideRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LanjoIconBox(icon: icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
