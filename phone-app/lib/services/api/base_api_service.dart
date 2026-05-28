import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/token_usage.dart';

/// API 服务抽象基类
/// 所有 AI 平台的 API 服务都继承此类
abstract class BaseApiService {
  /// API Key
  final String apiKey;

  /// 自定义 Base URL（中转站使用）
  final String? baseUrl;

  /// 请求超时时间
  static const Duration _timeout = Duration(seconds: 15);

  /// 最大重试次数
  static const int _maxRetries = 2;

  BaseApiService({required this.apiKey, this.baseUrl});

  /// 获取平台标识
  String get source;

  /// 获取默认 Base URL
  String get defaultBaseUrl;

  /// 获取实际使用的 Base URL
  String get effectiveBaseUrl =>
      (baseUrl != null && baseUrl!.isNotEmpty) ? baseUrl! : defaultBaseUrl;

  /// 获取 token 使用情况
  Future<TokenUsage> fetchUsage();

  /// 验证 API Key 是否有效
  Future<bool> validate();

  /// 通用 HTTP GET 请求，带错误处理和自动重试
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    return _request('GET', endpoint, headers: headers);
  }

  /// 通用 HTTP POST 请求
  Future<http.Response> post(
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _request('POST', endpoint, headers: headers, body: body);
  }

  /// 内部请求实现，带重试机制
  Future<http.Response> _request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    // 构建完整 URL
    final uri = Uri.parse('$effectiveBaseUrl$endpoint');

    // 合并默认 headers
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };

    Exception? lastException;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        late http.Response response;

        switch (method.toUpperCase()) {
          case 'GET':
            response = await http
                .get(uri, headers: requestHeaders)
                .timeout(_timeout);
            break;
          case 'POST':
            response = await http
                .post(uri, headers: requestHeaders, body: body)
                .timeout(_timeout);
            break;
          default:
            throw UnsupportedError('不支持的 HTTP 方法: $method');
        }

        // 成功返回
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // 4xx 客户端错误不重试
        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw ApiException(
            '请求失败 (${response.statusCode}): ${_extractErrorMessage(response)}',
            statusCode: response.statusCode,
          );
        }

        // 5xx 服务端错误，可重试
        lastException = ApiException(
          '服务端错误 (${response.statusCode})',
          statusCode: response.statusCode,
        );
      } on TimeoutException {
        lastException = ApiException('请求超时，请检查网络连接');
      } catch (e) {
        if (e is ApiException) rethrow;
        lastException = ApiException('网络请求失败: $e');
      }

      // 如果还有重试次数，等待后重试
      if (attempt < _maxRetries) {
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      }
    }

    throw lastException ?? ApiException('请求失败（未知错误）');
  }

  /// 从响应中提取错误信息
  String _extractErrorMessage(http.Response response) {
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        return body['error']?['message']?.toString() ??
            body['message']?.toString() ??
            response.body;
      }
    } catch (_) {
      // 解析失败直接返回原始 body
    }
    return response.body;
  }

  /// 解析 JSON 响应
  Map<String, dynamic> parseJson(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw ApiException('响应格式异常: 期望 JSON 对象');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('JSON 解析失败: $e');
    }
  }
}

/// API 异常类
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}
