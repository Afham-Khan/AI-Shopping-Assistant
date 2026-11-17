/// Form validators. Each returns an error message or null (TextFormField style).
///
/// ```dart
/// AppTextField(validator: Validators.email)
/// AppTextField(validator: Validators.required('Name'))
/// ```
abstract final class Validators {
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _otpRe = RegExp(r'^\d{6}$');
  static final _phoneRe = RegExp(r'^\+?[0-9][0-9\s-]{8,15}$');

  static String? Function(String?) required([String field = 'This field']) =>
      (value) => (value == null || value.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Mirrors the API rule: at least 8 characters with a letter and a number.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!v.contains(RegExp('[A-Za-z]')) || !v.contains(RegExp('[0-9]'))) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// For the login form: presence only (don't leak rules on sign in).
  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Password is required' : null;

  static String? Function(String?) confirmPassword(String Function() original) =>
      (value) {
        if (value == null || value.isEmpty) return 'Please confirm your password';
        return value == original() ? null : "Passwords don't match";
      };

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name is too short';
    if (v.length > 80) return 'Name is too long';
    return null;
  }

  /// Optional phone: valid when empty.
  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return _phoneRe.hasMatch(v) ? null : 'Enter a valid phone number';
  }

  static String? otp(String? value) =>
      _otpRe.hasMatch(value?.trim() ?? '') ? null : 'Enter the 6-digit code';

  static String? Function(String?) minLength(int min, [String field = 'This field']) =>
      (value) => (value?.trim().length ?? 0) < min ? '$field must be at least $min characters' : null;

  /// Runs validators in order and returns the first error.
  static String? Function(String?) combine(List<String? Function(String?)> validators) =>
      (value) {
        for (final validate in validators) {
          final error = validate(value);
          if (error != null) return error;
        }
        return null;
      };

  /// Rough strength for the register hint.
  static PasswordStrength strength(String value) {
    if (value.isEmpty) return PasswordStrength.empty;
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (value.contains(RegExp('[a-z]')) && value.contains(RegExp('[A-Z]'))) score++;
    if (value.contains(RegExp('[0-9]'))) score++;
    if (value.contains(RegExp(r'[^A-Za-z0-9]'))) score++;
    if (password(value) != null) return PasswordStrength.weak;
    if (score <= 2) return PasswordStrength.fair;
    if (score == 3) return PasswordStrength.good;
    return PasswordStrength.strong;
  }
}

enum PasswordStrength {
  empty('', 0),
  weak('Weak', 1),
  fair('Fair', 2),
  good('Good', 3),
  strong('Strong', 4);

  const PasswordStrength(this.label, this.level);

  final String label;

  /// 0-4, for drawing the strength bar.
  final int level;
}
