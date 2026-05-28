# Token Monitor

基于小米手表 (VelaJS) 的 AI Token 余量监控工具。

## 项目结构

```
token-monitor/
├── watch-app/          # VelaJS 手表端快应用
├── phone-app/          # Flutter 手机端应用
├── docs/               # 文档（协议、API 适配等）
├── scripts/            # 构建/签名/部署脚本
└── README.md
```

## 架构

```
┌──────────────────────────────────────────┐
│              API 数据源                    │
│  OpenAI │ Claude │ DeepSeek │ 中转站      │
└──────────────┬───────────────────────────┘
               │ HTTP
               ▼
┌──────────────────────────────────────────┐
│         Flutter 手机端 App                │
│  • API 密钥管理 & 安全存储                 │
│  • 多源并发查询 & 缓存                     │
│  • interconnect 桥接 → 手表               │
└──────────────┬───────────────────────────┘
               │ interconnect (Android ↔ VelaJS)
               ▼
┌──────────────────────────────────────────┐
│         VelaJS 手表端 App                 │
│  • Token 余量列表展示                      │
│  • 下拉刷新 / 自动轮询                     │
│  • 本地缓存                               │
└──────────────────────────────────────────┘
```

## 支持的 API 源

| 平台 | 接口 | 状态 |
|------|------|------|
| OpenAI / Codex | `/dashboard/billing/usage` | ✅ |
| DeepSeek | `/user/balance` | ✅ |
| Anthropic Claude | 通过账单页解析 | 🔧 |
| 第三方中转站 | 兼容 OpenAI 格式 | ✅ |

## 开发环境

### 手表端
- [AIoT-IDE](https://iot.mi.com/vela/quickapp/zh/guide/start/use-ide.html)
- 目标设备：Redmi Watch 5 / 6

### 手机端
- Flutter SDK 3.x+
- Android SDK 33+
- 最低 Android 版本：API 26 (Android 8.0)

## 快速开始

### 1. 手表端

```bash
cd watch-app
# 使用 AIoT-IDE 打开项目
```

### 2. 手机端

```bash
cd phone-app
flutter pub get
flutter run
```

### 3. 签名一致性（重要！）

interconnect 要求手表快应用与手机 App 的包名和签名完全一致。

```bash
# 使用脚本转换签名
./scripts/convert-signature.sh keystore.jks
```

## 通信协议

详见 [docs/protocol.md](docs/protocol.md)

## License

MIT
