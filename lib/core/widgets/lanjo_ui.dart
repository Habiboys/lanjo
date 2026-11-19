import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';

/// Crisp minimalist architectural container with hairline border and zero drop-shadow clutter.
class LanjoSurface extends StatelessWidget {
  const LanjoSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 18,
    this.color,
    this.borderColor,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? context.lanjoCard;
    final border = borderColor ?? context.lanjoBorder;

    Widget content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (onTap != null || onLongPress != null) {
      content = InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: content,
      ),
    );
  }
}

/// Squircle tinted icon container replacing generic Material CircleAvatar icons.
class LanjoIconBox extends StatelessWidget {
  const LanjoIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
    this.iconSize,
    this.radius,
    this.tintedBackground = true,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final double? radius;
  final bool tintedBackground;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final effectiveRadius = radius ?? (size * 0.30);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tintedBackground
            ? color.withValues(alpha: isDark ? 0.16 : 0.10)
            : context.lanjoSurfaceSecondary,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: iconSize ?? (size * 0.46),
      ),
    );
  }
}

/// Clean minimalist section header with optional right action button.
class LanjoSectionHeader extends StatelessWidget {
  const LanjoSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Minimalist status badge pill with clean tint and crisp border.
class LanjoPillBadge extends StatelessWidget {
  const LanjoPillBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean grab handle & title header for modal bottom sheets.
class LanjoSheetHeader extends StatelessWidget {
  const LanjoSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: context.lanjoBorder,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onClose ?? () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                backgroundColor: context.lanjoSurfaceSecondary,
                minimumSize: const Size(34, 34),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(LucideIcons.x, size: 17, color: context.lanjoMuted),
              tooltip: 'Tutup',
            ),
          ],
        ),
      ],
    );
  }
}

/// Subtle staggered entrance motion powered by `flutter_animate`.
class LanjoFadeSlideIn extends StatelessWidget {
  const LanjoFadeSlideIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.durationMs = 280,
    this.offsetY = 10,
  });

  final Widget child;
  final int delayMs;
  final int durationMs;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return child;

    return child
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        )
        .moveY(
          begin: offsetY,
          end: 0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
  }
}
