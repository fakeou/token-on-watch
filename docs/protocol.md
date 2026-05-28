# 通信协议

手表端 (VelaJS) 与手机端 (Flutter/Android) 通过 `system.interconnect` 通信。

## 消息格式

所有消息均为 JSON 格式，包含 `action` 字段标识消息类型。

## 消息类型

### 1. 手表 → 手机：查询请求

```json
{
  "action": "query",
  "requestId": "uuid-string",
  "sources": ["openai", "claude", "deepseek", "relay_1"],
  "timestamp": 1719900000000
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| action | String | 是 | 固定值 `"query"` |
| requestId | String | 是 | 请求唯一标识，用于匹配响应 |
| sources | Array | 否 | 指定查询的源，空数组或省略表示查询全部 |
| timestamp | Number | 是 | 请求时间戳 (ms) |

### 2. 手机 → 手表：查询响应

```json
{
  "action": "response",
  "requestId": "uuid-string",
  "data": [
    {
      "id": "openai_main",
      "source": "openai",
      "name": "OpenAI GPT-4",
      "status": "active",
      "tokens": {
        "used": 150000,
        "limit": 500000,
        "remaining": 350000,
        "unit": "tokens"
      },
      "balance": {
        "amount": 18.50,
        "currency": "USD"
      },
      "billing": {
        "period_start": "2025-01-01",
        "period_end": "2025-02-01"
      },
      "updated_at": 1719900000000
    }
  ],
  "errors": [],
  "timestamp": 1719900000000
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| action | String | 固定值 `"response"` |
| requestId | String | 匹配的请求 ID |
| data | Array | 各源的 token 使用数据 |
| errors | Array | 查询失败的源信息 |
| timestamp | Number | 响应时间戳 (ms) |

#### data 数组元素

| 字段 | 类型 | 说明 |
|------|------|------|
| id | String | 唯一标识，如 `"openai_main"` |
| source | String | 平台标识 |
| name | String | 显示名称 |
| status | String | `"active"` / `"expired"` / `"error"` |
| tokens | Object | token 用量信息 |
| balance | Object / null | 账户余额（部分平台支持） |
| billing | Object / null | 计费周期信息 |
| updated_at | Number | 数据更新时间 |

#### errors 数组元素

```json
{
  "id": "claude_main",
  "source": "claude",
  "code": 401,
  "message": "Invalid API key"
}
```

### 3. 手表 → 手机：单源刷新

```json
{
  "action": "refresh_one",
  "requestId": "uuid-string",
  "sourceId": "openai_main",
  "timestamp": 1719900000000
}
```

### 4. 手机 → 手表：状态推送

手机端定时刷新后主动推送（无需手表请求）：

```json
{
  "action": "push",
  "data": [...],
  "timestamp": 1719900000000
}
```

### 5. 连接状态检查

手表端通过 `connect.getReadyState()` 检查连接：

- `status: 1` → 连接成功
- `status: 2` → 连接断开

## 错误码

| code | 说明 |
|------|------|
| 0 | 成功 |
| 400 | 请求参数错误 |
| 401 | API Key 无效 |
| 429 | 请求频率超限 |
| 500 | 服务端错误 |
| 1000 | 未知错误 |
| 1001 | 手机端 App 未安装 |
| 1006 | 连接断开 |

## 实现约束

1. **包名一致**：watch `manifest.json` 的 `package` = phone `applicationId`
2. **签名一致**：watch 签名 PEM = phone 签名 JKS（需格式转换）
3. **消息大小**：单条消息建议 < 4KB
4. **刷新间隔**：建议 ≥ 5 分钟，避免 API 限流
