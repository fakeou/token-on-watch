/// API 配置模型
/// 存储各 AI 平台的 API 连接配置信息
class ApiConfig {
  /// UUID 唯一标识
  final String id;

  /// 平台来源：openai / claude / deepseek / relay
  final String source;

  /// 用户自定义显示名称
  final String name;

  /// API Key（注意：实际存储时通过 flutter_secure_storage 加密）
  final String apiKey;

  /// 自定义 Base URL（中转站必填）
  final String? baseUrl;

  /// Session Cookie（中转站可选，用于获取用户余额）
  final String? sessionCookie;

  /// 是否启用该配置
  final bool enabled;

  /// 创建时间
  final DateTime createdAt;

  const ApiConfig({
    required this.id,
    required this.source,
    required this.name,
    required this.apiKey,
    this.baseUrl,
    this.sessionCookie,
    this.enabled = true,
    required this.createdAt,
  });

  /// 支持的平台列表
  static const List<String> supportedSources = [
    'deepseek',
    'kimi',
    'mimo',
    'newapi',
    'sub2api',
    'openai',
    'claude',
  ];

  /// 平台显示名称映射
  static const Map<String, String> sourceNames = {
    'deepseek': 'DeepSeek',
    'kimi': 'Kimi (月之暗面)',
    'mimo': '小米 Mimo',
    'newapi': 'NewAPI 中转站',
    'sub2api': 'Sub2API 中转站',
    'relay': '中转站',
    'openai': 'OpenAI',
    'claude': 'Claude (Anthropic)',
  };

  /// 平台图标映射
  static const Map<String, String> sourceIcons = {
    'deepseek': '🔮',
    'kimi': '🌙',
    'mimo': '📱',
    'newapi': '🆕',
    'sub2api': '🔄',
    'relay': '🔄',
    'openai': '🤖',
    'claude': '🧠',
  };

  /// 获取平台显示名称
  String get sourceDisplayName => sourceNames[source] ?? source;

  /// 获取平台图标
  String get sourceIcon => sourceIcons[source] ?? '❓';

  /// 是否为中转站类型（需要 baseUrl）
  bool get isRelay => source == 'relay';

  /// 是否需要自定义 Base URL
  bool get needsBaseUrl => source == 'relay' || source == 'mimo' || source == 'newapi' || source == 'sub2api';

  /// 是否支持自定义 Base URL（可选）
  bool get supportsBaseUrl => source == 'relay' || source == 'mimo' || source == 'openai' || source == 'claude';

  /// 从 JSON 创建
  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      id: json['id'] as String,
      source: json['source'] as String,
      name: json['name'] as String,
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String?,
      sessionCookie: json['sessionCookie'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 转换为 JSON（注意：apiKey 不应序列化到普通存储中）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'name': name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'sessionCookie': sessionCookie,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 序列化（不含 apiKey，用于普通存储）
  Map<String, dynamic> toJsonSafe() {
    return {
      'id': id,
      'source': source,
      'name': name,
      'baseUrl': baseUrl,
      'sessionCookie': sessionCookie,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  ApiConfig copyWith({
    String? id,
    String? source,
    String? name,
    String? apiKey,
    String? baseUrl,
    String? sessionCookie,
    bool? enabled,
    DateTime? createdAt,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      source: source ?? this.source,
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      sessionCookie: sessionCookie ?? this.sessionCookie,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'ApiConfig(id: $id, source: $source, name: $name, enabled: $enabled)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ApiConfig && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
