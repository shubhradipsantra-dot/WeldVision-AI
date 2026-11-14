import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  
  String? _userId;
  String? _email;
  bool _isLoggedIn = false;

  String? get userId => _userId;
  String? get email => _email;
  bool get isLoggedIn => _isLoggedIn;

  Future<void> initialize() async {
    // 1. Try to load the saved session from Secure Storage
    final userId = await _authService.getUserId();
    final token = await _authService.getToken();
    final email = await _authService.getUserEmail(); // ✅ Fetch email too
    
    // 🔍 DEBUG: Check the console to see if the session was actually saved
    debugPrint('🔍 APP START: userId=$userId, tokenExists=${token != null}, email=$email');

    if (userId != null && token != null) {
      _userId = userId;
      _email = email; // ✅ Restore email so the UI can display it
      _isLoggedIn = true;
      debugPrint('✅ APP START: Session restored successfully! Email: $_email');
      notifyListeners();
    } else {
      debugPrint('❌ APP START: No saved session found. User must log in.');
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final result = await _authService.login(cleanEmail, password);
      if (result != null) {
        _userId = result['user_id'];
        _email = cleanEmail;
        _isLoggedIn = true;
        
        // 🔍 DEBUG: Confirm we saved it
        debugPrint('✅ LOGIN SUCCESS: Saved userId=$_userId, email=$_email');
        
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Login error: $e');
      rethrow;
    }
  }

  Future<bool> register(String email, String password) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final result = await _authService.register(cleanEmail, password);
      if (result != null) {
        _userId = result['user_id'];
        _email = cleanEmail;
        _isLoggedIn = true;
        
        // 🔍 DEBUG: Confirm we saved it
        debugPrint('✅ REGISTER SUCCESS: Saved userId=$_userId, email=$_email');
        
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Register error: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _userId = null;
    _email = null;
    _isLoggedIn = false;
    debugPrint('👋 LOGOUT: Session cleared.');
    notifyListeners();
  }
}