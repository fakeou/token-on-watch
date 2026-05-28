# Token Monitor - 手机端

AI 平台 Token 用量监控 Flutter Android App。

## 功能

- 🤖 管理多个 AI 平台（OpenAI / Claude / DeepSeek / 第三方中转站）的 API 配置
- 📊 从各平台 API 实时查询 token 使用情况和余额
- ⌚ 通过 Android interconnect 将数据推送到小米手表 VelaJS 快应用
- 🔐 API Key 加密存储，安全可靠
- ⏰ 定时自动刷新，支持手动刷新

## 支持的平台

| 平台 | API | 数据源 |
|------|-----|--------|
| OpenAI | Billing API | 用量 / 额度 |
| Claude (Anthropic) | Messages API | Key 有效性验证 |
| DeepSeek | Balance API | 余额信息 |
| 第三方中转站 | OpenAI 兼容 | 自动探测 |

## 项目结构

```
lib/
├── main.dart                          # 应用入口
├── app.dart                           # MaterialApp 配置 + 主题
├── models/
│   ├── token_usage.dart               # Token 用量模型
│   └── api_config.dart                # API 配置模型
├── services/
│   ├── api/
│   │   ├── base_api_service.dart      # API 抽象基类
│   │   ├── openai_service.dart        # OpenAI 服务
│   │   ├── anthropic_service.dart     # Claude 服务
│   │   ├── deepseek_service.dart      # DeepSeek 服务
│   │   ├── relay_service.dart         # 中转站服务
│   │   └── api_service_factory.dart   # 服务工厂
│   ├── interconnect/
│   │   ├── watch_bridge.dart          # Platform Channel 桥接
│   │   └── protocol.dart             # 通信协议常量
│   ├── storage/
│   │   ├── secure_storage.dart        # API Key 加密存储
│   │   └── config_storage.dart        # 配置持久化
│   └── scheduler/
│       └── refresh_scheduler.dart     # 定时刷新调度
├── screens/
│   ├── home_screen.dart               # 主页
│   ├── api_config_screen.dart         # 配置编辑页
│   └── account_detail_screen.dart     # 账户详情页
└── widgets/
    ├── token_card.dart                # Token 卡片
    ├── status_indicator.dart          # 状态指示器
    └── empty_state.dart               # 空状态
```

## 开发环境

- Flutter SDK: >=3.0.0
- Dart SDK: >=3.0.0
- Android: minSdkVersion 21

## 运行

```bash
# 获取依赖
flutter pub get

# 运行调试版
flutter run

# 构建发布版
flutter build apk --release
```

## 测试

```bash
flutter test
```

## Android 原生层

### Platform Channel

- 通道名: `com.example.tokenmonitor/interconnect`
- 方法:
  - `send` - 发送消息到手表
  - `isConnected` - 查询连接状态
  - `diagnose` - 获取诊断信息

### Interconnect 插件

位于 `android/app/src/main/kotlin/com/example/tokenmonitor/InterconnectPlugin.kt`

实现了与小米手表 VelaJS 快应用的 interconnect 通信协议。
需要根据实际的 interconnect SDK 替换 TODO 标记处的代码。

## 依赖

| 包 | 用途 |
|----|------|
| `http` | HTTP 请求 |
| `flutter_secure_storage` | API Key 加密存储 |
| `provider` | 状态管理 |
| `uuid` | 生成唯一 ID |
| `intl` | 日期格式化 |
| `shared_preferences` | 配置持久化 |

## 协议

手机端与手表端通过 JSON 消息通信：

| 操作 | 说明 |
|------|------|
| `query` | 手表请求查询数据 |
| `response` | 手机返回查询结果 |
| `refresh_one` | 手表请求刷新单个源 |
| `push` | 手机主动推送数据 |
| `ping/pong` | 心跳检测 |
