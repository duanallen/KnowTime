# 知时 KnowTime

知时（KnowTime）是一款运行在 HarmonyOS 手机与平板上的时间感知型深度专注助手：以番茄钟式计时为核心，配合专注统计、桌面服务卡片与后台提醒，帮助用户感知时间去向、保持深度专注。仓库同时包含配套的云端埋点函数，用于统计活跃、留存与专注时长等运营指标。

- 包名：com.knowtime.app
- 版本：1.0.0（versionCode 1000000）
- 平台：HarmonyOS 6.0.1（API 21）

## 功能特性

- 专注计时：环形进度（TimerRing）展示倒计时，结束支持震动与三种内置铃声提醒
- 专注统计：专注会话经本地 RDB 数据库持久化，统计页提供多维度分析
- 桌面卡片：2x2 / 2x4 / 4x4 三种规格服务卡片，无需打开应用即可查看专注状态
- 后台提醒：基于系统提醒代理（PUBLISH_AGENT_REMINDER），结合屏幕状态感知
- 隐私合规：内置隐私政策页与隐私偏好管理，支持系统备份扩展
- 云端埋点：使用事件上报至华为云 FunctionGraph，经 API 网关接收

## 环境准备

开始之前，请确认本机已具备：

- DevEco Studio 6.0.1 及以上
- HarmonyOS SDK 6.0.1（API 21）
- Node.js（Hvigor 构建工具运行时依赖，DevEco Studio 自带）
- ohpm（OpenHarmony 包管理器，随 DevEco Studio 安装）
- hdc（真机调试命令行工具，随 SDK 工具链安装）

## 快速开始

### 安装依赖并构建 HAP

前置条件：已完成环境准备，且 SDK 路径已在 DevEco Studio 或环境变量中配置。

1. 克隆仓库，进入项目根目录
2. 执行 `ohpm install` 安装依赖
3. 执行 `hvigorw assembleHap` 构建

预期结果：构建结束输出 BUILD SUCCESSFUL，`entry/build/default/outputs/default/` 目录下生成 HAP 产物。

故障排除：

- 依赖安装失败：删除 `oh_modules` 目录后重新执行 `ohpm install`
- 构建卡死或状态异常：执行 `hvigorw --stop-daemon` 停止守护进程；仍异常时删除用户目录下 `.hvigor/project_caches` 中对应项目的缓存后重试

### 在真机或模拟器上运行

前置条件：已连接真机（`hdc list targets` 可见设备）或已创建模拟器。

1. 用 DevEco Studio 打开项目根目录
2. 在设备选择器中选中目标设备
3. 选择 `Run > Run 'entry'`

预期结果：应用完成安装并自动启动，进入首页。

### 运行单元测试

1. 在项目根目录执行 `hvigorw ohosTest`

预期结果：hypium 测试用例全部执行通过，控制台输出测试报告。

## 配置

### 签名

`build-profile.json5` 已内置 default 调试签名配置，可直接用于本地运行。发布版本需在 DevEco Studio 的 `Project Structure > Signing Configs` 中配置正式发布证书与 Profile。

### 云端埋点上报

埋点接收端为华为云 FunctionGraph 函数，代码位于 `cloud-function/`。

1. 在华为云控制台创建 FunctionGraph 函数（运行时 Node.js 18），上传 `cloud-function/` 下的代码
2. 为该函数创建 API 网关触发器（HTTPS + POST），记录生成的调用 URL
3. 将该 URL 填入 `entry/src/main/ets/analytics/AnalyticsService.ets` 中的 `ANALYTICS_ENDPOINT` 常量

预期结果：触发埋点事件后，云函数日志中可见对应的上报记录。费用估算与详细步骤见 [DEPLOYMENT.md](DEPLOYMENT.md)。

## 项目结构

```
KnowTime/
├── AppScope/                      # 应用级全局配置（bundleName、图标、应用名）
├── entry/                         # 主 HAP 模块
│   └── src/main/
│       ├── ets/
│       │   ├── analytics/         # 埋点上报服务（AnalyticsService）
│       │   ├── common/            # 主题与设计令牌
│       │   ├── components/        # 可复用 UI 组件（TimerRing 计时圆环）
│       │   ├── database/          # 本地 RDB 数据库访问层
│       │   ├── entryability/      # 应用入口 Ability
│       │   ├── entrybackupability/# 备份扩展 Ability
│       │   ├── formability/       # 桌面卡片扩展 Ability
│       │   ├── models/            # 数据模型（FocusSession 等）
│       │   ├── pages/             # 页面：首页/专注/统计/我的/设置/关于/隐私政策
│       │   ├── services/          # 应用信息、屏幕状态、提醒、隐私偏好等服务
│       │   ├── viewmodel/         # 专注计时与统计的视图模型层
│       │   └── widget/pages/      # 桌面卡片 UI（2x2 / 2x4 / 4x4）
│       ├── resources/             # 多语言与深色模式资源、铃声、隐私政策文本
│       └── module.json5           # 模块配置（Ability、权限、路由）
├── cloud-function/                # 云端埋点接收函数（FunctionGraph）
├── build-profile.json5            # 应用级构建配置（签名、SDK 版本、构建模式）
├── oh-package.json5               # 应用级依赖（hypium、hamock）
└── hvigorfile.ts                  # Hvigor 构建脚本入口
```

## 参考信息

### 技术栈

| 类别 | 说明 |
|------|------|
| 平台 | HarmonyOS，SDK 6.0.1（API 21），目标设备 phone / tablet |
| 语言 | ArkTS（.ets），ArkUI 声明式 UI |
| 构建工具 | Hvigor + ohpm |
| 本地存储 | RDB 关系型数据库 |
| 测试框架 | @ohos/hypium 1.0.25、@ohos/hamock 1.0.0 |
| 后端 | 华为云 FunctionGraph（Node.js 18）+ API 网关 |

### 权限说明

| 权限 | 用途 |
|------|------|
| `ohos.permission.VIBRATE` | 专注结束时的震动提醒 |
| `ohos.permission.PUBLISH_AGENT_REMINDER` | 后台定时提醒代理 |

## 参与贡献

1. Fork 本仓库，从主分支切出特性分支
2. 完成改动后执行 `hvigorw ohosTest`，确认测试全部通过
3. 提交前确认代码通过 `code-linter.json5` 定义的检查规则（@performance/recommended、@typescript-eslint/recommended 及安全规则集）
4. 提交 PR，描述变更动机与验证方式

## 相关文档

- [DEPLOYMENT.md](DEPLOYMENT.md)：云函数部署、App 端配置与上架流程
- [codebase-structure.md](codebase-structure.md)：代码库结构详解
- [cloud-function/README.md](cloud-function/README.md)：云函数说明
