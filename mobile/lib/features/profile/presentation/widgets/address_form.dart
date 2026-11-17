import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/form_reveal.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/providers/auth_controller.dart';
import '../../data/models/address.dart';
import '../../providers/profile_providers.dart';

/// Pakistani mobile/landline: `03XX XXXXXXX` or `+92 3XX XXXXXXX`.
String? validatePkPhone(String? value) {
  final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (v.isEmpty) return 'Phone is required';
  final ok = RegExp(r'^(\+92|0092|0)?3\d{9}$').hasMatch(v) || RegExp(r'^(\+92|0)?[1-9]\d{8,9}$').hasMatch(v);
  return ok ? null : 'Enter a valid Pakistani number, e.g. 0300 1234567';
}

/// Create / edit an address. Saves through [addressesProvider] and calls
/// [onSaved] with the server's copy. Used by the address screen and inline
/// in checkout.
class AddressForm extends ConsumerStatefulWidget {
  const AddressForm({super.key, this.initial, required this.onSaved, this.onCancel, this.submitLabel});

  final Address? initial;
  final ValueChanged<Address> onSaved;
  final VoidCallback? onCancel;
  final String? submitLabel;

  @override
  ConsumerState<AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<AddressForm> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.initial?.label ?? 'Home');
  late final _name = TextEditingController(text: widget.initial?.fullName ?? ref.read(currentUserProvider)?.name ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? ref.read(currentUserProvider)?.phone ?? '');
  late final _line1 = TextEditingController(text: widget.initial?.line1);
  late final _line2 = TextEditingController(text: widget.initial?.line2);
  late final _city = TextEditingController(text: widget.initial?.city);
  late final _postal = TextEditingController(text: widget.initial?.postalCode);
  late String? _province = pakistanProvinces.contains(widget.initial?.province) ? widget.initial!.province : null;
  bool _busy = false;
  ApiException? _error;

  static const _labels = ['Home', 'Office', 'Other'];

  @override
  void dispose() {
    for (final c in [_label, _name, _phone, _line1, _line2, _city, _postal]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!FormReveal.validate(_form)) {
      setState(() => _error = const ApiException(FormReveal.fixFields));
      return;
    }
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final address = Address(
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      line1: _line1.text.trim(),
      line2: _line2.text.trim().isEmpty ? null : _line2.text.trim(),
      city: _city.text.trim(),
      province: _province!,
      postalCode: _postal.text.trim().isEmpty ? null : _postal.text.trim(),
    );
    try {
      final saved = await ref.read(addressesProvider.notifier).save(address, id: widget.initial?.id);
      if (mounted) widget.onSaved(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // keep the (auto-disposed) address list alive while saving
    ref.listen(addressesProvider, (_, _) {});
    final t = context.textTheme;
    const gap = SizedBox(height: AppSpacing.md);

    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < 420
          ? Column(children: [a, gap, b])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: a), const SizedBox(width: AppSpacing.sm), Expanded(child: b)],
            ),
    );

    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
            Text('Label', style: t.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final l in _labels)
                  ChoiceChip(
                    label: Text(l),
                    selected: _label.text == l,
                    onSelected: (_) => setState(() => _label.text = l),
                  ),
              ],
            ),
            gap,
            pair(
              AppTextField(
                label: 'Full name',
                controller: _name,
                prefixIcon: Icons.person_outline_rounded,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                validator: Validators.name,
                errorText: _error?.fieldError('fullName'),
              ),
              AppTextField(
                label: 'Phone',
                controller: _phone,
                hint: '0300 1234567',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                validator: validatePkPhone,
                errorText: _error?.fieldError('phone'),
              ),
            ),
            gap,
            AppTextField(
              label: 'Address line 1',
              controller: _line1,
              hint: 'House / flat, street, block',
              prefixIcon: Icons.home_outlined,
              autofillHints: const [AutofillHints.streetAddressLine1],
              textCapitalization: TextCapitalization.words,
              validator: Validators.combine([Validators.required('Address'), Validators.minLength(5, 'Address')]),
              errorText: _error?.fieldError('line1'),
            ),
            gap,
            AppTextField(
              label: 'Address line 2 (optional)',
              controller: _line2,
              hint: 'Area, landmark',
              autofillHints: const [AutofillHints.streetAddressLine2],
              textCapitalization: TextCapitalization.words,
            ),
            gap,
            pair(
              AppTextField(
                label: 'City',
                controller: _city,
                prefixIcon: Icons.location_city_outlined,
                autofillHints: const [AutofillHints.addressCity],
                textCapitalization: TextCapitalization.words,
                validator: Validators.required('City'),
                errorText: _error?.fieldError('city'),
              ),
              AppTextField(
                label: 'Postal code (optional)',
                controller: _postal,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.postalCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                validator: (v) => (v == null || v.isEmpty || v.length == 5) ? null : '5 digits',
              ),
            ),
            gap,
            Text('Province', style: t.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: _province,
              isExpanded: true,
              hint: const Text('Select province'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.map_outlined, size: 20),
                errorText: _error?.fieldError('province'),
              ),
              items: [for (final p in pakistanProvinces) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() => _province = v),
              validator: (v) => v == null ? 'Select a province' : null,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                if (widget.onCancel != null) ...[
                  Expanded(child: AppButton.secondary(label: 'Cancel', onPressed: _busy ? null : widget.onCancel)),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: AppButton(
                    label: widget.submitLabel ?? (widget.initial == null ? 'Save address' : 'Save changes'),
                    loading: _busy,
                    expand: true,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
