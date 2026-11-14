import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Singleton wrapper around flutter_local_notifications.
/// Call [NotificationService.init] once from main.dart before runApp(),
/// passing a [navigatorKey] so a tapped notification can push a route
/// even if no relevant screen is currently in memory (e.g. app was
/// killed and is being launched fresh by the notification tap).
///
/// Notification strategy for training jobs:
///   - Progress milestones (25 / 50 / 75 %) — indeterminate progress bar,
///     shows current step name in the body. Uses id=2 so each milestone
///     *replaces* the previous one in the notification shade.
///   - Completion — high-priority heads-up with model name.
///   - Failure   — high-priority heads-up with retry hint.
///
/// All three carry `payload: jobId` so tapping any of them can reopen
/// TrainingProgressScreen for that specific job (see
/// [_handleNotificationTap] and the wiring required in main.dart, noted
/// below).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by whoever calls init() — used to navigate when a notification
  /// is tapped while there's no BuildContext handy (e.g. app was in the
  /// background or fully terminated).
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Route builder supplied by the app, so this service doesn't need to
  /// import TrainingProgressScreen directly (keeps the dependency
  /// direction one-way: screens depend on services, not the reverse).
  /// main.dart wires this to:
  ///   (jobId) => MaterialPageRoute(
  ///     builder: (_) => TrainingProgressScreen(jobId: jobId),
  ///   )
  Route Function(String jobId)? _trainingRouteBuilder;

  Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    required Route Function(String jobId) trainingRouteBuilder,
  }) async {
    _navigatorKey = navigatorKey;
    _trainingRouteBuilder = trainingRouteBuilder;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      initSettings,
      // Fires when the app is running (foreground or background) and
      // the user taps the notification.
      onDidReceiveNotificationResponse: _handleNotificationTap,
      // Fires when the app is fully terminated and gets launched BY the
      // notification tap. flutter_local_notifications buffers this and
      // delivers it once a listener is registered above, so no separate
      // wiring is needed here — but main.dart should still check
      // `getNotificationAppLaunchDetails()` once at startup in case the
      // plugin's redelivery timing doesn't line up with when this
      // listener gets attached (see note in main.dart wiring below).
    );

    // Request notification permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Cold-start case: the app was terminated and got launched by the
    // user tapping a training notification. onDidReceiveNotificationResponse
    // above won't fire for this — it only covers taps that happen while
    // the plugin is already initialized — so check explicitly here.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        // Defer to next frame so the navigator is guaranteed mounted.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToJob(payload);
        });
      }
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _navigateToJob(payload);
    }
  }

  void _navigateToJob(String jobId) {
    final navState = _navigatorKey?.currentState;
    final routeBuilder = _trainingRouteBuilder;
    if (navState == null || routeBuilder == null) return;
    navState.push(routeBuilder(jobId));
  }

  // ── Progress milestone (25 / 50 / 75 %) ────────────────────────────────
  //
  // Uses notification id=2 so each milestone silently replaces the previous
  // one. Shows an indeterminate progress bar on Android so the user knows
  // the job is still running, together with the current pipeline step name.
  // Silent (no sound/vibration) — it is informational, not urgent.

  Future<void> showTrainingProgress({
    required int progress,    // 25, 50, or 75
    required String stepLabel, // e.g. "YOLO Training"
    required String jobId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'training_progress_channel',
      'Training Progress',
      channelDescription:
          'Silent progress updates for ongoing model training jobs',
      importance: Importance.low,   // no heads-up pop, no sound
      priority: Priority.low,
      onlyAlertOnce: true,          // don't vibrate on update
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      icon: '@mipmap/ic_launcher',
      // Keep the notification alive while training runs.
      ongoing: true,
      autoCancel: false,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      2, // fixed id — updates in place
      '⚙️ Training in progress — $progress%',
      stepLabel,
      details,
      payload: jobId,
    );
  }

  // ── Training complete ───────────────────────────────────────────────────

  Future<void> showTrainingComplete({
    required String jobId,
    String? modelName,
  }) async {
    // Cancel the ongoing progress notification first.
    await _plugin.cancel(2);

    const androidDetails = AndroidNotificationDetails(
      'training_channel',
      'Model Training',
      channelDescription:
          'Completion and failure alerts for YOLO model training jobs',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _plugin.show(
      0, // id 0 = completion
      '✅ Training Complete',
      modelName != null
          ? 'Model "$modelName" is ready to use.'
          : 'Your custom weld inspection model is ready.',
      details,
      payload: jobId,
    );
  }

  // ── Training failed ─────────────────────────────────────────────────────

  Future<void> showTrainingFailed({required String jobId}) async {
    // Cancel the ongoing progress notification first.
    await _plugin.cancel(2);

    const androidDetails = AndroidNotificationDetails(
      'training_channel',
      'Model Training',
      channelDescription:
          'Completion and failure alerts for YOLO model training jobs',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _plugin.show(
      1, // id 1 = failure
      '❌ Training Failed',
      'Something went wrong during model training. Please try again.',
      details,
      payload: jobId,
    );
  }
}