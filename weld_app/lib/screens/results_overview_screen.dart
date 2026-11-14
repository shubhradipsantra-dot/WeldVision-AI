import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/industrial_widgets.dart';
import '../services/api_service.dart';
import 'result_screen.dart';
import 'existing_models_screen.dart';
import 'train_model_screen.dart';

/// RESULT tab — a rolling log of recent inspection outcomes across
/// every model and capture mode (image / video / live), styled as a
/// shop-floor readout rather than a generic activity feed.
class ResultsOverviewScreen extends StatefulWidget {
  const ResultsOverviewScreen({super.key});

  @override
  State<ResultsOverviewScreen> createState() => _ResultsOverviewScreenState();
}

class _ResultsOverviewScreenState extends State<ResultsOverviewScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _apiService.getRecentInspections(limit: 50);
      if (!mounted) return;
      setState(() => _history = items.cast<Map<String, dynamic>>());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load results: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, int> get _summary {
    int pass = 0, fail = 0, review = 0;
    for (final item in _history) {
      switch (((item['decision'] as String?) ?? '').toUpperCase()) {
        case 'ACCEPT': pass++; break;
        case 'REJECT': fail++; break;
        default: review++;
      }
    }
    return {'pass': pass, 'fail': fail, 'review': review};
  }

  void _handleNavTap(int index) {
    if (index == 2) return; // already on Result
    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    late final Widget destination;
    switch (index) {
      case 1:
        destination = const ExistingModelsScreen();
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
    final summary = _summary;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      bottomNavigationBar: IndustrialNavBar(currentIndex: 2, onTap: _handleNavTap),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.arc,
          backgroundColor: AppColors.bgPanel,
          onRefresh: _fetchHistory,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SectionEyebrow('Inspection Log', color: AppColors.arc),
                    const SizedBox(height: 10),
                    Text('Result Feed', style: AppText.display(size: 26)),
                    const SizedBox(height: 4),
                    Text(
                      'Every accept, reject and review call across your production line.',
                      style: AppText.body(size: 13),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: MetricChip(label: 'Pass', value: '${summary['pass']}', icon: Icons.check_circle_outline, color: AppColors.pass)),
                        const SizedBox(width: 10),
                        Expanded(child: MetricChip(label: 'Fail', value: '${summary['fail']}', icon: Icons.cancel_outlined, color: AppColors.fail)),
                        const SizedBox(width: 10),
                        Expanded(child: MetricChip(label: 'Review', value: '${summary['review']}', icon: Icons.flag_outlined, color: AppColors.caution)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_loading && _history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(child: CircularProgressIndicator(color: AppColors.arc)),
                      )
                    else if (_error != null && _history.isEmpty)
                      _buildEmptyState(icon: Icons.wifi_off, message: _error!)
                    else if (_history.isEmpty)
                      _buildEmptyState(icon: Icons.fact_check_outlined, message: 'No inspections logged yet.')
                    else
                      ..._history.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ResultLogCard(item: item, onTap: () => _openDetail(item)),
                          )),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> item) {
    final decision = (item['decision'] as String?) ?? 'REVIEW';
    final defectCount = (item['defect_count'] as int?) ?? 0;
    final imageUrl = (item['image_url'] as String?) ?? (item['imageUrl'] as String?) ?? '';
    final defects = (item['defects'] as List?) ?? const [];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          decision: decision,
          defectCount: defectCount,
          imageUrl: imageUrl,
          defects: defects,
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: AppDecor.panel(),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 32),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: AppText.body(size: 13)),
        ],
      ),
    );
  }
}

class _ResultLogCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _ResultLogCard({required this.item, required this.onTap});

  Color _decisionColor(String d) {
    switch (d.toUpperCase()) {
      case 'ACCEPT': return AppColors.pass;
      case 'REJECT': return AppColors.fail;
      default: return AppColors.caution;
    }
  }

  IconData _sourceIcon(String? source) {
    switch (source) {
      case 'frame':
      case 'video':
        return Icons.videocam_outlined;
      default:
        return Icons.image_outlined;
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = (item['decision'] as String?) ?? '—';
    final defectCount = (item['defect_count'] as int?) ?? 0;
    final source = item['source'] as String?;
    final color = _decisionColor(decision);
    final isPass = decision.toUpperCase() == 'ACCEPT';
    final isFail = decision.toUpperCase() == 'REJECT';
    final statusText = isPass ? 'PASS' : (isFail ? 'FAIL' : 'REVIEW');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecor.panel(accent: color.withValues(alpha: 0.25), radius: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(_sourceIcon(source), color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(decision.toUpperCase(), style: AppText.data(size: 14, color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(statusText, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      defectCount == 0 ? 'No defects detected' : '$defectCount defect${defectCount > 1 ? 's' : ''} found',
                      style: AppText.body(size: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_relativeTime(item['created_at'] as String?), style: AppText.body(size: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
