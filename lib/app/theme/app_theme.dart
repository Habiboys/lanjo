import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Core brand and semantic design tokens for Lanjo.
/// Derived directly from the Lanjo mark: Charcoal Obsidian ink paired with
/// Deep Teal-Emerald accents on architectural Porcelain surfaces.
abstract final class ArusColors {
  static const String fontFamily = 'PlusJakartaSans';

  // Brand accents
  static const Color primary = Color(0xFF0D7A6F); // Deep Teal
  static const Color primaryLight = Color(0xFF10B981); // Vibrant Emerald
  static const Color primaryVibrant = Color(0xFF00C853); // Logo Emerald Dot
  static const Color heroDeep = Color(0xFF0B2A2B); // Obsidian Teal
  static const Color heroMid = Color(0xFF0B524D);
  static const Color heroEnd = Color(0xFF0F766E);

  // Semantic accents (refined, controlled saturation)
  static const Color income = Color(0xFF059669); // Emerald 600
  static const Color expense = Color(0xFFE11D48); // Rose 600
  static const Color warning = Color(0xFFD97706); // Amber 600
  static const Color transfer = Color(0xFF4F46E5); // Indigo 600

  // Neutral architectural surfaces — Light
  static const Color neutralSurfaceLight = Color(0xFFF7F8FA);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color surfaceSecondaryLight = Color(0xFFF0F2F5);
  static const Color borderLight = Color(0xFFE5E8ED);
  static const Color inkLight = Color(0xFF11181C);
  static const Color mutedLight = Color(0xFF687076);
  static const Color subtleLight = Color(0xFF889096);

  // Neutral architectural surfaces — Dark
  static const Color neutralSurfaceDark = Color(0xFF0A0E12);
  static const Color cardDark = Color(0xFF121820);
  static const Color surfaceSecondaryDark = Color(0xFF1A222D);
  static const Color borderDark = Color(0x14FFFFFF);
  static const Color inkDark = Color(0xFFF8FAFC);
  static const Color mutedDark = Color(0xFF94A3B8);
  static const Color subtleDark = Color(0xFF64748B);
}

/// Extension on [BuildContext] for quick access to adaptive minimalist tokens.
extension LanjoThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get lanjoBg =>
      isDark ? ArusColors.neutralSurfaceDark : ArusColors.neutralSurfaceLight;
  Color get lanjoCard => isDark ? ArusColors.cardDark : ArusColors.cardLight;
  Color get lanjoSurfaceSecondary => isDark
      ? ArusColors.surfaceSecondaryDark
      : ArusColors.surfaceSecondaryLight;
  Color get lanjoBorder =>
      isDark ? ArusColors.borderDark : ArusColors.borderLight;
  Color get lanjoInk => isDark ? ArusColors.inkDark : ArusColors.inkLight;
  Color get lanjoMuted =>
      isDark ? ArusColors.mutedDark : ArusColors.mutedLight;
  Color get lanjoSubtle =>
      isDark ? ArusColors.subtleDark : ArusColors.subtleLight;
}

abstract final class ArusTheme {
  static TextTheme _buildTextTheme(Color ink, Color muted) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.15,
        color: ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.2,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.25,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.3,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.05,
        height: 1.45,
        color: ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      labelMedium: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontFamily: ArusColors.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: muted,
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: ArusColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE6F4F1),
      onPrimaryContainer: Color(0xFF064E46),
      secondary: Color(0xFF182226),
      onSecondary: Colors.white,
      secondaryContainer: ArusColors.surfaceSecondaryLight,
      onSecondaryContainer: ArusColors.inkLight,
      tertiary: ArusColors.transfer,
      onTertiary: Colors.white,
      error: ArusColors.expense,
      onError: Colors.white,
      errorContainer: Color(0xFFFFE4E6),
      onErrorContainer: Color(0xFF881337),
      surface: ArusColors.neutralSurfaceLight,
      onSurface: ArusColors.inkLight,
      surfaceContainerLowest: ArusColors.cardLight,
      surfaceContainerLow: Color(0xFFFAFBFC),
      surfaceContainer: ArusColors.cardLight,
      surfaceContainerHigh: ArusColors.surfaceSecondaryLight,
      surfaceContainerHighest: Color(0xFFE8ECEF),
      onSurfaceVariant: ArusColors.mutedLight,
      outline: Color(0xFFD0D7DE),
      outlineVariant: ArusColors.borderLight,
    );

    final textTheme = _buildTextTheme(ArusColors.inkLight, ArusColors.mutedLight);

    return ThemeData(
      useMaterial3: true,
      fontFamily: ArusColors.fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: ArusColors.neutralSurfaceLight,
      dividerColor: ArusColors.borderLight,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: ArusColors.neutralSurfaceLight,
        foregroundColor: ArusColors.inkLight,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: ArusColors.inkLight, size: 21),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: ArusColors.cardLight,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: ArusColors.borderLight, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ArusColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 10,
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 14.5),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(fontSize: 12.5),
        iconColor: ArusColors.inkLight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ArusColors.surfaceSecondaryLight.withValues(alpha: 0.72),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(
          color: ArusColors.subtleLight,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: ArusColors.mutedLight,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ArusColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ArusColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ArusColors.expense),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF141D21),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ArusColors.inkLight,
          backgroundColor: ArusColors.cardLight,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: ArusColors.borderLight),
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ArusColors.primary,
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ArusColors.cardLight,
        selectedColor: const Color(0xFF141D21),
        disabledColor: ArusColors.surfaceSecondaryLight,
        labelStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ArusColors.inkLight,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: const BorderSide(color: ArusColors.borderLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ArusColors.cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: ArusColors.borderLight),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ArusColors.cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF141D21),
        contentTextStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ArusColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return ArusColors.primary;
          return const Color(0xFFD5DCE2);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF141D21);
            }
            return ArusColors.cardLight;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return ArusColors.inkLight;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: ArusColors.borderLight),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ArusColors.primaryLight,
      onPrimary: Color(0xFF042219),
      primaryContainer: Color(0xFF0D332D),
      onPrimaryContainer: Color(0xFF8CE9CD),
      secondary: ArusColors.inkDark,
      onSecondary: Color(0xFF0A0E12),
      secondaryContainer: ArusColors.surfaceSecondaryDark,
      onSecondaryContainer: ArusColors.inkDark,
      tertiary: Color(0xFF818CF8),
      onTertiary: Color(0xFF0A0E12),
      error: Color(0xFFFB7185),
      onError: Color(0xFF4C0519),
      errorContainer: Color(0xFF4C0519),
      onErrorContainer: Color(0xFFFFCCD5),
      surface: ArusColors.neutralSurfaceDark,
      onSurface: ArusColors.inkDark,
      surfaceContainerLowest: Color(0xFF070A0D),
      surfaceContainerLow: ArusColors.cardDark,
      surfaceContainer: ArusColors.cardDark,
      surfaceContainerHigh: ArusColors.surfaceSecondaryDark,
      surfaceContainerHighest: Color(0xFF232E3B),
      onSurfaceVariant: ArusColors.mutedDark,
      outline: Color(0xFF2B3543),
      outlineVariant: ArusColors.borderDark,
    );

    final textTheme = _buildTextTheme(ArusColors.inkDark, ArusColors.mutedDark);

    return ThemeData(
      useMaterial3: true,
      fontFamily: ArusColors.fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: ArusColors.neutralSurfaceDark,
      dividerColor: ArusColors.borderDark,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: ArusColors.neutralSurfaceDark,
        foregroundColor: ArusColors.inkDark,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: ArusColors.inkDark, size: 21),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: ArusColors.cardDark,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: ArusColors.borderDark, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ArusColors.borderDark,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 10,
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 14.5),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(fontSize: 12.5),
        iconColor: ArusColors.inkDark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ArusColors.surfaceSecondaryDark.withValues(alpha: 0.72),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(
          color: ArusColors.subtleDark,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: ArusColors.mutedDark,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ArusColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ArusColors.primaryLight, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ArusColors.primaryLight,
          foregroundColor: const Color(0xFF041C14),
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ArusColors.inkDark,
          backgroundColor: ArusColors.cardDark,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: ArusColors.borderDark),
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ArusColors.primaryLight,
          textStyle: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ArusColors.cardDark,
        selectedColor: ArusColors.primaryLight,
        labelStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ArusColors.inkDark,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF041C14),
        ),
        checkmarkColor: const Color(0xFF041C14),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: const BorderSide(color: ArusColors.borderDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ArusColors.cardDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: ArusColors.borderDark),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ArusColors.cardDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ArusColors.surfaceSecondaryDark,
        contentTextStyle: const TextStyle(
          fontFamily: ArusColors.fontFamily,
          color: ArusColors.inkDark,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ArusColors.borderDark),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ArusColors.primaryLight,
        foregroundColor: const Color(0xFF041C14),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return ArusColors.primaryLight;
            }
            return ArusColors.cardDark;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF041C14);
            }
            return ArusColors.inkDark;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: ArusColors.borderDark),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}

/// TextStyle helper with tabular numbers so amounts align vertically without jitter.
TextStyle lanjoMoneyStyle(
  BuildContext context, {
  double fontSize = 15,
  FontWeight fontWeight = FontWeight.w700,
  Color? color,
  double letterSpacing = -0.3,
}) {
  return TextStyle(
    fontFamily: ArusColors.fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color ?? context.lanjoInk,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Maps string icon names stored in SQLite to minimalist stroke [LucideIcons].
IconData arusIconFromName(String name) {
  return switch (name) {
    'wallet' => LucideIcons.wallet,
    'bank' || 'account_balance' => LucideIcons.landmark,
    'ewallet' || 'smartphone' => LucideIcons.smartphone,
    'savings' => LucideIcons.piggyBank,
    'credit_card' => LucideIcons.creditCard,
    'paylater' => LucideIcons.calendarClock,
    'restaurant' => LucideIcons.utensils,
    'directions_car' => LucideIcons.car,
    'home' => LucideIcons.home,
    'shopping_bag' => LucideIcons.shoppingBag,
    'medical_services' => LucideIcons.stethoscope,
    'school' => LucideIcons.graduationCap,
    'movie' => LucideIcons.clapperboard,
    'wifi' => LucideIcons.wifi,
    'receipt_long' => LucideIcons.receiptText,
    'family_restroom' => LucideIcons.users,
    'payments' => LucideIcons.banknote,
    'laptop_mac' => LucideIcons.laptop,
    'card_giftcard' => LucideIcons.gift,
    'storefront' => LucideIcons.store,
    'redeem' => LucideIcons.sparkles,
    'coffee' => LucideIcons.coffee,
    'local_gas_station' => LucideIcons.fuel,
    'more_horiz' => LucideIcons.moreHorizontal,
    _ => LucideIcons.shapes,
  };
}
