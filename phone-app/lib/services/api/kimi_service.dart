import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// Kimi (月之暗面) API 服务
/// 查询 Kimi 账户的余额信息
/// API 文档: https://platform.moonshot.cn/docs
class KimiService extends BaseApiService {
  @override
  final String source = 'kimi';

  @override
  final String defaultBaseUrl = 'https://api.moonshot.cn';

  KimiService({required super.apiKey, super.baseUrl});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
      };

  /// 获取 token 使用情况
  /// Kimi 提供 /v1/users/me/balance 接口返回余额信息
  @override
  Future<TokenUsage> fetchUsage() async {
    try {
      final response = await get(
        '/v1/users/me/balance',
        headers: _headers,
      );
      final data = parseJson(response);

      // Kimi 返回格式:
      // { "data": { "available_balance": 100.0, "voucher_balance": 0.0, "cash_balance": 100.0 } }
      final balanceData = data['data'] as Map<String, dynamic>?;

      if (balanceData == null) {
        return _emptyUsage();
      }

      final availableBalance =
          (balanceData['available_balance'] as num?)?.toDouble() ?? 0.0;
      final voucherBalance =
          (balanceData['voucher_balance'] as num?)?.toDouble() ?? 0.0;
      final cashBalance =
          (balanceData['cash_balance'] as num?)?.toDouble() ?? 0.0;

      // 总余额 = 现金余额 + 券余额
      final totalBalance = cashBalance + voucherBalance;
      final usedBalance = totalBalance - availableBalance;

      // Kimi 使用货币余额（元），转换为"分"作为 token 类比
      final totalCents = (totalBalance * 100).round();
      final usedCents = (usedBalance * 100).round();
      final remainingCents = (availableBalance * 100).round();

      return TokenUsage(
        id: '${source}_main',
        source: source,
        name: 'Kimi',
        status: 'active',
        tokensUsed: usedCents.abs(),
        tokensLimit: totalCents,
        tokensRemaining: remainingCents,
        balanceAmount: availableBalance,
        balanceCurrency: 'CNY',
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取 Kimi 用量失败: $e');
    }
  }

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    try {
      final response = await get(
        '/v1/users/me/balance',
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      // 尝试 models 接口验证
      try {
        final response = await get('/v1/models', headers: _headers);
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// 构建空用量对象
  TokenUsage _emptyUsage() {
    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: 'Kimi',
      status: 'active',
      tokensUsed: 0,
      tokensLimit: 0,
      tokensRemaining: 0,
      updatedAt: DateTime.now(),
    );
  }
}
