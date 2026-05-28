import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储服务
/// 使用 flutter_secure_storage 加密存储 API Key 等敏感信息
class SecureStorage {
  /// Flutter Secure Storage 实例
  final FlutterSecureStorage _storage;

  /// Key 前缀，防止与其他应用冲突
  static const String _keyPrefix = 'tokenmonitor_';

  /// 单例模式
  static final SecureStorage _instance = SecureStorage._();
  factory SecureStorage() => _instance;

  SecureStorage._()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  /// 保存 API Key
  /// [configId] 对应 ApiConfig.id
  /// [apiKey] 要存储的 API Key
  Future<void> saveApiKey(String configId, String apiKey) async {
    final key = '${_keyPrefix}apikey_$configId';
    await _storage.write(key: key, value: apiKey);
  }

  /// 获取 API Key
  /// [configId] 对应 ApiConfig.id
  /// 返回 null 表示未找到
  Future<String?> getApiKey(String configId) async {
    final key = '${_keyPrefix}apikey_$configId';
    return await _storage.read(key: key);
  }

  /// 删除 API Key
  /// [configId] 对应 ApiConfig.id
  Future<void> deleteApiKey(String configId) async {
    final key = '${_keyPrefix}apikey_$configId';
    await _storage.delete(key: key);
  }

  /// 删除所有存储的 API Key
  Future<void> deleteAllApiKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith('${_keyPrefix}apikey_')) {
        await _storage.delete(key: key);
      }
    }
  }

  /// 检查是否存在指定配置的 API Key
  Future<bool> hasApiKey(String configId) async {
    final key = '${_keyPrefix}apikey_$configId';
    return await _storage.containsKey(key: key);
  }

  /// 获取所有已存储的 API Key 的配置 ID 列表
  Future<List<String>> getAllApiKeyIds() async {
    final all = await _storage.readAll();
    final ids = <String>[];
    for (final key in all.keys) {
      if (key.startsWith('${_keyPrefix}apikey_')) {
        final id = key.replaceFirst('${_keyPrefix}apikey_', '');
        ids.add(id);
      }
    }
    return ids;
  }
}
