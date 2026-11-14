import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/industrial_widgets.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'specific_model_screen.dart';
import 'image_screen.dart';
import 'video_screen.dart';
import 'live_screen.dart';
import 'existing_models_screen.dart';
import 'results_overview_screen.dart';
import 'train_model_screen.dart';

// ─── COLOR ALIASES (mapped from centralized AppColors) ──────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _warningColor = AppColors.caution;
const Color _dangerColor = AppColors.fail;

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  // Stats state
  Map<String, String> _stats = const {
    'inspections': '186',
    'passRate': '97.2%',
    'avgDefects': '2.4',
    'activeScans': '3',
  };
  bool _loadingStats = true;
  int _unreadCount = 2;


  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _fetchStats();
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ✅ Fetch real stats via ApiService (uses AppConfig.baseUrl — no hardcoded URL)
  Future<void> _fetchStats() async {
    if (!mounted) return;
    setState(() => _loadingStats = true);

    try {
      final apiService = ApiService();
      final data = await apiService.getStats().timeout(const Duration(seconds: 6));
      if (!mounted) return;
      final int inspections = (data['inspections_today'] as num?)?.toInt() ?? 186;
      final double passRate = (data['pass_rate'] as num?)?.toDouble() ?? 97.2;
      final double avgDefects = (data['avg_defects'] as num?)?.toDouble() ?? 2.4;
      final int activeScans = (data['active_scans'] as num?)?.toInt() ?? 3;
      setState(() {
        _stats = {
          'inspections': '$inspections',
          'passRate': '${passRate.toStringAsFixed(1)}%',
          'avgDefects': avgDefects.toStringAsFixed(1),
          'activeScans': '$activeScans',
        };
        _loadingStats = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('session expired') || msg.contains('401')) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }
      setState(() => _loadingStats = false);
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // Show notifications dialog
  void _showNotifications() {
    setState(() => _unreadCount = 0);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: _primaryColor, size: 24),
            SizedBox(width: 10),
            Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildNotificationItem(
              icon: Icons.check_circle_outline,
              iconColor: _successColor,
              title: 'Inspection Complete',
              subtitle: 'Weld #1234 passed quality check',
              time: '2m ago',
            ),
            const SizedBox(height: 12),
            _buildNotificationItem(
              icon: Icons.warning_amber_rounded,
              iconColor: _warningColor,
              title: 'Model Update Available',
              subtitle: 'Version 2.1 ready for download',
              time: '1h ago',
            ),
            const SizedBox(height: 12),
            _buildNotificationItem(
              icon: Icons.error_outline,
              iconColor: _dangerColor,
              title: 'Defect Detected',
              subtitle: 'Critical defect in Weld #1230',
              time: '3h ago',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: _textSecondary)),
            ],
          ),
        ),
        Text(time, style: const TextStyle(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ✅ Updated Settings Dialog with User Info and Logout
  void _showSettings() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings_outlined, color: _primaryColor, size: 24),
            SizedBox(width: 10),
            Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary)),
          ],
        ),
        content: Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            final userEmail = userProvider.email ?? 'user@weldvision.com';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ Show logged-in user email
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.email_outlined, color: _textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          userEmail,
                          style: const TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _buildSettingsItem(icon: Icons.person_outline, title: 'Profile', onTap: () {}),
                _buildSettingsItem(icon: Icons.notifications_outlined, title: 'Notification Preferences', onTap: () {}),
                _buildSettingsItem(icon: Icons.dark_mode_outlined, title: 'Appearance', onTap: () {}),
                _buildSettingsItem(icon: Icons.help_outline, title: 'Help & Support', onTap: () {}),
                _buildSettingsItem(icon: Icons.info_outline, title: 'About', onTap: () {}),
                const Divider(height: 24),
                // ✅ Logout Button
                _buildSettingsItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  textColor: _dangerColor,
                  onTap: () async {
                    Navigator.of(dialogContext).pop(); // Close dialog first
                    
                    await userProvider.logout(); // Clear secure storage
                    
                    if (mounted) {
                      // ✅ Redirect to Login Screen and clear navigation stack
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  // ✅ Updated to support custom text color (for Logout)
  Widget _buildSettingsItem({
    required IconData icon, 
    required String title, 
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? _textSecondary, size: 22),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor ?? _textPrimary)),
      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: textColor ?? _textSecondary),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  // Show update dialog
  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.system_update_outlined, color: _warningColor, size: 24),
            SizedBox(width: 10),
            Text('Update Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 2.1 is ready to download', style: TextStyle(fontSize: 14, color: _textSecondary)),
            SizedBox(height: 16),
            Text('What\'s New:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary)),
            SizedBox(height: 8),
            Text('• Improved defect detection accuracy', style: TextStyle(fontSize: 13, color: _textSecondary)),
            Text('• Faster processing speed', style: TextStyle(fontSize: 13, color: _textSecondary)),
            Text('• Bug fixes and performance improvements', style: TextStyle(fontSize: 13, color: _textSecondary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later', style: TextStyle(fontWeight: FontWeight.w700, color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _warningColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Update started in background'),
                  backgroundColor: _successColor,
                ),
              );
            },
            child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ✅ Bottom nav — Command (this screen) / Models / Result / Train.
  // Only Command is a true "tab" here; the others push their existing
  // full screens so every previously-wired flow keeps working exactly
  // as before, but the tab bar makes the whole app feel like one
  // continuous instrument instead of a stack of separate pages.
  void _handleNavTap(int index) {
    if (index == 0) return; // already on Command
    late final Widget destination;
    switch (index) {
      case 1:
        destination = const ExistingModelsScreen();
        break;
      case 2:
        destination = const ResultsOverviewScreen();
        break;
      case 3:
        destination = const TrainModelScreen();
        break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      bottomNavigationBar: IndustrialNavBar(currentIndex: 0, onTap: _handleNavTap),
      body: DecoratedBox(
        decoration: AppDecor.shopFloor,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: const BlueprintGrid(spacing: 32),
              ),
            ),
            SafeArea(
              child: RefreshIndicator(
                color: _primaryColor,
                backgroundColor: _bgColor,
                onRefresh: _fetchStats,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildTopBar()
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .slideY(begin: -0.2, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 24),

                          _buildHeroCard()
                              .animate()
                              .fadeIn(delay: 100.ms, duration: 500.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 28),

                          _buildSectionHeader(
                            'Production Overview',
                            _loadingStats,
                            _fetchStats,
                            onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResultsOverviewScreen())),
                          ),
                          const SizedBox(height: 16),
                          _buildStatsGrid()
                              .animate()
                              .fadeIn(delay: 200.ms, duration: 500.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 28),

                          _buildSectionHeader('Quick Actions', false, null),
                          const SizedBox(height: 16),
                          _buildQuickActionsGrid()
                              .animate()
                              .fadeIn(delay: 300.ms, duration: 500.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 28),

                          _buildAlertBanner()
                              .animate()
                              .fadeIn(delay: 400.ms, duration: 500.ms),

                          const SizedBox(height: 28),

                          _buildSectionHeader('Select Detection Model', false, null),
                          const SizedBox(height: 16),
                          _DashboardModelCard(
                            tag: '01',
                            title: 'Generic Model',
                            subtitle: 'Broad weld-defect detection trained across multiple weld types. Best for general-purpose inspection.',
                            icon: Icons.hub_outlined,
                            accentColor: const Color(0xFF3B82F6),
                            badges: const ['Image', 'Video', 'Live'],
                            metaLabel: 'Always Available',
                            isRecommended: true,
                            isSelected: true,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen())),
                          ).animate().fadeIn(delay: 500.ms, duration: 450.ms).slideX(begin: -0.04, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 16),

                          _DashboardModelCard(
                            tag: '02',
                            title: 'Specific Model',
                            subtitle: 'Fine-tuned for your weld process — higher accuracy and real-time inference optimised for defined joints.',
                            icon: Icons.my_location_outlined,
                            accentColor: const Color(0xFF8B5CF6),
                            badges: const ['Real-time', 'High Accuracy', 'Custom'],
                            metaLabel: 'Requires Trained Model',
                            isRecommended: false,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SpecificModelScreen())),
                          ).animate().fadeIn(delay: 600.ms, duration: 450.ms).slideX(begin: -0.04, end: 0, curve: Curves.easeOutCubic),

                          const SizedBox(height: 32),

                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _successColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _successColor.withOpacity(0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _LiveDot(color: _successColor),
                                  const SizedBox(width: 8),
                                  Text('System Ready', style: TextStyle(color: _successColor, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ).animate().fadeIn(delay: 700.ms, duration: 400.ms),
                          ),
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

  // ✅ Updated Top Bar to show dynamic user name via Provider
  Widget _buildTopBar() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        final userEmail = userProvider.email ?? 'user@weldvision.com';
        final namePart = userEmail.split('@').first;
        final displayName = namePart.isNotEmpty 
            ? namePart[0].toUpperCase() + namePart.substring(1) 
            : 'User';

        return Row(
          children: [
            // Glowing Avatar
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_primaryColor, Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Container(
                      color: _bgColor,
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
                      color: _successColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bgColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _successColor.withOpacity(0.5),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: _textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Glassmorphic Circular Action Buttons
            _buildGlassIconButton(
              icon: Icons.notifications_none_outlined,
              onTap: _showNotifications,
              badgeCount: _unreadCount,
            ),
            const SizedBox(width: 10),
            _buildGlassIconButton(
              icon: Icons.settings_outlined,
              onTap: _showSettings,
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
                color: _cardColor.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF223049), width: 1.2),
              ),
              child: Icon(icon, color: _textSecondary, size: 20),
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
                color: _dangerColor,
                shape: BoxShape.circle,
                border: Border.all(color: _bgColor, width: 1.5),
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

  Widget _buildHeroCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: _cardColor,
          border: Border.all(color: _primaryColor.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                'https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?auto=format&fit=crop&w=900&q=80',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => Container(color: _cardColor),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : Container(color: _cardColor),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _bgColor.withOpacity(0.98),
                      _bgColor.withOpacity(0.85),
                      _bgColor.withOpacity(0.2),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            // Laser scanning effect
            const Positioned.fill(child: _HeroScannerOverlay()),
            // Tech corner marks
            Positioned(
              left: 12,
              top: 12,
              child: Opacity(
                opacity: 0.3,
                child: Text(
                  'SYSTEM: ACTIVE_SCAN',
                  style: GoogleFonts.orbitron(
                    fontSize: 8,
                    color: _primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: _primaryColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'WELDVISION COGNITIVE CORE',
                        style: GoogleFonts.orbitron(
                          color: _primaryColor.withOpacity(0.95),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ready to Inspect?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 240,
                    child: Text(
                      'Initiate new AI-powered weld scans or review telemetry reports.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageScreen(modelName: null))),
                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                    label: const Text('Start New Inspection', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      shadowColor: _primaryColor.withOpacity(0.35),
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

  Widget _buildSectionHeader(String title, bool isLoading, VoidCallback? onRefresh, {VoidCallback? onViewAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
        if (isLoading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
        else if (onViewAll != null)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('View All', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryColor)),
                  Icon(Icons.chevron_right, size: 18, color: _primaryColor),
                ],
              ),
            ),
          )
        else if (onRefresh != null)
          InkWell(
            onTap: onRefresh,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.refresh, size: 20, color: _textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        _StatCard(title: 'Inspections', value: _stats['inspections']!, trend: '+12%', trendUp: true, icon: Icons.fact_check_outlined, color: _primaryColor),
        _StatCard(title: 'Pass Rate', value: _stats['passRate']!, trend: '+2.1%', trendUp: true, icon: Icons.trending_up, color: _successColor),
        _StatCard(title: 'Avg Defects', value: _stats['avgDefects']!, trend: '-0.5', trendUp: false, icon: Icons.gps_fixed, color: _warningColor),
        _StatCard(title: 'Active Scans', value: _stats['activeScans']!, trend: 'LIVE', trendUp: null, icon: Icons.videocam_outlined, color: const Color(0xFF8B5CF6)),
      ],
    );
  }

  Widget _buildQuickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _QuickActionCard(
          title: 'Image Scan',
          subtitle: 'Upload & Inspect',
          icon: Icons.image_outlined,
          color: const Color(0xFF3B82F6),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageScreen(modelName: null))),
        ),
        _QuickActionCard(
          title: 'Video Scan',
          subtitle: 'Record & Analyze',
          icon: Icons.videocam_outlined,
          color: const Color(0xFF8B5CF6),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoScreen(modelName: null))),
        ),
        _QuickActionCard(
          title: 'Live Stream',
          subtitle: 'Real-time Scan',
          icon: Icons.sensors,
          color: const Color(0xFFFBBF24),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveScreen(modelName: null))),
        ),
        _QuickActionCard(
          title: 'Reports',
          subtitle: 'View Analytics',
          icon: Icons.assessment_outlined,
          color: const Color(0xFF22C55E),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reports feature coming soon!'),
                backgroundColor: _primaryColor,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlertBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _warningColor.withOpacity(0.04),
        border: Border.all(color: _warningColor.withOpacity(0.25), width: 1.2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _warningColor.withOpacity(0.01),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _warningColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_outlined, color: _warningColor, size: 18),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: _LiveDot(color: _warningColor),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MODEL UPDATE DETECTED',
                  style: GoogleFonts.orbitron(
                    fontWeight: FontWeight.w800,
                    color: _warningColor,
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Version 2.1 is available for deployment.',
                  style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _warningColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: _showUpdateDialog,
            child: Text(
              'UPDATE',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroScannerOverlay extends StatefulWidget {
  const _HeroScannerOverlay();

  @override
  State<_HeroScannerOverlay> createState() => _HeroScannerOverlayState();
}

class _HeroScannerOverlayState extends State<_HeroScannerOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final topPos = _controller.value * height;
            return Stack(
              children: [
                Positioned(
                  top: topPos,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.scan,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.scan.withOpacity(0.8),
                          blurRadius: 10,
                          spreadRadius: 1.5,
                        ),
                        BoxShadow(
                          color: AppColors.scan.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: topPos - 30 > 0 ? topPos - 30 : 0,
                  height: topPos - 30 > 0 ? 30 : topPos,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.scan.withOpacity(0.06),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatefulWidget {
  final String title;
  final String value;
  final String trend;
  final bool? trendUp;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.trend,
    required this.trendUp,
    required this.icon,
    required this.color,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final trendColor = widget.trendUp == true 
        ? _successColor 
        : (widget.trendUp == false ? _dangerColor : widget.color);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  widget.color.withOpacity(0.08),
                  widget.color.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.color.withOpacity(_isHovered ? 0.35 : 0.15),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(_isHovered ? 0.12 : 0.04),
                  blurRadius: _isHovered ? 14 : 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Opacity(
                    opacity: 0.05,
                    child: Icon(widget.icon, size: 64, color: widget.color),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.color.withOpacity(0.25),
                              width: 1,
                            ),
                          ),
                          child: Icon(widget.icon, size: 16, color: widget.color),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: trendColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: trendColor.withOpacity(0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.trendUp != null)
                                Icon(
                                  widget.trendUp! ? Icons.arrow_upward : Icons.arrow_downward,
                                  size: 10,
                                  color: trendColor,
                                ),
                              const SizedBox(width: 2),
                              Text(
                                widget.trend,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: trendColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.value,
                          style: GoogleFonts.orbitron(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _textPrimary,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.title.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                            letterSpacing: 0.8,
                          ),
                          maxLines: 1,
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
      ),
    );
  }
}

class _QuickActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered 
                    ? widget.color.withOpacity(0.5) 
                    : const Color(0xFF223049),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHovered ? 0.25 : 0.15),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: const Offset(0, 4),
                ),
                if (_isHovered)
                  BoxShadow(
                    color: widget.color.withOpacity(0.08),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -2,
                  top: -2,
                  child: Opacity(
                    opacity: _isHovered ? 0.4 : 0.15,
                    child: Icon(Icons.crop_free, size: 14, color: widget.color),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.color.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pulse = (sin(_c.value * 2 * pi) + 1) / 2;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [BoxShadow(color: widget.color.withOpacity(0.4 + pulse * 0.4), blurRadius: 4 + pulse * 6, spreadRadius: pulse * 1.5)],
          ),
        );
      },
    );
  }
}

class _DashboardModelCard extends StatefulWidget {
  final String tag;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<String> badges;
  final String metaLabel;
  final bool isRecommended;
  final bool isSelected;
  final VoidCallback onTap;

  const _DashboardModelCard({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.badges,
    required this.metaLabel,
    required this.isRecommended,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  State<_DashboardModelCard> createState() => _DashboardModelCardState();
}

class _DashboardModelCardState extends State<_DashboardModelCard> {
  bool _pressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : (_isHovered ? 1.01 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.isSelected 
                    ? accent 
                    : (_isHovered ? accent.withOpacity(0.4) : const Color(0xFF223049)),
                width: widget.isSelected || _isHovered ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_pressed ? 0.15 : 0.25),
                  blurRadius: _pressed ? 12 : 20,
                  offset: Offset(0, _pressed ? 4 : 8),
                ),
                if (widget.isSelected)
                  BoxShadow(
                    color: accent.withOpacity(0.08),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  if (widget.isSelected)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.08,
                        child: const BlueprintGrid(spacing: 18),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isSelected ? accent : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: accent.withOpacity(0.2)),
                                    ),
                                    child: Text(
                                      widget.tag,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [accent.withOpacity(0.85), accent],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withOpacity(0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(widget.icon, color: Colors.white, size: 24),
                                  ),
                                  const Spacer(),
                                  if (widget.isRecommended)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _successColor.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _successColor.withOpacity(0.25)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 12, color: _successColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            'RECOMMENDED',
                                            style: GoogleFonts.orbitron(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: _successColor,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _primaryColor.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _primaryColor.withOpacity(0.25)),
                                      ),
                                      child: Text(
                                        'PRO',
                                        style: GoogleFonts.orbitron(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: _primaryColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: _textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.subtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _textSecondary,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 13, color: _textSecondary.withOpacity(0.8)),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.metaLabel,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: widget.badges
                                    .map((b) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: accent.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: accent.withOpacity(0.18)),
                                          ),
                                          child: Text(
                                            b.toUpperCase(),
                                            style: GoogleFonts.orbitron(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                              color: accent,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isSelected ? accent : Colors.transparent,
                            border: Border.all(
                              color: widget.isSelected ? accent : const Color(0xFF3A4A66),
                              width: widget.isSelected ? 0 : 2,
                            ),
                          ),
                          child: widget.isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
