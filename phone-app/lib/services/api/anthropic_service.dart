import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// Anthropic Claude API 服务
/// 注意：Anthropic 目前没有公开的 usage/billing API
/// 此服务通过最小请求验证 Key 有效性，用户需手动输入额度信息
class AnthropicService extends BaseApiService {
  @override
  final String source = 'claude';

  @override
  final String defaultBaseUrl = 'https://api.anthropic.com';

  AnthropicService({required super.apiKey, super.baseUrl});

  Map<String, String> get _headers => {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      };

  /// 获取 token 使用情况
  /// 由于 Anthropic 无公开 usage API，通过最小请求验证后返回基础信息
  /// 用户可在配置中手动设置额度
  @override
  Future<TokenUsage> fetchUsage() async {
    try {
      final isValid = await _validateByKey();
      if (!isValid) {
        return _errorUsage('API Key 无效');
      }

      return TokenUsage(
        id: '${source}_main',
        source: source,
        name: 'Claude',
        status: 'active',
        tokensUsed: 0,
        tokensLimit: 0,
        tokensRemaining: 0,
        balanceAmount: null,
        balanceCurrency: null,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取 Claude 用量失败: $e');
    }
  }

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    try {
      return await _validateByKey();
    } catch (_) {
      return false;
    }
  }

  /// 通过发送最小请求验证 Key 有效性
  Future<bool> _validateByKey() async {
    try {
      // 使用最少 token 的请求来验证
      final response = await post(
        '/v1/messages',
        headers: _headers,
        body: '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}',
      );
      return response.statusCode == 200;
    } on ApiException catch (e) {
      // 401 说明 Key 无效
      if (e.statusCode == 401) return false;
      // 429 说明 Key 有效但超出速率限制
      if (e.statusCode == 429) return true;
      // 其他错误假设 Key 有效
      return true;
    }
  }

  /// 构建错误状态的用量对象
  TokenUsage _errorUsage(String message) {
    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: 'Claude',
      status: 'error',
      tokensUsed: 0,
      tokensLimit: 0,
      tokensRemaining: 0,
      updatedAt: DateTime.now(),
    );
  }
}
