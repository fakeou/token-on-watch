import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// 第三方中转站 API 服务
/// 支持 NewAPI 和 Sub2API 两种主流中转站的余额查询
/// 同时兼容 OpenAI 格式的 billing API
class RelayService extends BaseApiService {
  @override
  final String source = 'relay';

  @override
  final String defaultBaseUrl = ''; // 中转站必须提供 baseUrl

  RelayService({required super.apiKey, super.baseUrl})
      : assert(baseUrl != null && baseUrl.isNotEmpty, '中转站必须提供 baseUrl');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      };

  /// 获取 token 使用情况
  /// 按优先级尝试：NewAPI → Sub2API → OpenAI billing
  @override
  Future<TokenUsage> fetchUsage() async {
    final errors = <String>[];
    print('[Relay] fetchUsage 开始, baseUrl=$baseUrl');

    // ========== 1. 尝试 NewAPI ==========
    try {
      print('[Relay] 尝试 NewAPI: /api/user/self');
      final result = await _tryNewApi();
      if (result != null) {
        print('[Relay] NewAPI 成功: balance=${result.balanceAmount}');
        return result;
      }
      print('[Relay] NewAPI 返回 null（非 NewAPI 格式）');
    } catch (e) {
      print('[Relay] NewAPI 失败: $e');
      errors.add('NewAPI: $e');
    }

    // ========== 2. 尝试 Sub2API ==========
    try {
      print('[Relay] 尝试 Sub2API: /v1/usage');
      final result = await _trySub2Api();
      if (result != null) {
        print('[Relay] Sub2API 成功: balance=${result.balanceAmount}');
        return result;
      }
      print('[Relay] Sub2API 返回 null（非 Sub2API 格式）');
    } catch (e) {
      print('[Relay] Sub2API 失败: $e');
      errors.add('Sub2API: $e');
    }

    // ========== 3. 尝试 OpenAI 格式 billing API ==========
    try {
      print('[Relay] 尝试 OpenAI Billing');
      final result = await _tryOpenAiBilling();
      if (result != null) {
        print('[Relay] OpenAI Billing 成功');
        return result;
      }
      print('[Relay] OpenAI Billing 返回 null');
    } catch (e) {
      print('[Relay] OpenAI Billing 失败: $e');
      errors.add('OpenAI Billing: $e');
    }

    // 所有方式都失败，检查连接是否可达
    final isReachable = await _checkReachable();
    print('[Relay] 可达性检查: $isReachable');
    if (!isReachable) {
      throw ApiException('无法连接到中转站: ${baseUrl ?? "未设置"}');
    }

    // 连接可达但无可用的余额 API
    print('[Relay] 连接可达但无可用余额 API, 返回基础对象');
    return _basicUsage();
  }

  // ==================== NewAPI 适配 ====================

  /// NewAPI: GET /api/usage/token
  /// 这是 API Key 认证的正确端点（/api/user/self 需要 session cookie）
  /// 响应: { "code": true, "data": { "total_granted": 500000, "total_used": 123456, "total_available": 376544, "name": "..." } }
  /// 单位: 万分之一美元 (1 = $0.0001)
  Future<TokenUsage?> _tryNewApi() async {
    // /api/usage/token — API Key 认证端点
    final response = await get('/api/usage/token', headers: _headers);
    final json = parseJson(response);
    print('[Relay] NewAPI /api/usage/token 响应 keys: ${json.keys.toList()}');

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return null;

    print('[Relay] NewAPI /api/usage/token data: $data');

    final totalGranted = (data['total_granted'] as num?)?.toDouble();
    final totalUsed = (data['total_used'] as num?)?.toDouble();
    final totalAvailable = (data['total_available'] as num?)?.toDouble();

    if (totalGranted == null && totalAvailable == null) return null;
    print('[Relay] NewAPI 匹配成功: granted=$totalGranted, used=$totalUsed, available=$totalAvailable');

    // 转换为美元: NewAPI 的 1 单位 = $0.0001
    final availableDollars = (totalAvailable ?? 0) / 10000.0;

    final name = data['name'] as String?;

    return TokenUsage(
      id: '${source}_newapi',
      source: source,
      name: name ?? '中转站',
      status: 'active',
      balanceAmount: availableDollars,
      balanceCurrency: 'USD',
      updatedAt: DateTime.now(),
    );
  }

  // ==================== Sub2API 适配 ====================

  /// Sub2API: GET /v1/usage
  /// 响应字段: balance, quota.limit, quota.used, quota.remaining, remaining, mode, status
  /// 通过 API Key (sk-xxx) 认证，不是登录 token
  Future<TokenUsage?> _trySub2Api() async {
    final response = await get('/v1/usage', headers: _headers);
    final json = parseJson(response);

    print('[Relay] Sub2API 返回 keys: ${json.keys.toList()}');
    print('[Relay] Sub2API balance=${json['balance']}, mode=${json['mode']}, remaining=${json['remaining']}');
    print('[Relay] Sub2API quota=${json['quota']}');
    print('[Relay] Sub2API subscription=${json['subscription']}');
    print('[Relay] Sub2API usage=${json['usage']}');
    print('[Relay] Sub2API planName=${json['planName']}, unit=${json['unit']}');

    // Sub2API /v1/usage 返回的不是 {success: true} 格式
    // 如果 API Key 无效会返回 {code: "INVALID_API_KEY", message: "..."}
    if (json['code'] != null) return null;

    final remaining = (json['remaining'] as num?)?.toDouble();
    final status = json['isValid'] == true ? 'active' : 'error';
    final planName = json['planName'] as String?;

    // subscription 包含限额和已用信息
    final subscription = json['subscription'] as Map<String, dynamic>?;
    // usage 包含总计用量
    final usage = json['usage'] as Map<String, dynamic>?;

    if (subscription == null && remaining == null) return null;

    // 优先用月度限额作为总额度
    final monthlyLimit = (subscription?['monthly_limit_usd'] as num?)?.toDouble() ?? 0;
    final monthlyUsed = (subscription?['monthly_usage_usd'] as num?)?.toDouble() ?? 0;
    final weeklyLimit = (subscription?['weekly_limit_usd'] as num?)?.toDouble() ?? 0;
    final weeklyUsed = (subscription?['weekly_usage_usd'] as num?)?.toDouble() ?? 0;
    final dailyLimit = (subscription?['daily_limit_usd'] as num?)?.toDouble() ?? 0;
    final dailyUsed = (subscription?['daily_usage_usd'] as num?)?.toDouble() ?? 0;

    // 总已用金额（从 usage.total.actual_cost）
    final totalUsage = usage?['total'] as Map<String, dynamic>?;
    final totalActualCost = (totalUsage?['actual_cost'] as num?)?.toDouble() ?? 0;

    final remainingDollars = remaining ?? 0;

    // 用月度限额作为主要额度展示
    final totalDollars = monthlyLimit > 0 ? monthlyLimit : remainingDollars + totalActualCost;
    final usedDollars = monthlyLimit > 0 ? monthlyUsed : totalActualCost;

    // 附加限额信息到 name
    final limitInfo = <String>[];
    if (dailyLimit > 0) limitInfo.add('日\${dailyLimit.toStringAsFixed(0)}');
    if (weeklyLimit > 0) limitInfo.add('周\${weeklyLimit.toStringAsFixed(0)}');
    if (monthlyLimit > 0) limitInfo.add('月\${monthlyLimit.toStringAsFixed(0)}');

    return TokenUsage(
      id: '${source}_sub2api',
      source: source,
      name: planName ?? '中转站',
      status: status,
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

  // ==================== OpenAI Billing 适配 ====================

  /// OpenAI 格式 billing API（兼容大部分通用中转站）
  Future<TokenUsage?> _tryOpenAiBilling() async {
    final errors = <String>[];

    // 尝试多种 billing API 路径
    final usageEndpoints = [
      '/dashboard/billing/usage',
      '/v1/dashboard/billing/usage',
      '/api/dashboard/billing/usage',
    ];

    final subscriptionEndpoints = [
      '/dashboard/billing/subscription',
      '/v1/dashboard/billing/subscription',
      '/api/dashboard/billing/subscription',
    ];

    Map<String, dynamic>? usageData;
    for (final endpoint in usageEndpoints) {
      try {
        final response = await get(endpoint, headers: _headers);
        usageData = parseJson(response);
        break;
      } catch (e) {
        errors.add('$endpoint: $e');
      }
    }

    Map<String, dynamic>? subscriptionData;
    for (final endpoint in subscriptionEndpoints) {
      try {
        final response = await get(endpoint, headers: _headers);
        subscriptionData = parseJson(response);
        break;
      } catch (e) {
        errors.add('$endpoint: $e');
      }
    }

    if (usageData == null && subscriptionData == null) return null;

    print('[Relay] OpenAI Billing subscriptionData=$subscriptionData');
    print('[Relay] OpenAI Billing usageData=$usageData');

    final rawHardLimit =
        (subscriptionData?['hard_limit_usd'] as num?)?.toDouble() ?? 0.0;
    final totalUsage =
        (usageData?['total_usage'] as num?)?.toDouble() ?? 0.0;

    // NewAPI 变体的 hard_limit_usd 实际是万分之一美元单位（100000000 = $10000）
    // 正常 OpenAI 的 hard_limit_usd 是实际美元（如 120.0）
    // 判断：超过 10000 认为是 NewAPI quota 单位，需要除以 10000
    final hardLimit =
        rawHardLimit > 10000 ? rawHardLimit / 10000.0 : rawHardLimit;

    // total_usage 通常以 cents 为单位（除以 100 得美元）
    final usedDollars = totalUsage / 100.0;
    final remainingDollars = hardLimit > 0
        ? (hardLimit - usedDollars).clamp(0.0, hardLimit)
        : 0.0;

    return TokenUsage(
      id: '${source}_openai_compat',
      source: source,
      name: '中转站',
      status: 'active',
      tokensUsed: usedDollars.round(),
      tokensLimit: hardLimit.round(),
      tokensRemaining: remainingDollars.round(),
      balanceAmount: remainingDollars > 0 ? remainingDollars : null,
      balanceCurrency: hardLimit > 0 ? 'USD' : null,
      updatedAt: DateTime.now(),
    );
  }

  // ==================== 工具方法 ====================

  /// 验证 API Key 是否有效
  @override
  Future<bool> validate() async {
    print('[Relay] validate 开始, baseUrl=$baseUrl');
    try {
      // 尝试 NewAPI 验证（API Key 端点 /api/usage/token）
      print('[Relay] validate: 尝试 NewAPI /api/usage/token');
      final newApiResp = await get('/api/usage/token', headers: _headers);
      print('[Relay] validate: NewAPI status=${newApiResp.statusCode}');
      if (newApiResp.statusCode == 200) {
        final json = parseJson(newApiResp);
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null && (data['total_granted'] != null || data['total_available'] != null)) {
          print('[Relay] validate: NewAPI 成功');
          return true;
        }
      }
    } catch (e) {
      print('[Relay] validate: NewAPI 失败: $e');
    }

    try {
      // 尝试 Sub2API 验证 (GET /v1/usage)
      print('[Relay] validate: 尝试 Sub2API /v1/usage');
      final sub2Resp = await get('/v1/usage', headers: _headers);
      print('[Relay] validate: Sub2API status=${sub2Resp.statusCode}');
      if (sub2Resp.statusCode == 200) {
        final json = parseJson(sub2Resp);
        if (json['code'] == null) {
          print('[Relay] validate: Sub2API 成功');
          return true;
        }
      }
    } catch (e) {
      print('[Relay] validate: Sub2API 失败: $e');
    }

    try {
      // 尝试 models 接口验证
      print('[Relay] validate: 尝试 /v1/models');
      final response = await get('/v1/models', headers: _headers);
      print('[Relay] validate: models status=${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('[Relay] validate: models 失败: $e');
      try {
        return await _checkReachable();
      } catch (_) {
        return false;
      }
    }
  }

  /// 检测中转站是否可达
  Future<bool> _checkReachable() async {
    try {
      final response = await get('/', headers: _headers);
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// 构建基础用量对象（当所有 API 都不可用时）
  TokenUsage _basicUsage() {
    return TokenUsage(
      id: '${source}_main',
      source: source,
      name: '中转站',
      status: 'active',
      tokensUsed: 0,
      tokensLimit: 0,
      tokensRemaining: 0,
      updatedAt: DateTime.now(),
    );
  }
}
