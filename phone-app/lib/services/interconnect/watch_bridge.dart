import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../models/token_usage.dart';
import 'protocol.dart';

/// 手表通信桥接
/// 通过 Platform Channel 与 Android 原生层通信，
/// 进而与小米手表 VelaJS 快应用进行数据交换
class WatchBridge {
  /// Platform Channel 实例
  static const MethodChannel _channel =
      MethodChannel(Protocol.channelName);

  /// 消息监听流控制器
  final StreamController<WatchMessage> _messageController =
      StreamController<WatchMessage>.broadcast();

  /// 是否已初始化
  bool _initialized = false;

  /// 连接状态
  bool _connected = false;

  /// 单例模式
  static final WatchBridge _instance = WatchBridge._();
  factory WatchBridge() => _instance;

  WatchBridge._();

  /// 监听手表消息的数据流
  Stream<WatchMessage> get onMessage => _messageController.stream;

  /// 当前连接状态
  bool get isConnected => _connected;

  /// 初始化桥接，注册原生回调
  void initialize() {
    if (_initialized) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
  }

  /// 处理来自原生层的方法调用
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMessage':
        _handleMessage(call.arguments);
        break;
      case 'onConnectionChanged':
        _handleConnectionChanged(call.arguments);
        break;
      case 'onError':
        _handleError(call.arguments);
        break;
    }
  }

  /// 处理收到的消息
  void _handleMessage(dynamic arguments) {
    try {
      if (arguments is Map) {
        final message = WatchMessage.fromMap(
          Map<dynamic, dynamic>.from(arguments),
        );
        _messageController.add(message);
      }
    } catch (e) {
      // 消息解析失败，忽略
    }
  }

  /// 处理连接状态变化
  void _handleConnectionChanged(dynamic arguments) {
    if (arguments is Map) {
      _connected = arguments['connected'] == true;
    }
  }

  /// 处理错误
  void _handleError(dynamic arguments) {
    // 错误处理，可扩展日志记录
  }

  /// 发送查询响应到手表
  /// [data] token 使用数据列表
  /// [requestId] 关联的请求 ID
  Future<void> sendResponse(List<TokenUsage> data, String requestId) async {
    final payload = {
      'action': Protocol.actionResponse,
      'requestId': requestId,
      'data': data.map((e) => e.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _send(payload);
  }

  /// 主动推送数据到手表
  /// [data] token 使用数据列表
  Future<void> sendPush(List<TokenUsage> data) async {
    final payload = {
      'action': Protocol.actionPush,
      'data': data.map((e) => e.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _send(payload);
  }

  /// 发送错误响应
  Future<void> sendError(String message, String? requestId) async {
    final payload = {
      'action': Protocol.actionError,
      'requestId': requestId,
      'error': message,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _send(payload);
  }

  /// 检查手表连接状态
  Future<bool> checkConnection() async {
    try {
      final result = await _channel.invokeMethod<bool>('isConnected');
      _connected = result ?? false;
      return _connected;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  /// 请求手机侧刷新穿戴节点、权限和监听状态
  Future<void> refreshConnection() async {
    try {
      await _channel.invokeMethod('refreshConnection');
    } on MissingPluginException {
      // Platform Channel 未注册（可能在测试环境）
    }
  }

  /// 请求启动手表快应用
  Future<void> launchWatchApp() async {
    try {
      await _channel.invokeMethod('launchWatchApp');
    } on MissingPluginException {
      // Platform Channel 未注册（可能在测试环境）
    }
  }

  /// 获取连接诊断信息
  Future<Map<String, dynamic>> diagnose() async {
    try {
      final result = await _channel.invokeMethod<Map>('diagnose');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {
      // 诊断失败
    }
    return {
      'connected': _connected,
      'initialized': _initialized,
      'error': '无法获取诊断信息',
    };
  }

  /// 发送消息到原生层
  Future<void> _send(Map<String, dynamic> payload) async {
    try {
      final jsonStr = json.encode(payload);
      await _channel.invokeMethod('send', {'data': jsonStr});
    } on MissingPluginException {
      // Platform Channel 未注册（可能在测试环境）
    } on PlatformException catch (e) {
      throw Exception('发送消息失败: ${e.message}');
    }
  }

  /// 释放资源
  void dispose() {
    _messageController.close();
    _initialized = false;
  }
}
