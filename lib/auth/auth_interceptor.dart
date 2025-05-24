import 'dart:async';
import 'package:dio/dio.dart';
import '../api_config.dart';
import 'token_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._storage);

  final Dio _dio;                // <-- główny Dio z apki
  final TokenStorage _storage;

  /// Flaga + completer trzymające w kupie równoległe 401-ki
  bool _refreshing = false;
  Completer<void>? _refCompleter;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final access = await _storage.access;
    if (access != null) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // ► refresh tylko przy 401 (unauthorized)
    if (err.response?.statusCode == 401) {
      // 1️⃣  jeżeli ktoś JUŻ odświeża – czekamy
      if (_refreshing) {
        await _refCompleter?.future;
      } else {
        // 2️⃣  startujemy własny refresh
        _refreshing   = true;
        _refCompleter = Completer<void>();
        final ok      = await _refreshToken();
        _refreshing   = false;
        _refCompleter!.complete();         // obudź pozostałe requesty
        if (!ok) return handler.next(err); // refresh failed → logout w UI
      }

      // 3️⃣  powtórz ORYGINALNE żądanie z nowym access-tokenem
      final newAccess = await _storage.access;
      final clone = err.requestOptions..headers['Authorization'] = 'Bearer $newAccess';

      try {
        final res = await _dio.fetch(clone);
        return handler.resolve(res);      // sukces – zwróć powtórzoną odpowiedź
      } on DioException catch (e) {
        return handler.next(e);           // powtórka nie pykła → błąd dalej
      }
    }

    // inne błędy – przepuszczamy
    return handler.next(err);
  }

  /// Wywoływane RAZ przy pierwszym 401.
  Future<bool> _refreshToken() async {
    final refresh = await _storage.refresh;
    if (refresh == null) return false;

    // Używa OSOBNEGO, „nagiego” Dio żeby uniknąć rekurencji interceptorów
    final bare = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

    try {
      final res = await bare.post(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
        options: Options(contentType: Headers.jsonContentType),
      );

      await _storage.save(res.data['accessToken'], res.data['refreshToken']);
      return true;
    } on DioException {
      await _storage.clear();
      return false;
    }
  }
}
