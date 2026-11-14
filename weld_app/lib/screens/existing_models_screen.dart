import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/industrial_widgets.dart';
import 'specific_inspection_screen.dart';
import 'results_overview_screen.dart';
import 'train_model_screen.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _dangerColor = AppColors.fail;

const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Shared date formatter — e.g. "18 May 2025" or "18 May 2025 • 10:24 AM".
String formatModelDate(DateTime d, {bool includeTime = true}) {
  final datePart = '${d.day} ${_kMonths[d.month - 1]} ${d.year}';
  if (!includeTime) return datePart;
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour < 12 ? 'AM' : 'PM';
  final minute = d.minute.toString().padLeft(2, '0');
  return '$datePart • $hour12:$minute $period';
}

class ExistingModelsScreen extends StatefulWidget {
  const ExistingModelsScreen({super.key});

  @override
  State<ExistingModelsScreen> createState() => _ExistingModelsScreenState();
}

class _ExistingModelsScreenState extends State<ExistingModelsScreen> {
  final ApiService _apiService = ApiService();

  // ✅ Changed to Map to hold both name and gcs_uri cleanly
  List<Map<String, dynamic>> models = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadModels();
  }

  Future<void> loadModels() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      // ✅ ApiService handles auth and returns the list directly (or a map with 'models' key)
      final dynamic data = await _apiService.getModels();
      
      // Safely handle whether ApiService returns a List directly or a Map with a 'models' key
      final List<dynamic> modelsList = data is Map 
          ? (data['models'] ?? []) 
          : (data is List ? data : []);
      
      // We map 'model_name' to 'name' for backward compatibility with the UI.
      // We also capture a timestamp so we can sort by actual training
      // recency instead of trusting whatever order the backend returns
      // (which was effectively alphabetical, e.g. "10" before "9"), plus
      // 'status'/'progress' so in-progress training jobs can be shown
      // alongside completed models.
      final mappedModels = modelsList.map((model) {
        final rawTimestamp = model['created_at'] ??
            model['createdAt'] ??
            model['trained_at'] ??
            model['training_date'] ??
            model['timestamp'] ??
            model['date_created'] ??
            model['updated_at'];
        return {
          'name': model['model_name'] ?? model['name'] ?? 'Unknown Model',
          'gcs_uri': model['gcs_uri'] ?? '',
          'status': model['status'] ?? 'ready',
          'progress': model['progress'],
          'created_at': DateTime.tryParse(rawTimestamp?.toString() ?? ''),
        };
      }).toList();

      // Sort newest-first. Models with a valid timestamp always sort
      // above ones without (which keep their original relative order),
      // so the most recently trained model is always at the top.
      mappedModels.sort((a, b) {
        final aTime = a['created_at'] as DateTime?;
        final bTime = b['created_at'] as DateTime?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          models = mappedModels;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load models: $e'), backgroundColor: _dangerColor),
        );
      }
    }
  }

  Future<void> _deleteModel(String modelName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Model', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
        content: Text(
          'Are you sure you want to delete "$modelName"? This action cannot be undone.',
          style: const TextStyle(color: _textSecondary, fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _textSecondary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _dangerColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // ✅ Uses ApiService with auth headers
      final success = await _apiService.deleteModel(modelName);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$modelName" deleted successfully'), backgroundColor: _successColor),
        );
        loadModels();
      } else if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete "$modelName"'), backgroundColor: _dangerColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: _dangerColor),
        );
      }
    }
  }

  Future<void> _renameModel(String oldName) async {
    final controller = TextEditingController(text: oldName);
    String? errorText;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Rename Model', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a new name for your model.', style: TextStyle(color: _textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  final name = value.trim();
                  if (name.isEmpty) {
                    setDialogState(() => errorText = 'Name cannot be empty');
                    return;
                  }
                  if (name == oldName) {
                    Navigator.pop(ctx);
                    return;
                  }
                  Navigator.pop(ctx, name);
                },
                style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'New model name',
                  hintStyle: const TextStyle(color: _textSecondary),
                  errorText: errorText,
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _primaryColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onChanged: (_) {
                  if (errorText != null) setDialogState(() => errorText = null);
                },
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: _textSecondary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Name cannot be empty');
                  return;
                }
                if (name == oldName) {
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(ctx, name);
              },
              child: const Text('Rename', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (newName == null) return;

    try {
      // ✅ Uses ApiService with auth headers
      await _apiService.renameModel(oldName, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName"'), backgroundColor: _successColor),
        );
        loadModels();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename: $e'), backgroundColor: _dangerColor),
        );
      }
    }
  }

  void _handleNavTap(int index) {
    if (index == 1) return; // already on Models
    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    late final Widget destination;
    switch (index) {
      case 2:
        destination = const ResultsOverviewScreen();
        break;
      case 3:
        destination = const TrainModelScreen();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final total = models.length;
    final readyCount = models.where((m) => m['status'] != 'training').length;
    final trainingCount = total - readyCount;

    return Scaffold(
      backgroundColor: _bgColor,
      bottomNavigationBar: IndustrialNavBar(currentIndex: 1, onTap: _handleNavTap),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (!loading && models.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _buildSummaryBar(total, readyCount, trainingCount),
              ),
            Expanded(
              child: loading
                  ? _buildLoadingState()
                  : models.isEmpty
                      ? _buildEmptyState()
                      : _buildModelsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(int total, int ready, int training) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF223049)),
      ),
      child: Row(
        children: [
          Expanded(child: _SummaryStat(icon: Icons.inventory_2_outlined, iconColor: _primaryColor, value: '$total', label: 'Total Models')),
          Container(width: 1, height: 34, color: const Color(0xFF223049)),
          Expanded(child: _SummaryStat(icon: Icons.check_circle_outline, iconColor: _successColor, value: '$ready', label: 'Ready')),
          Container(width: 1, height: 34, color: const Color(0xFF223049)),
          Expanded(child: _SummaryStat(icon: Icons.schedule_outlined, iconColor: const Color(0xFF8B5CF6), value: '$training', label: 'Training')),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      color: _bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCircleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
          const SizedBox(width: 16),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Existing Models', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
                  SizedBox(height: 2),
                  Text('Manage and use your trained models', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
                ],
              ),
            ),
          ),
          _buildCircleButton(Icons.refresh, loadModels, iconColor: _primaryColor),
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

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 4),
          ),
          const SizedBox(height: 20),
          const Text('Fetching Models...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textSecondary)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.model_training_outlined, color: _primaryColor, size: 48),
            ),
            const SizedBox(height: 24),
            const Text('No Models Yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textPrimary)),
            const SizedBox(height: 8),
            const Text('You haven\'t trained any custom models. Upload a video or image folder to get started.', style: TextStyle(fontSize: 14, color: _textSecondary, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context), 
              icon: const Icon(Icons.add_rounded),
              label: const Text('Train New Model', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelsList() {
    return RefreshIndicator(
      color: _primaryColor,
      backgroundColor: _bgColor,
      onRefresh: loadModels,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: models.length + 1, // +1 for the trailing "Import Model" card
        itemBuilder: (context, index) {
          if (index == models.length) {
            return _ImportModelCard(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainModelScreen())),
            );
          }

          final model = models[index];
          final name = model['name'] as String;
          final status = (model['status'] as String?) ?? 'ready';
          final isTraining = status == 'training';
          final isNewest = index == 0 && !isTraining;
          final createdAt = model['created_at'] as DateTime?;
          final progress = model['progress'];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ModelCard(
              name: name,
              isNewest: isNewest,
              isTraining: isTraining,
              createdAt: createdAt,
              progress: progress is num ? progress.toInt() : null,
              onTap: isTraining
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpecificInspectionScreen(
                        modelName: name,
                        trainedOn: createdAt != null ? formatModelDate(createdAt, includeTime: false) : null,
                        activatedAt: createdAt != null ? formatModelDate(createdAt) : null,
                        onRename: () => _renameModel(name),
                        onDelete: () => _deleteModel(name),
                      ))),
              onRename: () => _renameModel(name),
              onDelete: () => _deleteModel(name),
            ),
          );
        },
      ),
    );
  }
}

// ─── MODEL CARD WIDGET ────────────────────────────────────────────────
const Color _trainingColor = Color(0xFF8B5CF6);

class _ModelCard extends StatelessWidget {
  final String name;
  final bool isNewest;
  final bool isTraining;
  final DateTime? createdAt;
  final int? progress;
  final VoidCallback? onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ModelCard({
    required this.name,
    required this.isNewest,
    this.isTraining = false,
    this.createdAt,
    this.progress,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  String _formatDate(DateTime d) => formatModelDate(d);

  @override
  Widget build(BuildContext context) {
    final accent = isTraining ? _trainingColor : (isNewest ? _primaryColor : _successColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(20),
            border: (isNewest || isTraining) ? Border.all(color: accent.withOpacity(0.35), width: 1.5) : Border.all(color: const Color(0xFF223049)),
            boxShadow: [
              BoxShadow(
                color: (isNewest || isTraining) ? accent.withOpacity(0.08) : Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withOpacity(0.8), accent],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Icon(isTraining ? Icons.hourglass_top_rounded : Icons.memory_outlined, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _textPrimary),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isNewest) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('LATEST', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _primaryColor, letterSpacing: 0.5)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTraining
                          ? (progress != null ? 'Training… $progress%' : 'Training in progress')
                          : (isNewest ? 'Most recently trained' : 'Ready for inspection'),
                      style: TextStyle(fontSize: 12.5, color: isTraining ? _trainingColor : _textSecondary, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: _textSecondary.withOpacity(0.7)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _formatDate(createdAt!),
                              style: const TextStyle(fontSize: 11.5, color: _textSecondary, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTraining)
                          SizedBox(
                            width: 11, height: 11,
                            child: CircularProgressIndicator(strokeWidth: 2, color: accent, value: progress != null ? progress! / 100 : null),
                          )
                        else
                          Icon(Icons.check, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Text(isTraining ? 'Training' : 'Ready', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent)),
                      ],
                    ),
                  ),
                  if (!isTraining) ...[
                    const SizedBox(height: 6),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18213A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.more_horiz, color: _textSecondary, size: 18),
                      ),
                      onSelected: (value) {
                        if (value == 'rename') onRename();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, size: 18, color: _textPrimary),
                            const SizedBox(width: 12),
                            const Text('Rename', style: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_outline, size: 18, color: _dangerColor),
                            const SizedBox(width: 12),
                            const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600, color: _dangerColor)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SUMMARY STAT (Total / Ready / Training) ──────────────────────────
class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _SummaryStat({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.3)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _textSecondary)),
      ],
    );
  }
}

// ─── IMPORT MODEL CARD ─────────────────────────────────────────────────
class _ImportModelCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ImportModelCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryColor.withOpacity(0.4), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.add, color: _primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Import Model', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary)),
                    SizedBox(height: 2),
                    Text('Add a new trained model', style: TextStyle(fontSize: 12.5, color: _textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _textSecondary.withOpacity(0.7), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}