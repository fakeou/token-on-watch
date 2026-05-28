import 'package:flutter_test/flutter_test.dart';
import 'package:token_monitor/models/token_usage.dart';
import 'package:token_monitor/models/api_config.dart';
import 'package:token_monitor/services/api/api_service_factory.dart';

void main() {
  group('TokenUsage 模型测试', () {
    test('fromJson / toJson 序列化反序列化', () {
      final json = {
        'id': 'openai_main',
        'source': 'openai',
        'name': 'OpenAI GPT-4',
        'status': 'active',
        'tokensUsed': 5000,
        'tokensLimit': 10000,
        'tokensRemaining': 5000,
        'balanceAmount': 10.5,
        'balanceCurrency': 'USD',
        'periodStart': '2024-01-01T00:00:00.000',
        'periodEnd': '2024-01-31T00:00:00.000',
        'updatedAt': '2024-01-15T12:00:00.000',
      };

      final usage = TokenUsage.fromJson(json);

      expect(usage.id, 'openai_main');
      expect(usage.source, 'openai');
      expect(usage.name, 'OpenAI GPT-4');
      expect(usage.status, 'active');
      expect(usage.tokensUsed, 5000);
      expect(usage.tokensLimit, 10000);
      expect(usage.tokensRemaining, 5000);
      expect(usage.balanceAmount, 10.5);
      expect(usage.balanceCurrency, 'USD');
      expect(usage.isActive, true);
      expect(usage.isExpired, false);
      expect(usage.isError, false);
      expect(usage.hasBalance, true);

      // 验证 toJson 往返一致
      final toJson = usage.toJson();
      expect(toJson['id'], 'openai_main');
      expect(toJson['source'], 'openai');
    });

    test('百分比计算', () {
      final usage = TokenUsage(
        id: 'test',
        source: 'openai',
        name: 'Test',
        status: 'active',
        tokensUsed: 7500,
        tokensLimit: 10000,
        tokensRemaining: 2500,
        updatedAt: DateTime.now(),
      );

      expect(usage.usagePercent, 0.75);
      expect(usage.remainingPercent, 0.25);
      expect(usage.usagePercentText, '75.0%');
    });

    test('copyWith 修改部分字段', () {
      final original = TokenUsage(
        id: 'test',
        source: 'openai',
        name: 'Test',
        status: 'active',
        tokensUsed: 100,
        tokensLimit: 1000,
        tokensRemaining: 900,
        updatedAt: DateTime(2024, 1, 1),
      );

      final copied = original.copyWith(
        status: 'expired',
        tokensUsed: 500,
      );

      expect(copied.id, 'test');
      expect(copied.status, 'expired');
      expect(copied.tokensUsed, 500);
      expect(copied.tokensLimit, 1000);
      expect(copied.updatedAt, DateTime(2024, 1, 1));
    });

    test('零额度边界情况', () {
      final usage = TokenUsage(
        id: 'test',
        source: 'openai',
        name: 'Test',
        status: 'active',
        tokensUsed: 0,
        tokensLimit: 0,
        tokensRemaining: 0,
        updatedAt: DateTime.now(),
      );

      expect(usage.usagePercent, 0.0);
      expect(usage.remainingPercent, 0.0);
      expect(usage.usagePercentText, 'N/A');
      expect(usage.hasBalance, false);
      expect(usage.balanceText, 'N/A');
    });
  });

  group('ApiConfig 模型测试', () {
    test('fromJson / toJson 序列化反序列化', () {
      final json = {
        'id': 'test-id-123',
        'source': 'openai',
        'name': 'OpenAI 主账号',
        'apiKey': 'sk-test-key',
        'baseUrl': null,
        'enabled': true,
        'createdAt': '2024-01-15T12:00:00.000',
      };

      final config = ApiConfig.fromJson(json);

      expect(config.id, 'test-id-123');
      expect(config.source, 'openai');
      expect(config.name, 'OpenAI 主账号');
      expect(config.apiKey, 'sk-test-key');
      expect(config.baseUrl, null);
      expect(config.enabled, true);
      expect(config.isRelay, false);
      expect(config.needsBaseUrl, false);
      expect(config.sourceDisplayName, 'OpenAI');
    });

    test('中转站配置需要 baseUrl', () {
      final config = ApiConfig(
        id: 'relay-1',
        source: 'relay',
        name: '中转站',
        apiKey: 'key',
        baseUrl: 'https://api.example.com',
        createdAt: DateTime.now(),
      );

      expect(config.isRelay, true);
      expect(config.needsBaseUrl, true);
      expect(config.sourceIcon, '🔄');
    });

    test('toJsonSafe 不包含 apiKey', () {
      final config = ApiConfig(
        id: 'test',
        source: 'openai',
        name: 'Test',
        apiKey: 'sk-secret-key',
        createdAt: DateTime.now(),
      );

      final safeJson = config.toJsonSafe();
      expect(safeJson.containsKey('apiKey'), false);
    });

    test('支持的平台列表完整', () {
      expect(ApiConfig.supportedSources, contains('openai'));
      expect(ApiConfig.supportedSources, contains('claude'));
      expect(ApiConfig.supportedSources, contains('deepseek'));
      expect(ApiConfig.supportedSources, contains('relay'));
      expect(ApiConfig.supportedSources.length, 4);
    });
  });

  group('ApiServiceFactory 测试', () {
    test('创建 OpenAI 服务', () {
      final config = ApiConfig(
        id: 'test',
        source: 'openai',
        name: 'Test',
        apiKey: 'sk-test',
        createdAt: DateTime.now(),
      );

      final service = ApiServiceFactory.create(config);
      expect(service.source, 'openai');
    });

    test('创建 Claude 服务', () {
      final config = ApiConfig(
        id: 'test',
        source: 'claude',
        name: 'Test',
        apiKey: 'sk-ant-test',
        createdAt: DateTime.now(),
      );

      final service = ApiServiceFactory.create(config);
      expect(service.source, 'claude');
    });

    test('创建 DeepSeek 服务', () {
      final config = ApiConfig(
        id: 'test',
        source: 'deepseek',
        name: 'Test',
        apiKey: 'sk-ds-test',
        createdAt: DateTime.now(),
      );

      final service = ApiServiceFactory.create(config);
      expect(service.source, 'deepseek');
    });

    test('创建 Relay 服务', () {
      final config = ApiConfig(
        id: 'test',
        source: 'relay',
        name: 'Test',
        apiKey: 'key',
        baseUrl: 'https://api.example.com',
        createdAt: DateTime.now(),
      );

      final service = ApiServiceFactory.create(config);
      expect(service.source, 'relay');
    });

    test('不支持的平台类型抛出异常', () {
      final config = ApiConfig(
        id: 'test',
        source: 'unsupported',
        name: 'Test',
        apiKey: 'key',
        createdAt: DateTime.now(),
      );

      expect(
        () => ApiServiceFactory.create(config),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
