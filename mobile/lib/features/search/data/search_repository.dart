import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';

@immutable
class SuggestedProduct {
  const SuggestedProduct({required this.id, required this.title, this.thumbnail, this.price = 0});

  factory SuggestedProduct.fromJson(Map<String, dynamic> json) => SuggestedProduct(
    id: JsonX.asInt(json['id']),
    title: JsonX.asString(json['title']),
    thumbnail: JsonX.asStringOrNull(json['thumbnail']),
    price: JsonX.asDouble(json['price']),
  );

  final int id;
  final String title;
  final String? thumbnail;
  final double price;
}

/// `GET /search/suggestions?q=`.
@immutable
class SearchSuggestions {
  const SearchSuggestions({this.products = const [], this.categories = const [], this.queries = const []});

  factory SearchSuggestions.fromJson(Map<String, dynamic> json) => SearchSuggestions(
    products: JsonX.asList(json['products'], SuggestedProduct.fromJson),
    categories: [
      for (final c in JsonX.asList(json['categories'], (m) => m))
        (name: JsonX.asString(c['name']), slug: JsonX.asString(c['slug'])),
    ],
    queries: JsonX.asStringList(json['queries']),
  );

  final List<SuggestedProduct> products;
  final List<({String name, String slug})> categories;
  final List<String> queries;

  bool get isEmpty => products.isEmpty && categories.isEmpty && queries.isEmpty;
}

class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  Future<SearchSuggestions> suggestions(String q) =>
      _api.get('/search/suggestions', query: {'q': q}, decode: (d) => SearchSuggestions.fromJson(d as Json));

  Future<List<String>> trending() => _api.get('/search/trending', decode: JsonX.asStringList);

  Future<List<String>> history() => _api.get(
    '/search/history',
    decode: (d) => [for (final e in JsonX.asList(d, (m) => m)) JsonX.asString(e['query'])],
  );

  Future<void> saveHistory(String query, {int? resultsCount}) =>
      _api.post<void>('/search/history', body: {'query': query, 'resultsCount': ?resultsCount});

  Future<void> clearHistory() => _api.delete<void>('/search/history');
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) => SearchRepository(ref.watch(apiClientProvider)));

final trendingSearchesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(searchRepositoryProvider).trending(),
);

/// Recent searches (signed-in only). Empty for guests.
/// `.notifier.record(q)` after a search, `.notifier.clear()` to wipe.
final searchHistoryProvider = AsyncNotifierProvider.autoDispose<SearchHistoryController, List<String>>(
  SearchHistoryController.new,
);

class SearchHistoryController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    if (!ref.watch(isAuthenticatedProvider)) return const <String>[];
    return ref.watch(searchRepositoryProvider).history();
  }

  /// Saves [query] (signed-in only) and moves it to the top locally.
  /// Never throws: history is a convenience.
  Future<void> record(String query) async {
    final q = query.trim();
    if (q.isEmpty || !ref.read(isAuthenticatedProvider)) return;
    final current = state.value ?? const <String>[];
    state = AsyncData([q.toLowerCase(), ...current.where((e) => e != q.toLowerCase())].take(10).toList());
    try {
      await ref.read(searchRepositoryProvider).saveHistory(q);
    } on ApiException {
      // keep the local copy
    }
  }

  /// Throws [ApiException] so the UI can say why.
  Future<void> clear() async {
    await ref.read(searchRepositoryProvider).clearHistory();
    if (ref.mounted) state = const AsyncData(<String>[]);
  }
}

/// Debounced in the screen; keyed by the trimmed query so repeats are cached.
final searchSuggestionsProvider = FutureProvider.autoDispose.family<SearchSuggestions, String>(
  (ref, q) => ref.watch(searchRepositoryProvider).suggestions(q),
);
