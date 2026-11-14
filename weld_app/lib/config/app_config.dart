/// Central configuration for the WeldVision AI app.
///
/// Change [localBackendUrl] to match the IP address / port of the machine
/// running the FastAPI server on your local network.
///
/// [useLocalBackend] switches the entire app between the local GPU server
/// and an optional cloud deployment.  For development keep it [true].
class AppConfig {
  AppConfig._();

  /// IP address (or hostname) of the machine running `uvicorn app:app`.
  /// Must be reachable from the Android device (same Wi-Fi network or USB).
  static const String _localHost = '192.168.31.180';
  static const int    _localPort = 8000;

  /// Set to [false] to route traffic through the cloud backend instead.
  static const bool useLocalBackend = true;

  /// Base URL used by every API and Auth call.
  static String get baseUrl {
    if (useLocalBackend) {
      return 'http://$_localHost:$_localPort';
    }
    // Cloud Run fallback (not used by default)
    return 'https://weldvision-backend-361420640572.asia-south1.run.app';
  }
}
