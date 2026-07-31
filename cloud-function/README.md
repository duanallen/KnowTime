# 华为云 FunctionGraph 部署指南

## 部署步骤

### 1. 创建函数
```
华为云控制台 → 函数工作流 FunctionGraph → 创建函数
- 运行时: Node.js 18.x
- 函数名称: knowtime-analytics
- 委托权限: 默认
```

### 2. 上传代码
将以下文件打包成 zip 上传：
- index.js
- package.json

### 3. 创建 API 网关触发器
```
函数详情 → 触发器 → 创建触发器
- 触发器类型: API 网关
- API 名称: knowtime-api
- 分组: 默认
- 请求协议: HTTPS
- 请求方法: POST
- 后端超时: 5000ms
```
触发器创建后会得到 URL，类似：
`https://xxx.apig.example.com/knowtime-api/analytics`

### 4. 配置环境变量（可选，用于数据库方案）
```
DB_ENDPOINT=xxx.gaussdb.myhuaweicloud.com
DB_USERNAME=admin
DB_PASSWORD=your_password
DB_NAME=knowtime
```

### 5. 更新 App 配置
将步骤 3 得到的 URL 填入：
`entry/src/main/ets/analytics/AnalyticsService.ets`
第 40 行：`const ANALYTICS_ENDPOINT = 'https://你的触发器URL'`

### 6. 测试
```bash
curl -X POST https://你的触发器URL \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "device_id": "test-001",
      "event": "app_launch",
      "properties": {},
      "timestamp": 1750000000000,
      "session_id": "sess-001"
    }]
  }'
```
预期返回：`{"ok":true,"processed":1}`

## 查询统计

### 使用华为云 LTS（日志服务 - 免费方案）
```
华为云控制台 → 日志服务 LTS → 日志流
自动采集 console.log 输出的日志
搜索示例：
  - 今日总事件数: *
  - 独立设备: 去重 device_id
```

### 使用 GaussDB（数据库方案 - 完整版）
```sql
-- 日活用户
SELECT COUNT(DISTINCT device_id)
FROM analytics_events
WHERE DATE(created_at) = CURRENT_DATE;

-- 周活用户
SELECT COUNT(DISTINCT device_id)
FROM analytics_events
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days';

-- 今日人均专注时长
SELECT AVG(CAST(properties->>'duration_minutes' AS INTEGER))
FROM analytics_events
WHERE event = 'focus_complete'
AND DATE(created_at) = CURRENT_DATE;

-- 上月用户留存率
WITH first_use AS (
  SELECT device_id, MIN(DATE(created_at)) AS first_date
  FROM analytics_events GROUP BY device_id
)
SELECT
  COUNT(DISTINCT CASE WHEN ae.created_at::date = fu.first_date + INTERVAL '30 days'
    THEN ae.device_id END) * 100.0 /
  NULLIF(COUNT(DISTINCT fu.device_id), 0) AS retention_rate
FROM first_use fu
LEFT JOIN analytics_events ae ON ae.device_id = fu.device_id
WHERE fu.first_date = CURRENT_DATE - INTERVAL '30 days';
```

## 费用估算

| 服务 | 用量 | 月费 |
|------|------|------|
| FunctionGraph (调用) | 10万次/月 | ≈ ¥0 |
| API 网关 | 10万次/月 | ≈ ¥0.7 |
| LTS (日志) | 1GB/月 | ≈ ¥0 |
| **总计** | | **< ¥1/月** |

> 华为云有免费额度：FunctionGraph 100万次/月、LTS 500MB/月
> 对于 MVP 阶段完全够用
