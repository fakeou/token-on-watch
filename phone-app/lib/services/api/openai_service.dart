import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// OpenAI / Codex API 服务
/// 查询 OpenAI 账户的 token 使用情况和余额
class OpenAIService extends BaseApiService {
  @override
  final String source = 'openai';

  @override
  final String defaultBaseUrl = 'https://api.openai.com';

  OpenAIService({required super.apiKey, super.baseUrl});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
      };

  /// 获取 token 使用情况
  /// 合并 billing/usage 和 billing/subscription 接口的数据
  @override
  Future<TokenUsage> fetchUsage() async {
    try {
      // 并行请求用量和订阅信息
      final results = await Future.wait([
        _fetchSubscription(),
        _fetchUsage(),
      ]);

      final subscription = results[0];
      final usage = results[1];

      final hardLimit = (subscription['hard_limit_usd'] as num?)?.toDouble() ??
          (subscription['system_hard_limit_usd'] as num?)?.toDouble() ??
          0.0;
      final totalUsed = (usage['total_usage'] as num?)?.toDouble() ?? 0.0;

      // OpenAI 的 usage 以分为单位
      final usedDollars = totalUsed / 100.0;
      final remainingDollars = (hardLimit - usedDollars).clamp(0.0, hardLimit);

      return TokenUsage(
        id: '${source}_main',
        source: source,
        name: 'OpenAI',
        status: 'active',
        tokensUsed: usedDollars.round(),
        tokensLimit: hardLimit.round(),
        tokensRemaining: remainingDollars.round(),
        balanceAmount: remainingDollars,
        balanceCurrency: 'USD',
        periodStart: _getBillingPeriodStart(),
        periodEnd: _getBillingPeriodEnd(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取 OpenAI 用量失败: $e');
    }
  }

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    try {
      final response = await get(
        '/v1/models',
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取订阅信息
  Future<Map<String, dynamic>> _fetchSubscription() async {
    try {
      final response = await get(
        '/dashboard/billing/subscription',
        headers: _headers,
      );
      return parseJson(response);
    } catch (e) {
      // 订阅接口可能不可用，返回默认值
      return {'hard_limit_usd': 0.0};
    }
  }

  /// 获取使用量信息
  Future<Map<String, dynamic>> _fetchUsage() async {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = now;

    final response = await get(
      '/dashboard/billing/usage'
          '?start_date=${_formatDate(startDate)}'
          '&end_date=${_formatDate(endDate)}',
      headers: _headers,
    );
    return parseJson(response);
  }

  /// 获取计费周期开始时间
  DateTime _getBillingPeriodStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  /// 获取计费周期结束时间
  DateTime _getBillingPeriodEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0);
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
