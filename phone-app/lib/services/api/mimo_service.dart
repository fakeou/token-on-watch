import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// 小米 Mimo API 服务
/// 查询小米 Mimo 账户的余额信息
/// Mimo 使用 OpenAI 兼容接口
class MimoService extends BaseApiService {
  @override
  final String source = 'mimo';

  @override
  final String defaultBaseUrl = 'https://api.mimo.xiaomi.com';

  MimoService({required super.apiKey, super.baseUrl});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
      };

  /// 获取 token 使用情况
  /// Mimo 提供 /v1/users/balance 接口返回余额信息
  @override
  Future<TokenUsage> fetchUsage() async {
    try {
      // 尝试获取余额信息
      final balanceData = await _fetchBalance();
      if (balanceData != null) {
        return balanceData;
      }

      // 如果余额接口不可用，尝试获取用量信息
      final usageData = await _fetchUsage();
      if (usageData != null) {
        return usageData;
      }

      // 都不可用，返回基础信息
      return _basicUsage();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取 Mimo 用量失败: $e');
    }
  }

  /// 尝试获取余额信息
  Future<TokenUsage?> _fetchBalance() async {
    // 尝试多种余额接口路径
    final endpoints = [
      '/v1/users/balance',
      '/v1/users/me/balance',
      '/api/user/balance',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await get(endpoint, headers: _headers);
        final data = parseJson(response);

        // 尝试解析不同格式的余额数据
        final balance = _parseBalanceResponse(data);
        if (balance != null) return balance;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 尝试获取用量信息
  Future<TokenUsage?> _fetchUsage() async {
    // 尝试多种用量接口路径
    final endpoints = [
      '/v1/dashboard/billing/usage',
      '/api/dashboard/billing/usage',
    ];

    final subscriptionEndpoints = [
      '/v1/dashboard/billing/subscription',
      '/api/dashboard/billing/subscription',
    ];

    Map<String, dynamic>? usageData;
    Map<String, dynamic>? subscriptionData;

    for (final endpoint in endpoints) {
      try {
        final response = await get(endpoint, headers: _headers);
        usageData = parseJson(response);
        break;
      } catch (_) {
        continue;
      }
    }

    for (final endpoint in subscriptionEndpoints) {
      try {
        final response = await get(endpoint, headers: _headers);
        subscriptionData = parseJson(response);
        break;
      } catch (_) {
        continue;
      }
    }

    if (usageData == null && subscriptionData == null) return null;

    final hardLimit =
        (subscriptionData?['hard_limit_usd'] as num?)?.toDouble() ?? 0.0;
    final totalUsage =
        (usageData?['total_usage'] as num?)?.toDouble() ?? 0.0;

    final usedDollars = totalUsage / 100.0;
    final remainingDollars = hardLimit > 0
        ? (hardLimit - usedDollars).clamp(0.0, hardLimit)
        : 0.0;

    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: 'Mimo',
      status: 'active',
      tokensUsed: usedDollars.round(),
      tokensLimit: hardLimit.round(),
      tokensRemaining: remainingDollars.round(),
      balanceAmount: remainingDollars > 0 ? remainingDollars : null,
      balanceCurrency: hardLimit > 0 ? 'CNY' : null,
      updatedAt: DateTime.now(),
    );
  }

  /// 解析余额响应
  TokenUsage? _parseBalanceResponse(Map<String, dynamic> data) {
    // 格式1: { "data": { "available_balance": 100.0 } }
    if (data.containsKey('data') && data['data'] is Map) {
      final balanceData = data['data'] as Map<String, dynamic>;
      final available = (balanceData['available_balance'] as num?)?.toDouble() ??
          (balanceData['balance'] as num?)?.toDouble() ??
          0.0;
      final total = (balanceData['total_balance'] as num?)?.toDouble() ??
          (balanceData['total'] as num?)?.toDouble() ??
          available;

      if (available > 0 || total > 0) {
        final used = total - available;
        return TokenUsage(
          id: '${source}_main',
          source: source,
          name: 'Mimo',
          status: 'active',
          tokensUsed: (used * 100).round().abs(),
          tokensLimit: (total * 100).round(),
          tokensRemaining: (available * 100).round(),
          balanceAmount: available,
          balanceCurrency: 'CNY',
          updatedAt: DateTime.now(),
        );
      }
    }

    // 格式2: { "balance": 100.0, "total": 200.0 }
    if (data.containsKey('balance')) {
      final available = (data['balance'] as num?)?.toDouble() ?? 0.0;
      final total = (data['total'] as num?)?.toDouble() ?? available;

      if (available > 0 || total > 0) {
        final used = total - available;
        return TokenUsage(
          id: '${source}_main',
          source: source,
          name: 'Mimo',
          status: 'active',
          tokensUsed: (used * 100).round().abs(),
          tokensLimit: (total * 100).round(),
          tokensRemaining: (available * 100).round(),
          balanceAmount: available,
          balanceCurrency: 'CNY',
          updatedAt: DateTime.now(),
        );
      }
    }

    return null;
  }

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    try {
      // 尝试余额接口
      final response = await get('/v1/users/balance', headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      try {
        // 尝试 models 接口
        final response = await get('/v1/models', headers: _headers);
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// 构建基础用量对象
  TokenUsage _basicUsage() {
    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: 'Mimo',
      status: 'active',
      tokensUsed: 0,
      tokensLimit: 0,
      tokensRemaining: 0,
      updatedAt: DateTime.now(),
    );
  }
}
