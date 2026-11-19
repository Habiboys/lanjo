import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/amount_input_field.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Offline-first onboarding without login or registration (FR-01).
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  final _nicknameController = TextEditingController();
  final _salaryController = TextEditingController();
  final _walletNameController = TextEditingController(text: 'Dompet Utama');
  final _balanceController = TextEditingController(text: '0');

  int _step = 0;
  String _currency = 'IDR';
  String _walletType = 'bank';
  int? _paydayDay;
  bool _scheduleSalaryReminder = true;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    _salaryController.dispose();
    _walletNameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_saving) return;
    final walletName = _walletNameController.text.trim();
    if (walletName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama dompet pertamamu.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final ledger = ref.read(ledgerEngineProvider);
      final openingBalance = int.tryParse(_balanceController.text.trim()) ?? 0;
      final salaryVal = int.tryParse(_salaryController.text.trim());
      final monthlySalary =
          (salaryVal != null && salaryVal > 0) ? salaryVal : null;

      final walletId = await ledger.createWallet(
        name: walletName,
        accountType: _walletType,
        icon: _walletType == 'cash'
            ? 'wallet'
            : (_walletType == 'ewallet' ? 'ewallet' : 'bank'),
        colorValue: ArusColors.primary.toARGB32(),
        openingBalance: openingBalance,
        setAsDefault: true,
      );

      await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
          .write(
        AppSettingsCompanion(
          nickname: Value(
            _nicknameController.text.trim().isEmpty
                ? null
                : _nicknameController.text.trim(),
          ),
          baseCurrency: Value(_currency),
          paydayDay: Value(_paydayDay),
          monthlySalary: Value(monthlySalary),
          defaultWalletId: Value(walletId),
          onboardingCompleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (_scheduleSalaryReminder &&
          _paydayDay != null &&
          monthlySalary != null) {
        final period = ArusDateUtils.currentFinancialPeriod(
          paydayDay: _paydayDay,
        );
        await ref.read(billServiceProvider).createBill(
              name: 'Gaji Bulanan',
              kind: 'income',
              estimatedAmount: monthlySalary,
              categoryId: DefaultCategoryIds.salary,
              walletId: walletId,
              frequency: 'monthly',
              firstDueDate: period.endExclusive,
              reminderOffsets: '1,0',
            );
      }

      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan profil: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Minimalist segmented step indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? theme.colorScheme.primary
                                    : context.lanjoBorder,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${_step + 1} / 3',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.lanjoMuted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Step 1: Intro
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                'assets/images/lanjo_icon.png',
                                width: 48,
                                height: 48,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Image.asset(
                              theme.brightness == Brightness.dark
                                  ? 'assets/images/lanjo_wordmark_dark.png'
                                  : 'assets/images/lanjo_wordmark_light.png',
                              height: 26,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Selamat datang di Lanjo',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Pengelola uang harian yang tenang, transparan, dan 100% tersimpan aman di perangkatmu tanpa perlu akun.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: context.lanjoMuted,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const LanjoSurface(
                          child: Column(
                            children: [
                              _BenefitRow(
                                icon: LucideIcons.shieldCheck,
                                color: ArusColors.income,
                                title: 'Offline & Privat Penuh',
                                subtitle:
                                    'Semua data dompet dan catatan tinggal secara lokal di HP-mu.',
                              ),
                              Divider(indent: 66),
                              _BenefitRow(
                                icon: LucideIcons.sparkles,
                                color: ArusColors.primary,
                                title: 'Asisten AI Cerdas',
                                subtitle:
                                    'Catat cepat lewat kalimat bebas, scan struk, atau suara.',
                              ),
                              Divider(indent: 66),
                              _BenefitRow(
                                icon: LucideIcons.walletCards,
                                color: ArusColors.transfer,
                                title: 'Safe-to-Spend Harian',
                                subtitle:
                                    'Tahu persis berapa yang aman dibelanjakan hari ini tanpa stres.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Step 2: Local Profile
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Profil Lokal',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Semua pengaturan ini opsional dan tersimpan di perangkat.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.lanjoMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        LanjoSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _nicknameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nama panggilan (opsional)',
                                  hintText: 'Contoh: Budi',
                                ),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _currency,
                                decoration: const InputDecoration(
                                  labelText: 'Mata uang utama',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'IDR',
                                    child: Text('Rupiah (IDR)'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _currency = v);
                                },
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<int?>(
                                isExpanded: true,
                                initialValue: _paydayDay,
                                decoration: const InputDecoration(
                                  labelText: 'Tanggal gajian (opsional)',
                                  helperText:
                                      'Untuk menghitung Safe-to-Spend sampai gajian berikutnya.',
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Lewati (ikuti akhir bulan)'),
                                  ),
                                  for (var d = 1; d <= 31; d++)
                                    DropdownMenuItem<int?>(
                                      value: d,
                                      child: Text('Setiap tanggal $d'),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _paydayDay = v),
                              ),
                              const SizedBox(height: 14),
                              AmountInputField(
                                controller: _salaryController,
                                label: 'Estimasi besar gaji bulanan (opsional)',
                                quickAmounts: const [
                                  1000000,
                                  3000000,
                                  5000000,
                                  10000000,
                                ],
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Dipakai untuk pengingat jadwal gaji masuk di Salary Day (bukan tagihan) & preset pembagian gaji. Tidak otomatis menambah saldo sebelum gaji benar-benar masuk.',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (_paydayDay != null &&
                                  (int.tryParse(_salaryController.text.trim()) ??
                                          0) >
                                      0) ...[
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Jadwalkan pengingat gajian bulanan',
                                  ),
                                  value: _scheduleSalaryReminder,
                                  onChanged: (v) => setState(
                                    () => _scheduleSalaryReminder = v,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Step 3: First Wallet & Opening Balance
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Dompet Pertama',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Saldo awal dicatat sebagai modal awal, bukan pemasukan bulanan.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.lanjoMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        LanjoSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _walletNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nama dompet',
                                  hintText: 'Contoh: BCA, Tunai, GoPay',
                                ),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _walletType,
                                decoration: const InputDecoration(
                                  labelText: 'Jenis dompet',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'bank',
                                    child: Text('Rekening Bank'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'cash',
                                    child: Text('Uang Tunai'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ewallet',
                                    child: Text('E-Wallet'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'savings',
                                    child: Text('Tabungan'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _walletType = v);
                                },
                              ),
                              const SizedBox(height: 16),
                              AmountInputField(
                                controller: _balanceController,
                                label: 'Saldo awal saat ini',
                                quickAmounts: const [
                                  100000,
                                  500000,
                                  1000000,
                                  5000000,
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: context.lanjoCard,
                border: Border(top: BorderSide(color: context.lanjoBorder)),
              ),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _step--);
                        _pageController.animateToPage(
                          _step,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: const Text('Kembali'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (_step < 2) {
                              setState(() => _step++);
                              _pageController.animateToPage(
                                _step,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                              );
                            } else {
                              _complete();
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_step < 2 ? 'Lanjut' : 'Mulai Pakai Lanjo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                const SizedBox(height: 2),
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
