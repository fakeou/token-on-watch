# Token Monitor - VelaJS Watch App

AI 平台 Token 用量监控 VelaJS 快应用，运行在小米手表（Redmi Watch 5/6）上。

## 功能特性

- 📊 实时显示多个 AI 平台的 Token 使用余量
- 📱 通过 BLE/Interconnect 与手机端 Flutter App 通信
- 🔄 支持手动/自动刷新（5分钟/15分钟/30分钟）
- 💾 本地缓存，离线可查看历史数据
- 🎨 适配方形表盘（480×480）深色主题

## 支持的 AI 平台

- OpenAI
- Claude (Anthropic)
- DeepSeek
- 第三方中转站

## 项目结构

```
watch-app/
├── manifest.json          # 应用配置
├── package.json           # 依赖配置
├── sign/                  # 签名文件
│   ├── debug/
│   └── release/
├── src/
│   ├── app.ux             # 应用入口
│   ├── pages/
│   │   ├── index/         # 首页：Token 余量列表
│   │   ├── detail/        # 详情页：单源详细信息
│   │   └── settings/      # 设置页：刷新间隔、缓存管理
│   └── common/
│       ├── connector.js   # Interconnect 通信封装
│       ├── cache.js       # 本地缓存管理
│       └── format.js      # 数据格式化工具
└── README.md
```

## 开发环境

### 前置要求

- Node.js >= 14
- HAP Toolkit（小米快应用开发工具）
- 小米手表模拟器或真机

### 安装依赖

```bash
npm install
```

### 开发模式

```bash
npm run watch
```

### 构建

```bash
npm run build
```

### 启动调试服务器

```bash
npm run server
```

## 技术要点

### 通信机制

手表端通过 `@system.interconnect` 与手机端通信：

1. 手表端调用 `connector.connect()` 建立连接
2. 通过 `connector.requestData(sources)` 请求数据
3. 手机端返回 token 使用数据
4. 数据自动缓存到 `@system.storage`

### UI 设计规范

| 项目 | 值 |
|------|-----|
| 背景色 | #1A1A1A |
| 卡片背景 | #2A2A2A |
| 主色调 | #4FC3F7（蓝色）|
| 成功色 | #66BB6A（绿色）|
| 警告色 | #FFA726（橙色）|
| 危险色 | #EF5350（红色）|
| 设计宽度 | 480px |
| 圆角 | 12px |

### 状态颜色规则

- 绿色 `#66BB6A`：使用率 < 70%
- 橙色 `#FFA726`：使用率 70% ~ 90%
- 红色 `#EF5350`：使用率 > 90%

## 签名

开发时使用 `sign/debug/` 下的证书，发布时使用 `sign/release/` 下的证书。

> ⚠️ 当前为占位证书，正式发布前需替换为真实签名文件。

## 许可证

MIT
