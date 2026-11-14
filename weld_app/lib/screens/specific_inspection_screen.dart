import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import 'image_screen.dart';
import 'video_screen.dart';
import 'live_inference_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _borderColor = AppColors.border;

class SpecificInspectionScreen extends StatelessWidget {
  final String modelName;

  // ── Optional model metadata ─────────────────────────────────────
  // The backend currently only tracks model_name / gcs_uri / created_at,
  // so these are optional and fall back to placeholders when not supplied.
  // Pass real values in from the caller once the backend exposes them
  // (e.g. training date, model architecture, eval accuracy, version tag).
  final String? trainedOn;
  final String? modelType;
  final String? accuracy;
  final String? version;
  final String? activatedAt;

  // ── Optional management actions (wired from the models list screen) ──
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const SpecificInspectionScreen({
    super.key,
    required this.modelName,
    this.trainedOn,
    this.modelType,
    this.accuracy,
    this.version,
    this.activatedAt,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── CUSTOM TOP BAR ───────────────────────────────────────
            _buildTopBar(context),

            // ── SCROLLABLE CONTENT ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. MODEL HERO CARD ─────────────────────────────
                    _buildModelHeroCard(context)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 32),

                    // ── 2. INSPECTION MODES ────────────────────────────
                    const Text(
                      'Inspection Modes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                    const SizedBox(height: 16),

                    _buildModeCard(
                      title: 'Image Inspection',
                      subtitle: 'Capture or upload weld images for defect detection.',
                      icon: Icons.image_outlined,
                      color: const Color(0xFF3B82F6),
                      badge: 'Recommended',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageScreen(modelName: modelName))),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 12),

                    _buildModeCard(
                      title: 'Video Inspection',
                      subtitle: 'Analyze recorded weld videos frame by frame.',
                      icon: Icons.video_library_outlined,
                      color: const Color(0xFF8B5CF6),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(modelName: modelName))),
                    ).animate().fadeIn(delay: 400.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 12),

                    _buildModeCard(
                      title: 'Live Inspection',
                      subtitle: 'On-device real-time detection (no cloud required).',
                      icon: Icons.videocam_outlined,
                      color: const Color(0xFF22C55E),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveInferenceScreen(modelName: modelName))),
                    ).animate().fadeIn(delay: 450.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 32),

                    // ── 3. ACTIVE CONFIGURATION ────────────────────────
                    const Text(
                      'Active Configuration',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)
                    ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                    const SizedBox(height: 16),

                    _buildActiveConfigCard(context)
                        .animate()
                        .fadeIn(delay: 600.ms, duration: 400.ms)
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 12),

                    _buildSwitchModelCard(context)
                        .animate()
                        .fadeIn(delay: 650.ms, duration: 400.ms)
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 32),

                    // ── 4. SYSTEM STATUS ───────────────────────────────
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _successColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.all(Radius.circular(20)),
                          border: Border.all(color: _successColor.withOpacity(0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PulsingDot(color: _successColor),
                            SizedBox(width: 8),
                            Text('Model Ready', style: TextStyle(color: _successColor, fontWeight: FontWeight.w700, fontSize: 13)),
                          ],
                        ),
                      ).animate().fadeIn(delay: 700.ms, duration: 400.ms),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── WIDGET BUILDERS ────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: _bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Model Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                const Text(
                  'Manage and inspect using your selected model',
                  style: TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Selected: ', style: TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500)),
                      TextSpan(text: modelName, style: const TextStyle(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: _cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: _textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildModelHeroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        border: Border.all(color: _borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF6366F1), _primaryColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                  boxShadow: [BoxShadow(color: Color.fromRGBO(79, 70, 229, 0.3), blurRadius: 12, offset: Offset(0, 6))],
                ),
                child: const Icon(Icons.memory, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _successColor.withOpacity(0.1),
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingDot(color: _successColor, size: 6),
                              SizedBox(width: 6),
                              Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _successColor, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                          ),
                          child: const Text('Ready for Inspection', style: TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onRename != null || onDelete != null) _buildKebabMenu(context),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: _borderColor, height: 1),
          const SizedBox(height: 20),

          // ── Stat row: Trained On / Model Type / Accuracy / Version ──
          Row(
            children: [
              Expanded(
                child: _buildStat(
                  icon: Icons.calendar_today_outlined,
                  iconColor: const Color(0xFF8B5CF6),
                  label: 'Trained On',
                  value: trainedOn ?? '—',
                ),
              ),
              Expanded(
                child: _buildStat(
                  icon: Icons.track_changes_outlined,
                  iconColor: _primaryColor,
                  label: 'Model Type',
                  value: modelType ?? 'Custom YOLO',
                ),
              ),
              Expanded(
                child: _buildStat(
                  icon: Icons.trending_up,
                  iconColor: _successColor,
                  label: 'Accuracy',
                  value: accuracy ?? '—',
                ),
              ),
              Expanded(
                child: _buildStat(
                  icon: Icons.layers_outlined,
                  iconColor: const Color(0xFFF97316),
                  label: 'Version',
                  value: version ?? '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat({required IconData icon, required Color iconColor, required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: _textPrimary, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildKebabMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: _textSecondary),
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _borderColor)),
      onSelected: (value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (context) => [
        if (onRename != null)
          const PopupMenuItem(
            value: 'rename',
            child: Row(children: [
              Icon(Icons.edit_outlined, color: _textPrimary, size: 18),
              SizedBox(width: 10),
              Text('Rename Model', style: TextStyle(color: _textPrimary)),
            ]),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 10),
              Text('Delete Model', style: TextStyle(color: Color(0xFFEF4444))),
            ]),
          ),
      ],
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      color: _cardColor,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: _borderColor),
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: _textSecondary)),
                    if (badge != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: _primaryColor, size: 12),
                            const SizedBox(width: 4),
                            Text(badge, style: const TextStyle(fontSize: 11, color: _primaryColor, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: _textSecondary.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveConfigCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: _successColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _successColor.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: _successColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Currently Using', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _successColor)),
                    const SizedBox(height: 4),
                    Text(
                      modelName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.access_time, color: _textSecondary.withOpacity(0.7), size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  activatedAt != null ? 'Activated on $activatedAt' : 'Activated on this device',
                  style: const TextStyle(fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _showModelDetails(context),
                style: TextButton.styleFrom(
                  foregroundColor: _successColor,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchModelCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.pop(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryColor.withOpacity(0.4), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: _primaryColor, size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Switch or Change Model', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary)),
                    SizedBox(height: 2),
                    Text('Choose a different trained model', style: TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _textSecondary.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }

  void _showModelDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Model Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Name', modelName),
            _detailRow('Trained On', trainedOn ?? '—'),
            _detailRow('Model Type', modelType ?? 'Custom YOLO'),
            _detailRow('Accuracy', accuracy ?? '—'),
            _detailRow('Version', version ?? '—'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: _primaryColor),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _textPrimary, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ─── ANIMATED UI HELPERS ──────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingDot({required this.color, this.size = 8});

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
          width: widget.size,
          height: widget.size,
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