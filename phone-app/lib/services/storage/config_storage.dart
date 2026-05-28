import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api_config.dart';

/// 配置存储服务
/// 使用 SharedPreferences 持久化存储 API 配置列表
/// 注意：API Key 不存储在此处，使用 SecureStorage 单独加密存储
class ConfigStorage {
  /// SharedPreferences 存储 Key
  static const String _configsKey = 'tokenmonitor_configs';

  /// 单例模式
  static final ConfigStorage _instance = ConfigStorage._();
  factory ConfigStorage() => _instance;

  ConfigStorage._();

  /// 加载所有配置
  Future<List<ApiConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_configsKey);

    if (jsonStr == null || jsonStr.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList
          .map((item) => ApiConfig.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 数据损坏，返回空列表
      return [];
    }
  }

  /// 保存配置列表（全量覆盖）
  Future<void> saveConfigs(List<ApiConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(configs.map((c) => c.toJsonSafe()).toList());
    await prefs.setString(_configsKey, jsonStr);
  }

  /// 添加单个配置
  Future<void> addConfig(ApiConfig config) async {
    final configs = await loadConfigs();
    configs.add(config);
    await saveConfigs(configs);
  }

  /// 删除指定配置
  Future<void> removeConfig(String id) async {
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.id == id);
    await saveConfigs(configs);
  }

  /// 更新指定配置
  Future<void> updateConfig(ApiConfig config) async {
    final configs = await loadConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configs[index] = config;
      await saveConfigs(configs);
    }
  }

  /// 获取指定配置
  Future<ApiConfig?> getConfig(String id) async {
    final configs = await loadConfigs();
    try {
      return configs.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 清除所有配置
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configsKey);
  }
}
