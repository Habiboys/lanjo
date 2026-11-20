import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Custom Theme & Color Studio allowing users to pick Light/Dark/System mode,
/// curated color palettes, or any custom hue/saturation/hex accent color.
class AppearanceSettingsPage extends ConsumerStatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  ConsumerState<AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState
    extends ConsumerState<AppearanceSettingsPage> {
  static const List<Color> _quickSwatches = [
    Color(0xFF0D7A6F),
    Color(0xFF0284C7),
    Color(0xFF2563EB),
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFF9333EA),
    Color(0xFFDB2777),
    Color(0xFFBE123C),
    Color(0xFFEA580C),
    Color(0xFFB45309),
    Color(0xFF15803D),
    Color(0xFF334155),
  ];

  late HSLColor _customHsl;
  late TextEditingController _hexCtrl;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(themeAccentProvider);
    _customHsl = HSLColor.fromColor(initial.seed);
    _hexCtrl = TextEditingController(text: initial.hexCode);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _syncControlsFromColor(Color color) {
    _customHsl = HSLColor.fromColor(color);
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    _hexCtrl.text = hex;
    _hexError = null;
  }

  Future<void> _setThemeMode(String mode) async {
    final db = ref.read(appDatabaseProvider);
    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        themeMode: Value(mode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _selectPreset(LanjoThemePalette preset) async {
    setState(() => _syncControlsFromColor(preset.seed));
    await ref.read(themeAccentProvider.notifier).selectPreset(preset);
  }

  Future<void> _applyHexInput() async {
    final parsed = LanjoThemePalette.tryParseHex(_hexCtrl.text);
    if (parsed == null) {
      setState(() => _hexError = 'Format hex tidak valid (contoh: #1D4ED8)');
      return;
    }
    setState(() => _syncControlsFromColor(parsed));
    await ref.read(themeAccentProvider.notifier).setCustomColor(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final palette = ref.watch(themeAccentProvider);
    final mode = settings?.themeMode ?? 'system';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tema & Warna Kustom'),
        actions: [
          if (palette.id != LanjoThemePresets.emerald.id)
            TextButton(
              onPressed: () => _selectPreset(LanjoThemePresets.emerald),
              child: const Text('Reset'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          Text(
            'PRATINJAU LANGSUNG',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        palette.heroDeep,
                        palette.heroMid,
                        palette.heroEnd,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'AMAN DIBELANJAKAN / HARI',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                              palette.isCustom
                                  ? 'Kustom ${palette.hexCode}'
                                  : palette.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rp145.000',
                        style: lanjoMoneyStyle(
                          context,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kas likuid Rp3,2jt • 14 hari lagi',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.74),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LanjoPillBadge(
                            label: palette.name,
                            icon: LucideIcons.palette,
                            color: context.lanjoPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(value: true, onChanged: (_) {}),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Tombol'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'MODE TAMPILAN',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            padding: const EdgeInsets.all(14),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 'system',
                  icon: Icon(LucideIcons.smartphone, size: 15),
                  label: Text(
                    'Sistem',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'light',
                  icon: Icon(LucideIcons.sun, size: 15),
                  label: Text(
                    'Terang',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(LucideIcons.moon, size: 15),
                  label: Text(
                    'Gelap',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => _setThemeMode(s.first),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'KOLEKSI TEMA PILIHAN',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in LanjoThemePresets.all)
                  _PresetCardChip(
                    preset: preset,
                    selected: !palette.isCustom && palette.id == preset.id,
                    onTap: () => _selectPreset(preset),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'RACIK WARNA KUSTOM BEBAS',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 8),
          LanjoSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final swatch in _quickSwatches)
                      InkWell(
                        onTap: () {
                          setState(() => _syncControlsFromColor(swatch));
                          ref
                              .read(themeAccentProvider.notifier)
                              .setCustomColor(swatch);
                        },
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.seed.toARGB32() ==
                                      swatch.toARGB32()
                                  ? context.lanjoInk
                                  : Colors.white.withValues(alpha: 0.5),
                              width: palette.seed.toARGB32() ==
                                      swatch.toARGB32()
                                  ? 2.5
                                  : 1,
                            ),
                          ),
                          child: palette.seed.toARGB32() == swatch.toARGB32()
                              ? const Icon(
                                  LucideIcons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Spektrum Warna',
                      style: theme.textTheme.labelMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${_customHsl.hue.round()}°',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Slider(
                  value: _customHsl.hue.clamp(0.0, 360.0),
                  min: 0,
                  max: 360,
                  onChanged: (hue) {
                    final next = _customHsl.withHue(hue);
                    final color = next.toColor();
                    setState(() => _syncControlsFromColor(color));
                    ref
                        .read(themeAccentProvider.notifier)
                        .previewCustomColor(color);
                  },
                  onChangeEnd: (hue) {
                    final color = _customHsl.withHue(hue).toColor();
                    ref
                        .read(themeAccentProvider.notifier)
                        .setCustomColor(color);
                  },
                ),
                Row(
                  children: [
                    Text(
                      'Intensitas Warna',
                      style: theme.textTheme.labelMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${(_customHsl.saturation * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                Slider(
                  value: _customHsl.saturation.clamp(0.15, 0.95),
                  min: 0.15,
                  max: 0.95,
                  onChanged: (sat) {
                    final next = _customHsl.withSaturation(sat);
                    final color = next.toColor();
                    setState(() => _syncControlsFromColor(color));
                    ref
                        .read(themeAccentProvider.notifier)
                        .previewCustomColor(color);
                  },
                  onChangeEnd: (sat) {
                    final color = _customHsl.withSaturation(sat).toColor();
                    ref
                        .read(themeAccentProvider.notifier)
                        .setCustomColor(color);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hexCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Kode Warna Hex',
                          hintText: '#0D7A6F',
                          errorText: _hexError,
                          prefixIcon: Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: palette.seed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _applyHexInput,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Terapkan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetCardChip extends StatelessWidget {
  const _PresetCardChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final LanjoThemePalette preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? context.lanjoPrimary : context.lanjoBorder;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? preset.primary.withValues(alpha: context.isDark ? 0.20 : 0.08)
              : context.lanjoSurfaceSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [preset.heroDeep, preset.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(
                      LucideIcons.check,
                      size: 13,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              preset.name,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.lanjoInk,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
