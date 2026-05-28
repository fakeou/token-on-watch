import 'package:flutter/material.dart';
import '../app.dart';
import '../models/api_config.dart';
import '../models/token_usage.dart';
import '../services/api/api_service_factory.dart';
import '../services/interconnect/watch_bridge.dart';
import '../services/storage/config_storage.dart';
import '../services/storage/secure_storage.dart';
import '../services/scheduler/refresh_scheduler.dart';
import '../widgets/token_card.dart';
import '../widgets/status_indicator.dart';
import '../widgets/empty_state.dart';
import 'api_config_screen.dart';
import 'account_detail_screen.dart';

/// 主页 - 显示所有已配置 API 源的 token 用量列表
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 配置列表
  List<ApiConfig> _configs = [];

  /// Token 用量数据
  final Map<String, TokenUsage> _usageMap = {};

  /// 加载状态
  bool _loading = true;

  /// 错误信息
  String? _error;

  /// 手表连接状态
  bool _watchConnected = false;

  /// 刷新调度器
  final RefreshScheduler _scheduler = RefreshScheduler();

  /// 配置存储
  final ConfigStorage _configStorage = ConfigStorage();

  /// 安全存储
  final SecureStorage _secureStorage = SecureStorage();

  /// 手表桥接
  final WatchBridge _watchBridge = WatchBridge();

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HomeScreen.initState 开始');
    _loadConfigs();
    _checkWatchConnection();
    _listenWatchMessages();

    // 设置定时刷新（每5分钟）
    _scheduler.start(
      const Duration(minutes: 5),
      _refreshAll,
    );
    _scheduler.onError = (error) {
      debugPrint('⚠️ 调度器错误: $error');
    };
    debugPrint('🏠 HomeScreen.initState 完成');
  }

  @override
  void dispose() {
    _scheduler.dispose();
    super.dispose();
  }

  /// 加载配置列表
  Future<void> _loadConfigs() async {
    debugPrint('📦 _loadConfigs 开始');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _configs = await _configStorage.loadConfigs();
      debugPrint('📦 加载了 ${_configs.length} 个配置');
      // 为每个配置加载 API Key
      for (var i = 0; i < _configs.length; i++) {
        final apiKey = await _secureStorage.getApiKey(_configs[i].id);
        if (apiKey != null) {
          _configs[i] = _configs[i].copyWith(apiKey: apiKey);
        }
      }
      debugPrint('📦 API Key 加载完成，开始刷新');
      await _refreshAll();
      debugPrint('📦 _loadConfigs 完成');
    } catch (e, stackTrace) {
      debugPrint('🔴 _loadConfigs 异常: $e');
      debugPrint('   堆栈: $stackTrace');
      setState(() {
        _error = '加载配置失败: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  /// 刷新所有已启用配置的 token 用量
  Future<List<TokenUsage>> _refreshAll() async {
    final enabledConfigs = _configs.where((c) => c.enabled).toList();
    final futures = enabledConfigs.map(_fetchUsage);

    await Future.wait(futures, eagerError: false);

    if (mounted) {
      setState(() {});
    }

    // 推送数据到手表
    final usageList = _usageMap.values.toList();
    if (usageList.isNotEmpty && _watchConnected) {
      try {
        await _watchBridge.sendPush(usageList);
      } catch (_) {
        // 推送失败不影响主流程
      }
    }

    return usageList;
  }

  /// 获取单个配置的 token 用量
  Future<void> _fetchUsage(ApiConfig config) async {
    try {
      final service = ApiServiceFactory.create(config);
      final usage = await service.fetchUsage();
      _usageMap[config.id] = usage.copyWith(name: config.name);
    } catch (e) {
      // 单个源失败不影响其他源
      _usageMap[config.id] = TokenUsage(
        id: config.id,
        source: config.source,
        name: config.name,
        status: 'error',
        updatedAt: DateTime.now(),
      );
    }
  }

  /// 检查手表连接状态
  Future<void> _checkWatchConnection() async {
    final connected = await _watchBridge.checkConnection();
    if (mounted) {
      setState(() {
        _watchConnected = connected;
      });
    }
  }

  /// 监听手表消息
  void _listenWatchMessages() {
    _watchBridge.onMessage.listen((message) {
      if (message.isQuery) {
        // 手表查询请求
        _handleWatchQuery(message);
      } else if (message.isRefreshOne) {
        // 单源刷新请求
        _handleWatchRefreshOne(message);
      } else if (message.isPing) {
        // 心跳响应
        setState(() {
          _watchConnected = true;
        });
      }
    });
  }

  /// 处理手表查询请求
  Future<void> _handleWatchQuery(dynamic message) async {
    final sources = message.sources;
    List<TokenUsage> responseData;

    if (sources == null || sources.isEmpty) {
      // 返回所有数据
      responseData = _usageMap.values.toList();
    } else {
      // 返回指定源的数据
      responseData = _usageMap.values
          .where((u) => sources.contains(u.source))
          .toList();
    }

    await _watchBridge.sendResponse(responseData, message.requestId ?? '');
  }

  /// 处理手表单源刷新请求
  Future<void> _handleWatchRefreshOne(dynamic message) async {
    final sourceId = message.sourceId;
    if (sourceId == null) return;

    final index = _configs.indexWhere((c) => c.id == sourceId);
    if (index < 0) return;

    final config = _configs[index];
    await _fetchUsage(config);
    setState(() {});

    if (_usageMap.containsKey(sourceId)) {
      await _watchBridge.sendResponse(
        [_usageMap[sourceId]!],
        message.requestId ?? '',
      );
    }
  }

  /// 导航到配置编辑页
  Future<void> _navigateToConfig({ApiConfig? config}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ApiConfigScreen(config: config),
      ),
    );

    if (result == true) {
      await _loadConfigs();
    }
  }

  /// 导航到详情页
  void _navigateToDetail(TokenUsage usage) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountDetailScreen(usage: usage),
      ),
    );
  }

  /// 删除配置
  Future<void> _deleteConfig(ApiConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('确认删除'),
        content: Text('确定要删除 "${config.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _configStorage.removeConfig(config.id);
      await _secureStorage.deleteApiKey(config.id);
      _usageMap.remove(config.id);
      await _loadConfigs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Token Monitor'),
        actions: [
          // 手表连接状态指示器
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: StatusIndicator(
              connected: _watchConnected,
              onTap: _checkWatchConnection,
            ),
          ),
          // 添加按钮
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _navigateToConfig(),
            tooltip: '添加 API 配置',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// 构建主体内容
  Widget _buildBody() {
    // 加载中
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // 错误状态
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConfigs,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 空状态
    if (_configs.isEmpty) {
      return EmptyState(
        icon: Icons.add_circle_outline,
        title: '暂无配置',
        description: '点击右上角 + 按钮添加你的第一个 AI 平台配置',
        actionLabel: '添加配置',
        onAction: () => _navigateToConfig(),
      );
    }

    // 数据列表
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _configs.length,
        itemBuilder: (context, index) {
          final config = _configs[index];
          final usage = _usageMap[config.id];

          return TokenCard(
            config: config,
            usage: usage,
            onTap: () {
              if (usage != null) {
                _navigateToDetail(usage);
              }
            },
            onLongPress: () => _showConfigActions(config),
          );
        },
      ),
    );
  }

  /// 显示配置操作菜单
  void _showConfigActions(ApiConfig config) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('编辑配置'),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToConfig(config: config);
              },
            ),
            ListTile(
              leading: Icon(
                config.enabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
                color: AppColors.warning,
              ),
              title: Text(config.enabled ? '禁用' : '启用'),
              onTap: () async {
                Navigator.pop(ctx);
                final updated = config.copyWith(enabled: !config.enabled);
                await _configStorage.updateConfig(updated);
                await _loadConfigs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.success),
              title: const Text('刷新'),
              onTap: () async {
                Navigator.pop(ctx);
                await _fetchUsage(config);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('删除', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConfig(config);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
