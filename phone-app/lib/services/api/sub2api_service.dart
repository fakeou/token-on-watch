import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// Sub2API 中转站服务
/// 使用 /v1/usage 端点查询余额和限额窗口
class Sub2ApiService extends BaseApiService {
  @override
  final String source = 'sub2api';

  @override
  final String defaultBaseUrl = ''; // 必须提供 baseUrl

  Sub2ApiService({required super.apiKey, super.baseUrl})
      : assert(baseUrl != null && baseUrl.isNotEmpty, 'Sub2API 必须提供 baseUrl');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      };

  @override
  Future<TokenUsage> fetchUsage() async {
    final response = await get('/v1/usage', headers: _headers);
    final json = parseJson(response);

    // API Key 无效时返回 { code: "INVALID_API_KEY", message: "..." }
    if (json['code'] != null) {
      throw ApiException('Sub2API 错误: ${json['message'] ?? json['code']}');
    }

    final remaining = (json['remaining'] as num?)?.toDouble();
    final isValid = json['isValid'] == true;
    final planName = json['planName'] as String?;

    final subscription = json['subscription'] as Map<String, dynamic>?;
    final usage = json['usage'] as Map<String, dynamic>?;

    if (subscription == null && remaining == null) {
      throw ApiException('Sub2API 响应格式异常');
    }

    // 各时段限额
    final dailyLimit = (subscription?['daily_limit_usd'] as num?)?.toDouble() ?? 0;
    final dailyUsed = (subscription?['daily_usage_usd'] as num?)?.toDouble() ?? 0;
    final weeklyLimit = (subscription?['weekly_limit_usd'] as num?)?.toDouble() ?? 0;
    final weeklyUsed = (subscription?['weekly_usage_usd'] as num?)?.toDouble() ?? 0;
    final monthlyLimit = (subscription?['monthly_limit_usd'] as num?)?.toDouble() ?? 0;
    final monthlyUsed = (subscription?['monthly_usage_usd'] as num?)?.toDouble() ?? 0;

    // 总已用金额
    final totalUsage = usage?['total'] as Map<String, dynamic>?;
    final totalActualCost = (totalUsage?['actual_cost'] as num?)?.toDouble() ?? 0;

    final remainingDollars = remaining ?? 0;
    final totalDollars = monthlyLimit > 0 ? monthlyLimit : remainingDollars + totalActualCost;
    final usedDollars = monthlyLimit > 0 ? monthlyUsed : totalActualCost;

    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: planName ?? 'Sub2API',
      status: isValid ? 'active' : 'error',
      tokensUsed: usedDollars.round(),
      tokensLimit: totalDollars.round(),
      tokensRemaining: remainingDollars.round(),
      balanceAmount: remainingDollars,
      balanceCurrency: 'USD',
      updatedAt: DateTime.now(),
      dailyLimit: dailyLimit > 0 ? dailyLimit : null,
      dailyUsed: dailyLimit > 0 ? dailyUsed : null,
      weeklyLimit: weeklyLimit > 0 ? weeklyLimit : null,
      weeklyUsed: weeklyLimit > 0 ? weeklyUsed : null,
      monthlyLimit: monthlyLimit > 0 ? monthlyLimit : null,
      monthlyUsed: monthlyLimit > 0 ? monthlyUsed : null,
    );
  }

  @override
  Future<bool> validate() async {
    try {
      final response = await get('/v1/usage', headers: _headers);
      if (response.statusCode == 200) {
        final json = parseJson(response);
        return json['code'] == null; // 没有 error code 就算有效
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
