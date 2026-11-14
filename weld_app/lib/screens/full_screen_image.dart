import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class FullScreenImage extends StatefulWidget {
  final String imageUrl;
  final Map<String, String>? headers;
  final String? heroTag;
  final String title;

  const FullScreenImage({
    super.key,
    required this.imageUrl,
    this.headers,
    this.heroTag,
    this.title = 'Defect Inspection',
  });

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  
  Map<String, String>? _headers;
  bool _isLoadingHeaders = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animation != null) {
          _transformationController.value = _animation!.value;
        }
      });
    _loadHeaders();
  }

  Future<void> _loadHeaders() async {
    if (widget.headers != null) {
      if (mounted) {
        setState(() {
          _headers = widget.headers;
          _isLoadingHeaders = false;
        });
      }
    } else {
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
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = _Matrix4Tween(
      begin: _transformationController.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward(from: 0.0);
  }

  void _zoom(double factor) {
    final startMatrix = Matrix4.copy(_transformationController.value);
    final scale = startMatrix.getMaxScaleOnAxis();
    final newScale = (scale * factor).clamp(1.0, 12.0);
    
    if ((newScale - scale).abs() < 0.01) return;

    final size = MediaQuery.of(context).size;
    final focalPoint = Offset(size.width / 2, size.height / 2);
    
    final actualScaleFactor = newScale / scale;
    
    final zoomMatrix = Matrix4.identity()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(actualScaleFactor, actualScaleFactor)
      ..translate(-focalPoint.dx, -focalPoint.dy);
      
    final endMatrix = zoomMatrix * startMatrix;
    _animateTo(endMatrix);
  }

  void _resetZoom() {
    _animateTo(Matrix4.identity());
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.black45, Colors.transparent],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoadingHeaders
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : GestureDetector(
                    onDoubleTap: () {
                      final scale = _transformationController.value.getMaxScaleOnAxis();
                      if (scale > 1.1) {
                        _resetZoom();
                      } else {
                        _zoom(2.5);
                      }
                    },
                    child: widget.heroTag != null
                        ? Hero(tag: widget.heroTag!, child: _buildImageViewer())
                        : _buildImageViewer(),
                  ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32 + bottomPadding,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.all(Radius.circular(30)),
                border: Border.all(color: Colors.white10),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(Icons.remove, 'Zoom Out', () => _zoom(0.8)),
                  _buildControlButton(Icons.center_focus_strong, 'Reset View', _resetZoom),
                  _buildControlButton(Icons.add, 'Zoom In', () => _zoom(1.25)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 12.0,
      panEnabled: true,
      boundaryMargin: const EdgeInsets.all(100),
      child: Image.network(
        widget.imageUrl,
        headers: _headers ?? {},
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Loading image...', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                  child: const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('Failed to load image', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Please check your connection and try again.', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _Matrix4Tween extends Tween<Matrix4> {
  _Matrix4Tween({Matrix4? begin, Matrix4? end}) : super(begin: begin, end: end);

  @override
  Matrix4 lerp(double t) {
    final b = begin!.storage;
    final e = end!.storage;
    final result = Matrix4.zero();
    for (int i = 0; i < 16; i++) {
      result.storage[i] = b[i] + (e[i] - b[i]) * t;
    }
    return result;
  }
}
