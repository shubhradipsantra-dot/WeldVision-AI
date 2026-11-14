import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import 'train_model_screen.dart';
import 'existing_models_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _warningColor = AppColors.caution;

/// Faint diagonal wave lines used as a decorative background accent,
/// matching the flowing-line motif used elsewhere in the app's cards.
class _WaveLinesPainter extends CustomPainter {
  final Color color;
  final double opacity;

  _WaveLinesPainter({required this.color, this.opacity = 0.12});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 0; i < 3; i++) {
      final path = Path();
      final yOffset = size.height * (0.25 + i * 0.22);
      path.moveTo(-20, yOffset);
      for (double x = -20; x <= size.width + 20; x += 20) {
        final y = yOffset + sin((x / size.width * 2 * pi) + i * 1.4) * (8 + i * 3);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveLinesPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}

class SpecificModelScreen extends StatelessWidget {
  const SpecificModelScreen({super.key});

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: _primaryColor, size: 24),
            SizedBox(width: 10),
            Text('About Specific Models', style: TextStyle(fontWeight: FontWeight.w800, color: _textPrimary)),
          ],
        ),
        content: const Text(
          'Specific Models are custom-trained AI models tailored to your unique weld geometry, lighting conditions, and production environment. Training a new model allows the system to achieve higher accuracy and fewer false positives compared to the generic model.',
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700, color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── EVERYTHING FITS IN ONE VIEWPORT — NO SCROLLING ──────────────
    // Instead of a SingleChildScrollView, the body is a fixed Column
    // where each section is wrapped in Expanded with a flex weight.
    // Flutter divides up whatever vertical space is actually available
    // on the device between those sections, so nothing overflows and
    // nothing needs to scroll — sections just resize to fit smaller
    // or larger screens.
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── TOP BAR ──────────────────────────────────────────
              _buildTopBar(context),
              const SizedBox(height: 10),

              // ── 1. HERO INTRODUCTION CARD ─────────────────────────
              Expanded(
                flex: 24,
                child: _buildHeroCard()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
              ),
              const SizedBox(height: 12),

              // ── 2. MODEL MANAGEMENT ACTION CARDS ──────────────────
              const Text(
                'Model Management',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.2),
              ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
              const SizedBox(height: 8),

              Expanded(
                flex: 40,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        context,
                        title: 'Train New Model',
                        subtitle: 'Create a custom AI model from weld footage.',
                        icon: Icons.autorenew_rounded,
                        color: const Color(0xFF8B5CF6),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainModelScreen())),
                      ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionCard(
                        context,
                        title: 'Existing Models',
                        subtitle: 'Select a trained model and start inspecting.',
                        icon: Icons.folder_special_outlined,
                        color: const Color(0xFF3B82F6),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExistingModelsScreen())),
                      ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── 3. CAPABILITIES FEATURE GRID ──────────────────────
              const Text(
                'Key Capabilities',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.2),
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
              const SizedBox(height: 8),

              Expanded(
                flex: 20,
                child: _buildFeaturesRow()
                    .animate()
                    .fadeIn(delay: 450.ms, duration: 400.ms)
                    .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
              ),
              const SizedBox(height: 10),

              // ── 4. SYSTEM STATUS ──────────────────────────────────
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _successColor.withOpacity(0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDot(color: _successColor),
                      SizedBox(width: 8),
                      Text('System Ready', style: TextStyle(color: _successColor, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ).animate().fadeIn(delay: 550.ms, duration: 400.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WIDGET BUILDERS ────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Specific Model', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
              Text('AI Model Hub', style: TextStyle(fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        _buildCircleButton(Icons.info_outline, () => _showInfoDialog(context), iconColor: _textSecondary),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap, {Color iconColor = _textPrimary}) {
    return Material(
      color: _cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: iconColor, size: 18),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: constraints.maxHeight < 120 ? 12 : 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2F9BFF), Color(0xFF7C3AED)], // Indigo to Purple
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _WaveLinesPainter(color: Colors.white, opacity: 0.14)),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Process-Specific AI',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Train custom models tailored to your specific weld geometry for maximum accuracy.',
                          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF223049)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _WaveLinesPainter(color: color, opacity: 0.15)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                        child: Icon(Icons.chevron_right, size: 15, color: color),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 11.5, color: _textSecondary, height: 1.25),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesRow() {
    return Row(
      children: [
        Expanded(child: _buildFeatureCard(Icons.speed_outlined, 'Real-Time', const Color(0xFF8B5CF6))),
        const SizedBox(width: 10),
        Expanded(child: _buildFeatureCard(Icons.trending_up_outlined, 'High Accuracy', _successColor)),
        const SizedBox(width: 10),
        Expanded(child: _buildFeatureCard(Icons.dataset_outlined, 'Custom Dataset', const Color(0xFF3B82F6))),
        const SizedBox(width: 10),
        Expanded(child: _buildFeatureCard(Icons.precision_manufacturing_outlined, 'Industry Specific', _warningColor)),
      ],
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF223049)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _textPrimary, height: 1.2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── ANIMATED UI HELPERS ──────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500)
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = (sin(_controller.value * 2 * pi) + 1) / 2;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.4 + pulse * 0.4),
                blurRadius: 4 + pulse * 6,
                spreadRadius: pulse * 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}