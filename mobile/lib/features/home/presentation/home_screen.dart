import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../../ai/presentation/widgets/for_you_rail.dart';
import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/require_auth.dart';
import '../../catalog/data/models/catalog_models.dart';
import '../../catalog/data/models/product_query.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../compare_tray/compare_tray_provider.dart';
import '../../notifications/providers/notifications_providers.dart';
import 'widgets/ask_bar.dart';
import 'widgets/banner_carousel.dart';
import 'widgets/home_sections.dart';

/// AI-first home: greeting, "Ask Zelora" prompt, AI shortcuts, banners,
/// departments, flash deals, personal picks and curated rails.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(unreadNotificationsProvider.notifier).refresh();
    try {
      ref.invalidate(homeFeedProvider);
      await ref.read(homeFeedProvider.future);
    } catch (_) {
      // the error state shows in place
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        edgeOffset: MediaQuery.paddingOf(context).top,
        child: CustomScrollView(
          slivers: [
            const _HomeAppBar(),
            const _Box(child: _Greeting()),
            const _Box(top: AppSpacing.md, child: AskBar()),
            _Box(
              top: AppSpacing.md,
              child: QuickActions(
                onCompare: () => context.push(Routes.compareOf(ref.read(compareTrayProvider.notifier).ids)),
              ),
            ),
            ...switch (feed) {
              AsyncValue(:final value?) => _content(context, value),
              AsyncValue(:final error?) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: ErrorState(
                      error: error,
                      compact: true,
                      onRetry: () => ref.invalidate(homeFeedProvider),
                    ),
                  ),
                ),
              ],
              _ => _loading(context),
            },
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  List<Widget> _loading(BuildContext context) => [
    const _Box(top: AppSpacing.xl, child: BannerCarouselSkeleton()),
    const _Box(top: AppSpacing.xl, child: _HeaderSkeleton()),
    const SliverToBoxAdapter(
      child: Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: DepartmentTilesSkeleton()),
    ),
    const _Box(top: AppSpacing.xl, child: _HeaderSkeleton()),
    const _Rail(top: AppSpacing.sm, child: ProductRail.loading()),
  ];

  List<Widget> _content(BuildContext context, HomeFeed feed) {
    final wide = context.isWide;
    return [
      if (feed.banners.isNotEmpty) _Box(top: AppSpacing.xl, child: BannerCarousel(banners: feed.banners)),
      if (feed.departments.isNotEmpty) ...[
        _Box(
          top: AppSpacing.xl,
          child: SectionHeader(
            title: 'Shop by department',
            onSeeAll: () => context.go(Routes.explore),
            actionLabel: 'All',
          ),
        ),
        wide
            ? _Box(top: AppSpacing.sm, child: DepartmentTiles(departments: feed.departments))
            : _Rail(top: AppSpacing.xs, child: DepartmentTiles(departments: feed.departments)),
      ],
      if (feed.flashDeals.isNotEmpty) ...[
        _Box(
          top: AppSpacing.xl,
          child: _FlashHeader(
            endsAt: feed.dealEndsAt,
            onSeeAll: () => context.push(
              Routes.productList(onSale: true, sort: ProductSort.discount.value, title: 'Flash deals'),
            ),
          ),
        ),
        _Rail(top: AppSpacing.sm, child: ProductRail(products: feed.flashDeals)),
      ],
      // AI recommendations (owned by the AI feature; renders its own header)
      const _Rail(top: AppSpacing.xl, child: ForYouRail()),
      ..._rail(context, 'Trending now', 'What everyone is buying', feed.trending, ProductSort.popular),
      ..._rail(context, 'Top rated', 'Loved by shoppers', feed.topRated, ProductSort.rating),
      ..._rail(context, 'New arrivals', 'Fresh in the store', feed.newArrivals, ProductSort.newest),
    ];
  }

  List<Widget> _rail(BuildContext context, String title, String subtitle, List<ProductSummary> items, ProductSort sort) {
    if (items.isEmpty) return const [];
    return [
      _Box(
        top: AppSpacing.xl,
        child: SectionHeader(
          title: title,
          subtitle: subtitle,
          onSeeAll: () => context.push(Routes.productList(sort: sort.value, title: title)),
        ),
      ),
      _Rail(top: AppSpacing.sm, child: ProductRail(products: items)),
    ];
  }
}

/// Section with page gutters, capped at the content width.
class _Box extends StatelessWidget {
  const _Box({required this.child, this.top = 0});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: ResponsiveCenter(child: child),
      ),
    );
  }
}

/// Edge-to-edge horizontal content (rails pad themselves), capped on desktop.
class _Rail extends StatelessWidget {
  const _Rail({required this.child, this.top = 0});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: ResponsiveCenter(padding: EdgeInsets.zero, child: child),
      ),
    );
  }
}

class _HomeAppBar extends ConsumerWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return SliverAppBar(
      floating: true,
      snap: true,
      titleSpacing: context.pagePadding,
      // the rail already shows the logo on wide screens
      title: context.useBottomNav
          ? const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: AppLogo(size: 30))
          : null,
      actions: [
        IconButton(
          tooltip: 'Search',
          onPressed: () => context.push(Routes.search),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
          onPressed: () {
            if (!requireAuth(context, ref, message: 'Sign in to see your notifications')) return;
            context.push(Routes.notifications);
          },
          icon: AppBadge(count: unread, child: const Icon(Icons.notifications_none_rounded)),
        ),
        SizedBox(width: context.pagePadding - AppSpacing.xxs),
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  static String _partOfDay(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUserProvider.select((u) => u?.firstName));
    final t = context.textTheme;
    final colors = context.colors;
    final hello = name == null || name.isEmpty ? 'Welcome to ${AppConfig.appName}' : '${_partOfDay(DateTime.now())}, $name';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(hello, style: (context.isWide ? t.displaySmall : t.headlineMedium)),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Tell '),
                TextSpan(
                  text: 'Zel',
                  style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: ' what you need. It finds the best match.'),
              ],
            ),
            style: t.bodyMedium!.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _FlashHeader extends StatelessWidget {
  const _FlashHeader({required this.endsAt, required this.onSeeAll});

  final DateTime? endsAt;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(Icons.bolt_rounded, color: colors.sale, size: 26),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: [
              Semantics(header: true, child: Text('Flash deals', style: context.textTheme.titleLarge)),
              if (endsAt != null) DealCountdown(endsAt: endsAt!),
            ],
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(foregroundColor: colors.muted),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('See all', semanticsLabel: 'See all flash deals'), Icon(Icons.chevron_right_rounded, size: 18)],
          ),
        ),
      ],
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Skeleton(width: 160, height: 18),
  );
}
