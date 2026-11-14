import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A "⋮" icon button that, when tapped, morphs into an "✕" and pops out
/// an inline Rename / Delete menu anchored right next to it — instead of
/// opening a bottom sheet.
///
/// Drop this in place of the old IconButton(Icons.more_vert, ...).
class AnimatedModelOptionsButton extends StatefulWidget {
  const AnimatedModelOptionsButton({
    super.key,
    required this.onRename,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<AnimatedModelOptionsButton> createState() =>
      _AnimatedModelOptionsButtonState();
}

class _AnimatedModelOptionsButtonState
    extends State<AnimatedModelOptionsButton>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );

  OverlayEntry? _overlayEntry;
  bool _open = false;

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _show();
    }
  }

  void _show() {
    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context);
    final anchorSize = renderBox.size;
    final anchorOffset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return _OptionsOverlay(
          anchorOffset: anchorOffset,
          anchorSize: anchorSize,
          controller: _controller,
          onDismiss: _close,
          onRename: () {
            _close();
            widget.onRename();
          },
          onDelete: () {
            _close();
            widget.onDelete();
          },
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _open = true);
    _controller.forward(from: 0);
  }

  void _close() {
    if (!_open) return;
    _controller.reverse().whenComplete(_removeOverlay);
    setState(() => _open = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _anchorKey,
      tooltip: 'Options',
      onPressed: _toggle,
      icon: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // FIX: Keep the icon as Icons.more_vert! 
          // Rotating the 3 vertical dots by 135° (0.375 turns) creates 
          // a perfect "✕" morphing illusion. Using Icons.add or Icons.close 
          // breaks this visual trick.
          return RotationTransition(
            turns: Tween<double>(begin: 0, end: 0.375) // 135°
                .animate(CurvedAnimation(
                    parent: _controller, curve: Curves.easeOutBack)),
            child: const Icon(
              Icons.more_vert, 
              color: AppColors.textMuted,
            ),
          );
        },
      ),
    );
  }
}

/// The floating overlay: scrim + the inline popup menu that grows out of
/// the anchor icon's position.
class _OptionsOverlay extends StatelessWidget {
  const _OptionsOverlay({
    required this.anchorOffset,
    required this.anchorSize,
    required this.controller,
    required this.onDismiss,
    required this.onRename,
    required this.onDelete,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final AnimationController controller;
  final VoidCallback onDismiss;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  static const double _menuWidth = 168;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Anchor the menu's top-right corner to the icon's top-right corner,
    // so it visually "grows" out from where the ⋮ button was.

    double left = anchorOffset.dx + anchorSize.width - _menuWidth;
    if (left < 8) left = 8;
    if (left + _menuWidth > screenSize.width - 8) {
      left = screenSize.width - 8 - _menuWidth;
    }
    final top = anchorOffset.dy + anchorSize.height + 4;

    final growAnim = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    );
    final fadeAnim = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    return Stack(
      children: [
        // Invisible full-screen tap target to dismiss.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _menuWidth,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              return Opacity(
                opacity: fadeAnim.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  // Slight upward drift as it grows, like it's emerging
                  // from the icon rather than just fading on top of it.
                  offset: Offset(0, (1 - growAnim.value) * -12),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ScaleTransition(
                      scale: growAnim,
                      alignment: Alignment.topRight,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _OptionsMenuCard(
              onRename: onRename,
              onDelete: onDelete,
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionsMenuCard extends StatelessWidget {
  const _OptionsMenuCard({
    required this.onRename,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.circular(14),
          // NOTE: If you get a compilation error on .withValues, 
          // change it to .withOpacity(0.25) for Flutter < 3.27 compatibility.
          border: Border.all(color: AppColors.arc.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuRow(
              icon: Icons.drive_file_rename_outline,
              label: 'Rename',
              color: AppColors.arc,
              onTap: onRename,
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.textMuted.withValues(alpha: 0.15),
            ),
            _MenuRow(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: AppColors.fail,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppText.body(color: color),
            ),
          ],
        ),
      ),
    );
  }
}