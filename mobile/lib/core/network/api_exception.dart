import 'package:dio/dio.dart';

/// The only error type the UI needs to handle.
///
/// Every failure coming out of [ApiClient] (HTTP errors, timeouts, offline,
/// bad JSON) is converted to this. Show [message] to the user and use
/// [fieldErrors] for inline form errors (`errorText: e.fieldError('email')`).
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
  });

  // client-side codes (server codes like TOKEN_EXPIRED pass through as-is)
  static const networkError = 'NETWORK_ERROR';
  static const timeout = 'TIMEOUT';
  static const cancelled = 'CANCELLED';
  static const unknown = 'UNKNOWN';
  static const authRequired = 'AUTH_REQUIRED';

  final String message;
  final int? statusCode;
  final String? code;

  /// field → message, from the API's `errors: [{ field, message }]`.
  final Map<String, String> fieldErrors;

  bool get isNetwork => code == networkError || code == timeout;
  bool get isCancelled => code == cancelled;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 400 || statusCode == 422;
  bool get hasFieldErrors => fieldErrors.isNotEmpty;

  String? fieldError(String field) => fieldErrors[field];

  /// Wraps anything thrown into an [ApiException] (use in catch blocks / UI).
  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) return ApiException.fromDio(error);
    return ApiException('Something went wrong. Please try again.', code: unknown);
  }

  factory ApiException.fromDio(DioException e) {
    if (e.error is ApiException) return e.error! as ApiException;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException('The server is taking too long to respond.', code: timeout);
      case DioExceptionType.connectionError:
        return const ApiException(
          "Can't reach the server. Check your connection or the server address in Settings.",
          code: networkError,
        );
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.', code: cancelled);
      case DioExceptionType.badCertificate:
        return const ApiException('Secure connection failed.', code: networkError);
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    final response = e.response;
    if (response == null) {
      // dio reports CORS / refused connections on web as `unknown` with no response
      return const ApiException(
        "Can't reach the server. Check your connection or the server address in Settings.",
        code: networkError,
      );
    }
    return ApiException.fromResponse(response.statusCode, response.data);
  }

  /// Builds an exception from an error envelope
  /// `{ success: false, message, code?, errors?: [{ field, message }] }`.
  factory ApiException.fromResponse(int? statusCode, Object? body) {
    String? message;
    String? code;
    final fields = <String, String>{};

    if (body is Map) {
      message = body['message']?.toString();
      code = body['code']?.toString();
      final errors = body['errors'];
      if (errors is List) {
        for (final item in errors) {
          if (item is Map && item['field'] != null) {
            // keep the first message per field
            fields.putIfAbsent(item['field'].toString(), () => item['message']?.toString() ?? 'Invalid value');
          }
        }
      }
    }

    return ApiException(
      (message == null || message.isEmpty) ? _defaultMessage(statusCode) : message,
      statusCode: statusCode,
      code: code,
      fieldErrors: fields,
    );
  }

  static String _defaultMessage(int? status) => switch (status) {
    400 => 'Please check the highlighted fields.',
    401 => 'Please sign in to continue.',
    403 => "You don't have access to this.",
    404 => "We couldn't find that.",
    409 => 'That already exists.',
    429 => 'Too many attempts. Please wait a moment.',
    final s? when s >= 500 => 'The server had a problem. Please try again.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => message;
}
