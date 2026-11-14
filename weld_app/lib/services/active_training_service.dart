import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the single in-flight training job (if any) so the UI can find
/// its way back to it from two different entry points:
///
///  1. TrainModelScreen — shows a "Model training…" card whenever a job
///     is active, even if the user backed out of TrainingProgressScreen.
///  2. A tapped training notification — needs to know which jobId to
///     reopen TrainingProgressScreen with, including from a cold start
///     where no screen has been built yet and nothing is in memory.
///
/// Backed by SharedPreferences (survives app restarts), and exposes a
/// ValueNotifier (survives navigation, updates UI live without polling)
/// for the common case where the app is already running.
///
/// NOTE: assumes at most one training job in flight at a time, which
/// matches the existing UI (one TrainModelScreen, no job queue/list).
/// If multi-job training is added later, this needs to become a list.
class ActiveTrainingJob {
  final String jobId;
  final String? suggestedName;
  final DateTime startedAt;

  const ActiveTrainingJob({
    required this.jobId,
    required this.suggestedName,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'suggestedName': suggestedName,
        'startedAt': startedAt.toIso8601String(),
      };

  factory ActiveTrainingJob.fromJson(Map<String, dynamic> json) {
    return ActiveTrainingJob(
      jobId: json['jobId'] as String,
      suggestedName: json['suggestedName'] as String?,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ActiveTrainingService {
  ActiveTrainingService._();
  static final ActiveTrainingService instance = ActiveTrainingService._();

  static const String _prefsKey = 'active_training_job';
  static const String _promptedKeyPrefix = 'training_prompted_';

  /// Null when no job is currently training. UI (e.g. TrainModelScreen)
  /// listens to this directly instead of polling — it's updated the
  /// instant a job starts/finishes from anywhere in the app.
  final ValueNotifier<ActiveTrainingJob?> current =
      ValueNotifier<ActiveTrainingJob?>(null);

  bool _loaded = false;

  /// Call once at startup (e.g. in main(), or lazily the first time
  /// TrainModelScreen builds) to restore any job that was active before
  /// the app was last closed/killed.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        current.value = ActiveTrainingJob.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // No persisted job, or corrupt entry — treat as "nothing active".
    }
  }

  Future<void> setActive(String jobId, {String? suggestedName}) async {
    final job = ActiveTrainingJob(
      jobId: jobId,
      suggestedName: suggestedName,
      startedAt: DateTime.now(),
    );
    current.value = job;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(job.toJson()));
    } catch (_) {
      // Persistence failure isn't fatal — the in-memory notifier still
      // lets the card show for the rest of this app session.
    }
  }

  /// Call when a job reaches 'completed' or 'failed' so the card on
  /// TrainModelScreen disappears and stale jobs don't resurrect after
  /// restart.
  Future<void> clear(String jobId) async {
    // Only clear if this is still the job we think is active — guards
    // against a stale completion callback clearing a *newer* job that
    // started after this one (shouldn't happen given the one-job-at-a-
    // time assumption, but cheap to guard against).
    if (current.value?.jobId != jobId && current.value != null) return;
    current.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Whether the "save/rename model" sheet has already been shown for
  /// this job. Reopening TrainingProgressScreen for an already-completed
  /// job (e.g. via tapping the "training complete" notification) creates
  /// a brand-new widget instance whose in-memory `_notified` flag resets
  /// to false — without this persisted check, that would show the save
  /// sheet a second time for a job that's already been named.
  Future<bool> wasPrompted(String jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_promptedKeyPrefix$jobId') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Marks this job as having already shown the save/rename sheet, so it
  /// won't be shown again from a future screen instance.
  Future<void> markPrompted(String jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_promptedKeyPrefix$jobId', true);
    } catch (_) {}
  }
}

