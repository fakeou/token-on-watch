/// 通信协议常量
/// 定义手机端与手表端之间的消息协议
class Protocol {
  /// 查询操作 - 手表请求查询所有或指定源的 token 数据
  static const String actionQuery = 'query';

  /// 响应操作 - 手机返回查询结果
  static const String actionResponse = 'response';

  /// 单源刷新 - 手表请求刷新指定源的数据
  static const String actionRefreshOne = 'refresh_one';

  /// 主动推送 - 手机主动推送最新数据到手表
  static const String actionPush = 'push';

  /// 错误响应
  static const String actionError = 'error';

  /// 连接状态查询
  static const String actionPing = 'ping';

  /// 连接状态响应
  static const String actionPong = 'pong';

  /// 平台通道名称
  static const String channelName = 'com.example.tokenmonitor/interconnect';

  /// 支持的操作列表
  static const List<String> allActions = [
    actionQuery,
    actionResponse,
    actionRefreshOne,
    actionPush,
    actionError,
    actionPing,
    actionPong,
  ];
}

/// 手表消息模型
/// 解析从手表端接收到的消息
class WatchMessage {
  /// 操作类型
  final String action;

  /// 请求 ID（用于 response 关联）
  final String? requestId;

  /// 请求查询的源列表（query 操作）
  final List<String>? sources;

  /// 指定的单个源 ID（refresh_one 操作）
  final String? sourceId;

  /// 消息时间戳
  final DateTime timestamp;

  /// 附加数据
  final Map<String, dynamic>? data;

  const WatchMessage({
    required this.action,
    this.requestId,
    this.sources,
    this.sourceId,
    required this.timestamp,
    this.data,
  });

  /// 从 JSON 创建
  factory WatchMessage.fromJson(Map<String, dynamic> json) {
    return WatchMessage(
      action: json['action'] as String? ?? '',
      requestId: json['requestId'] as String?,
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      sourceId: json['sourceId'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// 从 Map（Platform Channel 参数）创建
  factory WatchMessage.fromMap(Map<dynamic, dynamic> map) {
    return WatchMessage.fromJson(
      Map<String, dynamic>.from(map),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'action': action,
      'requestId': requestId,
      'sources': sources,
      'sourceId': sourceId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
    };
  }

  /// 是否为查询请求
  bool get isQuery => action == Protocol.actionQuery;

  /// 是否为单源刷新请求
  bool get isRefreshOne => action == Protocol.actionRefreshOne;

  /// 是否为 Ping 请求
  bool get isPing => action == Protocol.actionPing;

  @override
  String toString() {
    return 'WatchMessage(action: $action, requestId: $requestId, sources: $sources)';
  }
}
