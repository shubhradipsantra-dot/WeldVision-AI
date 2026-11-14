import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/industrial_widgets.dart';
import 'login_screen.dart';
import 'image_screen.dart';
import 'video_screen.dart';
import 'live_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bg        = AppColors.bgBase;
const Color _panel     = AppColors.bgPanel;
const Color _elevated  = AppColors.bgElevated;
const Color _border    = AppColors.border;
const Color _primary   = AppColors.scan;
const Color _success   = AppColors.pass;
const Color _warning   = AppColors.caution;
const Color _danger    = AppColors.fail;
const Color _textPri   = AppColors.textPrimary;
const Color _textSec   = AppColors.textSecondary;
const Color _textMuted = AppColors.textMuted;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  Map<String, String> _stats = const {
    'inspections': '—',
    'passRate': '—',
    'avgDefects': '—',
  };
  bool _loadingStats   = true;
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _fetchHistory();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() => _loadingHistory = true);
    try {
      final items = await _api.getRecentInspections(limit: 20);
      if (!mounted) return;
      setState(() => _history = items.cast<Map<String, dynamic>>());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load history: $e'), backgroundColor: _danger),
      );
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;
    setState(() => _loadingStats = true);
    try {
      final data = await _api.getStats();
      final int inspections       = data['inspections_today'] ?? 0;
      final double passRate       = (data['pass_rate']   as num?)?.toDouble() ?? 0;
      final double avgDefects     = (data['avg_defects'] as num?)?.toDouble() ?? 0;
      if (!mounted) return;
      setState(() {
        _stats = {
          'inspections': '$inspections',
          'passRate'   : '${passRate.toStringAsFixed(0)}%',
          'avgDefects' : avgDefects.toStringAsFixed(1),
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load stats: $e'), backgroundColor: _danger),
      );
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: DecoratedBox(
        decoration: AppDecor.shopFloor,
        child: Stack(
          children: [
            // Blueprint grid background
            Positioned.fill(
              child: Opacity(
                opacity: 0.18,
                child: const BlueprintGrid(spacing: 36),
              ),
            ),
            SafeArea(
              child: RefreshIndicator(
                color: _primary,
                backgroundColor: _panel,
                onRefresh: () async {
                  await Future.wait([_fetchStats(), _fetchHistory()]);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildTopBar(),
                          const SizedBox(height: 24),
                          _buildHeroCard(),
                          const SizedBox(height: 28),
                          _buildSectionHeader("Today's Overview", _loadingStats, _fetchStats),
                          const SizedBox(height: 14),
                          _buildStatsRow(),
                          const SizedBox(height: 28),
                          _buildSectionHeader('Quick Actions', false, null),
                          const SizedBox(height: 14),
                          _buildQuickActionsGrid(),
                          const SizedBox(height: 28),
                          _buildSystemStatus(),
                          const SizedBox(height: 28),
                          _buildSectionHeader('Recent Inspections', _loadingHistory, _fetchHistory),
                          const SizedBox(height: 14),
                          if (_loadingHistory && _history.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(color: _primary, strokeWidth: 3),
                              ),
                            )
                          else if (_history.isEmpty)
                            _buildEmptyHistory()
                          else
                            ..._history.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistoryCard(item: item),
                            )),
                        ]),
                      ),
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

  // ─── TOP BAR ─────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final email       = userProvider.email ?? 'user@weldvision.com';
        final namePart    = email.split('@').first;
        final displayName = namePart.isNotEmpty
            ? namePart[0].toUpperCase() + namePart.substring(1)
            : 'Operator';

        return Row(
          children: [
            // Glowing Avatar — styled to match LandingScreen's header exactly
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_primary, Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Container(
                      color: _bg,
                      alignment: Alignment.center,
                      child: Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _success,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bg, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _success.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: _textSec,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: _textPri,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Logout — restyled as a Landing-style glass icon button
            _buildGlassIconButton(
              icon: Icons.logout_rounded,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: _panel,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800, color: _textPri)),
                    content: const Text('Are you sure you want to log out?', style: TextStyle(color: _textSec)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel', style: TextStyle(color: _textSec, fontWeight: FontWeight.w700)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await userProvider.logout();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _panel.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border, width: 1.2),
              ),
              child: Icon(icon, color: _textSec, size: 20),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: _danger,
                shape: BoxShape.circle,
                border: Border.all(color: _bg, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── HERO CARD ────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A6B), Color(0xFF2E1065)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _primary.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.20), blurRadius: 30, offset: const Offset(0, 12)),
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Blueprint grid texture overlay
            Positioned.fill(
              child: Opacity(opacity: 0.07, child: const BlueprintGrid(spacing: 24)),
            ),
            // Corner bracket decorations
            Positioned(top: 12, right: 12, child: _CornerBracket(color: _primary.withOpacity(0.4))),
            Positioned(bottom: 12, left: 12, child: _CornerBracket(color: _primary.withOpacity(0.25), flip: true)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _primary.withOpacity(0.4)),
                          boxShadow: [BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 12)],
                        ),
                        child: const Icon(Icons.precision_manufacturing, color: _primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WELD VISION AI',
                            style: GoogleFonts.orbitron(
                              color: _primary.withOpacity(0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'Inspection Hub',
                            style: GoogleFonts.inter(
                              color: _textPri,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Pulsing live indicator
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _success.withOpacity(0.08 + 0.06 * _pulseCtrl.value),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _success.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _success,
                                  boxShadow: [BoxShadow(color: _success.withOpacity(0.7 * _pulseCtrl.value), blurRadius: 8)],
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text('ACTIVE', style: GoogleFonts.orbitron(color: _success, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ready to Inspect?',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a new weld inspection or review recent results from your production line.',
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageScreen(modelName: null)));
                        if (mounted) { _fetchStats(); _fetchHistory(); }
                      },
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(
                        'Start New Inspection',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        shadowColor: _primary.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SECTION HEADER ───────────────────────────────────────────────
  Widget _buildSectionHeader(String title, bool isLoading, VoidCallback? onRefresh) {
    return Row(
      children: [
        Container(width: 3, height: 18, decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: _textPri, letterSpacing: -0.3),
          ),
        ),
        if (isLoading)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
        else if (onRefresh != null)
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _elevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.refresh_rounded, size: 16, color: _textSec),
            ),
          ),
      ],
    );
  }

  // ─── STATS ROW ───────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _StatCard(label: 'Inspections', value: _stats['inspections']!, icon: Icons.fact_check_outlined, color: _primary, trend: '+12%', trendUp: true)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Pass Rate', value: _stats['passRate']!, icon: Icons.verified_outlined, color: _success, trend: '+2.1%', trendUp: true)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Avg Defects', value: _stats['avgDefects']!, icon: Icons.bug_report_outlined, color: _danger, trend: '-0.5', trendUp: false)),
      ],
    );
  }

  // ─── QUICK ACTIONS 2×2 ───────────────────────────────────────────
  Widget _buildQuickActionsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.image_search_outlined,
                label: 'Image Scan',
                sublabel: 'Upload & inspect',
                color: const Color(0xFF3B82F6),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageScreen(modelName: null)));
                  if (mounted) { _fetchStats(); _fetchHistory(); }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.video_library_outlined,
                label: 'Video Scan',
                sublabel: 'Analyze footage',
                color: const Color(0xFF8B5CF6),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoScreen(modelName: null)));
                  if (mounted) { _fetchStats(); _fetchHistory(); }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.sensors,
                label: 'Live Stream',
                sublabel: 'Real-time detection',
                color: const Color(0xFFFBBF24),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveScreen(modelName: null))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.assessment_outlined,
                label: 'Reports',
                sublabel: 'Coming soon',
                color: const Color(0xFF22C55E),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reports coming soon!'), backgroundColor: _primary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── SYSTEM STATUS BANNER ─────────────────────────────────────────
  Widget _buildSystemStatus() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _success.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _success.withOpacity(0.25), width: 1.2),
        boxShadow: [BoxShadow(color: _success.withOpacity(0.04), blurRadius: 16)],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _success.withOpacity(0.1 + 0.05 * _pulseCtrl.value),
                border: Border.all(color: _success.withOpacity(0.3 + 0.2 * _pulseCtrl.value)),
              ),
              child: const Icon(Icons.check_circle_outline, color: _success, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Systems Operational',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: _textPri, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'AI engine and backend are running smoothly.',
                  style: GoogleFonts.inter(color: _textSec, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('v2.1', style: GoogleFonts.orbitron(color: _success, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY HISTORY ────────────────────────────────────────────────
  Widget _buildEmptyHistory() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: _elevated, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
            child: const Icon(Icons.history_toggle_off_outlined, color: _textMuted, size: 28),
          ),
          const SizedBox(height: 14),
          Text('No Inspections Yet', style: GoogleFonts.inter(color: _textPri, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Start an inspection to see results here.', style: GoogleFonts.inter(color: _textSec, fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STAT CARD
// ═══════════════════════════════════════════════════════════════════
class _StatCard extends StatefulWidget {
  final String label, value, trend;
  final IconData icon;
  final Color color;
  final bool trendUp;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.trend, required this.trendUp});
  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.color.withOpacity(0.3), width: 1.2),
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 16, color: widget.color),
              ),
              const SizedBox(height: 10),
              Text(
                widget.value,
                style: GoogleFonts.orbitron(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPri,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _textSec),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (widget.trendUp ? _success : _danger).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.trendUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 9,
                      color: widget.trendUp ? _success : _danger,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.trend,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: widget.trendUp ? _success : _danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ACTION CARD
// ═══════════════════════════════════════════════════════════════════
class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label, required this.sublabel, required this.color, required this.onTap});
  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: widget.color.withOpacity(0.3), width: 1.2),
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 4)),
              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.color.withOpacity(0.7), widget.color],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: widget.color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 14),
              Text(widget.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _textPri)),
              const SizedBox(height: 2),
              Text(widget.sublabel, style: GoogleFonts.inter(fontSize: 11, color: _textSec)),
            ],
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// CORNER BRACKET DECORATOR
// ═══════════════════════════════════════════════════════════════════
class _CornerBracket extends StatelessWidget {
  final Color color;
  final bool flip;
  const _CornerBracket({required this.color, this.flip = false});
  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      scaleY: flip ? -1 : 1,
      child: CustomPaint(
        size: const Size(20, 20),
        painter: _BracketPainter(color: color),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const d = 10.0;
    canvas.drawLine(Offset(0, d), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(d, 0), paint);
  }
  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════
// HISTORY CARD
// ═══════════════════════════════════════════════════════════════════
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _HistoryCard({required this.item});

  Color _decisionColor(String? d) {
    switch ((d ?? '').toUpperCase()) {
      case 'ACCEPT': return _success;
      case 'REJECT': return _danger;
      case 'REVIEW': return _warning;
      default:       return _textSec;
    }
  }

  IconData _sourceIcon(String? source) {
    switch (source) {
      case 'frame':
      case 'video': return Icons.videocam_outlined;
      default:      return Icons.image_outlined;
    }
  }

  String _statusLabel(String? d) {
    switch ((d ?? '').toUpperCase()) {
      case 'ACCEPT': return 'PASS';
      case 'REJECT': return 'FAIL';
      default:       return 'REVIEW';
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '—';
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision    = (item['decision']    as String?) ?? '—';
    final defectCount = (item['defect_count'] as int?)   ?? 0;
    final source      = item['source'] as String?;
    final color       = _decisionColor(decision);
    final statusLabel = _statusLabel(decision);

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            // Colored left edge indicator
            Container(width: 4, height: 72, color: color),
            const SizedBox(width: 14),
            // Source icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_sourceIcon(source), color: color, size: 22),
            ),
            const SizedBox(width: 14),
            // Main text
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          decision.toUpperCase(),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _textPri),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(statusLabel, style: GoogleFonts.orbitron(fontSize: 8, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      defectCount == 0
                          ? 'No defects detected'
                          : '$defectCount defect${defectCount > 1 ? 's' : ''} found',
                      style: GoogleFonts.inter(fontSize: 12, color: _textSec),
                    ),
                  ],
                ),
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                _relativeTime(item['created_at'] as String?),
                style: GoogleFonts.inter(fontSize: 11, color: _textMuted, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}