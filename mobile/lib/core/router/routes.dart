/// Every route in the app, plus helpers that build concrete locations.
///
/// Conventions
/// - Navigate with the helpers, never hand-written strings:
///   `context.push(Routes.product(42))`, `context.go(Routes.home)`.
/// - `context.go` for tab roots and "start over" flows (login → home);
///   `context.push` for drill-down screens so back works.
/// - Path params are for identity: `/product/:id` (int id or slug),
///   `/account/orders/:id`, `/order-success/:id`.
/// - Query params are for optional filters/state and are all strings:
///   - products list: `category, department, brand (comma list), q, sort,
///     onSale=true, title` (title = header text to show)
///   - compare: `ids=1,2,3` · smart search: `q` · assistant: `c` (conversation
///     id) and `prompt` (message to send on open; `q` is accepted as an alias)
///     · address form: `id` (edit)
///   - auth screens: `from` = location to return to after sign-in.
/// - Protected routes (see [Routes.protected]) redirect guests to
///   `/login?from=<location>`; after sign-in the router sends them back.
/// - Tab roots (home/explore/assistant/cart/account) live inside the shell;
///   everything else opens full-screen above it.
abstract final class Routes {
  // boot & auth
  static const splash = '/splash';
  static const onboarding = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const interests = '/interests';

  // shell tabs
  static const home = '/';
  static const explore = '/explore';
  static const assistant = '/assistant';
  static const cart = '/cart';
  static const account = '/account';

  // nested in tabs (keep the nav bar)
  static const conversations = '/assistant/history';
  static const orders = '/account/orders';
  static const orderDetail = '/account/orders/:id';
  static const editProfile = '/account/edit';
  static const addresses = '/account/addresses';
  static const addressForm = '/account/addresses/form';
  static const changePassword = '/account/password';
  static const memory = '/account/memory';

  // full-screen
  static const products = '/products';
  static const productDetail = '/product/:id';
  static const reviews = '/product/:id/reviews';
  static const search = '/search';
  static const wishlist = '/wishlist';
  static const checkout = '/checkout';
  static const orderSuccess = '/order-success/:id';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const compare = '/compare';
  static const finder = '/finder';
  static const aiLab = '/ai-lab';
  static const smartSearch = '/smart-search';
  static const visualSearch = '/visual-search';
  static const bundleBuilder = '/bundle-builder';
  static const productAsk = '/product/:id/ask';
  static const shoppingDna = '/shopping-dna';
  static const discover = '/discover';
  static const giftFinder = '/gift-finder';
  static const priceAlerts = '/price-alerts';

  /// Screens that need a signed-in user (prefix match).
  static const protected = <String>[
    interests,
    // assistant handles guests itself (sign-in prompt inside the tab)
    cart,
    orders,
    editProfile,
    addresses,
    changePassword,
    wishlist,
    checkout,
    '/order-success',
    notifications,
    shoppingDna,
    priceAlerts,
    memory,
  ];

  /// Auth screens a signed-in user is bounced away from.
  static const authOnly = <String>[login, register, forgotPassword];

  static bool isProtected(String path) =>
      protected.any((p) => path == p || path.startsWith('$p/'));

  // ---------- location builders ----------

  /// [idOrSlug]: int id or slug string.
  static String product(Object idOrSlug) => '/product/${Uri.encodeComponent('$idOrSlug')}';

  static String reviewsOf(int productId) => '/product/$productId/reviews';

  static String productAskOf(int productId) => '/product/$productId/ask';

  static String productList({
    String? category,
    String? department,
    List<String>? brands,
    String? q,
    String? sort,
    bool onSale = false,
    String? title,
  }) => _withQuery(products, {
    'category': category,
    'department': department,
    'brand': brands?.join(','),
    'q': q,
    'sort': sort,
    'onSale': onSale ? 'true' : null,
    'title': title,
  });

  static String searchWith({String? q}) => _withQuery(search, {'q': q});

  static String orderDetailOf(int orderId) => '/account/orders/$orderId';

  static String orderSuccessOf(int orderId) => '/order-success/$orderId';

  static String addressFormFor({int? addressId}) =>
      _withQuery(addressForm, {'id': addressId?.toString()});

  static String assistantWith({int? conversationId, String? prompt}) =>
      _withQuery(assistant, {'c': conversationId?.toString(), 'prompt': prompt});

  static String compareOf(List<int> productIds) => _withQuery(compare, {'ids': productIds.join(',')});

  static String smartSearchOf(String query) => _withQuery(smartSearch, {'q': query});

  static String loginFrom(String? from) => _withQuery(login, {'from': _safeFrom(from)});

  static String registerFrom(String? from) => _withQuery(register, {'from': _safeFrom(from)});

  static String interestsFrom(String? from) => _withQuery(interests, {'from': _safeFrom(from)});

  /// Only allow in-app return targets (avoid open redirects / loops).
  static String? _safeFrom(String? from) {
    if (from == null || from.isEmpty || !from.startsWith('/') || from.startsWith('//')) return null;
    final path = Uri.parse(from).path;
    if (path == splash || path == onboarding || authOnly.contains(path)) return null;
    return from;
  }

  /// Validated `from` param, or [fallback].
  static String returnTo(String? from, {String fallback = home}) => _safeFrom(from) ?? fallback;

  static String _withQuery(String path, Map<String, String?> params) {
    final query = <String, String>{
      for (final e in params.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return query.isEmpty ? path : Uri(path: path, queryParameters: query).toString();
  }
}
