# API 源适配指南

## OpenAI / Codex

### 端点

| 用途 | 方法 | 路径 |
|------|------|------|
| 用量查询 | GET | `/dashboard/billing/usage` |
| 订阅信息 | GET | `/dashboard/billing/subscription` |

### Base URL
- 官方: `https://api.openai.com`
- 中转站: 用户自定义

### 认证
```
Authorization: Bearer {api_key}
```

### 响应示例
```json
{
  "total_usage": 1500000,  // 单位: 千分之一美分
  "daily_costs": [
    {
      "timestamp": 1719878400,
      "line_items": [
        {"name": "gpt-4", "cost": 150}
      ]
    }
  ]
}
```

---

## DeepSeek

### 端点

| 用途 | 方法 | 路径 |
|------|------|------|
| 余额查询 | GET | `/user/balance` |

### Base URL
- 官方: `https://api.deepseek.com`

### 认证
```
Authorization: Bearer {api_key}
```

### 响应示例
```json
{
  "is_available": true,
  "balance_infos": [
    {
      "currency": "CNY",
      "total_balance": "100.00",
      "granted_balance": "50.00",
      "topped_up_balance": "50.00"
    }
  ]
}
```

---

## Anthropic Claude

### 说明
Anthropic 目前没有公开的 usage/billing API。

### 可选方案

1. **验证 Key 有效性**: 发送一个最小请求到 `/v1/messages`
2. **手动配置额度**: 用户在手机端手动输入总配额
3. **解析账单**: 通过邮箱或网页端获取（未来可扩展）

### Base URL
- 官方: `https://api.anthropic.com`

### 认证
```
x-api-key: {api_key}
anthropic-version: 2023-06-01
```

---

## 第三方中转站

### 通用适配策略

多数中转站兼容 OpenAI 格式，按以下顺序探测：

1. `{base_url}/dashboard/billing/usage`
2. `{base_url}/v1/dashboard/billing/usage`
3. `{base_url}/api/user/dashboard/billing/usage`

### 常见中转站

| 名称 | Base URL 格式 | 备注 |
|------|--------------|------|
| OpenRouter | `https://openrouter.ai/api` | 有自己的余额接口 |
| One API | `https://your-domain.com` | 兼容 OpenAI |
| New API | `https://your-domain.com` | 兼容 OpenAI |

### OpenRouter 特殊处理

```json
GET https://openrouter.ai/api/v1/auth/key
Authorization: Bearer {api_key}

// 响应
{
  "data": {
    "label": "My Key",
    "usage": 1.50,
    "limit": 10.00,
    "is_free_tier": false
  }
}
```

---

## 错误处理

### HTTP 状态码

| 码 | 含义 | 处理 |
|----|------|------|
| 200 | 成功 | 解析响应 |
| 401 | 认证失败 | 标记 API Key 无效 |
| 403 | 权限不足 | 提示用户检查权限 |
| 429 | 限流 | 退避重试 |
| 5xx | 服务端错误 | 重试或展示缓存数据 |

### 通用重试策略

```
第 1 次重试: 等待 1 秒
第 2 次重试: 等待 2 秒
第 3 次重试: 等待 5 秒
超过 3 次: 返回错误，展示缓存数据
```
