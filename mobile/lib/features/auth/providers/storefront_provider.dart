import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';

/// Real numbers and photos for the welcome / sign-in screens, so the first
/// thing a visitor sees is the actual store rather than stock art.
class StorefrontGlance {
  const StorefrontGlance({
    required this.products,
    required this.departments,
    required this.categories,
    required this.images,
  });

  final int products;
  final int departments;
  final int categories;

  /// A few department cover photos (raw API urls).
  final List<String> images;
}

/// Null when the store can't be reached — callers fall back to quiet
/// placeholders (never an error screen before sign-in).
final storefrontGlanceProvider = FutureProvider<StorefrontGlance?>((ref) async {
  try {
    final departments = await ref.watch(apiClientProvider).get<List<dynamic>>(
      '/catalog/departments',
      decode: (d) => d is List ? d : const [],
    );
    var products = 0;
    var categories = 0;
    final images = <String>[];
    for (final item in departments.whereType<Map<String, dynamic>>()) {
      products += JsonX.asInt(item['productCount']);
      final cats = item['categories'];
      if (cats is List) categories += cats.length;
      final image = JsonX.asStringOrNull(item['imageUrl']);
      if (image != null && image.isNotEmpty) images.add(image);
    }
    return StorefrontGlance(
      products: products,
      departments: departments.length,
      categories: categories,
      images: images,
    );
  } on Object {
    return null;
  }
});

/// A handful of real products for the onboarding vignettes. Empty when offline.
final onboardingProductsProvider = FutureProvider<List<ProductSummary>>((ref) async {
  try {
    final page = await ref.watch(apiClientProvider).getPage(
      '/products',
      query: {'limit': 10, 'sort': 'rating'},
      item: ProductSummary.fromJson,
    );
    return page.items;
  } on Object {
    return const [];
  }
});

/// Snap & Find vignette: a real product plus three look-alikes from the same
/// category (target first). Prefers categories whose products look alike in
/// a photo (watches, sunglasses, shoes); empty when offline.
final onboardingSnapProvider = FutureProvider<List<ProductSummary>>((ref) async {
  final api = ref.watch(apiClientProvider);
  for (final slug in const ['mens-watches', 'sunglasses', 'womens-watches', 'mens-shoes']) {
    try {
      final page = await api.getPage(
        '/products',
        query: {'category': slug, 'limit': 4, 'sort': 'rating'},
        item: ProductSummary.fromJson,
      );
      if (page.items.length >= 4) return page.items;
    } on Object {
      return const [];
    }
  }
  return const [];
});

enum StoreStatus { checking, online, offline }

/// Live reachability of the configured server, with round-trip time.
/// Re-checks whenever the server address changes.
final storeHealthProvider = FutureProvider.autoDispose<({StoreStatus status, int? ms})>((ref) async {
  final url = ref.watch(serverUrlProvider);
  try {
    final latency = await ApiClient.checkHealth(url);
    return (status: StoreStatus.online, ms: latency.inMilliseconds);
  } on Object {
    return (status: StoreStatus.offline, ms: null);
  }
});
