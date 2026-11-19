import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/providers/core_providers.dart';
import '../core/providers/service_providers.dart';
import '../core/widgets/app_lock_gate.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class ArusApp extends ConsumerStatefulWidget {
  const ArusApp({
    super.key,
    this.enableBackgroundServices = true,
  });

  final bool enableBackgroundServices;

  @override
  ConsumerState<ArusApp> createState() => _ArusAppState();
}

class _ArusAppState extends ConsumerState<ArusApp> {
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableBackgroundServices) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initBackgroundServices());
    }
  }

  Future<void> _initBackgroundServices() async {
    if (_servicesInitialized) return;
    _servicesInitialized = true;

    final router = ref.read(appRouterProvider);
    final localNotif = ref.read(localNotificationServiceProvider);
    await localNotif.initialize(
      onTap: (deepLink) {
        if (deepLink != null && deepLink.isNotEmpty) {
          router.push(deepLink);
        }
      },
    );

    await ref.read(nativeBridgeServiceProvider).initialize(
      onNavigateRoute: (route) {
        if (route.isNotEmpty) router.push(route);
      },
      onSharedText: (sharedText) {
        router.push(
          Uri(
            path: '/ai/quick-expense',
            queryParameters: {'text': sharedText},
          ).toString(),
        );
      },
      onSharedImage: (imagePath) {
        router.push(
          Uri(
            path: '/ai/receipt-scanner',
            queryParameters: {'path': imagePath},
          ).toString(),
        );
      },
      onSmartInboxChanged: () {
        if (mounted) {
          ref.read(smartInboxRevisionProvider.notifier).state++;
        }
      },
    );

    AppSettingRecord? settings;
    try {
      settings = await ref.read(appSettingsProvider.future);
    } catch (_) {
      settings = null;
    }
    if (settings != null) {
      await localNotif.scheduleDailyReminder(
        hour: settings.dailyReminderHour,
        minute: settings.dailyReminderMinute,
        enabled: settings.localNotificationsEnabled,
      );
      await ref.read(fcmServiceProvider).initialize(enabled: settings.fcmEnabled);
    }
  }

  void _syncAndroidHomeWidget() {
    if (!widget.enableBackgroundServices) return;
    final sts = ref.read(safeToSpendProvider).valueOrNull;
    if (sts == null) return;
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final txs = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    var todayExpense = 0;
    for (final tx in txs) {
      if (tx.occurredAt.year == now.year &&
          tx.occurredAt.month == now.month &&
          tx.occurredAt.day == now.day) {
        if (tx.type == 'expense') todayExpense += tx.amount;
        if (tx.type == 'refund') todayExpense -= tx.amount;
      }
    }
    if (todayExpense < 0) todayExpense = 0;
    ref.read(nativeBridgeServiceProvider).syncHomeWidget(
          sts: sts,
          todayExpense: todayExpense,
          privacyMode: settings?.privacyMode ?? false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    ref.listen(safeToSpendProvider, (_, _) => _syncAndroidHomeWidget());
    ref.listen(transactionsStreamProvider, (_, _) => _syncAndroidHomeWidget());
    ref.listen(appSettingsProvider, (_, _) => _syncAndroidHomeWidget());

    final themeMode = switch (settings?.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'Lanjo',
      debugShowCheckedModeBanner: false,
      theme: ArusTheme.light(),
      darkTheme: ArusTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        final content = AppLockGate(child: child ?? const SizedBox.shrink());
        if (!kIsWeb) return content;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                elevation: 8,
                clipBehavior: Clip.antiAlias,
                borderRadius: MediaQuery.sizeOf(context).width > 500
                    ? BorderRadius.circular(24)
                    : BorderRadius.zero,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}
