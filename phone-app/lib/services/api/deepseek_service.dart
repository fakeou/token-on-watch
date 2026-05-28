import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// DeepSeek API 服务
/// 查询 DeepSeek 账户的余额信息
class DeepSeekService extends BaseApiService {
  @override
  final String source = 'deepseek';

  @override
  final String defaultBaseUrl = 'https://api.deepseek.com';

  DeepSeekService({required super.apiKey, super.baseUrl});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
      };

  /// 获取 token 使用情况
  /// DeepSeek 提供 /user/balance 接口返回余额信息
  @override
  Future<TokenUsage> fetchUsage() async {
    try {
      final response = await get(
        '/user/balance',
        headers: _headers,
      );
      final data = parseJson(response);

      final balanceInfos = data['balance_infos'] as List<dynamic>?;
      if (balanceInfos == null || balanceInfos.isEmpty) {
        return _emptyUsage();
      }

      // 取第一个余额信息
      final balanceInfo = balanceInfos[0] as Map<String, dynamic>;
      final currency = balanceInfo['currency'] as String? ?? 'CNY';
      final totalBalance =
          double.tryParse(balanceInfo['total_balance']?.toString() ?? '0') ??
              0.0;
      final grantedBalance =
          double.tryParse(balanceInfo['granted_balance']?.toString() ?? '0') ??
              0.0;
      final toppedUpBalance = double.tryParse(
              balanceInfo['topped_up_balance']?.toString() ?? '0') ??
          0.0;

      // 余额总额 = 赠送余额 + 充值余额
      final availableBalance = grantedBalance + toppedUpBalance;
      final usedBalance = totalBalance - availableBalance;

      // DeepSeek 使用货币余额，这里将元转换为"分"作为 token 类比
      final totalCents = (totalBalance * 100).round();
      final usedCents = (usedBalance * 100).round();
      final remainingCents = (availableBalance * 100).round();

      return TokenUsage(
        id: '${source}_main',
        source: source,
        name: 'DeepSeek',
        status: 'active',
        tokensUsed: usedCents.abs(),
        tokensLimit: totalCents,
        tokensRemaining: remainingCents,
        balanceAmount: availableBalance,
        balanceCurrency: currency,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取 DeepSeek 用量失败: $e');
    }
  }

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    try {
      final response = await get(
        '/user/balance',
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 构建空用量对象
  TokenUsage _emptyUsage() {
    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: 'DeepSeek',
      status: 'active',
      tokensUsed: 0,
      tokensLimit: 0,
      tokensRemaining: 0,
      updatedAt: DateTime.now(),
    );
  }
}
