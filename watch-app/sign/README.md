# 签名文件说明

本目录包含应用签名所需的证书和私钥文件。

## 目录结构

```
sign/
├── debug/
│   ├── certificate.pem    # 调试证书
│   └── private.pem        # 调试私钥
└── release/
    ├── certificate.pem    # 发布证书
    └── private.pem        # 发布私钥
```

## 使用说明

- **debug/**：开发调试阶段使用，由开发工具自动生成
- **release/**：正式发布时使用，需要申请正式证书

## 注意事项

- ⚠️ 当前文件为占位文件，正式开发前需替换为真实签名
- 🔒 私钥文件（private.pem）请勿泄露或提交到公开仓库
- 📋 建议将 `sign/release/` 加入 `.gitignore`

## 生成签名

使用小米快应用签名工具生成：

```bash
hap sign --generate --config sign.config.js
```

或参考 [小米快应用文档](https://iot.mi.com/vela/) 获取详细说明。
