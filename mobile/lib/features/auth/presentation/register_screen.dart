import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_strength_meter.dart';

/// Account creation. New users are redirected to the interests screen.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    // repaint the strength meter as the user types
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      TextInput.finishAutofillContext();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _error?.fieldErrors ?? const {};
    final colors = context.colors;

    return AuthScaffold(
      eyebrow: 'New account',
      title: 'Create your account',
      subtitle: 'Takes a minute. Then Zel can remember your taste, your budget and what you saved.',
      onBack: context.canPop() ? () => context.pop() : null,
      footer: AuthFooterLink(
        question: 'Already have an account?',
        action: 'Sign in',
        onTap: () => context.pushReplacement(Routes.loginFrom(widget.from)),
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorBanner(message: fieldErrors.isEmpty ? _error?.message : null),
              AppTextField(
                label: 'Full name',
                controller: _name,
                hint: 'Ali Khan',
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: Validators.name,
                errorText: fieldErrors['name'],
                enabled: !_busy,
              ),
              AppSpacing.gapMd,
              AppTextField(
                label: 'Email',
                controller: _email,
                hint: 'you@example.com',
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                errorText: fieldErrors['email'],
                enabled: !_busy,
              ),
              AppSpacing.gapMd,
              AppTextField(
                label: 'Password',
                controller: _password,
                isPassword: true,
                prefixIcon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.newPassword],
                validator: Validators.password,
                errorText: fieldErrors['password'],
                enabled: !_busy,
              ),
              AppSpacing.gapXs,
              PasswordStrengthMeter(password: _password.text),
              AppSpacing.gapMd,
              AppTextField(
                label: 'Confirm password',
                controller: _confirm,
                isPassword: true,
                prefixIcon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.newPassword],
                validator: Validators.confirmPassword(() => _password.text),
                onSubmitted: (_) => _submit(),
                enabled: !_busy,
              ),
              AppSpacing.gapXl,
              AppButton(label: 'Create account', onPressed: _submit, loading: _busy, expand: true),
              AppSpacing.gapSm,
              Text(
                'By creating an account you agree to the Terms and Privacy Policy.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall!.copyWith(color: colors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
