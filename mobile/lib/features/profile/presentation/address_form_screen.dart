import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/address.dart';
import '../providers/profile_providers.dart';
import 'widgets/address_form.dart';

/// Add a new address, or edit [addressId].
class AddressFormScreen extends ConsumerWidget {
  const AddressFormScreen({super.key, this.addressId});

  final int? addressId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = addressId != null;
    final async = editing ? ref.watch(addressesProvider) : null;
    Address? initial;
    if (editing) {
      for (final a in async?.value ?? const <Address>[]) {
        if (a.id == addressId) initial = a;
      }
    }

    void done(Address a) {
      AppSnack.success(context, editing ? 'Address updated' : 'Address saved');
      context.pop();
    }

    final Widget body;
    if (editing && async!.isLoading && initial == null) {
      body = const LoadingView();
    } else if (editing && initial == null) {
      body = async!.hasError
          ? ErrorState(error: async.error, onRetry: () => ref.invalidate(addressesProvider))
          : EmptyState(
              icon: Icons.location_off_outlined,
              title: 'Address not found',
              message: 'It may have been deleted.',
              actionLabel: 'Back',
              onAction: () => context.pop(),
            );
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          ResponsiveCenter(
            maxWidth: 560,
            child: AddressForm(key: ValueKey(initial?.id), initial: initial, onSaved: done),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit address' : 'New address')),
      body: body,
    );
  }
}
