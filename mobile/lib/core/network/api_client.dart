import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_exception.dart';

export 'api_exception.dart';

typedef Json = Map<String, dynamic>;

/// Converts the envelope's `data` into a model, e.g. `(d) => User.fromJson(d)`.
typedef Decoder<T> = T Function(dynamic data);

/// Raw success envelope `{ success, data, meta?, message? }`.
class ApiEnvelope {
  const ApiEnvelope({this.data, this.meta = const {}, this.message});

  final dynamic data;
  final Json meta;
  final String? message;
}

/// One page of a list endpoint. [meta] keeps endpoint extras
/// (`facets` on /products, `summary` on reviews).
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    this.meta = const {},
  });

  const Paginated.empty()
    : items = const [],
      page = 1,
      limit = 20,
      total = 0,
      totalPages = 1,
      meta = const {};

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final Json meta;

  bool get hasMore => page < totalPages;
  bool get isEmpty => items.isEmpty;

  /// Appends the next page (infinite scroll).
  Paginated<T> append(Paginated<T> next) => Paginated(
    items: [...items, ...next.items],
    page: next.page,
    limit: next.limit,
    total: next.total,
    totalPages: next.totalPages,
    meta: next.meta,
  );
}

/// Thin typed wrapper over Dio for the Zelora API.
///
/// Every method unwraps the envelope and returns `data` (decoded by
/// [decode] when given) or throws [ApiException]. Never catch DioException
/// in features — catch [ApiException].
class ApiClient {
  ApiClient(this.dio);

  final Dio dio;

  Future<T> get<T>(String path, {Json? query, Decoder<T>? decode, CancelToken? cancelToken}) =>
      _call('GET', path, query: query, decode: decode, cancelToken: cancelToken);

  Future<T> post<T>(String path, {Object? body, Json? query, Decoder<T>? decode, CancelToken? cancelToken}) =>
      _call('POST', path, body: body, query: query, decode: decode, cancelToken: cancelToken);

  Future<T> put<T>(String path, {Object? body, Json? query, Decoder<T>? decode, CancelToken? cancelToken}) =>
      _call('PUT', path, body: body, query: query, decode: decode, cancelToken: cancelToken);

  Future<T> patch<T>(String path, {Object? body, Json? query, Decoder<T>? decode, CancelToken? cancelToken}) =>
      _call('PATCH', path, body: body, query: query, decode: decode, cancelToken: cancelToken);

  Future<T> delete<T>(String path, {Object? body, Json? query, Decoder<T>? decode, CancelToken? cancelToken}) =>
      _call('DELETE', path, body: body, query: query, decode: decode, cancelToken: cancelToken);

  /// GET a paginated list: `getPage('/products', query: {...}, item: ProductSummary.fromJson)`.
  Future<Paginated<T>> getPage<T>(
    String path, {
    required T Function(Json json) item,
    Json? query,
    CancelToken? cancelToken,
  }) async {
    final envelope = await send('GET', path, query: query, cancelToken: cancelToken);
    return _guardParse(() {
      final items = decodeList(envelope.data, item);
      final meta = envelope.meta;
      int readInt(String key, int fallback) => (meta[key] as num?)?.toInt() ?? fallback;
      return Paginated<T>(
        items: items,
        page: readInt('page', 1),
        limit: readInt('limit', items.length),
        total: readInt('total', items.length),
        totalPages: readInt('totalPages', 1),
        meta: meta,
      );
    });
  }

  /// Low-level request returning the whole envelope (when you need `message`/`meta`).
  Future<ApiEnvelope> send(
    String method,
    String path, {
    Object? body,
    Json? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: cleanQuery(query),
        cancelToken: cancelToken,
        options: Options(method: method),
      );
      final data = response.data;
      if (data is! Map) {
        throw ApiException('Unexpected response from the server.', statusCode: response.statusCode, code: ApiException.unknown);
      }
      if (data['success'] == false) throw ApiException.fromResponse(response.statusCode, data);
      final meta = data['meta'];
      return ApiEnvelope(
        data: data['data'],
        meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
        message: data['message']?.toString(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> _call<T>(
    String method,
    String path, {
    Object? body,
    Json? query,
    Decoder<T>? decode,
    CancelToken? cancelToken,
  }) async {
    final envelope = await send(method, path, body: body, query: query, cancelToken: cancelToken);
    if (decode == null) return envelope.data as T;
    return _guardParse(() => decode(envelope.data));
  }

  // a model/contract mismatch should surface as a friendly error, not a red screen
  T _guardParse<T>(T Function() parse) {
    try {
      return parse();
    } on ApiException {
      rethrow;
    } catch (e, st) {
      debugPrint('ApiClient: failed to parse response: $e\n$st');
      throw const ApiException('Unexpected data from the server.', code: 'PARSE_ERROR');
    }
  }

  /// Drops null/empty values and joins lists with commas (`brand=apple,samsung`).
  static Json? cleanQuery(Json? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is Iterable) {
        if (value.isEmpty) return;
        out[key] = value.join(',');
        return;
      }
      out[key] = value is bool ? value.toString() : value;
    });
    return out;
  }

  /// Pings `GET /health` on an arbitrary server (Settings → Test connection).
  /// Returns the round-trip time or throws [ApiException].
  static Future<Duration> checkHealth(String baseUrl) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.normalize(baseUrl)}${AppConfig.apiPrefix}',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    final watch = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('/health');
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        throw const ApiException('That address responded, but it is not the Zelora API.');
      }
      return watch.elapsed;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } finally {
      dio.close();
    }
  }
}

/// Decodes a JSON array with [item]; tolerates null.
List<T> decodeList<T>(dynamic data, T Function(Json json) item) {
  if (data is! List) return <T>[];
  return [for (final e in data) item(Map<String, dynamic>.from(e as Map))];
}

/// Attaches the bearer token and transparently refreshes it.
///
/// On `401 code: TOKEN_EXPIRED` the first failing request calls
/// `/auth/refresh`; concurrent failures await that same refresh
/// (single-flight), then every request is retried once with the new token.
/// If the refresh is rejected the session is expired → auth switches to guest.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.dio, required this.tokens});

  /// Put `extra: {AuthInterceptor.skipAuth: true}` on a request to send it anonymously.
  static const skipAuth = 'skipAuth';
  static const _retried = 'retried';

  final Dio dio;
  final TokenStore tokens;
  Future<bool>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (token != null && options.extra[skipAuth] != true) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final response = err.response;
    final sentToken = _sentToken(options);

    if (response?.statusCode != 401 || sentToken == null || options.extra[_retried] == true) {
      return handler.next(err);
    }

    final body = response?.data;
    final code = body is Map ? body['code'] : null;

    if (code == 'TOKEN_EXPIRED') {
      final refreshed = await _refreshOnce(sentToken);
      if (!refreshed) return handler.next(err);
      try {
        options.extra[_retried] = true;
        handler.resolve(await dio.fetch<dynamic>(options));
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }

    // token is malformed/revoked: nothing to refresh, end the session
    if (code == 'INVALID_TOKEN') await tokens.expire();
    handler.next(err);
  }

  String? _sentToken(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  Future<bool> _refreshOnce(String sentToken) {
    // another request already rotated the token while this one was in flight
    final current = tokens.accessToken;
    if (current != null && current != sentToken) return Future.value(true);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      await tokens.expire();
      return false;
    }
    // a bare client so the refresh call never re-enters this interceptor
    final client = Dio(
      BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: dio.options.connectTimeout,
        receiveTimeout: dio.options.receiveTimeout,
      ),
    );
    try {
      final response = await client.post<dynamic>('/auth/refresh', data: {'refreshToken': refreshToken});
      final data = (response.data as Map)['data'] as Map;
      await tokens.save(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      // only drop the session if the server rejected it; keep it when offline
      if (e.response != null) await tokens.expire();
      return false;
    } catch (_) {
      await tokens.expire();
      return false;
    } finally {
      client.close();
    }
  }
}

/// Compact one-line request log in debug builds: `GET /products → 200 (84 ms)`.
class _DebugLogInterceptor extends Interceptor {
  static const _startKey = 'startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions o, int? status, [String? error]) {
    final started = o.extra[_startKey];
    final ms = started is DateTime ? DateTime.now().difference(started).inMilliseconds : null;
    debugPrint('[api] ${o.method} ${o.path} → ${status ?? error} ${ms == null ? '' : '($ms ms)'}');
  }
}

/// Configured Dio. Rebuilt automatically when the server address changes.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStoreProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      // AI endpoints can take a few seconds when an LLM is involved
      receiveTimeout: const Duration(seconds: 45),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(AuthInterceptor(dio: dio, tokens: tokens));
  if (kDebugMode) dio.interceptors.add(_DebugLogInterceptor());

  ref.onDispose(dio.close);
  return dio;
});

/// The API client every repository should use.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));
