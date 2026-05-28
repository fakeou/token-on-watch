/// Token 用量模型
/// 通用模型，适配所有 AI 平台的 token 使用情况
class TokenUsage {
  /// 唯一标识，格式如 "openai_main"
  final String id;

  /// 平台标识，如 "openai" / "claude" / "deepseek" / "relay"
  final String source;

  /// 显示名称，如 "OpenAI GPT-4"
  final String name;

  /// 状态：active / expired / error
  final String status;

  /// 已使用 token 数
  final int tokensUsed;

  /// token 总额度
  final int tokensLimit;

  /// 剩余 token 数
  final int tokensRemaining;

  /// 余额金额（部分平台使用货币余额而非 token）
  final double? balanceAmount;

  /// 余额货币单位，如 "USD" / "CNY"
  final String? balanceCurrency;

  /// 计费周期开始时间
  final DateTime? periodStart;

  /// 计费周期结束时间
  final DateTime? periodEnd;

  /// 最后更新时间
  final DateTime updatedAt;

  // ========= 限额窗口（Sub2API 专用，其他平台为 null）=========

  /// 每日限额（USD）
  final double? dailyLimit;
  /// 每日已用（USD）
  final double? dailyUsed;
  /// 每周限额（USD）
  final double? weeklyLimit;
  /// 每周已用（USD）
  final double? weeklyUsed;
  /// 每月限额（USD）
  final double? monthlyLimit;
  /// 每月已用（USD）
  final double? monthlyUsed;

  /// 是否有限额窗口数据
  bool get hasQuotaWindows => dailyLimit != null || weeklyLimit != null || monthlyLimit != null;

  const TokenUsage({
    required this.id,
    required this.source,
    required this.name,
    required this.status,
    this.tokensUsed = 0,
    this.tokensLimit = 0,
    this.tokensRemaining = 0,
    this.balanceAmount,
    this.balanceCurrency,
    this.periodStart,
    this.periodEnd,
    required this.updatedAt,
    this.dailyLimit,
    this.dailyUsed,
    this.weeklyLimit,
    this.weeklyUsed,
    this.monthlyLimit,
    this.monthlyUsed,
  });

  /// 使用百分比（0.0 - 1.0）
  double get usagePercent {
    if (tokensLimit <= 0) return 0.0;
    return (tokensUsed / tokensLimit).clamp(0.0, 1.0);
  }

  /// 剩余百分比（0.0 - 1.0）
  double get remainingPercent {
    if (tokensLimit <= 0) return 0.0;
    return (tokensRemaining / tokensLimit).clamp(0.0, 1.0);
  }

  /// 是否为活跃状态
  bool get isActive => status == 'active';

  /// 是否已过期
  bool get isExpired => status == 'expired';

  /// 是否出错
  bool get isError => status == 'error';

  /// 是否有货币余额信息
  bool get hasBalance => balanceAmount != null && balanceCurrency != null;

  /// 格式化的使用百分比文本
  String get usagePercentText {
    if (tokensLimit <= 0) return 'N/A';
    return '${(usagePercent * 100).toStringAsFixed(1)}%';
  }

  /// 格式化的 token 数量（带千分位）
  String get tokensUsedFormatted => _formatNumber(tokensUsed);
  String get tokensLimitFormatted => _formatNumber(tokensLimit);
  String get tokensRemainingFormatted => _formatNumber(tokensRemaining);

  /// 格式化余额
  String get balanceText {
    if (!hasBalance) return 'N/A';
    return '${balanceCurrency ?? ''} ${balanceAmount!.toStringAsFixed(2)}';
  }

  /// 格式化日期范围
  String get periodText {
    if (periodStart == null || periodEnd == null) return '';
    final start = '${periodStart!.month}/${periodStart!.day}';
    final end = '${periodEnd!.month}/${periodEnd!.day}';
    return '$start - $end';
  }

  /// 数字千分位格式化
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  /// 从 JSON 创建
  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      id: json['id'] as String,
      source: json['source'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      tokensUsed: (json['tokensUsed'] as num?)?.toInt() ?? 0,
      tokensLimit: (json['tokensLimit'] as num?)?.toInt() ?? 0,
      tokensRemaining: (json['tokensRemaining'] as num?)?.toInt() ?? 0,
      balanceAmount: (json['balanceAmount'] as num?)?.toDouble(),
      balanceCurrency: json['balanceCurrency'] as String?,
      periodStart: json['periodStart'] != null
          ? DateTime.tryParse(json['periodStart'] as String)
          : null,
      periodEnd: json['periodEnd'] != null
          ? DateTime.tryParse(json['periodEnd'] as String)
          : null,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      dailyLimit: (json['dailyLimit'] as num?)?.toDouble(),
      dailyUsed: (json['dailyUsed'] as num?)?.toDouble(),
      weeklyLimit: (json['weeklyLimit'] as num?)?.toDouble(),
      weeklyUsed: (json['weeklyUsed'] as num?)?.toDouble(),
      monthlyLimit: (json['monthlyLimit'] as num?)?.toDouble(),
      monthlyUsed: (json['monthlyUsed'] as num?)?.toDouble(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source,
      'name': name,
      'status': status,
      'tokensUsed': tokensUsed,
      'tokensLimit': tokensLimit,
      'tokensRemaining': tokensRemaining,
      'balanceAmount': balanceAmount,
      'balanceCurrency': balanceCurrency,
      'periodStart': periodStart?.toIso8601String(),
      'periodEnd': periodEnd?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'dailyLimit': dailyLimit,
      'dailyUsed': dailyUsed,
      'weeklyLimit': weeklyLimit,
      'weeklyUsed': weeklyUsed,
      'monthlyLimit': monthlyLimit,
      'monthlyUsed': monthlyUsed,
    };
  }

  /// 复制并修改
  TokenUsage copyWith({
    String? id,
    String? source,
    String? name,
    String? status,
    int? tokensUsed,
    int? tokensLimit,
    int? tokensRemaining,
    double? balanceAmount,
    String? balanceCurrency,
    DateTime? periodStart,
    DateTime? periodEnd,
    DateTime? updatedAt,
    double? dailyLimit,
    double? dailyUsed,
    double? weeklyLimit,
    double? weeklyUsed,
    double? monthlyLimit,
    double? monthlyUsed,
  }) {
    return TokenUsage(
      id: id ?? this.id,
      source: source ?? this.source,
      name: name ?? this.name,
      status: status ?? this.status,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      tokensLimit: tokensLimit ?? this.tokensLimit,
      tokensRemaining: tokensRemaining ?? this.tokensRemaining,
      balanceAmount: balanceAmount ?? this.balanceAmount,
      balanceCurrency: balanceCurrency ?? this.balanceCurrency,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      updatedAt: updatedAt ?? this.updatedAt,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      dailyUsed: dailyUsed ?? this.dailyUsed,
      weeklyLimit: weeklyLimit ?? this.weeklyLimit,
      weeklyUsed: weeklyUsed ?? this.weeklyUsed,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      monthlyUsed: monthlyUsed ?? this.monthlyUsed,
    );
  }

  @override
  String toString() {
    return 'TokenUsage(id: $id, source: $source, name: $name, status: $status, '
        'used: $tokensUsed, limit: $tokensLimit, remaining: $tokensRemaining)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TokenUsage && other.id == id && other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => id.hashCode ^ updatedAt.hashCode;
}
