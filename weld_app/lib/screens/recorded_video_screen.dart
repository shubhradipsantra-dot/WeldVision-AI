import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:provider/provider.dart';

import '../models/video_inspection_models.dart';
import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _warningColor = AppColors.caution;
const Color _dangerColor = AppColors.fail;

enum _ScreenState { idle, uploading, processing, ready, error }

class RecordedVideoScreen extends StatefulWidget {
  final String? modelName;
  const RecordedVideoScreen({super.key, this.modelName});

  @override
  State<RecordedVideoScreen> createState() => _RecordedVideoScreenState();
}

class _RecordedVideoScreenState extends State<RecordedVideoScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  _ScreenState _state = _ScreenState.idle;
  String? _errorMessage;
  VideoJobStatus? _jobStatus;

  Timer? _pollTimer;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadVideo() async {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() {
      _state = _ScreenState.uploading;
      _errorMessage = null;
      _jobStatus = null;
    });

    try {
      final jobId = await _apiService.uploadVideo(
        File(picked.path),
        modelName: widget.modelName,
      );
      
      if (!mounted) return;
      setState(() => _state = _ScreenState.processing);
      _startPolling(jobId);
    } catch (e) {
      if (!mounted) return;
      
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('session expired') || errorString.contains('401')) {
        await _handleSessionExpired();
        return;
      }

      setState(() {
        _state = _ScreenState.error;
        _errorMessage = _cleanErrorMessage(e.toString());
      });
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final status = await _apiService.getVideoStatus(jobId);
        if (!mounted) return;
        
        setState(() => _jobStatus = status);

        if (status.isDone) {
          _pollTimer?.cancel();
          _initializePlayer(jobId);
        } else if (status.isFailed) {
          _pollTimer?.cancel();
          setState(() {
            _state = _ScreenState.error;
            _errorMessage = status.error ?? 'Processing failed on the server.';
          });
        }
      } catch (e) {
        _pollTimer?.cancel();
        if (!mounted) return;

        final errorString = e.toString().toLowerCase();
        if (errorString.contains('session expired') || errorString.contains('401')) {
          await _handleSessionExpired();
          return;
        }

        setState(() {
          _state = _ScreenState.error;
          _errorMessage = _cleanErrorMessage('Status check failed: $e');
        });
      }
    });
  }

  Future<void> _handleSessionExpired() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    await userProvider.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _initializePlayer(String jobId) async {
    try {
      final videoUrl = _apiService.getVideoResultUrl(jobId);
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      
      await controller.initialize();
      if (!mounted) return;

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryColor,
          handleColor: _primaryColor,
          bufferedColor: _primaryColor.withOpacity(0.3),
          backgroundColor: _textPrimary.withOpacity(0.1),
        ),
      );

      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _state = _ScreenState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScreenState.error;
        _errorMessage = _cleanErrorMessage('Video playback initialization failed: $e');
      });
    }
  }

  void _seekTo(double seconds) {
    if (_videoController?.value.isInitialized == true) {
      _videoController?.seekTo(Duration(milliseconds: (seconds * 1000).round()));
      _chewieController?.play();
    }
  }

  void _reset() {
    _pollTimer?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
    setState(() {
      _state = _ScreenState.idle;
      _jobStatus = null;
      _errorMessage = null;
      _chewieController = null;
      _videoController = null;
    });
  }

  String _cleanErrorMessage(String error) {
    return error.replaceAll(RegExp(r'^(Exception: |Error: )', caseSensitive: false), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: switch (_state) {
                _ScreenState.idle => _buildIdleState(),
                _ScreenState.uploading => _buildBusyState(
                    title: 'Uploading Video', 
                    subtitle: 'Sending footage to the inspection server…'
                  ),
                _ScreenState.processing => _buildProcessingState(),
                _ScreenState.ready => _buildReadyState(),
                _ScreenState.error => _buildErrorState(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── WIDGET BUILDERS ────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: _bgColor,
      child: Row(
        children: [
          _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('Recorded Video', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
          ),
          if (_state == _ScreenState.ready || _state == _ScreenState.error)
            Tooltip(
              message: 'Analyze another video',
              child: _buildCircleButton(Icons.refresh, _reset, iconColor: _primaryColor),
            ),
        ],
      ),
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
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildIdleState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), _primaryColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: const Icon(Icons.video_library_outlined, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 32),
            const Text('Analyze Recorded Footage', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.5), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('Upload a weld inspection clip to scan it for defects. The system samples frames, runs AI detection, and returns an annotated video.', style: TextStyle(fontSize: 15, color: _textSecondary, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickAndUploadVideo,
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                label: const Text('Select Video', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyState({required String title, required String subtitle}) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                child: const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 4, color: _primaryColor)),
              ),
              const SizedBox(height: 32),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textPrimary), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: _textSecondary), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingState() {
    final progress = _jobStatus?.progress ?? 0.0;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120, height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120, height: 120,
                      child: CircularProgressIndicator(
                        value: progress > 0 ? progress / 100 : null, // null makes it indeterminate if progress is 0
                        strokeWidth: 8,
                        color: _primaryColor,
                        backgroundColor: _primaryColor.withOpacity(0.1),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${progress.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -1)),
                        const Text('Complete', style: TextStyle(fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text('Scanning for Defects', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Sampling frames and running weld inspection.\nThis may take a few minutes.', style: TextStyle(fontSize: 14, color: _textSecondary, height: 1.5), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _warningColor.withOpacity(0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 16, color: _warningColor),
                    SizedBox(width: 8),
                    Text('Processing', style: TextStyle(color: _warningColor, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _dangerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.error_outline, color: _dangerColor, size: 48),
            ),
            const SizedBox(height: 32),
            const Text('Something Went Wrong', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'Unknown error', style: const TextStyle(fontSize: 14, color: _textSecondary, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Try Again', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyState() {
    final status = _jobStatus;
    if (status == null || _chewieController == null || _videoController == null) {
      return const Center(child: CircularProgressIndicator(color: _primaryColor));
    }

    final decisionColor = switch (status.decision?.toUpperCase()) {
      'ACCEPT' => _successColor,
      'REVIEW' => _warningColor,
      'REJECT' => _dangerColor,
      _ => _textSecondary,
    };

    final aspectRatio = _videoController!.value.aspectRatio;
    final safeAspectRatio = (aspectRatio > 0) ? aspectRatio : 16 / 9;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video Player
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: safeAspectRatio,
                child: Chewie(controller: _chewieController!),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Decision Summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF223049)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: decisionColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: decisionColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    status.decision?.toUpperCase() ?? 'UNKNOWN',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: decisionColor, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${status.defectCount} Defect(s) Found', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                      const SizedBox(height: 4),
                      const Text('Tap a defect below to jump to that timestamp', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Defect Timeline Header
          Row(
            children: [
              Container(
                width: 4, 
                height: 20, 
                decoration: BoxDecoration(
                  color: _primaryColor, 
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text('DEFECT TIMELINE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 16),

          if (status.defects.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF223049)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _successColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.verified_outlined, color: _successColor, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text('No defects detected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                  const SizedBox(height: 4),
                  const Text('This clip passed all quality checks.', style: TextStyle(fontSize: 13, color: _textSecondary)),
                ],
              ),
            )
          else
            ...status.defects.map(_buildDefectRow),
        ],
      ),
    );
  }

  Widget _buildDefectRow(VideoDefect defect) {
    final isMajor = defect.severity.toUpperCase() == 'MAJOR';
    final severityColor = isMajor ? _dangerColor : _warningColor;
    final minutes = (defect.timestampSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (defect.timestampSec % 60).toString().padLeft(2, '0');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _seekTo(defect.timestampSec),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF223049)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$minutes:$seconds', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: severityColor)),
                    const SizedBox(height: 2),
                    Text(isMajor ? 'MAJOR' : 'MINOR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: severityColor.withOpacity(0.8), letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(defect.type, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMiniStat(Icons.percent_outlined, '${(defect.confidence * 100).toStringAsFixed(0)}%'),
                        const SizedBox(width: 12),
                        _buildMiniStat(Icons.square_foot_outlined, '${defect.areaMm2.toStringAsFixed(2)} mm²'),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_circle_outline, color: _primaryColor, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _textSecondary),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textSecondary)),
      ],
    );
  }
}