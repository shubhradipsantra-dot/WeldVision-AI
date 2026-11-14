import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Faint engineering-blueprint grid drawn behind hero content.
class BlueprintGrid extends StatelessWidget {
  final double spacing;
  final Color lineColor;

  const BlueprintGrid({
    super.key,
    this.spacing = 28,
    this.lineColor = const Color(0x141FE8FF),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(spacing: spacing, lineColor: lineColor),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double spacing;
  final Color lineColor;

  _GridPainter({required this.spacing, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// The app's signature visual motif: a scanner-style corner-bracket
/// frame, used on every image / camera surface (capture preview, live
/// feed, evidence photo) to read as an inspection viewfinder rather
/// than a plain photo.
class ScanFrame extends StatelessWidget {
  final Widget child;
  final Color color;
  final double bracketLength;
  final double thickness;
  final BorderRadius borderRadius;

  const ScanFrame({
    super.key,
    required this.child,
    this.color = AppColors.arc,
    this.bracketLength = 22,
    this.thickness = 3,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(borderRadius: borderRadius, child: child),
        Positioned.fill(
          child: CustomPaint(
            painter: _BracketPainter(
              color: color,
              length: bracketLength,
              thickness: thickness,
            ),
          ),
        ),
      ],
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final double length;
  final double thickness;

  _BracketPainter({required this.color, required this.length, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // top-left
    canvas.drawLine(Offset(0, length), Offset.zero, paint);
    canvas.drawLine(Offset.zero, Offset(length, 0), paint);
    // top-right
    canvas.drawLine(Offset(size.width - length, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, length), paint);
    // bottom-left
    canvas.drawLine(Offset(0, size.height - length), Offset(0, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(length, size.height), paint);
    // bottom-right
    canvas.drawLine(Offset(size.width - length, size.height), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - length), paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.length != length;
}

/// Small uppercase, wide-tracked label that introduces a section.
class SectionEyebrow extends StatelessWidget {
  final String label;
  final Color color;

  const SectionEyebrow(this.label, {super.key, this.color = AppColors.scan});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 2, color: color),
        const SizedBox(width: 8),
        Text(label.toUpperCase(), style: AppText.eyebrow(color: color)),
      ],
    );
  }
}

/// LED-style status pill, e.g. SYSTEM READY / ACCEPT / SCANNING.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: If you get a compilation error on .withValues, 
    // change it to .withOpacity(X) for Flutter < 3.27 compatibility.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: AppText.eyebrow(color: color).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Beveled control-panel button used for primary capture / upload actions.
class IndustrialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;

  const IndustrialButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.arc,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    return SizedBox(
      height: 64,
      child: Material(
        color: filled ? (disabled ? AppColors.bgElevated : color) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: filled ? Colors.black26 : color.withValues(alpha: disabled ? 0.3 : 1),
                width: filled ? 0 : 1.4,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: filled
                      ? (disabled ? AppColors.textMuted : Colors.black)
                      : color.withValues(alpha: disabled ? 0.3 : 1),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: filled
                        ? (disabled ? AppColors.textMuted : Colors.black)
                        : color.withValues(alpha: disabled ? 0.3 : 1),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mode-select panel used on Home / Video screens.
class ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgPanel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.display(size: 18)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppText.body(size: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact instrument-style data readout, e.g. "DEFECTS · 04".
class MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const MetricChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.scan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.eyebrow(color: AppColors.textMuted).copyWith(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.data(size: 20, color: color, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Severity tag used in the defect report list. Color is derived from
/// the severity string itself, so it always encodes real meaning.
class SeverityTag extends StatelessWidget {
  final String severity;

  const SeverityTag(this.severity, {super.key});

  Color _color() {
    // FIX: Added 'major' and 'minor' to match the backend's exact output.
    // Without this, 'MAJOR' would fall back to 'default' and show up as Green (Pass)!
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
      case 'major': 
        return AppColors.fail;
      case 'medium':
      case 'moderate':
      case 'minor': 
        return AppColors.caution;
      default:
        return AppColors.pass;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
      ),
    );
  }
}

/// One tab definition for [IndustrialNavBar].
class NavBarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavBarItem({required this.icon, required this.activeIcon, required this.label});
}

/// Persistent control-panel navigation bar fixed to the bottom of the
/// app shell — the tab strip that ties Command / Models / Result /
/// Train together so the product reads as one continuous instrument
/// rather than a stack of disconnected screens. Styling matches the
/// dark shop-floor theme: bgPanel base, hairline top edge, and the
/// signature "arc" orange used as the active-tab indicator, echoing
/// the tab treatment from the original iWDI mockup deck.
class IndustrialNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavBarItem> items;

  const IndustrialNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items = const [
      NavBarItem(icon: Icons.terminal_outlined, activeIcon: Icons.terminal_rounded, label: 'Command'),
      NavBarItem(icon: Icons.hub_outlined, activeIcon: Icons.hub, label: 'Models'),
      NavBarItem(icon: Icons.fact_check_outlined, activeIcon: Icons.fact_check, label: 'Result'),
      NavBarItem(icon: Icons.model_training_outlined, activeIcon: Icons.model_training, label: 'Train'),
    ],
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == currentIndex;
              final item = items[i];
              final color = selected ? AppColors.arc : AppColors.textMuted;

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          height: 2,
                          width: selected ? 22 : 0,
                          margin: const EdgeInsets.only(bottom: 7),
                          decoration: BoxDecoration(
                            color: AppColors.arc,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: selected
                                ? [BoxShadow(color: AppColors.arcGlow, blurRadius: 6, spreadRadius: 0.5)]
                                : null,
                          ),
                        ),
                        Icon(selected ? item.activeIcon : item.icon, size: 20, color: color),
                        const SizedBox(height: 4),
                        Text(
                          item.label.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                            letterSpacing: 1.3,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}