import '../../models/token_usage.dart';
import 'base_api_service.dart';

/// NewAPI 中转站服务
/// 使用 session cookie + /api/user/self 获取用户账户余额
class NewApiService extends BaseApiService {
  @override
  final String source = 'newapi';

  @override
  final String defaultBaseUrl = ''; // 必须提供 baseUrl

  final String sessionCookie;

  NewApiService({
    required super.apiKey,
    required super.baseUrl,
    this.sessionCookie = '',
  });

  Map<String, String> get _headers => {
        'Cookie': sessionCookie,
        'Accept': 'application/json',
      };

  @override
  Future<TokenUsage> fetchUsage() async {
    if (sessionCookie.isEmpty) {
      throw ApiException('NewAPI 需要 Session Cookie');
    }

    final response = await get('/api/user/self', headers: _headers);
    final json = parseJson(response);

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw ApiException('NewAPI Cookie 无效或已过期');
    }

    final quota = (data['quota'] as num?)?.toDouble();
    final usedQuota = (data['used_quota'] as num?)?.toDouble();
    if (quota == null) {
      throw ApiException('NewAPI 响应缺少余额数据');
    }

    // ikuncode NewAPI: quota 单位 = 1/500000 元
    final remainingYuan = quota / 500000.0;
    final usedYuan = (usedQuota ?? 0) / 500000.0;

    final username = data['username'] as String? ??
        data['display_name'] as String?;

    return TokenUsage(
      id: '${source}_user',
      source: source,
      name: username ?? 'NewAPI',
      status: 'active',
      balanceAmount: remainingYuan,
      balanceCurrency: 'CNY',
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> validate() async {
    try {
      if (sessionCookie.isEmpty) return false;
      final resp = await get('/api/user/self', headers: _headers);
      if (resp.statusCode == 200) {
        final json = parseJson(resp);
        return json['data'] != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
