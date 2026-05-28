import 'dart:async';

import '../../models/token_usage.dart';

/// 定时刷新调度器
/// 控制定时查询所有 API 源的 token 用量数据
class RefreshScheduler {
  /// 定时器实例
  Timer? _timer;

  /// 当前刷新间隔
  Duration _interval;

  /// 刷新回调函数
  Future<List<TokenUsage>> Function()? _onRefresh;

  /// 是否正在运行
  bool _running = false;

  /// 刷新中标志，防止重叠
  bool _refreshing = false;

  /// 最后刷新时间
  DateTime? _lastRefreshTime;

  /// 刷新错误回调
  void Function(Object error)? onError;

  RefreshScheduler({Duration interval = const Duration(minutes: 5)})
      : _interval = interval;

  /// 当前刷新间隔
  Duration get interval => _interval;

  /// 是否正在运行
  bool get isRunning => _running;

  /// 最后刷新时间
  DateTime? get lastRefreshTime => _lastRefreshTime;

  /// 启动定时刷新
  /// [interval] 刷新间隔
  /// [onRefresh] 刷新回调函数，返回最新的 token 使用数据
  void start(
    Duration interval,
    Future<List<TokenUsage>> Function() onRefresh,
  ) {
    _interval = interval;
    _onRefresh = onRefresh;
    _running = true;

    // 立即执行一次刷新
    _executeRefresh();

    // 设置定时器
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _executeRefresh());
  }

  /// 停止定时刷新
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _refreshing = false;
  }

  /// 修改刷新间隔
  /// [newInterval] 新的刷新间隔
  void changeInterval(Duration newInterval) {
    _interval = newInterval;

    if (_running && _onRefresh != null) {
      // 重启定时器以应用新间隔
      _timer?.cancel();
      _timer = Timer.periodic(_interval, (_) => _executeRefresh());
    }
  }

  /// 手动触发一次刷新
  Future<List<TokenUsage>?> refreshNow() async {
    if (_onRefresh == null) return null;
    return await _onRefresh!();
  }

  /// 执行刷新
  Future<void> _executeRefresh() async {
    // 防止重叠执行
    if (_refreshing || _onRefresh == null) return;

    _refreshing = true;
    try {
      await _onRefresh!();
      _lastRefreshTime = DateTime.now();
    } catch (e) {
      onError?.call(e);
    } finally {
      _refreshing = false;
    }
  }

  /// 释放资源
  void dispose() {
    stop();
    _onRefresh = null;
  }
}
