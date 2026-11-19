import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';

/// Reusable swipe-to-reveal action wrapper exposing Edit & Delete buttons
/// cleanly behind list cards across all modules.
class SwipeActionCard extends StatefulWidget {
  const SwipeActionCard({
    super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.editLabel = 'Edit',
    this.deleteLabel = 'Hapus',
    this.borderRadius = 18,
  });

  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String editLabel;
  final String deleteLabel;
  final double borderRadius;

  @override
  State<SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<SwipeActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const double _actionWidth = 72.0;

  double get _totalActionsWidth =>
      (widget.onEdit != null ? _actionWidth : 0.0) +
      (widget.onDelete != null ? _actionWidth : 0.0);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close() => _ctrl.animateTo(0.0, curve: Curves.easeOutCubic);

  void _open() => _ctrl.animateTo(1.0, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final maxReveal = _totalActionsWidth;
    if (maxReveal <= 0) return widget.child;

    final theme = Theme.of(context);
    final editBg = theme.colorScheme.primary;
    const deleteBg = ArusColors.expense;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                if (_ctrl.value <= 0.01) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onEdit != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: SizedBox(
                            width: _actionWidth - 6,
                            height: double.infinity,
                            child: Material(
                              color: editBg,
                              borderRadius: BorderRadius.circular(14),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  _close();
                                  widget.onEdit!();
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      LucideIcons.pencil,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.editLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.onDelete != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: SizedBox(
                            width: _actionWidth - 6,
                            height: double.infinity,
                            child: Material(
                              color: deleteBg,
                              borderRadius: BorderRadius.circular(14),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  _close();
                                  widget.onDelete!();
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      LucideIcons.trash2,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.deleteLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_ctrl.value * maxReveal, 0),
                child: child,
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                final next = _ctrl.value - (details.delta.dx / maxReveal);
                _ctrl.value = next.clamp(0.0, 1.0);
              },
              onHorizontalDragEnd: (details) {
                final vx = details.primaryVelocity ?? 0;
                if (vx < -220) {
                  _open();
                } else if (vx > 220) {
                  _close();
                } else if (_ctrl.value >= 0.4) {
                  _open();
                } else {
                  _close();
                }
              },
              onLongPress: () {
                if (_ctrl.value > 0.5) {
                  _close();
                } else {
                  _open();
                }
              },
              onTap: _ctrl.value > 0.5 ? _close : null,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
