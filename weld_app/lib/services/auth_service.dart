import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class AuthService {
  /// Points to the local FastAPI backend (same as ApiService).
  String get baseUrl => AppConfig.baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Storage keys
  static const String _tokenKey = 'access_token';
  static const String _userIdKey = 'user_id';
  static const String _emailKey = 'user_email'; // ✅ Added email key

  // Safe read that handles BAD_DECRYPT errors from stale encrypted data
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[AuthService] Failed to read "$key", clearing corrupt data: $e');
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  // Get stored token
  Future<String?> getToken() async {
    return await _safeRead(_tokenKey);
  }

  // Get stored user ID
  Future<String?> getUserId() async {
    return await _safeRead(_userIdKey);
  }

  // ✅ Get stored email
  Future<String?> getUserEmail() async {
    return await _safeRead(_emailKey);
  }

  // Register new user
  Future<Map<String, dynamic>?> register(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // ✅ Pass email to be saved
        await _saveToken(data['access_token'], data['user_id'], email);
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Registration failed');
      }
    } catch (e) {
      debugPrint('Register error: $e');
      rethrow;
    }
  }

  // Login user
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // ✅ Pass email to be saved
        await _saveToken(data['access_token'], data['user_id'], email);
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Login failed');
      }
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }

  // ✅ Save token, user ID, and email
  Future<void> _saveToken(String token, String userId, String email) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _emailKey, value: email);
  }

  // ── Forgot password flow ────────────────────────────────────────
  // Step 1: request a one-time code, emailed via Gmail SMTP by the backend.
  Future<String> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['message'] ?? 'Reset code sent.';
      throw Exception(data['detail'] ?? 'Failed to send reset code');
    } catch (e) {
      debugPrint('Forgot password error: $e');
      rethrow;
    }
  }

  // Step 2: verify the 6-digit code before showing the new-password step.
  Future<String> verifyResetOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-reset-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['message'] ?? 'Code verified.';
      throw Exception(data['detail'] ?? 'Invalid or expired code');
    } catch (e) {
      debugPrint('Verify reset OTP error: $e');
      rethrow;
    }
  }

  // Step 3: submit the code again alongside the new password (the
  // backend re-validates it so a stolen/expired code can't be reused).
  Future<String> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp, 'new_password': newPassword}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['message'] ?? 'Password updated.';
      throw Exception(data['detail'] ?? 'Failed to reset password');
    } catch (e) {
      debugPrint('Reset password error: $e');
      rethrow;
    }
  }

  // Resend a signup verification code (email confirmation, separate
  // from password reset).
  Future<String> resendVerification(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['message'] ?? 'Verification code resent.';
      throw Exception(data['detail'] ?? 'Failed to resend verification code');
    } catch (e) {
      debugPrint('Resend verification error: $e');
      rethrow;
    }
  }

  // Logout user
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _emailKey); // ✅ Delete email on logout
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  // Get authenticated HTTP headers
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}