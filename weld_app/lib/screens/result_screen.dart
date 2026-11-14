import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'full_screen_image.dart';

// ─── COLOR ALIASES (mapped from centralized AppColors) ──────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _warningColor = AppColors.caution;
const Color _dangerColor = AppColors.fail;

class ResultScreen extends StatefulWidget {
  final String decision;
  final int defectCount;
  final String imageUrl;
  final List<dynamic> defects;

  const ResultScreen({
    super.key,
    required this.decision,
    required this.defectCount,
    required this.imageUrl,
    required this.defects,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Map<String, String>? _headers;
  bool _isLoadingHeaders = true;

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  Future<void> _loadHeaders() async {
    try {
      final authHeaders = await AuthService().getAuthHeaders();
      if (mounted) {
        setState(() {
          _headers = authHeaders;
          _isLoadingHeaders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHeaders = false);
      }
    }
  }

  bool get _accepted => widget.decision.toUpperCase() == 'ACCEPT';

  double get _avgConfidence {
    if (widget.defects.isEmpty) return 0.0;
    final total = widget.defects.fold<double>(
      0.0,
      (sum, d) => sum + ((d["confidence"] as num?)?.toDouble() ?? 0.0),
    );
    return total / widget.defects.length;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _accepted ? _successColor : _dangerColor;

    return Scaffold(
      backgroundColor: _bgColor,
      body: DecoratedBox(
        decoration: AppDecor.shopFloor,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDecisionBanner(statusColor)
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              'Defects',
                              '${widget.defectCount}',
                              Icons.bug_report_outlined,
                              widget.defectCount == 0 ? _successColor : _dangerColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              'Avg. Confidence',
                              widget.defects.isEmpty ? '—' : '${(_avgConfidence * 100).toStringAsFixed(1)}%',
                              Icons.analytics_outlined,
                              _primaryColor,
                            ),
                          ),
                        ],
                      )
                          .animate()
                          .fadeIn(delay: 150.ms, duration: 500.ms)
                          .slideY(begin: 0.08, end: 0),

                      const SizedBox(height: 32),

                      Text('Evidence', style: AppText.display(size: 18)),
                      const SizedBox(height: 16),
                      _buildEvidenceImage(context)
                          .animate()
                          .fadeIn(delay: 300.ms, duration: 500.ms),

                      const SizedBox(height: 32),

                      Text('Defect Log (${widget.defects.length})', style: AppText.display(size: 18)),
                      const SizedBox(height: 16),

                      if (widget.defects.isEmpty)
                        _buildEmptyDefectState()
                            .animate()
                            .fadeIn(delay: 400.ms, duration: 400.ms)
                      else
                        ...widget.defects.asMap().entries.map((entry) {
                          final index = entry.key;
                          final d = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildDefectCard(index, d),
                          ).animate().fadeIn(delay: (400 + index * 80).ms, duration: 400.ms).slideX(begin: 0.04, end: 0);
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
        children: [
          _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('Inspection Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
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

  Widget _buildDecisionBanner(Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _accepted ? Icons.check_circle : Icons.cancel,
              color: statusColor,
              size: 36,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.decision.toUpperCase(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _accepted ? 'Weld meets quality standard' : 'Weld requires rework',
                  style: const TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF223049)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceImage(BuildContext context) {
    // ✅ Wrapped in Material + InkWell for native ripple tap feedback
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: () {
          if (widget.imageUrl.isNotEmpty && !_isLoadingHeaders) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenImage(
                  imageUrl: widget.imageUrl,
                  headers: _headers,
                  title: 'Inspection Evidence', // ✅ Added context for the full-screen view
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 280,
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF223049)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isLoadingHeaders)
                  const Center(child: CircularProgressIndicator(color: _primaryColor))
                else if (widget.imageUrl.isNotEmpty)
                  Image.network(
                    widget.imageUrl,
                    headers: _headers ?? {},
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                          color: _primaryColor,
                          strokeWidth: 3,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, color: _textSecondary.withOpacity(0.5), size: 48),
                            const SizedBox(height: 12),
                            const Text('Failed to load image', style: TextStyle(color: _textSecondary, fontSize: 14)),
                          ],
                        ),
                      );
                    },
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_not_supported_outlined, color: _textSecondary.withOpacity(0.5), size: 48),
                        const SizedBox(height: 12),
                        const Text('No image available', style: TextStyle(color: _textSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
                
                // Zoom Hint Overlay
                Positioned(
                  right: 16, bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDefectState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF223049)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: const Column(
        children: [
          Icon(Icons.verified_outlined, color: _successColor, size: 32),
          SizedBox(height: 12),
          Text('No defects detected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
          SizedBox(height: 4),
          Text('This weld passed all quality checks.', style: TextStyle(fontSize: 13, color: _textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDefectCard(int index, dynamic d) {
    // ✅ Safe casting for robust number formatting
    final confidence = ((d["confidence"] as num?)?.toDouble() ?? 0.0) * 100;
    final area = ((d["area_mm2"] as num?)?.toDouble() ?? 0.0);
    final severity = (d["severity"] ?? 'low').toString().toUpperCase();
    final sevColor = (severity == 'HIGH' || severity == 'MAJOR') ? _dangerColor : _warningColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF223049)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${index + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _primaryColor)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  (d["type"] ?? 'Unknown').toString(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sevColor.withOpacity(0.2)),
                ),
                child: Text(
                  severity,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sevColor, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMiniStat(Icons.square_foot_outlined, '${area.toStringAsFixed(2)} mm²'),
              const SizedBox(width: 16),
              _buildMiniStat(Icons.percent_outlined, '${confidence.toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _textSecondary),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textSecondary)),
      ],
    );
  }
}