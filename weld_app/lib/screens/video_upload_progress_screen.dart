import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../services/active_training_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'training_progress_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _dangerColor = AppColors.fail;

/// Shown while a video is uploading directly to GCS. Large files (100s of
/// MB - GBs) can take a while, so this gives the user a live percentage
/// instead of a frozen spinner / snackbar. On success it hands off to
/// [TrainingProgressScreen]; on failure it lets the user retry or go back.
class VideoUploadProgressScreen extends StatefulWidget {
  final File videoFile;
  const VideoUploadProgressScreen({super.key, required this.videoFile});

  @override
  State<VideoUploadProgressScreen> createState() => _VideoUploadProgressScreenState();
}

class _VideoUploadProgressScreenState extends State<VideoUploadProgressScreen> {
  final ApiService _apiService = ApiService();

  double _progress = 0.0; // 0.0 - 1.0
  int _totalBytes = 0;
  bool _failed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.videoFile.lengthSync();
    _startUpload();
  }

  Future<void> _startUpload() async {
    setState(() {
      _failed = false;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      final data = await _apiService.trainModel(
        widget.videoFile,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final jobId = data["job_id"] as String;
      await ActiveTrainingService.instance.setActive(jobId);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => TrainingProgressScreen(jobId: jobId)),
      );
    } catch (e) {
      if (!mounted) return;
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('session expired') || errorString.contains('401')) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.logout();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      final cleanError = e.toString().replaceAll(RegExp(r'^(Exception: |Error: )', caseSensitive: false), '');
      setState(() {
        _failed = true;
        _errorMessage = cleanError;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final uploadedBytes = (_progress * _totalBytes).round();
    final percentLabel = '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return PopScope(
      canPop: _failed, // don't let the user swipe/back away mid-upload
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          automaticallyImplyLeading: _failed,
          title: const Text('Uploading Video', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_failed) ...[
                  _buildUploadingCard(percentLabel, uploadedBytes),
                ] else ...[
                  _buildErrorCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadingCard(String percentLabel, int uploadedBytes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: const Color(0xFF223049)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  strokeWidth: 6,
                  backgroundColor: _primaryColor.withOpacity(0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
                ),
              ),
              Text(percentLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
            ],
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 24),
          const Text(
            'Uploading video to secure storage…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatBytes(uploadedBytes)} of ${_formatBytes(_totalBytes)}',
            style: const TextStyle(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 8,
              backgroundColor: _primaryColor.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Please keep the app open and stay on Wi-Fi if possible.\nThis can take a few minutes for large files.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: _dangerColor.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _dangerColor.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.error_outline, color: _dangerColor, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Upload Failed',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Something went wrong while uploading.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _textSecondary.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _startUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}