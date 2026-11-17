import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/models/user.dart';
import '../../auth/providers/auth_controller.dart';
import '../../notifications/providers/notifications_providers.dart';
import '../data/profile_repository.dart';
import '../providers/profile_providers.dart';

/// Account hub: profile header, activity stats and menus. Guests get a
/// sign-in card plus the settings that don't need an account.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: RefreshIndicator(
        onRefresh: () async {
          if (user == null) return;
          ref.invalidate(userStatsProvider);
          await Future.wait([
            ref.read(authControllerProvider.notifier).refreshUser(),
            ref.read(userStatsProvider.future).catchError((_) => const UserStats()),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ResponsiveCenter(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: user == null ? _guest(context) : _member(context, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _guest(BuildContext context) => [
    const SizedBox(height: AppSpacing.sm),
    const _GuestCard(),
    _MenuGroup(
      title: 'App',
      items: [
        _MenuItem(icon: Icons.settings_outlined, label: 'Settings', onTap: () => context.push(Routes.settings)),
        _MenuItem(icon: Icons.help_outline_rounded, label: 'Help & about', onTap: () => _about(context)),
      ],
    ),
  ];

  List<Widget> _member(BuildContext context, User user) => [
    const SizedBox(height: AppSpacing.sm),
    _ProfileHeader(user: user),
    const SizedBox(height: AppSpacing.md),
    const _Stats(),
    _MenuGroup(
      title: 'Shopping',
      items: [
        _MenuItem(icon: Icons.receipt_long_outlined, label: 'My orders', onTap: () => context.push(Routes.orders)),
        _MenuItem(icon: Icons.favorite_border_rounded, label: 'Wishlist', onTap: () => context.push(Routes.wishlist)),
        _MenuItem(icon: Icons.location_on_outlined, label: 'Addresses', onTap: () => context.push(Routes.addresses)),
        const _NotificationsItem(),
      ],
    ),
    _MenuGroup(
      title: 'Your AI',
      items: [
        _MenuItem(
          icon: Icons.fingerprint_rounded,
          label: 'My Shopping DNA',
          subtitle: 'What the AI has learned about your taste',
          onTap: () => context.push(Routes.shoppingDna),
          ai: true,
        ),
        _MenuItem(
          icon: Icons.science_outlined,
          label: 'AI Lab',
          subtitle: 'See how the assistant understands you',
          onTap: () => context.push(Routes.aiLab),
          ai: true,
        ),
      ],
    ),
    _MenuGroup(
      title: 'Account',
      items: [
        _MenuItem(icon: Icons.person_outline_rounded, label: 'Edit profile', onTap: () => context.push(Routes.editProfile)),
        _MenuItem(icon: Icons.lock_outline_rounded, label: 'Change password', onTap: () => context.push(Routes.changePassword)),
        _MenuItem(icon: Icons.settings_outlined, label: 'Settings', onTap: () => context.push(Routes.settings)),
        _MenuItem(icon: Icons.help_outline_rounded, label: 'Help & about', onTap: () => _about(context)),
      ],
    ),
    const SizedBox(height: AppSpacing.lg),
    const _SignOutButton(),
  ];

  static void _about(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: AppConfig.appName,
    applicationVersion: AppConfig.appVersion,
    applicationIcon: const AppLogo(size: 40, showWordmark: false),
    children: [
      const SizedBox(height: AppSpacing.sm),
      Text(
        '${AppConfig.appName} is an AI shopping assistant. Ask for what you need in plain words, '
        'compare products side by side and get picks tuned to your taste.\n\n'
        'Need help with an order? Open it from My orders — you can track, cancel or buy again from there.',
        style: context.textTheme.bodyMedium,
      ),
    ],
  );
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.sheetAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(size: 36, showWordmark: false),
          const SizedBox(height: AppSpacing.md),
          Text('Sign in to ${AppConfig.appName}', style: t.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Track orders, save your wishlist, check out faster and get AI picks tuned to you.',
            style: t.bodyMedium!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Sign in', expand: true, onPressed: () => context.push(Routes.loginFrom(Routes.account))),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Create an account',
            expand: true,
            onPressed: () => context.push(Routes.registerFrom(Routes.account)),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.sheetAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: colors.primarySoft,
            child: Text(user.initials, style: t.titleLarge!.copyWith(color: colors.primary)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(user.email, style: t.bodyMedium!.copyWith(color: colors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (user.createdAt != null)
                  Text('Member since ${DateFormat('MMMM y').format(user.createdAt!.toLocal())}', style: t.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit profile',
            onPressed: () => context.push(Routes.editProfile),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userStatsProvider);
    final s = async.value;
    final items = [
      ('Orders', s?.orders, () => context.push(Routes.orders)),
      ('Wishlist', s?.wishlist, () => context.push(Routes.wishlist)),
      ('Reviews', s?.reviews, null),
      ('AI chats', s?.conversations, () => context.go(Routes.conversations)),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _StatTile(label: items[i].$1, value: items[i].$2, onTap: items[i].$3, failed: async.hasError && s == null),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.onTap, required this.failed});

  final String label;
  final int? value;
  final VoidCallback? onTap;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label: ${value ?? 'loading'}',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xxs),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: context.motion(AppDurations.normal),
                  child: value == null
                      ? (failed ? Text('–', style: t.titleLarge) : const Skeleton(width: 24, height: 22))
                      : Text(Formatters.compact(value), key: ValueKey(value), style: t.titleLarge),
                ),
                const SizedBox(height: 2),
                Text(label, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items});

  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
            child: Semantics(header: true, child: Text(title, style: context.textTheme.titleSmall!.copyWith(color: colors.muted))),
          ),
          Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  items[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.ai = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool ai;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: ai ? context.colors.ai : null),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [?trailing, const Icon(Icons.chevron_right_rounded)],
      ),
      onTap: onTap,
    );
  }
}

class _NotificationsItem extends ConsumerWidget {
  const _NotificationsItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return _MenuItem(
      icon: Icons.notifications_none_rounded,
      label: 'Notifications',
      onTap: () => context.push(Routes.notifications),
      trailing: unread > 0
          ? Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Badge(label: Text('$unread'), largeSize: 20),
            )
          : null,
    );
  }
}

class _SignOutButton extends ConsumerStatefulWidget {
  const _SignOutButton();

  @override
  ConsumerState<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<_SignOutButton> {
  Future<void> _signOut() async {
    final out = await ConfirmDialog.show(
      context,
      title: 'Sign out?',
      message: 'You can sign back in any time to see your orders and wishlist.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      onConfirm: () => ref.read(authControllerProvider.notifier).logout(),
    );
    if (out && mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      label: 'Sign out',
      icon: Icons.logout_rounded,
      expand: true,
      onPressed: _signOut,
    );
  }
}
