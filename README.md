# Token Monitor

基于小米手表 (VelaJS) 的 AI Token 余量监控工具。

## 当前状态：通信通道待解决 ⚠️

### 问题

项目目标是让手机 App 通过 XMS `@system.interconnect` 将 token 数据实时推送到手表快应用。
在 **Redmi Watch 4** 上验证发现，官方 Mi Fitness 存在特性门控 `isSupportThirdPartyApp()` 返回 `false`，
导致 `getConnectedNodes()` 始终为空，XMS 互连通道无法建立。

### 已验证的事实

| 尝试路径 | 结果 |
|---|---|
| XMS `@system.interconnect` (RW4) | `isSupportThirdPartyApp: false`，节点为空 |
| 隐藏的第三方应用安装流程 | RPK 发送成功但授权列表为空 |
| 修改版 Mi Fitness (patch DEX) | DEX patch 成功，但重签名导致小米账号 401 无法登录 |
| Vela 快应用 HTTP/网络 | Redmi Watch 4 无 Wi-Fi，`system.network` 不支持 |

### DEX Patch 进展

已定位并成功 patch 了 Mi Fitness v3.55.0 中的 `isSupportThirdPartyApp()` 方法：

- 文件：`com.xiaomi.xms.wearable.extensions.DeviceModelExtKt` (classes12.dex)
- 原始逻辑：`isSupportFeature(model, "thirdparty_app") || isSupportFeature(model, "third_party_no_market")`
- Patch 后：直接 `return true` (字节码 `const/4 v0, 1; return v0`)
- **问题**：APK 重签名后，小米账号系统因签名证书不匹配返回 HTTP 401，无法登录

### 解决方案

按可行性排序：

1. **LSPosed / Xposed 运行时 hook**（推荐，保持原始签名）
   - 安装 LSPosed 框架
   - 编写 Xposed 模块 hook `isSupportThirdPartyApp()` 返回 true
   - 保持原始 Mi Fitness APK 签名不变，账号正常登录

2. **换手表**（最简单，无需修改）
   - Redmi Watch 5 / 6、小米手环 9 / 9 Pro / 10 / 10 Pro
   - Xiaomi Watch S3 / S4 / S5
   - 以上型号的官方 Mi Fitness 原生支持 `isSupportThirdPartyApp = true`
   - 无需任何破解，开箱即用

3. **通知同步**（保底方案）
   - 手机 App 推送 Android 通知 → Mi Fitness 同步到手表
   - 不走快应用，手表被动展示通知文本

### Vela 设备兼容性参考

| 设备 | 快应用 | 原生 interconnect | 网络 |
|---|---|---|---|
| Redmi Watch 4 | ✅ | ❌ 需修改 | ❌ |
| Redmi Watch 5 / 6 | ✅ | ✅ 原生 | ❌ |
| Xiaomi Watch S3 | ✅ | ✅ 原生 | ✅ Wi-Fi |
| Xiaomi Watch S4 / S5 | ✅ | ✅ 原生 | ❌ |
| 小米手环 8 Pro / 9 / 9 Pro | ✅ | ✅ 原生 | ❌ |
| 小米手环 10 / 10 Pro | ✅ | ✅ 原生 | ❌ |

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
- 目标设备：Redmi Watch 4（需 LSPosed hook）/ Redmi Watch 5+（原生支持）

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
