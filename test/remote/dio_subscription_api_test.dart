import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/config/api_config.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/core/network/api_client.dart';
import 'package:offline_first_app_flutter_demo/core/network/api_exception.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/dio_subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_dto.dart';

/// Replaces dio's real network layer: records each request and answers with
/// whatever the test's [handler] returns. No server needed.
class _FakeHttp implements HttpClientAdapter {
  _FakeHttp(this.handler);

  final ResponseBody Function(RequestOptions request) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _serverSubscription({String name = 'Netflix'}) => {
  '_id': 'abc',
  'name': name,
  'price': 9.99,
  'billingCycle': 'monthly',
  'nextPaymentDate': '2026-10-07T00:00:00.000Z',
  'category': 'Entertainment',
  'updatedAt': '2026-10-05T09:30:00.000Z',
  'deletedAt': null,
};

void main() {
  late _FakeHttp http;
  late DioSubscriptionApi api;

  /// Builds the API exactly like main.dart does, but with the fake network.
  void setUpApi(ResponseBody Function(RequestOptions) handler) {
    http = _FakeHttp(handler);
    final dio = createApiClient(
      const ApiConfig(baseUrl: 'http://test.local', apiKey: 'secret'),
    )..httpClientAdapter = http;
    api = DioSubscriptionApi(dio);
  }

  final dto = SubscriptionDto(
    id: 'abc',
    name: 'Netflix',
    price: 9.99,
    billingCycle: BillingCycles.monthly,
    nextPaymentDate: DateTime(2026, 10, 7),
    category: 'Entertainment',
    updatedAt: DateTime.utc(2026, 10, 5, 9, 30),
  );

  test('every request sends the API key', () async {
    setUpApi(
      (_) => _json({
        'subscriptions': [],
        'serverTime': '2026-10-05T10:00:00.000Z',
      }),
    );

    await api.pull();

    expect(http.requests.single.headers['x-api-key'], 'secret');
  });

  group('put', () {
    test('PUTs the DTO to /api/subscriptions/:id and reads applied', () async {
      setUpApi(
        (_) => _json({
          'applied': true,
          'subscription': _serverSubscription(),
        }, 201),
      );

      final result = await api.put(dto);

      final request = http.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/api/subscriptions/abc');
      expect(request.data, dto.toJson());
      expect(result.applied, isTrue);
      expect(result.subscription.id, 'abc');
    });

    test('returns the server version when not applied', () async {
      setUpApi(
        (_) => _json({
          'applied': false,
          'subscription': _serverSubscription(name: 'Server name'),
        }),
      );

      final result = await api.put(dto);

      expect(result.applied, isFalse);
      expect(result.subscription.name, 'Server name');
    });
  });

  group('delete', () {
    test('DELETEs with the change time in the body', () async {
      setUpApi((_) => _json({'message': 'Subscription deleted successfully.'}));

      await api.delete('abc', updatedAt: DateTime.utc(2026, 10, 5, 9, 45));

      final request = http.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/api/subscriptions/abc');
      expect(request.data, {'updatedAt': '2026-10-05T09:45:00.000Z'});
    });

    test('404 counts as success (the server never had it)', () async {
      setUpApi((_) => _json({'message': 'Subscription not found.'}, 404));

      await expectLater(
        api.delete('abc', updatedAt: DateTime.now()),
        completes,
      );
    });
  });

  group('pull', () {
    test('first sync sends no cursor', () async {
      setUpApi(
        (_) => _json({
          'subscriptions': [],
          'serverTime': '2026-10-05T10:00:00.000Z',
        }),
      );

      await api.pull();

      expect(http.requests.single.queryParameters, isEmpty);
    });

    test('later syncs send updatedSince and parse the response', () async {
      setUpApi(
        (_) => _json({
          'subscriptions': [_serverSubscription()],
          'serverTime': '2026-10-05T10:00:00.000Z',
        }),
      );

      final result = await api.pull(updatedSince: DateTime.utc(2026, 10, 5, 9));

      expect(
        http.requests.single.queryParameters['updatedSince'],
        '2026-10-05T09:00:00.000Z',
      );
      expect(result.subscriptions.single.name, 'Netflix');
      expect(result.serverTime, DateTime.utc(2026, 10, 5, 10));
    });
  });

  group('errors become ApiException', () {
    test('no response (offline / server down) → isNetworkError', () async {
      setUpApi((_) => throw const SocketException('Connection refused'));

      await expectLater(
        api.pull(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isNetworkError,
            'isNetworkError',
            isTrue,
          ),
        ),
      );
    });

    test('server error → status code and the server\'s message', () async {
      setUpApi((_) => _json({'message': 'The API key is invalid.'}, 401));

      await expectLater(
        api.pull(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isFalse)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'The API key is invalid.'),
        ),
      );
    });
  });
}
