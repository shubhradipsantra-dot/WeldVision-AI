import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

// ─── COLOR ALIASES ──────────────────────────────────────────────────
const Color _bgColor = AppColors.bgBase;
const Color _cardColor = AppColors.bgPanel;
const Color _borderColor = AppColors.border;
const Color _primaryColor = AppColors.scan;
const Color _textPrimary = AppColors.textPrimary;
const Color _textSecondary = AppColors.textSecondary;
const Color _successColor = AppColors.pass;
const Color _dangerColor = AppColors.fail;

/// Full forgot-password flow: request a code (emailed via the backend's
/// real Gmail SMTP integration) → verify the code → set a new password.
/// Three steps live in one screen so the person never loses context or
/// has to re-enter their email between steps.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, otp, newPassword, done }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();

  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _Step _step = _Step.email;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    final cleanError = message.replaceAll('Exception: ', '').replaceAll('Error: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cleanError.isNotEmpty ? cleanError : 'An unexpected error occurred.'),
        backgroundColor: _dangerColor,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );
  }

  Future<void> _requestCode() async {
    FocusScope.of(context).unfocus();
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final message = await _authService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      _showSuccess(message);
      setState(() => _step = _Step.otp);
      _startResendCooldown();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;
    setState(() => _isLoading = true);
    try {
      final message = await _authService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      _showSuccess(message);
      _startResendCooldown();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 30);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown--);
      return _resendCooldown > 0;
    });
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    if (!_otpFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.verifyResetOtp(_emailController.text.trim(), _otpController.text.trim());
      if (!mounted) return;
      setState(() => _step = _Step.newPassword);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    FocusScope.of(context).unfocus();
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.resetPassword(
        _emailController.text.trim(),
        _otpController.text.trim(),
        _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() => _step = _Step.done);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({required String label, required IconData icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textSecondary),
      prefixIcon: Icon(icon, color: _textSecondary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _cardColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primaryColor, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textPrimary),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.3,
            colors: [Color(0xFF122040), _bgColor],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: switch (_step) {
                  _Step.email => _buildEmailStep(),
                  _Step.otp => _buildOtpStep(),
                  _Step.newPassword => _buildPasswordStep(),
                  _Step.done => _buildDoneStep(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required IconData icon, required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: _primaryColor),
        ),
        const SizedBox(height: 24),
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.4)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w500, height: 1.4)),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _primaryButton({required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 6,
          shadowColor: _primaryColor.withOpacity(0.45),
        ),
        child: _isLoading
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        key: const ValueKey('step_email'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            icon: Icons.lock_reset_outlined,
            title: 'Forgot Password?',
            subtitle: "Enter the email on your account and we'll send a 6-digit reset code to your inbox.",
          ),
          TextFormField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _requestCode(),
            style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
            decoration: _fieldDecoration(label: 'Email Address', icon: Icons.email_outlined),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your email';
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 28),
          _primaryButton(label: 'Send Reset Code', onPressed: _requestCode),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Form(
      key: _otpFormKey,
      child: Column(
        key: const ValueKey('step_otp'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            icon: Icons.mark_email_read_outlined,
            title: 'Enter the Code',
            subtitle: 'We sent a 6-digit code to ${_emailController.text.trim()}. It expires in 10 minutes.',
          ),
          TextFormField(
            controller: _otpController,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            onFieldSubmitted: (_) => _verifyCode(),
            style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: 8),
            decoration: _fieldDecoration(label: '6-Digit Code', icon: Icons.pin_outlined).copyWith(counterText: ''),
            validator: (value) {
              if (value == null || value.trim().length != 6) return 'Enter the 6-digit code from your email';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _resendCooldown > 0 ? null : _resendCode,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(
                _resendCooldown > 0 ? 'Resend code in ${_resendCooldown}s' : 'Resend code',
                style: TextStyle(color: _resendCooldown > 0 ? _textSecondary : _primaryColor, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(label: 'Verify Code', onPressed: _verifyCode),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        key: const ValueKey('step_password'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            icon: Icons.password_outlined,
            title: 'Set a New Password',
            subtitle: 'Choose a new password for your account.',
          ),
          TextFormField(
            controller: _newPasswordController,
            autofocus: true,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
            decoration: _fieldDecoration(
              label: 'New Password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textSecondary),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter a new password';
              if (value.length < 6) return 'Password must be at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitNewPassword(),
            style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
            decoration: _fieldDecoration(
              label: 'Confirm New Password',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textSecondary),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please confirm your new password';
              if (value != _newPasswordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 28),
          _primaryButton(label: 'Reset Password', onPressed: _submitNewPassword),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Column(
      key: const ValueKey('step_done'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _successColor.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_outline, size: 48, color: _successColor),
        ),
        const SizedBox(height: 24),
        const Text('Password Updated', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: -0.4)),
        const SizedBox(height: 8),
        const Text(
          'Your password has been reset. Sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w500, height: 1.4),
        ),
        const SizedBox(height: 28),
        _primaryButton(label: 'Back to Sign In', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
