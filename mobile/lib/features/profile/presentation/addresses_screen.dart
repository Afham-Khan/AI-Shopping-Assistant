import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/address.dart';
import '../providers/profile_providers.dart';

/// Saved addresses: default badge, set default, edit, delete (confirmed).
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(addressesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Addresses')),
      floatingActionButton: (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.addressFormFor()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add address'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(addressesProvider);
          try {
            await ref.read(addressesProvider.future);
          } catch (_) {}
        },
        child: switch (async) {
          AsyncValue(:final value?) when value.isEmpty => LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: c.maxHeight,
                child: EmptyState(
                  icon: Icons.location_on_outlined,
                  title: 'No saved addresses',
                  message: 'Add one now and checkout becomes a single tap.',
                  actionLabel: 'Add address',
                  onAction: () => context.push(Routes.addressFormFor()),
                ),
              ),
            ),
          ),
          AsyncValue(:final value?) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              SliverResponsiveCenter.sidePadding(context, context.screenWidth, maxWidth: 720),
              AppSpacing.md,
              SliverResponsiveCenter.sidePadding(context, context.screenWidth, maxWidth: 720),
              96,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _AddressCard(address: value[i]),
          ),
          AsyncValue(:final error?) => ListView(
            children: [
              const SizedBox(height: AppSpacing.xxl),
              ErrorState(error: error, onRetry: () => ref.invalidate(addressesProvider)),
            ],
          ),
          _ => const ResponsiveCenter(maxWidth: 720, child: SkeletonList(count: 3)),
        },
      ),
    );
  }
}

enum _Action { setDefault, edit, delete }

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final Address address;

  Future<void> _onAction(BuildContext context, WidgetRef ref, _Action action) async {
    final notifier = ref.read(addressesProvider.notifier);
    try {
      switch (action) {
        case _Action.setDefault:
          await notifier.setDefault(address.id);
          if (context.mounted) AppSnack.success(context, '${address.label ?? 'Address'} is now your default');
        case _Action.edit:
          context.push(Routes.addressFormFor(addressId: address.id));
        case _Action.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete this address?'),
              content: Text(address.oneLine),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: context.colors.error),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await notifier.delete(address.id);
          if (context.mounted) AppSnack.info(context, 'Address deleted');
      }
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final a = address;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardAll,
        side: BorderSide(color: a.isDefault ? colors.text : colors.border, width: a.isDefault ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onAction(context, ref, _Action.edit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xxs, AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                a.label?.toLowerCase() == 'office' ? Icons.business_outlined : Icons.home_outlined,
                color: colors.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(a.label ?? 'Address', style: t.titleSmall),
                        if (a.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.inputAll),
                            child: Text('Default', style: t.labelSmall!.copyWith(color: colors.primary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(a.fullName, style: t.bodyMedium),
                    Text(a.phone, style: t.bodySmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(a.streetLine, style: t.bodyMedium),
                    Text(a.cityLine, style: t.bodyMedium),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                tooltip: 'Address options',
                onSelected: (action) => _onAction(context, ref, action),
                itemBuilder: (_) => [
                  if (!a.isDefault) const PopupMenuItem(value: _Action.setDefault, child: Text('Set as default')),
                  const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                  PopupMenuItem(
                    value: _Action.delete,
                    child: Text('Delete', style: TextStyle(color: colors.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
