import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lanjo/app/app.dart';
import 'package:lanjo/app/theme/app_theme.dart';
import 'package:lanjo/core/database/app_database.dart';
import 'package:lanjo/core/database/ledger_engine.dart';
import 'package:lanjo/core/native/native_bridge_service.dart';
import 'package:lanjo/core/providers/core_providers.dart';
import 'package:lanjo/core/widgets/catat_bottom_sheet.dart';
import 'package:lanjo/core/widgets/swipe_action_card.dart';
import 'package:lanjo/features/ai_assistant/presentation/ai_quick_expense_page.dart';
import 'package:lanjo/features/dashboard/presentation/dashboard_page.dart';
import 'package:lanjo/features/plans/presentation/plans_hub_page.dart';
import 'package:lanjo/features/settings/presentation/android_native_settings_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  testWidgets('Arus launches into offline onboarding flow on first open',
      (WidgetTester tester) async {
    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.select(db.appSettings).get();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const ArusApp(enableBackgroundServices: false),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Selamat datang di Lanjo'), findsOneWidget);
    expect(find.text('Lanjut'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });

  testWidgets('AiQuickExpense draft row with long category renders without overflow on 320px width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      final ledger = LedgerEngine(db);
      await ledger.createWallet(
        name: 'Dompet Utama Panjang',
        accountType: 'bank',
        icon: 'bank',
        colorValue: 0xFF0F766E,
        openingBalance: 500000,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          home: AiQuickExpensePage(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Catat Cepat dengan AI'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });

  testWidgets('SwipeActionCard reveals Edit and Hapus buttons when swiped left',
      (WidgetTester tester) async {
    var edited = false;
    var deleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SwipeActionCard(
              onEdit: () => edited = true,
              onDelete: () => deleted = true,
              child: const Card(
                margin: EdgeInsets.zero,
                child: ListTile(title: Text('Anggaran Makan')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsNothing);
    await tester.drag(find.text('Anggaran Makan'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Hapus'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);

    await tester.drag(find.text('Anggaran Makan'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('Refactored Dashboard, PlansHub, and CatatBottomSheet render on 320px width without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      final ledger = LedgerEngine(db);
      await ledger.createWallet(
        name: 'Dompet Utama',
        accountType: 'bank',
        icon: 'bank',
        colorValue: 0xFF0D7A6F,
        openingBalance: 1500000,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: ArusTheme.light(),
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.text('Catat Cepat'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: ArusTheme.dark(),
          home: const Scaffold(body: PlansHubPage()),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.text('Rencana Keuangan'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: ArusTheme.light(),
          home: const Scaffold(body: CatatBottomSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Catat Transaksi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });

  testWidgets('Smart Notification parser detects expense & income and renders in Dashboard Smart Inbox & AndroidNativeSettingsPage',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final gopay = NativeBridgeService.parseFinancialNotificationLocal(
      packageName: 'com.gojek.app',
      title: 'Pembayaran QRIS Berhasil',
      body: 'Kamu berhasil membayar Rp28.500 di Kopi Kenangan menggunakan GoPay.',
    );
    expect(gopay, isNotNull);
    expect(gopay!.sourceApp, 'GoPay');
    expect(gopay.amount, 28500);
    expect(gopay.type, 'expense');

    final livinIncome = NativeBridgeService.parseFinancialNotificationLocal(
      packageName: 'id.bmri.livin',
      title: 'Livin by Mandiri',
      body: 'Transfer masuk diterima sebesar Rp1.250.000,00 dari Klien.',
    );
    expect(livinIncome, isNotNull);
    expect(livinIncome!.sourceApp, "Livin' Mandiri");
    expect(livinIncome.amount, 1250000);
    expect(livinIncome.type, 'income');

    late AppDatabase db;
    final bridge = NativeBridgeService(useNativeChannel: false);
    await bridge.simulateBankNotification();

    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      final ledger = LedgerEngine(db);
      await ledger.createWallet(
        name: 'Dompet Utama',
        accountType: 'bank',
        icon: 'bank',
        colorValue: 0xFF0D7A6F,
        openingBalance: 1000000,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          nativeBridgeServiceProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(
          theme: ArusTheme.light(),
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Deteksi Otomatis Notifikasi'), findsOneWidget);
    expect(find.text('Simpan 1-Ketuk'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          nativeBridgeServiceProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(
          theme: ArusTheme.light(),
          home: const AndroidNativeSettingsPage(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.text('Fitur Pintar Android & Izin'), findsOneWidget);
    expect(find.text('Minta Semua Izin'), findsOneWidget);

    final pasted = await bridge.enqueueFinancialText(
      body: 'Transfer Rp75.000 ke PLN via BRImo berhasil.',
    );
    expect(pasted, isNotNull);
    expect(pasted!.amount, 75000);
    expect(pasted.sourceApp, 'BRImo');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });
}
