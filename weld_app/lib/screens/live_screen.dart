import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _primaryColor = AppColors.scan;
const Color _successColor = AppColors.pass;
const Color _dangerColor = AppColors.fail;

class LiveScreen extends StatefulWidget {
  final String? modelName;
  const LiveScreen({super.key, required this.modelName});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final ApiService _apiService = ApiService();

  CameraController? controller;
  List<Map<String, dynamic>> defects = [];
  String decision = "";
  bool processing = false;
  String? connectionError;
  double imageWidth = 640;
  double imageHeight = 640;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      
      controller = CameraController(backCamera, ResolutionPreset.medium);
      await controller!.initialize();
      
      if (!mounted) return;
      setState(() {});
      startDetection();
    } catch (e) {
      if (mounted) {
        setState(() {
          connectionError = 'Camera initialization failed: $e';
        });
      }
    }
  }

  void startDetection() {
    _runDetectionLoop();
  }

  Future<void> _runDetectionLoop() async {
    while (mounted && controller?.value.isInitialized == true) {
      if (!processing) {
        processing = true;
        try {
          final file = await controller!.takePicture();
          await uploadFrame(File(file.path));
          final fileToDelete = File(file.path);
          await fileToDelete.delete().catchError((_) => fileToDelete);
        } catch (e) {
          debugPrint("Live Detection Error: $e");
        } finally {
          processing = false;
        }
      }
      // Wait 1 second after processing completes before grabbing the next frame
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> uploadFrame(File image) async {
    try {
      final data = await _apiService.predictFrame(image, modelName: widget.modelName);

      if (!mounted) return;
      setState(() {
        decision = data["decision"]?.toString() ?? "";
        // ✅ The Gateway returns "defects" with normalized x, y, width, height
        defects = (data["defects"] as List?)?.cast<Map<String, dynamic>>() ?? [];
        imageWidth = (data["image_width"] ?? 640).toDouble();
        imageHeight = (data["image_height"] ?? 640).toDouble();
        connectionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      
      final errorString = e.toString().toLowerCase();
      final isSessionExpired = errorString.contains('session expired') || errorString.contains('401');
      
      setState(() {
        connectionError = isSessionExpired 
            ? 'Session expired. Redirecting...' 
            : 'Signal lost — reconnecting...';
      });

      if (isSessionExpired) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Color _decisionColor() {
    final dec = decision.toUpperCase();
    if (dec == 'ACCEPT') return _successColor;
    if (dec == 'REJECT') return _dangerColor;
    return _primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              const Text('INITIALIZING CAMERA...', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Please grant camera permissions if prompted.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller!),
                CustomPaint(
                  size: Size.infinite,
                  painter: DefectPainter(defects, imageWidth, imageHeight),
                ),
              ],
            ),
          ),

          const Positioned.fill(child: _ViewfinderCorners()),

          Positioned(
            top: 0, left: 0, right: 0, height: 160,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
          ),

          Positioned(
            top: 50, left: 20, right: 20,
            child: Row(
              children: [
                _GlassButton(icon: Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LIVE INSPECTION',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.modelName != null)
                        Text(
                          widget.modelName!,
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _GlassButton(icon: Icons.stop_circle_outlined, onTap: () => Navigator.pop(context), color: _dangerColor),
              ],
            ),
          ),

          Positioned(
            top: 110, left: 20,
            child: _GlassCard(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlowingDot(color: _decisionColor()),
                  const SizedBox(width: 8),
                  Text(
                    decision.isEmpty ? 'ANALYZING' : decision.toUpperCase(),
                    style: TextStyle(color: _decisionColor(), fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 110, right: 20,
            child: _GlassCard(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LiveDot(),
                  const SizedBox(width: 8),
                  const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                ],
              ),
            ),
          ),

          if (connectionError != null)
            Positioned(
              left: 20, right: 20, top: 170,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _dangerColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _dangerColor.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: _dangerColor, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(connectionError!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 0, left: 0, right: 0, height: 200,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Colors.transparent],
                ),
              ),
            ),
          ),

          Positioned(
            left: 20, right: 20, bottom: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('DEFECTS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(
                        '${defects.length}',
                        style: TextStyle(color: defects.isEmpty ? _successColor : _dangerColor, fontWeight: FontWeight.w900, fontSize: 24),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const _CaptureCycleIndicator(),
                const Spacer(),
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('STATUS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi, size: 14, color: connectionError == null ? _successColor : _dangerColor),
                          const SizedBox(width: 4),
                          Text(
                            connectionError == null ? 'CONNECTED' : 'LOST',
                            style: TextStyle(color: connectionError == null ? _successColor : _dangerColor, fontWeight: FontWeight.w800, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// HUD HELPER WIDGETS (Unchanged, they are perfect)
// ════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _GlassButton({required this.icon, required this.onTap, this.color = Colors.white});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: Colors.white24, width: 1)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _GlowingDot extends StatelessWidget {
  final Color color;
  const _GlowingDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)],
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
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _dangerColor, shape: BoxShape.circle)),
    );
  }
}

class _CaptureCycleIndicator extends StatefulWidget {
  const _CaptureCycleIndicator();
  @override
  State<_CaptureCycleIndicator> createState() => _CaptureCycleIndicatorState();
}

class _CaptureCycleIndicatorState extends State<_CaptureCycleIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
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
        return CustomPaint(
          size: const Size(48, 48),
          painter: _CyclePainter(_controller.value),
          child: const Center(
            child: Icon(Icons.center_focus_strong, color: Colors.white, size: 18),
          ),
        );
      },
    );
  }
}

class _CyclePainter extends CustomPainter {
  final double progress;
  _CyclePainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 2..style = PaintingStyle.stroke);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, 2 * math.pi * progress, false,
      Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
    );
  }
  @override
  bool shouldRepaint(covariant _CyclePainter oldDelegate) => oldDelegate.progress != progress;
}

class _ViewfinderCorners extends StatelessWidget {
  const _ViewfinderCorners();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _ViewfinderPainter());
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.4)..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final cornerLength = 30.0;
    final margin = 40.0;
    canvas.drawLine(Offset(margin, margin), Offset(margin + cornerLength, margin), paint);
    canvas.drawLine(Offset(margin, margin), Offset(margin, margin + cornerLength), paint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin - cornerLength, margin), paint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + cornerLength), paint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin + cornerLength, size.height - margin), paint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin, size.height - margin - cornerLength), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin), Offset(size.width - margin - cornerLength, size.height - margin), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin), Offset(size.width - margin, size.height - margin - cornerLength), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ════════════════════════════════════════════════════════════════════════
// ✅ UPDATED DEFECT PAINTER (Handles Normalized Gateway Coordinates)
// ════════════════════════════════════════════════════════════════════════

class DefectPainter extends CustomPainter {
  final List<Map<String, dynamic>> defects;
  final double imageWidth;
  final double imageHeight;

  DefectPainter(this.defects, this.imageWidth, this.imageHeight);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    final bracketPaint = Paint()
      ..color = _dangerColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cornerLength = 20.0;

    for (final d in defects) {
      double x, y, w, h;

      // ✅ Support BOTH normalized coordinates (from Local GPU Gateway) and absolute bbox (fallback)
      if (d.containsKey('x') && d.containsKey('y') && d.containsKey('width') && d.containsKey('height')) {
        x = (d['x'] as num).toDouble() * size.width;
        y = (d['y'] as num).toDouble() * size.height;
        w = (d['width'] as num).toDouble() * size.width;
        h = (d['height'] as num).toDouble() * size.height;
      } else {
        final bbox = d["bbox"];
        if (bbox is! List || bbox.length < 4) continue;
        final scaleX = size.width / imageWidth;
        final scaleY = size.height / imageHeight;
        x = (bbox[0] as num).toDouble() * scaleX;
        y = (bbox[1] as num).toDouble() * scaleY;
        w = (bbox[2] as num).toDouble() * scaleX;
        h = (bbox[3] as num).toDouble() * scaleY;
      }

      // Top Left
      canvas.drawLine(Offset(x, y), Offset(x + cornerLength, y), bracketPaint);
      canvas.drawLine(Offset(x, y), Offset(x, y + cornerLength), bracketPaint);
      // Top Right
      canvas.drawLine(Offset(x + w, y), Offset(x + w - cornerLength, y), bracketPaint);
      canvas.drawLine(Offset(x + w, y), Offset(x + w, y + cornerLength), bracketPaint);
      // Bottom Left
      canvas.drawLine(Offset(x, y + h), Offset(x + cornerLength, y + h), bracketPaint);
      canvas.drawLine(Offset(x, y + h), Offset(x, y + h - cornerLength), bracketPaint);
      // Bottom Right
      canvas.drawLine(Offset(x + w, y + h), Offset(x + w - cornerLength, y + h), bracketPaint);
      canvas.drawLine(Offset(x + w, y + h), Offset(x + w, y + h - cornerLength), bracketPaint);

      // Label
      final type = (d["class"] ?? d["type"] ?? 'Defect').toString();
      final textPainter = TextPainter(
        text: TextSpan(
          text: " $type ",
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelY = y > 24 ? y - 24 : y + h + 4;
      final bgRect = Rect.fromLTWH(x, labelY, textPainter.width, 20);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = _dangerColor,
      );
      textPainter.paint(canvas, Offset(x, labelY + 2));
    }
  }

  @override
  bool shouldRepaint(covariant DefectPainter oldDelegate) {
    return oldDelegate.defects != defects || 
           oldDelegate.imageWidth != imageWidth || 
           oldDelegate.imageHeight != imageHeight;
  }
}