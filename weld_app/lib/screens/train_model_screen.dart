import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../services/active_training_service.dart';
import '../theme/app_theme.dart';
import '../widgets/industrial_widgets.dart';
import 'login_screen.dart';
import 'training_progress_screen.dart';
import 'video_upload_progress_screen.dart';
import 'existing_models_screen.dart';
import 'results_overview_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _dangerColor = AppColors.fail;

class TrainModelScreen extends StatefulWidget {
  const TrainModelScreen({super.key});

  @override
  State<TrainModelScreen> createState() => _TrainModelScreenState();
}

class _TrainModelScreenState extends State<TrainModelScreen> {
  final ApiService _apiService = ApiService();
  bool _isUploading = false; // ✅ Prevents multiple simultaneous uploads

  @override
  void initState() {
    super.initState();
    ActiveTrainingService.instance.load();
  }

  Future<void> _handleSessionExpired(BuildContext context) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    await userProvider.logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _pickVideo(BuildContext context) async {
    if (_isUploading) return;
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    await _goToUploadScreen(context, video);
  }

  Future<void> _recordVideo(BuildContext context) async {
    if (_isUploading) return;
    final video = await ImagePicker().pickVideo(
      source: ImageSource.camera, 
      maxDuration: const Duration(minutes: 2)
    );
    if (video == null) return;
    await _goToUploadScreen(context, video);
  }

  Future<void> _goToUploadScreen(BuildContext context, XFile video) async {
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoUploadProgressScreen(videoFile: File(video.path))),
    );
    // Refresh the "active training" card in case an upload finished/started
    // while this screen was in the background.
    if (mounted) await ActiveTrainingService.instance.load();
  }

  Future<void> _pickImageFolder(BuildContext context) async {
    if (_isUploading) return;
    final images = await ImagePicker().pickMultiImage();
    if (images.isEmpty) return;
    await _uploadImages(context, images);
  }

  Future<void> _uploadImages(BuildContext context, List<XFile> images) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Uploading ${images.length} images..."),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))), // ✅ FIXED
        ),
      );
      
      final data = await _apiService.trainModelImages(images.map((e) => File(e.path)).toList());
      final jobId = data["job_id"] as String;
      
      await ActiveTrainingService.instance.setActive(jobId);
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Training started\nJob ID: $jobId"), 
          backgroundColor: _successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))), // ✅ FIXED
        ),
      );
      Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingProgressScreen(jobId: jobId)));
    } catch (e) {
      if (!context.mounted) return;
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('session expired') || errorString.contains('401')) {
        await _handleSessionExpired(context);
        return;
      }
      final cleanError = e.toString().replaceAll(RegExp(r'^(Exception: |Error: )', caseSensitive: false), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Upload failed: $cleanError"), 
          backgroundColor: _dangerColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))), // ✅ FIXED
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _resumeActiveJob(String jobId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingProgressScreen(jobId: jobId)));
  }

  void _handleNavTap(int index) {
    if (index == 3) return; // already on Train
    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    late final Widget destination;
    switch (index) {
      case 1:
        destination = const ExistingModelsScreen();
        break;
      case 2:
        destination = const ResultsOverviewScreen();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      bottomNavigationBar: IndustrialNavBar(currentIndex: 3, onTap: _handleNavTap),
      body: SafeArea(
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
                    ValueListenableBuilder<ActiveTrainingJob?>(
                      valueListenable: ActiveTrainingService.instance.current,
                      builder: (context, job, _) {
                        if (job == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ActiveTrainingCard(job: job, onTap: () => _resumeActiveJob(job.jobId)),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    const Text(
                      'Training Data Source', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)
                    ).animate().fadeIn(duration: 400.ms),
                    const SizedBox(height: 16),
                    
                    _buildSourceCard(
                      title: 'Upload Recorded Video',
                      subtitle: 'Use an existing weld inspection video to create a custom model.',
                      icon: Icons.video_library_outlined,
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _pickVideo(context),
                    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
                    
                    const SizedBox(height: 12),
                    
                    _buildSourceCard(
                      title: 'Capture Live Video',
                      subtitle: 'Record a new weld process video directly from the camera.',
                      icon: Icons.videocam_outlined,
                      color: const Color(0xFF3B82F6),
                      onTap: () => _recordVideo(context),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
                    
                    const SizedBox(height: 12),
                    
                    _buildSourceCard(
                      title: 'Upload Image Folder',
                      subtitle: 'Use a folder of already-captured weld images — skips frame extraction.',
                      icon: Icons.folder_outlined,
                      color: _successColor,
                      onTap: () => _pickImageFolder(context),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 32),

                    const Text(
                      'Training Workflow', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)
                    ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                    const SizedBox(height: 16),
                    
                    _buildWorkflowCard()
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 400.ms)
                        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
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
        children: [
          _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Train New Model', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                Text('AI Training Pipeline', style: TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500)),
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

  Widget _buildSourceCard({
    required String title, 
    required String subtitle, 
    required IconData icon, 
    required Color color, 
    required VoidCallback onTap
  }) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
      child: InkWell(
        onTap: _isUploading ? null : onTap, // ✅ Disable tap while uploading
        borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF223049)),
            borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.all(Radius.circular(16)), // ✅ FIXED
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
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: _textSecondary, height: 1.3)),
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

  Widget _buildWorkflowCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
        border: Border.all(color: const Color(0xFF223049)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.all(Radius.circular(10))), // ✅ FIXED
                child: const Icon(Icons.route_outlined, color: _primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Pipeline Steps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 24),
          _buildStep(1, 'Data Ingestion', 'Upload video or image folder', isLast: false),
          _buildStep(2, 'Frame Extraction', 'Sample frames for analysis', isLast: false),
          _buildStep(3, 'Auto Annotation', 'Generic model labels defects', isLast: false),
          _buildStep(4, 'YOLO Training', 'Fine-tune on your specific data', isLast: false),
          _buildStep(5, 'Model Export', 'Package for deployment', isLast: true),
        ],
      ),
    );
  }

  // ✅ Enhanced with a connecting vertical timeline line
  Widget _buildStep(int step, String title, String desc, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28, height: 28, alignment: Alignment.center,
              decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Text('$step', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _primaryColor)),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 48,
                color: _primaryColor.withOpacity(0.2),
                margin: const EdgeInsets.only(top: 4, bottom: 4),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 12, color: _textSecondary, height: 1.3)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// ACTIVE TRAINING CARD & HELPERS
// ════════════════════════════════════════════════════════════════════════

class _ActiveTrainingCard extends StatefulWidget {
  final ActiveTrainingJob job;
  final VoidCallback onTap;
  const _ActiveTrainingCard({required this.job, required this.onTap});
  
  @override
  State<_ActiveTrainingCard> createState() => _ActiveTrainingCardState();
}

class _ActiveTrainingCardState extends State<_ActiveTrainingCard> with TickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  late final AnimationController _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.job.suggestedName != null ? 'Training "${widget.job.suggestedName}"' : 'Model Training in Progress';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.all(Radius.circular(20)), // ✅ FIXED
            border: Border.all(color: _primaryColor.withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_pulseController, _spinController]),
                builder: (_, __) => SizedBox(
                  width: 56, height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primaryColor.withOpacity(0.08 + 0.10 * _pulseController.value),
                        ),
                      ),
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primaryColor.withOpacity(0.1),
                          border: Border.all(color: _primaryColor.withOpacity(0.4)),
                        ),
                        child: RotationTransition(
                          turns: _spinController,
                          child: const Icon(Icons.settings, color: _primaryColor, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        const _LiveDot(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Tap to view progress', style: TextStyle(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  
  @override
  void dispose() { 
    _controller.dispose(); 
    super.dispose(); 
  }
  
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _primaryColor, shape: BoxShape.circle)),
    );
  }
}