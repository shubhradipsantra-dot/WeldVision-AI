import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'result_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _dangerColor = AppColors.fail;

class ImageScreen extends StatefulWidget {
  final String? modelName;
  const ImageScreen({super.key, required this.modelName});

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  final ApiService _apiService = ApiService();

  File? image;
  bool isLoading = false;
  String? errorMessage;

  Future<void> pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery, 
        maxWidth: 1920, // ✅ Optimized for faster upload while maintaining AI accuracy
        maxHeight: 1920, 
        imageQuality: 80
      );
      if (pickedFile == null) return; // User canceled
      
      setState(() { 
        image = File(pickedFile.path); 
        errorMessage = null; 
      });
      await uploadImage();
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = 'Failed to access gallery. Please check app permissions.');
      }
    }
  }

  Future<void> captureImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera, 
        maxWidth: 1920, 
        maxHeight: 1920, 
        imageQuality: 80
      );
      if (pickedFile == null) return; // User canceled
      
      setState(() { 
        image = File(pickedFile.path); 
        errorMessage = null; 
      });
      await uploadImage();
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = 'Failed to access camera. Please check app permissions.');
      }
    }
  }

  void _clearImage() {
    setState(() {
      image = null;
      errorMessage = null;
    });
  }

  Future<void> uploadImage() async {
    if (image == null) return;
    
    setState(() { 
      isLoading = true; 
      errorMessage = null; 
    });
    
    try {
      final data = await _apiService.predictImage(image!, modelName: widget.modelName);
      
      if (!mounted) return;

      // ✅ Safe JSON parsing to prevent crashes on malformed backend responses
      final decisionData = data["decision"] as Map<String, dynamic>?;
      if (decisionData == null) {
        throw Exception("Invalid response format from server");
      }
      
      final String decision = (decisionData["decision"] ?? "UNKNOWN").toString();
      final List<dynamic> defects = decisionData["defects"] is List ? decisionData["defects"] : [];
      final String? error = decisionData["error"]?.toString();
      final String imageUrl = data["image_url"]?.toString() ?? "";

      if (decision == 'RETAKE') {
        setState(() => errorMessage = error != null && error.isNotEmpty
            ? 'Retake photo — ${error[0].toUpperCase()}${error.substring(1)}.' 
            : 'Retake photo — quality check failed. Please ensure the weld is clearly visible.');
        return;
      }
      
      if (mounted) {
        Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              decision: decision, 
              defectCount: defects.length, 
              imageUrl: imageUrl, 
              defects: defects,
            )
          )
        );
      }
      
    } catch (e) {
      if (!mounted) return;
      
      final errorString = e.toString().toLowerCase();
      // ✅ Check for both explicit text and standard HTTP 401 Unauthorized codes
      final isSessionExpired = errorString.contains('session expired') || errorString.contains('401');

      // ✅ FIX: previously this always showed a generic "cannot reach server"
      // message no matter what actually went wrong (timeout, server error,
      // bad response, real network failure). Now we surface what actually
      // happened, with a friendlier label for genuine connectivity issues.
      String friendlyMessage;
      if (isSessionExpired) {
        friendlyMessage = 'Your session has expired. Please log in again.';
      } else if (errorString.contains('took too long') || errorString.contains('timeout')) {
        friendlyMessage = 'The inspection server is taking longer than usual to respond. Please try again.';
      } else if (errorString.contains('socketexception') || errorString.contains('failed host lookup') || errorString.contains('connection refused') || errorString.contains('network is unreachable')) {
        friendlyMessage = 'Could not reach the inspection server. Please check your internet connection.';
      } else {
        final cleanError = e.toString().replaceAll(RegExp(r'^(Exception: |Error: )', caseSensitive: false), '');
        friendlyMessage = 'Inspection failed: $cleanError';
      }

      setState(() {
        errorMessage = friendlyMessage;
      });

      if (isSessionExpired) {
        await Future.delayed(const Duration(seconds: 1)); // Brief pause to show error
        if (mounted) {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.logout();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── CUSTOM TOP BAR ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: _bgColor,
              child: Row(
                children: [
                  _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Image Inspection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                        if (widget.modelName != null)
                          Text('Model: ${widget.modelName}', style: const TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── SCROLLABLE CONTENT ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. PREVIEW AREA ────────────────────────────────
                    _buildPreviewArea(),
                    const SizedBox(height: 24),

                    // ── 2. STATUS AREA (LOADING / ERROR) ───────────────
                    if (isLoading) _buildLoadingState(),
                    if (errorMessage != null && !isLoading) _buildErrorState(),
                    if (isLoading || errorMessage != null) const SizedBox(height: 24),

                    // ── 3. ACTION CARDS ────────────────────────────────
                    const Text('Capture Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                    const SizedBox(height: 16),
                    _buildCaptureCard(
                      title: 'Capture Photo',
                      subtitle: 'Use your camera to take a new picture',
                      icon: Icons.camera_alt_outlined,
                      color: const Color(0xFF3B82F6),
                      onPressed: isLoading ? null : captureImage,
                    ),
                    const SizedBox(height: 12),
                    _buildCaptureCard(
                      title: 'Upload from Gallery',
                      subtitle: 'Select an existing image from your device',
                      icon: Icons.upload_file_outlined,
                      color: const Color(0xFF8B5CF6),
                      onPressed: isLoading ? null : pickImage,
                    ),

                    const SizedBox(height: 32),

                    // ── 4. PRO-TIPS SECTION ────────────────────────────
                    const Text('Tips for best results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                    const SizedBox(height: 16),
                    _buildTipItem(Icons.lightbulb_outline, 'Ensure good lighting', 'Avoid harsh shadows on the weld.'),
                    _buildTipItem(Icons.center_focus_strong, 'Keep it centered', 'Place the weld in the middle of the frame.'),
                    _buildTipItem(Icons.zoom_in, 'Get close enough', 'Fill at least 50% of the frame with the weld.'),
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

  Widget _buildPreviewArea() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: image == null ? Border.all(color: const Color(0xFF2A3B57)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            if (image != null) ...[
              Positioned.fill(child: Image.file(image!, fit: BoxFit.cover)),
              Positioned(
                top: 16, right: 16,
                child: Material(
                  color: Colors.black.withOpacity(0.5),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _clearImage,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_bgColor, _cardColor],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.center_focus_strong, color: _primaryColor, size: 48),
                      ),
                      const SizedBox(height: 24),
                      const Text('No sample loaded', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
                      const SizedBox(height: 8),
                      const Text('Capture or upload a clear weld image', style: TextStyle(fontSize: 14, color: _textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 4),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Analyzing Weld...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
                SizedBox(height: 4),
                Text('AI is processing the image. Please wait.', style: TextStyle(fontSize: 13, color: _textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _dangerColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dangerColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _dangerColor.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.error_outline, color: _dangerColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Inspection Failed', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _dangerColor)),
                const SizedBox(height: 4),
                Text(errorMessage!, style: const TextStyle(fontSize: 13, color: _textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed, // ✅ InkWell automatically disables taps when this is null
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: isEnabled ? const Color(0xFF223049) : const Color(0xFF18213A)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isEnabled ? Colors.black.withOpacity(0.02) : Colors.transparent, 
                blurRadius: 10, 
                offset: const Offset(0, 4)
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: isEnabled 
                    ? LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : const LinearGradient(colors: [Colors.grey, Colors.grey]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isEnabled 
                    ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))] 
                    : null,
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title, 
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w700, 
                        color: isEnabled ? _textPrimary : _textSecondary
                      )
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle, 
                      style: TextStyle(
                        fontSize: 13, 
                        color: isEnabled ? _textSecondary : _textSecondary.withOpacity(0.6)
                      )
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios, 
                size: 16, 
                color: isEnabled ? _textSecondary.withOpacity(0.5) : Colors.transparent
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: _textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}