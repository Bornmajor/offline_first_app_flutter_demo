import 'package:dio/dio.dart';
import 'package:offline_first_app_flutter_demo/core/network/api_exception.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_dto.dart';

/// [SubscriptionApi] over HTTP with dio, talking to the Express server.
///
/// Its only jobs: build requests, parse responses, and turn dio errors into
/// [ApiException]. No sync decisions are made here.
class DioSubscriptionApi implements SubscriptionApi {
  DioSubscriptionApi(this._dio);

  /// Pre-configured with base URL, API key header and timeouts
  /// (see core/network/api_client.dart).
  final Dio _dio;

  static const _path = '/api/subscriptions';

  @override
  Future<PushResult> put(SubscriptionDto subscription) {
    return _call(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '$_path/${Uri.encodeComponent(subscription.id)}',
        data: subscription.toJson(),
      );
      final body = response.data!;
      return PushResult(
        applied: body['applied'] as bool,
        subscription: SubscriptionDto.fromJson(
          body['subscription'] as Map<String, dynamic>,
        ),
      );
    });
  }

  @override
  Future<void> delete(String id, {required DateTime updatedAt}) {
    return _call(() async {
      try {
        await _dio.delete<void>(
          '$_path/${Uri.encodeComponent(id)}',
          // When the user deleted it, so the server records the right time.
          data: {'updatedAt': updatedAt.toUtc().toIso8601String()},
        );
      } on DioException catch (error) {
        // 404 = the server never had it (e.g. created and deleted while
        // offline, never pushed). Nothing left to delete → success.
        if (error.response?.statusCode == 404) return;
        rethrow;
      }
    });
  }

  @override
  Future<PullResult> pull({DateTime? updatedSince}) {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {
          if (updatedSince != null)
            'updatedSince': updatedSince.toUtc().toIso8601String(),
        },
      );
      final body = response.data!;
      return PullResult(
        subscriptions: (body['subscriptions'] as List)
            .map(
              (json) => SubscriptionDto.fromJson(json as Map<String, dynamic>),
            )
            .toList(),
        serverTime: DateTime.parse(body['serverTime'] as String),
      );
    });
  }

  /// Runs a request and converts dio errors into [ApiException], so callers
  /// only ever catch one error type.
  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
