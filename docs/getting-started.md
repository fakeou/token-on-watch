# 开发指南

## 前置条件

### 手表端开发
1. 下载并安装 [AIoT-IDE](https://iot.mi.com/vela/quickapp/zh/guide/start/use-ide.html)
2. 安装 Node.js 16+
3. 目标设备：Redmi Watch 5 或 Redmi Watch 6

### 手机端开发
1. 安装 [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x+
2. 安装 Android Studio + Android SDK 33+
3. 准备一台 Android 手机（API 26+）

---

## 第一步：配置签名（关键！）

interconnect 通信要求手表快应用与手机 App 的**包名和签名完全一致**。

### 1.1 生成 Android 签名

```bash
# 如果还没有签名，先生成一个
keytool -genkey -v -keystore token-monitor.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias tokenmonitor
```

### 1.2 转换为 VelaJS 签名格式

```bash
cd token-monitor
./scripts/convert-signature.sh token-monitor.jks tokenmonitor your-password
```

这会在 `watch-app/sign/debug/` 和 `watch-app/sign/release/` 下生成：
- `private.pem` — 私钥
- `certificate.pem` — 证书

### 1.3 确认包名一致

| 位置 | 配置项 | 值 |
|------|--------|-----|
| `watch-app/manifest.json` | `package` | `com.example.tokenmonitor` |
| `phone-app/android/app/build.gradle` | `applicationId` | `com.example.tokenmonitor` |

---

## 第二步：手机端开发

```bash
cd phone-app

# 安装依赖
flutter pub get

# 运行（连接 Android 手机或模拟器）
flutter run

# 构建 APK
flutter build apk --release
```

### 配置 API 源

在手机 App 中：
1. 点击右上角 "+" 添加 API 源
2. 选择平台类型（OpenAI / DeepSeek / Claude / 中转站）
3. 输入 API Key 和可选的 Base URL
4. 点击"测试连接"验证
5. 保存

---

## 第三步：手表端开发

### 使用 AIoT-IDE

1. 打开 AIoT-IDE
2. File → Open Folder → 选择 `watch-app/` 目录
3. 选择目标设备（Redmi Watch 5 或 6）
4. 点击运行

### 模拟器调试

AIoT-IDE 内置模拟器，选择对应方形表盘尺寸即可调试。

---

## 第四步：联调测试

### 4.1 安装手机 App

```bash
cd phone-app
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 4.2 安装手表 App

使用 AIoT-IDE 打包并安装到手表。

### 4.3 测试通信

1. 确保手机和手表已蓝牙配对
2. 打开手机 App，添加至少一个 API 源
3. 打开手表 App
4. 手表 App 应自动连接手机 App
5. 下拉刷新测试数据获取

### 4.4 诊断工具

手表端 settings 页面提供连接诊断功能。
手机端可通过 `WatchBridge.diagnose()` 检查连接状态。

---

## 常见问题

### Q: 手表 App 提示"未安装手机 App"
A: 确认手机 App 已安装且包名与手表 manifest.json 中的 package 一致。

### Q: 连接后无法收到数据
A: 检查签名是否一致。使用 `./scripts/convert-signature.sh` 重新生成。

### Q: API 返回 401
A: API Key 无效或过期。在手机 App 中重新配置。

### Q: 中转站连不上
A: 确认 Base URL 正确（包含 `https://`），部分中转站需要在 URL 末尾加 `/v1`。

---

## 项目结构概览

```
token-monitor/
├── watch-app/          # VelaJS 快应用（手表端）
│   ├── src/pages/      # 页面：首页、详情、设置
│   ├── src/common/     # 公共：通信、缓存、工具
│   └── sign/           # 签名文件
├── phone-app/          # Flutter App（手机端）
│   ├── lib/models/     # 数据模型
│   ├── lib/services/   # API 服务、通信、存储
│   ├── lib/screens/    # 页面
│   └── lib/widgets/    # 组件
├── docs/               # 文档
│   ├── protocol.md     # 通信协议
│   └── api-sources.md  # API 适配
└── scripts/            # 工具脚本
    └── convert-signature.sh
```
