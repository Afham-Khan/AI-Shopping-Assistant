import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../data/profile_repository.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .changePassword(currentPassword: _current.text, newPassword: _next.text);
      if (!mounted) return;
      AppSnack.success(context, 'Password changed');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = Validators.strength(_next.text);
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          ResponsiveCenter(
            maxWidth: Breakpoints.maxForm,
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Use at least 8 characters with a letter and a number.',
                      style: context.textTheme.bodyMedium!.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
                    AppTextField(
                      label: 'Current password',
                      controller: _current,
                      isPassword: true,
                      prefixIcon: Icons.lock_outline_rounded,
                      autofillHints: const [AutofillHints.password],
                      validator: Validators.loginPassword,
                      errorText: _error?.fieldError('currentPassword'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'New password',
                      controller: _next,
                      isPassword: true,
                      prefixIcon: Icons.key_outlined,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.password,
                      errorText: _error?.fieldError('newPassword'),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (strength != PasswordStrength.empty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          for (var i = 1; i <= 4; i++) ...[
                            if (i > 1) const SizedBox(width: 4),
                            Expanded(
                              child: AnimatedContainer(
                                duration: context.motion(AppDurations.normal),
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i <= strength.level
                                      ? (strength.level <= 1
                                            ? colors.error
                                            : strength.level == 2
                                            ? colors.warning
                                            : colors.success)
                                      : colors.border,
                                  borderRadius: AppRadii.pillAll,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: AppSpacing.sm),
                          Text(strength.label, style: context.textTheme.labelSmall),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Confirm new password',
                      controller: _confirm,
                      isPassword: true,
                      prefixIcon: Icons.key_outlined,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.confirmPassword(() => _next.text),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(label: 'Update password', expand: true, loading: _busy, onPressed: _submit),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
