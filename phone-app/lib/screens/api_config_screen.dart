import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app.dart';
import '../models/api_config.dart';
import '../services/api/api_service_factory.dart';
import '../services/storage/config_storage.dart';
import '../services/storage/secure_storage.dart';

/// API 配置编辑页
/// 新增或编辑 AI 平台的 API 配置
class ApiConfigScreen extends StatefulWidget {
  /// 编辑模式传入已有配置，新增模式为 null
  final ApiConfig? config;

  const ApiConfigScreen({super.key, this.config});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _sessionCookieController = TextEditingController();

  /// 选中的平台类型
  late String _selectedSource;

  /// 是否正在测试连接
  bool _testing = false;

  /// 测试结果
  String? _testResult;
  bool? _testSuccess;

  /// 是否正在保存
  bool _saving = false;

  /// 是否为编辑模式
  bool get _isEditing => widget.config != null;

  final ConfigStorage _configStorage = ConfigStorage();
  final SecureStorage _secureStorage = SecureStorage();

  @override
  void initState() {
    super.initState();

    if (_isEditing) {
      final config = widget.config!;
      _selectedSource = config.source;
      _nameController.text = config.name;
      _baseUrlController.text = config.baseUrl ?? '';
      _sessionCookieController.text = config.sessionCookie ?? '';

      // 加载已保存的 API Key
      _secureStorage.getApiKey(config.id).then((key) {
        if (key != null && mounted) {
          _apiKeyController.text = key;
        }
      });
    } else {
      _selectedSource = 'deepseek';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _sessionCookieController.dispose();
    super.dispose();
  }

  /// 测试 API 连接
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final config = ApiConfig(
        id: 'test',
        source: _selectedSource,
        name: 'test',
        apiKey: _apiKeyController.text.trim(),
        baseUrl: _baseUrlController.text.trim().isEmpty
            ? null
            : _baseUrlController.text.trim(),
        sessionCookie: _sessionCookieController.text.trim().isEmpty
            ? null
            : _sessionCookieController.text.trim(),
        createdAt: DateTime.now(),
      );

      final service = ApiServiceFactory.create(config);
      final isValid = await service.validate();

      setState(() {
        _testSuccess = isValid;
        _testResult = isValid ? '连接成功 ✓' : '连接失败：API Key 无效';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = '连接失败：$e';
      });
    } finally {
      setState(() {
        _testing = false;
      });
    }
  }

  /// 保存配置
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    try {
      final id = _isEditing ? widget.config!.id : const Uuid().v4();
      final apiKey = _apiKeyController.text.trim();
      final baseUrl = _baseUrlController.text.trim();

      final config = ApiConfig(
        id: id,
        source: _selectedSource,
        name: _nameController.text.trim(),
        apiKey: '', // apiKey 不存入普通配置
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        sessionCookie: _sessionCookieController.text.trim().isEmpty
            ? null
            : _sessionCookieController.text.trim(),
        enabled: true,
        createdAt: _isEditing
            ? widget.config!.createdAt
            : DateTime.now(),
      );

      // 保存 API Key 到安全存储
      await _secureStorage.saveApiKey(id, apiKey);

      // 保存配置到普通存储
      if (_isEditing) {
        await _configStorage.updateConfig(config);
      } else {
        await _configStorage.addConfig(config);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑配置' : '添加配置'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 平台类型选择
              _buildSourceSelector(),
              const SizedBox(height: 24),

              // 名称输入
              _buildNameField(),
              const SizedBox(height: 16),

              // API Key 输入（NewAPI 用 cookie，不需要 API Key）
              if (_selectedSource != 'newapi') ...[
                _buildApiKeyField(),
                const SizedBox(height: 16),
              ],

              // Base URL 输入（中转站必填）
              if (_selectedSource == 'newapi' ||
                  _selectedSource == 'sub2api' ||
                  _selectedSource == 'relay' ||
                  _selectedSource == 'mimo') ...[
                _buildBaseUrlField(),
                const SizedBox(height: 16),
              ],

              // Session Cookie（NewAPI 可选，用于获取用户余额）
              if (_selectedSource == 'newapi') ...[
                _buildSessionCookieField(),
                const SizedBox(height: 16),
              ],

              // 测试连接
              _buildTestButton(),
              const SizedBox(height: 16),

              // 测试结果
              if (_testResult != null) _buildTestResult(),
            ],
          ),
        ),
      ),
    );
  }

  /// 平台类型选择器
  Widget _buildSourceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '平台类型',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ApiConfig.supportedSources.map((source) {
            final isSelected = _selectedSource == source;
            return ChoiceChip(
              label: Text('${ApiConfig.sourceIcons[source]} ${ApiConfig.sourceNames[source]}'),
              selected: isSelected,
              selectedColor: AppColors.primary.withOpacity(0.2),
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.divider,
              ),
              onSelected: (_) {
                setState(() {
                  _selectedSource = source;
                  _testResult = null;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 名称输入框
  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: const InputDecoration(
        labelText: '显示名称',
        hintText: '例如：OpenAI 主账号',
        prefixIcon: Icon(Icons.label_outline, color: AppColors.textSecondary),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '请输入显示名称';
        }
        return null;
      },
    );
  }

  /// API Key 输入框
  Widget _buildApiKeyField() {
    return TextFormField(
      controller: _apiKeyController,
      style: const TextStyle(color: AppColors.textPrimary),
      obscureText: true,
      decoration: const InputDecoration(
        labelText: 'API Key',
        hintText: 'sk-...',
        prefixIcon: Icon(Icons.key, color: AppColors.textSecondary),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '请输入 API Key';
        }
        return null;
      },
    );
  }

  /// Base URL 输入框
  Widget _buildBaseUrlField() {
    return TextFormField(
      controller: _baseUrlController,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: const InputDecoration(
        labelText: 'Base URL',
        hintText: 'https://api.example.com',
        prefixIcon: Icon(Icons.link, color: AppColors.textSecondary),
      ),
      validator: (value) {
        if (_selectedSource == 'newapi' ||
            _selectedSource == 'sub2api' ||
            _selectedSource == 'relay') {
          if (value == null || value.trim().isEmpty) {
            return '中转站必须提供 Base URL';
          }
          final uri = Uri.tryParse(value.trim());
          if (uri == null || !uri.hasScheme) {
            return '请输入有效的 URL（含 https://）';
          }
        }
        if (_selectedSource == 'mimo' && value != null && value.trim().isNotEmpty) {
          final uri = Uri.tryParse(value.trim());
          if (uri == null || !uri.hasScheme) {
            return '请输入有效的 URL（含 https://）';
          }
        }
        return null;
      },
    );
  }

  /// Session Cookie 输入框（NewAPI 必填）
  Widget _buildSessionCookieField() {
    return TextFormField(
      controller: _sessionCookieController,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: const InputDecoration(
        labelText: 'Session Cookie',
        hintText: '从浏览器开发者工具复制 Cookie',
        prefixIcon: Icon(Icons.cookie, color: AppColors.textSecondary),
      ),
      maxLines: 2,
      validator: (value) {
        if (_selectedSource == 'newapi') {
          if (value == null || value.trim().isEmpty) {
            return '请输入 Session Cookie';
          }
        }
        return null;
      },
    );
  }

  /// 测试连接按钮
  Widget _buildTestButton() {
    return OutlinedButton.icon(
      onPressed: _testing ? null : _testConnection,
      icon: _testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : const Icon(Icons.wifi_find),
      label: Text(_testing ? '测试中...' : '测试连接'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  /// 测试结果展示
  Widget _buildTestResult() {
    final color = _testSuccess == true ? AppColors.success : AppColors.danger;
    final icon = _testSuccess == true ? Icons.check_circle : Icons.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _testResult!,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
