import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _primaryColor = AppColors.scan;
const Color _textSecondary = Color(0xFF9CA3AF);
const Color _successColor = AppColors.pass;
const Color _warningColor = AppColors.caution;
const Color _dangerColor = AppColors.fail;

class LiveInferenceScreen extends StatefulWidget {
  final String? modelName;
  
  const LiveInferenceScreen({super.key, this.modelName});

  @override
  State<LiveInferenceScreen> createState() => _LiveInferenceScreenState();
}

class _LiveInferenceScreenState extends State<LiveInferenceScreen> {
  CameraController? _cameraController;
  final ApiService _apiService = ApiService();
  
  // ✅ Now stores detections returned from the Cloud Run Gateway
  List<Detection> _currentDetections = [];
  bool _isProcessing = false;
  String _statusMessage = 'Initializing camera...';
  
  Timer? _frameTimer;
  Timer? _fpsUpdateTimer;
  int _frameCount = 0;
  double _fps = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    
    // ✅ Accurate FPS calculation: reset count every second
    _fpsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _frameCount.toDouble();
          _frameCount = 0;
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Medium is the sweet spot for API calls
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() => _statusMessage = 'Camera ready');
        _startFrameProcessing();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Camera error: ${e.toString()}');
      }
    }
  }

  void _startFrameProcessing() {
    // ✅ Process at ~2 FPS (500ms) to prevent network overload and lag
    // Live API inference is heavier than local TFLite, so we throttle it.
    _frameTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_cameraController?.value.isStreamingImages == true && !_isProcessing) {
        await _processFrame();
      }
    });
  }

  Future<void> _processFrame() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() => _isProcessing = true);

    try {
      // 1. Capture frame
      final image = await _cameraController!.takePicture();
      final file = File(image.path);
      
      if (!mounted) {
        await file.delete().catchError((_) => file);
        return;
      }
      
      // 2. Send to Cloud Run Gateway (which forwards to Local GPU)
      final response = await _apiService.predictFrame(file, modelName: widget.modelName);
      
      if (mounted) {
        // 3. Map the API response to our Detection class
        final List<dynamic> defects = response['defects'] ?? [];
        final mappedDetections = defects.map<Detection>((d) {
          return Detection(
            // The local server returns 'class', but we support 'type' for backward compatibility
            className: (d['class'] ?? d['type'] ?? 'Unknown').toString(),
            confidence: (d['confidence'] ?? 0.0).toDouble(),
            // The local server returns normalized coordinates (0.0 to 1.0)
            x: (d['x'] ?? 0.0).toDouble(),
            y: (d['y'] ?? 0.0).toDouble(),
            width: (d['width'] ?? 0.0).toDouble(),
            height: (d['height'] ?? 0.0).toDouble(),
          );
        }).toList();

        setState(() {
          _currentDetections = mappedDetections;
          _frameCount++;
        });
      }
      
      // 4. Clean up temp file safely
      await file.delete().catchError((_) => file);
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _fpsUpdateTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          ),
          
          // 2. Detection Overlays (High-Performance CustomPaint)
          Positioned.fill(
            child: CustomPaint(
              painter: _DetectionOverlayPainter(detections: _currentDetections),
            ),
          ),
          
          // 3. Premium Glassmorphism Status Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC111827), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  // Close Button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      shape: const CircleBorder(),
                      side: const BorderSide(color: Colors.white10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Status Pill
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _successColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromRGBO(16, 185, 129, 0.6),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Metrics Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${_fps.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.visibility, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${_currentDetections.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── HIGH-PERFORMANCE DETECTION OVERLAY PAINTER ───────────────────────
class _DetectionOverlayPainter extends CustomPainter {
  final List<Detection> detections;

  _DetectionOverlayPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      // Coordinates are already normalized (0.0 to 1.0) by the Local GPU Server
      final left = detection.x * size.width;
      final top = detection.y * size.height;
      final width = detection.width * size.width;
      final height = detection.height * size.height;

      final rect = Rect.fromLTWH(left, top, width, height);
      final color = _getDefectColor(detection.className);

      // 1. Draw bounding box
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(rect, boxPaint);

      // 2. Prepare label text
      final label = '${detection.className} ${(detection.confidence * 100).toInt()}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // 3. Position label (above the box if there's room, otherwise below)
      final labelTop = top > (textPainter.height + 8) 
          ? top - textPainter.height - 8 
          : top + height + 4;
          
      final labelRect = Rect.fromLTWH(
        left,
        labelTop,
        textPainter.width + 16,
        textPainter.height + 8,
      );

      // 4. Draw rounded label background
      final bgPaint = Paint()..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
        bgPaint,
      );

      // 5. Draw label text
      textPainter.paint(canvas, Offset(labelRect.left + 8, labelRect.top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }

  Color _getDefectColor(String defectType) {
    final type = defectType.toLowerCase();
    if (type.contains('normal')) return _successColor;
    if (type.contains('porosity')) return _warningColor;
    if (type.contains('spatter')) return _dangerColor;
    if (type.contains('crack')) return _dangerColor;
    if (type.contains('undercut')) return const Color(0xFFFFD700); // Yellow
    if (type.contains('fusion')) return const Color(0xFF8B5CF6); // Purple
    if (type.contains('slag')) return const Color(0xFF3B82F6); // Blue
    return Colors.white;
  }
}

// ─── HELPER CLASS ───────────────────────────────────────────────────────
class Detection {
  final String className;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  Detection({
    required this.className,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}