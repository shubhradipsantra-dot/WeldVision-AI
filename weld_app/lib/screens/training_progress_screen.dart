import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/active_training_service.dart';
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
const Color _dangerColor = AppColors.fail;

// ---------------------------------------------------------------------------
// Training pipeline steps
// ---------------------------------------------------------------------------
class _TrainingStep {
  final String label;
  final String description;
  final IconData icon;
  final double start;
  final double end;

  const _TrainingStep({
    required this.label,
    required this.description,
    required this.icon,
    required this.start,
    required this.end,
  });
}

const List<_TrainingStep> _kSteps = [
  _TrainingStep(label: 'Frame Extraction', description: 'Sampling frames from the video', icon: Icons.movie_filter_outlined, start: 0, end: 15),
  _TrainingStep(label: 'Auto Annotation', description: 'Generic model labelling defects', icon: Icons.label_outline, start: 15, end: 45),
  _TrainingStep(label: 'Augmentation', description: 'Generating varied copies of each frame', icon: Icons.auto_awesome_outlined, start: 45, end: 50),
  _TrainingStep(label: 'YOLO Training', description: 'Fine-tuning on your weld data', icon: Icons.model_training, start: 50, end: 95),
  _TrainingStep(label: 'Model Export', description: 'Packaging weights for deployment', icon: Icons.inventory_2_outlined, start: 95, end: 100),
];

int _stepState(_TrainingStep step, double progress, String status) {
  if (status == 'completed') return 2;
  if (progress >= step.end) return 2;
  if (progress >= step.start) return 1;
  return 0;
}

String _currentStepLabel(double progress, String status) {
  if (status == 'completed') return 'Model Export';
  for (final step in _kSteps.reversed) {
    if (progress >= step.start) return step.label;
  }
  return 'Queued';
}

// ---------------------------------------------------------------------------

class TrainingProgressScreen extends StatefulWidget {
  final String jobId;
  const TrainingProgressScreen({super.key, required this.jobId});

  @override
  State<TrainingProgressScreen> createState() => _TrainingProgressScreenState();
}

class _TrainingProgressScreenState extends State<TrainingProgressScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  Timer? _pollTimer;
  String _status = 'queued';
  double _progress = 0;
  String? _suggestedName;
  bool _notified = false;
  final Set<int> _progressMilestonesNotified = {};

  late final AnimationController _barController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late Animation<double> _barAnim = Tween<double>(begin: 0, end: 0).animate(_barController);
  late final AnimationController _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final AnimationController _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void initState() {
    super.initState();
    ActiveTrainingService.instance.setActive(widget.jobId, suggestedName: _suggestedName);
    _checkStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _barController.dispose();
    _pulseController.dispose();
    _spinController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final data = await _apiService.checkTrainingStatus(widget.jobId);
      
      final newProgress = (data['progress'] ?? 0).toDouble();
      final newStatus = (data['status'] ?? 'queued') as String;
      
      if (!mounted) return;

      final oldValue = _barAnim.value;
      _barAnim = Tween<double>(begin: oldValue, end: newProgress / 100).animate(
        CurvedAnimation(parent: _barController, curve: Curves.easeOut)
      );
      _barController..reset()..forward();

      setState(() {
        _status = newStatus;
        _progress = newProgress;
        _suggestedName ??= data['model_name'] as String?;
      });

      if (_suggestedName != null) {
        ActiveTrainingService.instance.setActive(widget.jobId, suggestedName: _suggestedName);
      }

      for (final milestone in [25, 50, 75]) {
        if (newProgress >= milestone && !_progressMilestonesNotified.contains(milestone)) {
          _progressMilestonesNotified.add(milestone);
          await NotificationService.instance.showTrainingProgress(
            progress: milestone, 
            stepLabel: _currentStepLabel(newProgress, newStatus), 
            jobId: widget.jobId
          );
        }
      }

      if (newStatus == 'completed' && !_notified) {
        _notified = true;
        _pollTimer?.cancel();
        _spinController.stop();
        await NotificationService.instance.showTrainingComplete(jobId: widget.jobId, modelName: _suggestedName);
        await ActiveTrainingService.instance.clear(widget.jobId);

        // Guard against showing the save/rename sheet twice — e.g. once
        // from live polling, then again if the "training complete"
        // notification is tapped and reopens this screen as a fresh
        // widget instance for the same already-completed job.
        final alreadyPrompted = await ActiveTrainingService.instance.wasPrompted(widget.jobId);
        if (!alreadyPrompted) {
          await ActiveTrainingService.instance.markPrompted(widget.jobId);
          await Future.delayed(const Duration(milliseconds: 700));
          if (!mounted) return;
          _showNameSheet();
        }
      }

      if (newStatus == 'failed' && !_notified) {
        _notified = true;
        _pollTimer?.cancel();
        _spinController.stop();
        await NotificationService.instance.showTrainingFailed(jobId: widget.jobId);
        await ActiveTrainingService.instance.clear(widget.jobId);
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('session expired') || errorString.contains('401')) {
        _pollTimer?.cancel();
        if (mounted) {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.logout();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }
      debugPrint("Polling error (will retry): $e");
    }
  }

  Future<void> _showNameSheet() async {
    final List<String> existingNames = await _fetchExistingModelNames();
    if (!mounted) return;
    final controller = TextEditingController(text: _suggestedName ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final kb = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + kb),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: _textSecondary.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
                    Row(
                      children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: _successColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.check_circle_outline, color: _successColor, size: 26)),
                        const SizedBox(width: 14),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Training Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
                          Text('Model ready to deploy', style: TextStyle(color: _successColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Give your model a name, or tap an existing one to overwrite it.', style: TextStyle(color: _textSecondary, fontSize: 14)),
                    const SizedBox(height: 20),
                    const Text('MODEL NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _textSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'e.g. weld_v2_line3',
                        hintStyle: const TextStyle(color: _textSecondary),
                        errorText: errorText,
                        filled: true,
                        fillColor: _bgColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primaryColor, width: 2)),
                      ),
                      onChanged: (_) {
                        if (errorText != null) setSheetState(() => errorText = null);
                      },
                    ),
                    if (existingNames.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text('OR OVERWRITE EXISTING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _textSecondary, letterSpacing: 0.5)),
                      const SizedBox(height: 10),
                      ...existingNames.map((name) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                controller.text = name;
                                setSheetState(() => errorText = null);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF223049))),
                                child: Row(
                                  children: [
                                    const Icon(Icons.model_training, color: _primaryColor, size: 18),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(name, style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _dangerColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: const Text('OVERWRITE', style: TextStyle(fontSize: 10, color: _dangerColor, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, 
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textSecondary, 
                              side: BorderSide(color: const Color(0xFF2A3B57)), 
                              padding: const EdgeInsets.symmetric(vertical: 16), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ), 
                            child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700))
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2, 
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor, 
                              foregroundColor: Colors.white, 
                              padding: const EdgeInsets.symmetric(vertical: 16), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                              elevation: 0
                            ), 
                            onPressed: () async {
                              final name = controller.text.trim();
                              if (name.isEmpty) { setSheetState(() => errorText = 'Please enter a model name'); return; }
                              Navigator.pop(ctx);
                              await _saveModelName(name);
                              if (!mounted) return;
                              Navigator.pop(context);
                            }, 
                            child: const Text('Save Model', style: TextStyle(fontWeight: FontWeight.w700))
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<String>> _fetchExistingModelNames() async {
    try {
      final dynamic responseData = await _apiService.getModels();
      List<dynamic> rawModels = [];
      
      if (responseData is List) {
        rawModels = responseData;
      } else if (responseData is Map && responseData.containsKey('models')) {
        rawModels = responseData['models'] as List;
      }

      return rawModels
          .whereType<Map>()
          .map((m) => (m['model_name'] ?? m['name'] ?? 'Unknown Model').toString())
          .toList();
          
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveModelName(String name) async {
    final oldName = _suggestedName;
    try {
      // 1. Always attempt saveModelName (POST /rename-model with jobId).
      //    This registers or updates the model in the database.
      try {
        await _apiService.saveModelName(widget.jobId, name);
      } catch (e) {
        // If saveModelName failed, fallback to renameModel if oldName exists
        if (oldName != null && oldName.isNotEmpty && oldName != name) {
          await _apiService.renameModel(oldName, name);
        } else {
          rethrow;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model "$name" saved successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      final errorString = e.toString().toLowerCase();
      if (errorString.contains('session expired') || errorString.contains('401')) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.logout();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }

      final cleanError = e.toString().replaceAll(RegExp(r'^(Exception: |Error: )', caseSensitive: false), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save model: $cleanError'),
          backgroundColor: _dangerColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _status == 'completed';
    final isFailed = _status == 'failed';

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: FadeTransition(
                opacity: _entranceController,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: _entranceController, curve: Curves.easeOut)),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroCard(isComplete, isFailed),
                        const SizedBox(height: 32),
                        _buildStepsList(),
                        if (isFailed) ...[const SizedBox(height: 24), _buildErrorBanner()],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final shortId = widget.jobId.length >= 8 ? widget.jobId.substring(0, 8).toUpperCase() : widget.jobId.toUpperCase();
    
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
                Text('Model Training', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                Text('AI Training Progress', style: TextStyle(fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('JOB $shortId', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _primaryColor, letterSpacing: 0.5)),
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

  Widget _buildHeroCard(bool isComplete, bool isFailed) {
    final color = isFailed ? _dangerColor : isComplete ? _successColor : _primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: AnimatedBuilder(
              animation: Listenable.merge([_barAnim, _pulseController, _spinController]),
              builder: (_, __) => CustomPaint(
                painter: _ArcRingPainter(progress: _barAnim.value, color: color, pulse: _pulseController.value, isComplete: isComplete, isFailed: isFailed),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check_circle_outline, color: _successColor, size: 48)
                      : isFailed
                          ? const Icon(Icons.error_outline, color: _dangerColor, size: 48)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RotationTransition(turns: _spinController, child: Icon(Icons.settings, color: color, size: 28)),
                                const SizedBox(height: 4),
                                AnimatedBuilder(
                                  animation: _barAnim,
                                  builder: (_, __) => Text('${(_barAnim.value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary)),
                                ),
                              ],
                            ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              key: ValueKey(_status),
              isComplete ? 'TRAINING COMPLETE' : isFailed ? 'TRAINING FAILED' : _status.toUpperCase(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              key: ValueKey(_progress.toInt()),
              isComplete ? 'Your model is ready to deploy' : isFailed ? 'An error occurred — please retry' : _currentStepLabel(_progress, _status),
              style: const TextStyle(color: _textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 22),
          AnimatedBuilder(animation: _barAnim, builder: (_, __) => _SegmentedProgressBar(progress: _barAnim.value, color: color)),
        ],
      ),
    );
  }

  Widget _buildStepsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PIPELINE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 16),
        ...List.generate(_kSteps.length, (i) {
          final step = _kSteps[i];
          return _StepRow(step: step, state: _stepState(step, _progress, _status), isLast: i == _kSteps.length - 1, progress: _progress, pulseController: _pulseController, spinController: _spinController);
        }),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _dangerColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dangerColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _dangerColor.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded, color: _dangerColor, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Training Failed', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _dangerColor)),
                SizedBox(height: 4),
                Text('Please check your video quality and try initiating the training process again.', style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arc ring painter
// ---------------------------------------------------------------------------
class _ArcRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double pulse;
  final bool isComplete;
  final bool isFailed;

  _ArcRingPainter({required this.progress, required this.color, required this.pulse, required this.isComplete, required this.isFailed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 0, 2 * math.pi, false, Paint()..color = color.withOpacity(0.1)..strokeWidth = 10..style = PaintingStyle.stroke);

    if (progress > 0) {
      if (!isComplete && !isFailed) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, Paint()..color = color.withOpacity(0.15 + 0.12 * pulse)..strokeWidth = 20..style = PaintingStyle.stroke..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, Paint()..color = color..strokeWidth = 10..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

      if (!isComplete && progress < 1.0) {
        final tipAngle = startAngle + sweepAngle;
        final dot = Offset(center.dx + radius * math.cos(tipAngle), center.dy + radius * math.sin(tipAngle));
        canvas.drawCircle(dot, 10, Paint()..color = color.withOpacity(0.25 + 0.15 * pulse)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.drawCircle(dot, 6, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArcRingPainter old) => old.progress != progress || old.pulse != pulse || old.color != color;
}

// ---------------------------------------------------------------------------
// Segmented progress bar
// ---------------------------------------------------------------------------
class _SegmentedProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _SegmentedProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_kSteps.length, (i) {
        final step = _kSteps[i];
        final pct = progress * 100;
        final filled = pct >= step.end;
        final partial = pct > step.start && pct < step.end;
        final fill = partial ? ((pct - step.start) / (step.end - step.start)).clamp(0.0, 1.0) : filled ? 1.0 : 0.0;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _kSteps.length - 1 ? 4 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 6, color: color.withOpacity(0.1)),
                  FractionallySizedBox(widthFactor: fill, child: Container(height: 6, color: color)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual step row
// ---------------------------------------------------------------------------
class _StepRow extends StatelessWidget {
  final _TrainingStep step;
  final int state;
  final bool isLast;
  final double progress;
  final AnimationController pulseController;
  final AnimationController spinController;

  const _StepRow({required this.step, required this.state, required this.isLast, required this.progress, required this.pulseController, required this.spinController});

  @override
  Widget build(BuildContext context) {
    final isPending = state == 0;
    final isActive = state == 1;
    final isDone = state == 2;

    final labelColor = (isDone || isActive) ? _textPrimary : _textSecondary;
    final localProgress = isActive ? ((progress - step.start) / (step.end - step.start)).clamp(0.0, 1.0) : isDone ? 1.0 : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([pulseController, spinController]),
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: [
                  if (isActive) Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: _primaryColor.withOpacity(0.07 + 0.10 * pulseController.value))),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? _successColor.withOpacity(0.1) : isActive ? _primaryColor.withOpacity(0.1) : _cardColor,
                      border: Border.all(color: isDone ? _successColor.withOpacity(0.5) : isActive ? _primaryColor.withOpacity(0.5) : const Color(0xFF2A3B57)),
                    ),
                    child: isDone ? const Icon(Icons.check, color: _successColor, size: 18) : isActive ? RotationTransition(turns: spinController, child: Icon(step.icon, color: _primaryColor, size: 18)) : Icon(step.icon, color: _textSecondary, size: 18),
                  ),
                ],
              ),
            ),
            if (!isLast)
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 2,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: isDone ? [_successColor.withOpacity(0.6), _successColor.withOpacity(0.15)] : isActive ? [_primaryColor.withOpacity(0.5), const Color(0xFF223049)] : [const Color(0xFF223049), const Color(0xFF223049)]),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: TextStyle(color: labelColor, fontSize: 15, fontWeight: (isActive || isDone) ? FontWeight.w700 : FontWeight.w500)),
                const SizedBox(height: 2),
                Text(step.description, style: TextStyle(color: isPending ? _textSecondary : _textSecondary, fontSize: 12)),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(height: 4, color: _primaryColor.withOpacity(0.1)),
                        AnimatedFractionallySizedBox(widthFactor: localProgress, duration: const Duration(milliseconds: 500), curve: Curves.easeOut, child: Container(height: 4, decoration: BoxDecoration(gradient: LinearGradient(colors: [_primaryColor, _primaryColor.withOpacity(0.6)])))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${(localProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: _primaryColor, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}