import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/ai/presentation/ai_lab_screen.dart';
import '../../features/ai/presentation/compare_screen.dart';
import '../../features/ai/presentation/bundle_builder_screen.dart';
import '../../features/ai/presentation/finder_screen.dart';
import '../../features/ai/presentation/gift_finder_screen.dart';
import '../../features/ai/presentation/product_ask_screen.dart';
import '../../features/ai/presentation/shopping_dna_screen.dart';
import '../../features/ai/presentation/smart_search_screen.dart';
import '../../features/ai/presentation/visual_search_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/assistant/presentation/conversations_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/interests_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/auth/providers/onboarding_provider.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/catalog/presentation/explore_screen.dart';
import '../../features/catalog/presentation/product_list_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/checkout/presentation/order_success_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/product/presentation/product_detail_screen.dart';
import '../../features/product/presentation/reviews_screen.dart';
import '../../features/profile/presentation/account_screen.dart';
import '../../features/profile/presentation/address_form_screen.dart';
import '../../features/profile/presentation/addresses_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/shopping_memory_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/wishlist/presentation/price_alerts_screen.dart';
import '../../features/wishlist/presentation/wishlist_screen.dart';
import '../widgets/state_views.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app router. Re-runs [_redirect] whenever the session or onboarding
/// flag changes (the router itself is created once).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingDoneProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: _routes,
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

String? _redirect(Ref ref, GoRouterState state) {
  final auth = ref.read(authControllerProvider);
  final onboarded = ref.read(onboardingDoneProvider);
  final uri = state.uri;
  final path = uri.path;
  final from = uri.queryParameters['from'];

  // 1. hold on the splash while the session is restored, remembering deep links
  if (auth.isUnknown) {
    if (path == Routes.splash) return null;
    final keep = path == Routes.home ? null : uri.toString();
    return Uri(path: Routes.splash, queryParameters: keep == null ? null : {'from': keep}).toString();
  }

  // 2. leave the splash: intro → (signed in | guest | deep link) → login
  if (path == Routes.splash) {
    if (!onboarded) return Routes.onboarding;
    final target = Routes.returnTo(from);
    if (auth.isAuthenticated || auth.guestChosen) return target;
    final isPublicDeepLink = from != null && !Routes.isProtected(Uri.parse(target).path);
    return isPublicDeepLink ? target : Routes.loginFrom(from);
  }

  if (path == Routes.onboarding && onboarded) {
    return auth.isAuthenticated ? Routes.home : Routes.login;
  }

  // 3. signed-in users don't see auth screens; brand-new users pick interests first
  if (auth.isAuthenticated && Routes.authOnly.contains(path)) {
    final target = Routes.returnTo(from);
    if (auth.user?.isOnboarded == false) {
      return Routes.interestsFrom(target == Routes.home ? null : target);
    }
    return target;
  }

  // 4. guests are sent to login for protected screens, then back
  if (!auth.isAuthenticated && Routes.isProtected(path)) {
    return Routes.loginFrom(uri.toString());
  }

  return null;
}

/// `/account/orders` under `/account` → `orders`.
String _child(String full, String parent) => full.substring(parent.length + 1);

String? _q(GoRouterState s, String key) {
  final value = s.uri.queryParameters[key];
  return (value == null || value.isEmpty) ? null : value;
}

int _intParam(GoRouterState s, String key) => int.tryParse(s.pathParameters[key] ?? '') ?? 0;

final _routes = <RouteBase>[
  // boot & auth
  GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
  GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
  GoRoute(path: Routes.login, builder: (_, s) => LoginScreen(from: _q(s, 'from'))),
  GoRoute(path: Routes.register, builder: (_, s) => RegisterScreen(from: _q(s, 'from'))),
  GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
  GoRoute(path: Routes.interests, builder: (_, s) => InterestsScreen(from: _q(s, 'from'))),

  // tabs
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => AppShell(navigationShell: shell),
    branches: [
      StatefulShellBranch(
        routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())],
      ),
      StatefulShellBranch(
        routes: [GoRoute(path: Routes.explore, builder: (_, _) => const ExploreScreen())],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.assistant,
            builder: (_, s) => AssistantScreen(
              conversationId: int.tryParse(_q(s, 'c') ?? ''),
              initialPrompt: _q(s, 'prompt') ?? _q(s, 'q'),
            ),
            routes: [
              GoRoute(
                path: _child(Routes.conversations, Routes.assistant),
                builder: (_, _) => const ConversationsScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [GoRoute(path: Routes.cart, builder: (_, _) => const CartScreen())],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: Routes.account,
            builder: (_, _) => const AccountScreen(),
            routes: [
              GoRoute(
                path: _child(Routes.orders, Routes.account),
                builder: (_, _) => const OrdersScreen(),
                routes: [
                  GoRoute(path: ':id', builder: (_, s) => OrderDetailScreen(orderId: _intParam(s, 'id'))),
                ],
              ),
              GoRoute(
                path: _child(Routes.editProfile, Routes.account),
                builder: (_, _) => const EditProfileScreen(),
              ),
              GoRoute(
                path: _child(Routes.addresses, Routes.account),
                builder: (_, _) => const AddressesScreen(),
                routes: [
                  GoRoute(
                    path: _child(Routes.addressForm, Routes.addresses),
                    builder: (_, s) => AddressFormScreen(addressId: int.tryParse(_q(s, 'id') ?? '')),
                  ),
                ],
              ),
              GoRoute(
                path: _child(Routes.changePassword, Routes.account),
                builder: (_, _) => const ChangePasswordScreen(),
              ),
              GoRoute(
                path: _child(Routes.memory, Routes.account),
                builder: (_, _) => const ShoppingMemoryScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),

  // full-screen (root navigator, above the tabs)
  GoRoute(
    path: Routes.products,
    builder: (_, s) => ProductListScreen(
      category: _q(s, 'category'),
      department: _q(s, 'department'),
      brand: _q(s, 'brand'),
      q: _q(s, 'q'),
      sort: _q(s, 'sort'),
      onSale: _q(s, 'onSale') == 'true',
      title: _q(s, 'title'),
    ),
  ),
  GoRoute(
    path: Routes.productDetail,
    builder: (_, s) => ProductDetailScreen(idOrSlug: s.pathParameters['id']!),
    routes: [
      GoRoute(path: 'reviews', builder: (_, s) => ReviewsScreen(productId: _intParam(s, 'id'))),
      GoRoute(path: 'ask', builder: (_, s) => ProductAskScreen(productId: _intParam(s, 'id'))),
    ],
  ),
  GoRoute(path: Routes.search, builder: (_, s) => SearchScreen(initialQuery: _q(s, 'q'))),
  GoRoute(path: Routes.wishlist, builder: (_, _) => const WishlistScreen()),
  GoRoute(path: Routes.checkout, builder: (_, _) => const CheckoutScreen()),
  GoRoute(path: Routes.orderSuccess, builder: (_, s) => OrderSuccessScreen(orderId: _intParam(s, 'id'))),
  GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
  GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
  GoRoute(
    path: Routes.compare,
    builder: (_, s) => CompareScreen(
      productIds: [
        for (final id in (_q(s, 'ids') ?? '').split(',')) ?int.tryParse(id.trim()),
      ],
    ),
  ),
  GoRoute(path: Routes.finder, builder: (_, _) => const FinderScreen()),
  GoRoute(path: Routes.aiLab, builder: (_, _) => const AiLabScreen()),
  GoRoute(path: Routes.smartSearch, builder: (_, s) => SmartSearchScreen(query: _q(s, 'q') ?? '')),
  GoRoute(path: Routes.visualSearch, builder: (_, _) => const VisualSearchScreen()),
  GoRoute(path: Routes.bundleBuilder, builder: (_, _) => const BundleBuilderScreen()),
  GoRoute(path: Routes.shoppingDna, builder: (_, _) => const ShoppingDnaScreen()),
  GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverScreen()),
  GoRoute(path: Routes.giftFinder, builder: (_, _) => const GiftFinderScreen()),
  GoRoute(path: Routes.priceAlerts, builder: (_, _) => const PriceAlertsScreen()),
];

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        message: "The page you're looking for doesn't exist or has moved.",
        actionLabel: 'Go home',
        onAction: () => context.go(Routes.home),
      ),
    );
  }
}
