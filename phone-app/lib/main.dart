import 'package:flutter/material.dart';

import 'app.dart';
import 'services/interconnect/watch_bridge.dart';

/// 应用入口
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获所有未处理异常
  FlutterError.onError = (details) {
    debugPrint('🔴 FlutterError: ${details.exception}');
    debugPrint('   Stack: ${details.stack}');
  };

  // 初始化手表通信桥接
  try {
    WatchBridge().initialize();
    debugPrint('✅ WatchBridge 初始化成功');
  } catch (e) {
    debugPrint('⚠️ WatchBridge 初始化失败: $e');
  }

  runApp(const TokenMonitorApp());
}
