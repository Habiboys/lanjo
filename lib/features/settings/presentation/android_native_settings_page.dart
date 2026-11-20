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
/// Home Screen Widget, Runtime Device Permissions (Notifications, Camera,
/// Photos, Microphone), Clipboard/Share Bank Auto-Detector, Quick Settings Tile,
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
  Map<String, bool> _permStatuses = const {};
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
    final perms = await bridge.getPermissionStatuses();
    final enabled = await bridge.getAutoDetectEnabled();
    if (!mounted) return;
    setState(() {
      _permStatuses = perms;
      _autoDetectEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _requestPerm(String key) async {
    final bridge = ref.read(nativeBridgeServiceProvider);
    final granted = await bridge.requestPermission(key);
    await _refreshStatus();
    if (!mounted) return;
    if (!granted && key != 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Izin belum diberikan. Anda dapat mengaktifkannya manual lewat Setelan Aplikasi Android.',
          ),
          action: SnackBarAction(
            label: 'Buka Setelan',
            onPressed: bridge.openAppSettings,
          ),
        ),
      );
    }
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

  Future<void> _checkClipboardNow() async {
    final item = await ref
        .read(nativeBridgeServiceProvider)
        .scanClipboardForBankTransaction(force: true);
    if (!mounted) return;
    if (item != null) {
      ref.read(smartInboxRevisionProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Terdeteksi dari clipboard: ${item.sourceApp} (${MoneyFormatter.format(item.amount)})',
          ),
          action: SnackBarAction(
            label: 'Lihat Beranda',
            onPressed: () => context.go('/home'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak ada teks notifikasi/mutasi bank ber-nominal Rupiah di clipboard saat ini.',
          ),
        ),
      );
    }
  }

  Future<void> _showManualPasteDialog() async {
    final ctrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tempel SMS / Notifikasi Bank'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText:
                'Contoh: Pembayaran QRIS GoPay sebesar Rp35.000 di Indomaret berhasil.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Deteksi & Masuk Inbox'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty) return;

    final item = await ref.read(nativeBridgeServiceProvider).enqueueFinancialText(
          title: 'Tempel Notifikasi Bank',
          body: submitted,
        );
    if (!mounted) return;
    if (item != null) {
      ref.read(smartInboxRevisionProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Terdeteksi: ${item.sourceApp} (${MoneyFormatter.format(item.amount)}) → Smart Inbox Beranda',
          ),
          action: SnackBarAction(
            label: 'Buka Beranda',
            onPressed: () => context.go('/home'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nominal Rupiah (contoh: Rp25.000) tidak ditemukan di teks tersebut.'),
        ),
      );
    }
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

    final notifOk = _permStatuses['notifications'] ?? false;
    final cameraOk = _permStatuses['camera'] ?? false;
    final photosOk = _permStatuses['photos'] ?? false;
    final micOk = _permStatuses['microphone'] ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Fitur Pintar Android & Izin')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          // 1. Android Runtime Permissions Hub
          Text(
            '1. IZIN AKSES PERANGKAT ANDROID',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            child: Column(
              children: [
                _PermissionTile(
                  icon: LucideIcons.bell,
                  color: ArusColors.warning,
                  title: 'Notifikasi Pengingat & Tagihan',
                  subtitle: 'Diperlukan agar pengingat harian & jatuh tempo muncul di Android 13+',
                  granted: notifOk,
                  loading: _loading,
                  onRequest: () => _requestPerm('notifications'),
                ),
                const Divider(indent: 66),
                _PermissionTile(
                  icon: LucideIcons.camera,
                  color: ArusColors.primary,
                  title: 'Kamera (Foto Struk)',
                  subtitle: 'Memotret struk belanja langsung untuk di-scan AI',
                  granted: cameraOk,
                  loading: _loading,
                  onRequest: () => _requestPerm('camera'),
                ),
                const Divider(indent: 66),
                _PermissionTile(
                  icon: LucideIcons.image,
                  color: ArusColors.transfer,
                  title: 'Galeri & Foto',
                  subtitle: 'Memilih foto struk / lampiran bukti transaksi',
                  granted: photosOk,
                  loading: _loading,
                  onRequest: () => _requestPerm('photos'),
                ),
                const Divider(indent: 66),
                _PermissionTile(
                  icon: LucideIcons.mic,
                  color: ArusColors.income,
                  title: 'Mikrofon (Input Suara)',
                  subtitle: 'Mencatat transaksi lewat perintah suara',
                  granted: micOk,
                  loading: _loading,
                  onRequest: () => _requestPerm('microphone'),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _requestPerm('all'),
                          icon: const Icon(LucideIcons.shieldCheck, size: 17),
                          label: const Text('Minta Semua Izin'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(nativeBridgeServiceProvider)
                            .openAppSettings(),
                        icon: const Icon(LucideIcons.settings, size: 16),
                        label: const Text('Info App'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 2. Smart Auto-Detector (Clipboard + Share + Simulator)
          Text(
            '2. DETEKSI OTOMATIS TRANSAKSI BANK & E-WALLET',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Auto-Deteksi Clipboard & Share Mutasi (100% Offline)',
                  ),
                  subtitle: const Text(
                    'Saat kamu menyalin SMS/notifikasi BCA, Livin\', BRImo, BNI, Jago, SeaBank, GoPay, OVO, DANA, ShopeePay atau Share ke Lanjo, nominal otomatis masuk ke Smart Inbox Beranda.',
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
                          const Icon(
                            LucideIcons.info,
                            size: 17,
                            color: ArusColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mode Aman Sideload: pakai Copy/Clipboard atau Bagikan (Share) agar APK selalu lolos instalasi di Xiaomi/Android 13+.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.lanjoInk,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _checkClipboardNow,
                              icon: const Icon(LucideIcons.copy, size: 16),
                              label: const Text('Cek Clipboard'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showManualPasteDialog,
                              icon: const Icon(LucideIcons.pencil, size: 16),
                              label: const Text('Tempel Teks'),
                            ),
                          ),
                        ],
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

          // 3. Home Screen Widget Preview & Sync
          Text(
            '3. HOME SCREEN WIDGET ANDROID',
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

          // 4. Share Target, Quick Settings Tile & App Shortcuts
          Text(
            '4. PINTASAN SISTEM ANDROID LAINNYA',
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
                      'Selesai transfer di m-Banking / e-Wallet, ketuk tombol "Bagikan (Share)" → pilih Lanjo. Gambar struk otomatis masuk ke Scanner AI, teks masuk ke Smart Inbox & Catat Cepat AI.',
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

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.loading,
    required this.onRequest,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool granted;
  final bool loading;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (granted)
            const LanjoPillBadge(
              label: 'Aktif',
              icon: LucideIcons.check,
              color: ArusColors.income,
            )
          else
            OutlinedButton(
              onPressed: onRequest,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Izinkan', style: TextStyle(fontSize: 12)),
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
