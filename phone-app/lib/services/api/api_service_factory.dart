import '../../models/api_config.dart';
import 'base_api_service.dart';
import 'openai_service.dart';
import 'anthropic_service.dart';
import 'deepseek_service.dart';
import 'kimi_service.dart';
import 'mimo_service.dart';
import 'newapi_service.dart';
import 'sub2api_service.dart';
import 'relay_service.dart';

/// API 服务工厂
/// 根据平台类型创建对应的 API 服务实例
class ApiServiceFactory {
  /// 根据配置创建 API 服务实例
  static BaseApiService create(ApiConfig config) {
    switch (config.source) {
      case 'deepseek':
        return DeepSeekService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'kimi':
        return KimiService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'mimo':
        return MimoService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'newapi':
        return NewApiService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl ?? '',
          sessionCookie: config.sessionCookie ?? '',
        );
      case 'sub2api':
        return Sub2ApiService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'relay':
        return RelayService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'openai':
        return OpenAIService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      case 'claude':
        return AnthropicService(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        );
      default:
        throw ArgumentError('不支持的平台类型: ${config.source}');
    }
  }

  /// 获取所有支持的平台类型
  static List<String> get supportedSources => ApiConfig.supportedSources;

  /// 获取平台显示名称
  static String getSourceName(String source) {
    return ApiConfig.sourceNames[source] ?? source;
  }

  /// 获取平台图标
  static String getSourceIcon(String source) {
    return ApiConfig.sourceIcons[source] ?? '❓';
  }
}
