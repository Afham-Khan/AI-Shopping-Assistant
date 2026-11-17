import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/form_reveal.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/profile_repository.dart';

/// Name and phone (email is the sign-in identity and can't change here).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(currentUserProvider)?.name ?? '');
  late final _phone = TextEditingController(text: ref.read(currentUserProvider)?.phone ?? '');
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!FormReveal.validate(_form)) {
      setState(() => _error = const ApiException(FormReveal.fixFields));
      return;
    }
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(profileRepositoryProvider).updateProfile(name: _name.text, phone: _phone.text);
      ref.read(authControllerProvider.notifier).updateUser(user);
      if (!mounted) return;
      AppSnack.success(context, 'Profile updated');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          ResponsiveCenter(
            maxWidth: Breakpoints.maxForm,
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: colors.primarySoft,
                      child: Text(
                        (_name.text.isEmpty ? (user?.name ?? '?') : _name.text).initials,
                        style: context.textTheme.headlineSmall!.copyWith(color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
                  AppTextField(
                    label: 'Full name',
                    controller: _name,
                    prefixIcon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: Validators.name,
                    errorText: _error?.fieldError('name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Email',
                    initialValue: user?.email,
                    prefixIcon: Icons.mail_outline_rounded,
                    enabled: false,
                    helperText: 'Your email is used to sign in and can\'t be changed.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Phone (optional)',
                    controller: _phone,
                    hint: '0300 1234567',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                    validator: Validators.phone,
                    errorText: _error?.fieldError('phone'),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(label: 'Save changes', expand: true, loading: _busy, onPressed: _save),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
