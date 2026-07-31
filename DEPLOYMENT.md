# 知时 KnowTime - 完整部署上线指南

## 一、项目结构总览

```
KnowTime/
├── AppScope/                  # 鸿蒙应用配置
├── entry/                     # 主模块代码
│   └── src/main/ets/
│       ├── analytics/         # 埋点服务（上报到华为云函数）
│       ├── common/            # 主题/设计系统
│       ├── components/        # UI 组件
│       ├── database/          # 本地 RDB 数据库
│       ├── models/            # 数据模型
│       ├── pages/             # 4 个主页面
│       └── viewmodel/         # 状态管理 + 统计分析
├── cloud-function/            # 华为云函数代码（后端）
└── DEPLOYMENT.md              # 本文档
```

## 二、后端部署（华为云 FunctionGraph）

### 2.1 方式一：控制台手动部署（推荐新手）

1. 登录 [华为云控制台](https://console.huaweicloud.com)
2. 搜索"函数工作流 FunctionGraph"，进入
3. 点击"创建函数"：
   - 选择"从头开始"
   - 运行时：**Node.js 18.x**
   - 函数名称：`knowtime-analytics`
4. 上传代码：将 `cloud-function/` 下的 `index.js` 和 `package.json` 打包成 zip 上传
5. 创建 API 网关触发器：
   - 触发器类型：API 网关
   - 请求协议：HTTPS
   - 请求方法：POST
   - 创建后获得 URL（形如 `https://xxx.apig.cn-north-4.huaweicloudapis.com/...`）
6. **复制这个 URL**，下一步要用

### 2.2 方式二：Serverless Devs 命令行部署（推荐）

```bash
npm install -g @serverless-devs/s
s config add  # 选择华为云，输入 AK/SK
cd cloud-function
s deploy
```

### 2.3 费用

| 资源 | 免费额度 | MVP 用量估算 | 预计月费 |
|------|---------|-------------|---------|
| FunctionGraph 调用次数 | 100万次/月 | 5-10万次 | ¥0 |
| API 网关调用次数 | 100万次/月 | 5-10万次 | ¥0.5-1 |
| LTS 日志 | 500MB/月 | 100MB | ¥0 |
| **合计** | | | **< ¥1/月** |

## 三、App 端配置

### 3.1 填入上一步获得的 URL

编辑 `entry/src/main/ets/analytics/AnalyticsService.ets` 第 40 行：

```typescript
// 改动前
const ANALYTICS_ENDPOINT = ''

// 改动后（示例）
const ANALYTICS_ENDPOINT = 'https://xxxxxx.apig.cn-north-4.huaweicloudapis.com/analytics'
```

### 3.2 测试后台上报是否正常

先在华为云函数控制台执行一次测试：

```bash
curl -X POST https://你的URL \
  -H "Content-Type: application/json" \
  -d '{"events":[{"device_id":"test","event":"app_launch","properties":{},"timestamp":1700000000000,"session_id":"s1"}]}'
```

预期返回 `{"ok":true,"processed":1}`，然后到云函数日志中确认收到了事件。

## 四、打包上架

### 4.1 编译打包

用 DevEco Studio 打开 `KnowTime/` 目录：
1. Build → Build Hap(s)/App(s) → Build APP(s)
2. 生成 `.app` 文件

### 4.2 提交到华为应用商店

1. 注册 [华为开发者联盟](https://developer.huawei.com)
2. 进入"AppGallery Connect" → "我的应用" → 创建应用
3. 填写应用信息：
   - 应用名称：知时
   - 包名：com.knowtime.app
   - 分类：效率
4. 上传 .app 包
5. 填写隐私政策、权限说明
6. 提交审核

### 4.3 激励计划要求

鸿蒙应用开发者激励计划 2026 要求的指标：
- **应用上架** AppGallery ✅（必须）
- **用户量** 达到一定规模（通常 1000+ 安装）
- **活跃率** DAU/MAU 比值（通常 > 20%）
- **评分** 保持 4.0+

你的埋点系统可以跟踪这些数据：

| 激励指标 | 对应埋点 | 查询方式 |
|---------|---------|---------|
| 安装数 | 独立 device_id 总数 | `COUNT(DISTINCT device_id)` |
| DAU | 当天活跃 device_id | 按天统计 app_launch |
| WAU | 7天活跃 device_id | 按周统计 |
| 日人均使用次数 | 每天每设备 session_id 数 | `COUNT(DISTINCT session_id) / COUNT(DISTINCT device_id)` |
| 日人均专注时长 | focus_complete 的 duration_minutes | `AVG(duration_minutes)` |
| 次日留存 | 连续2天活跃的设备占比 | 跨日 device_id 交集 |

## 五、快速开始 Checklist

- [ ] 创建华为云 FunctionGraph 函数
- [ ] 配置 API 网关触发器，获取 URL
- [ ] 测试云函数接口返回 200
- [ ] 修改 `AnalyticsService.ets` 中的 `ANALYTICS_ENDPOINT`
- [ ] DevEco Studio 编译通过
- [ ] 真机安装测试，检查埋点上报
- [ ] AppGallery Connect 创建应用
- [ ] 提交审核
