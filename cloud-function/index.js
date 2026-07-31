/*
 * 知时 KnowTime - 华为云函数 (FunctionGraph) 埋点接收服务
 *
 * 功能：接收 App 端上报的匿名事件，存入华为云数据库
 *
 * 环境变量（在华为云函数控制台配置）：
 *   DB_ENDPOINT   - 华为云 GaussDB/GeminiDB 连接地址
 *   DB_USERNAME   - 数据库用户名
 *   DB_PASSWORD   - 数据库密码
 *   DB_NAME       - 数据库名
 *
 * 部署步骤：
 *   1. 在华为云 FunctionGraph 创建函数（Node.js 18）
 *   2. 上传本目录所有文件
 *   3. 配置环境变量
 *   4. 创建 API 网关触发器（HTTPS）
 *   5. 将触发器 URL 填入 App 的 ANALYTICS_ENDPOINT
 */

// ============================================================
// 方案 A：轻量级 - 使用华为云日志服务（LTS）记录，无需数据库
// ============================================================

// 如果使用 LTS，取消下面注释：
// const lts = require('@huawei-cloud/huawei-cloud-sdk-lts')

// ============================================================
// 方案 B：完整版 - 使用华为云 GaussDB（推荐）
// ============================================================

const crypto = require('crypto')

// ---------- 数据库连接（可选）----------
// const { Client } = require('pg')  // GaussDB 兼容 PostgreSQL
// let dbClient = null
//
// async function getDB() {
//   if (dbClient) return dbClient
//   dbClient = new Client({
//     host: process.env.DB_ENDPOINT,
//     user: process.env.DB_USERNAME,
//     password: process.env.DB_PASSWORD,
//     database: process.env.DB_NAME,
//     port: 8000,
//     ssl: { rejectUnauthorized: false }
//   })
//   await dbClient.connect()
//   return dbClient
// }

// ---------- 建表 SQL ----------
// 如果需要用数据库存储，先在 GaussDB 执行以下 SQL：
/*
CREATE TABLE IF NOT EXISTS analytics_events (
  id          SERIAL PRIMARY KEY,
  device_id   VARCHAR(64)  NOT NULL,
  app_version VARCHAR(16),
  event       VARCHAR(64)  NOT NULL,
  properties  JSONB,
  session_id  VARCHAR(64),
  created_at  TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_event ON analytics_events(event);
CREATE INDEX idx_device ON analytics_events(device_id);
CREATE INDEX idx_created ON analytics_events(created_at);
CREATE INDEX idx_device_date ON analytics_events(device_id, created_at::date);
*/

// ---------- 辅助函数 ----------
function md5(str) {
  return crypto.createHash('md5').update(str).digest('hex')
}

function now() {
  return new Date().toISOString()
}

// ---------- 核心 Handler ----------
exports.handler = async (event, context) => {
  // 华为云 FunctionGraph 的入口函数
  const requestId = context.request_id || 'unknown'
  console.log(`[${now()}] Request ${requestId} received`)

  try {
    const body = typeof event === 'string' ? JSON.parse(event) : event
    // API 网关触发器会把 HTTP body 放在 body 字段
    const payload = body.body ? JSON.parse(body.body) : body
    const { events } = payload

    if (!events || !Array.isArray(events) || events.length === 0) {
      return buildResponse(400, { error: 'events array required' })
    }

    // 处理每个事件
    const results = []
    for (const evt of events) {
      const entry = {
        device_id: md5(evt.device_id || 'unknown'),
        app_version: evt.app_version || '1.0.0',
        event: evt.event,
        properties: evt.properties || {},
        session_id: evt.session_id || '',
        client_timestamp: evt.timestamp || Date.now(),
        server_timestamp: now()
      }

      // === 方案 A：打印日志（LTS 自动采集） ===
      console.log(JSON.stringify({
        type: 'analytics_event',
        ...entry
      }))

      // === 方案 B：写入数据库（取消注释启用） ===
      // try {
      //   const db = await getDB()
      //   await db.query(
      //     `INSERT INTO analytics_events (device_id, app_version, event, properties, session_id, created_at)
      //      VALUES ($1, $2, $3, $4, $5, $6)`,
      //     [entry.device_id, entry.app_version, entry.event,
      //      JSON.stringify(entry.properties), entry.session_id, entry.server_timestamp]
      //   )
      // } catch (dbErr) {
      //   console.error('DB insert error:', dbErr.message)
      // }

      results.push({ id: md5(JSON.stringify(entry)), ok: true })
    }

    console.log(`[${now()}] Processed ${results.length} events`)

    return buildResponse(200, {
      ok: true,
      processed: results.length,
      server_time: now()
    })

  } catch (err) {
    console.error(`[${now()}] Error:`, err.message)
    return buildResponse(500, { error: 'Internal error', message: err.message })
  }
}

function buildResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify(body)
  }
}
