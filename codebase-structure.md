# KnowTime Codebase Document

> 📁 This document is a project overview. KnowTime（知时）是一个 HarmonyOS 时间感知型深度专注助手应用，提供番茄钟式专注计时、专注统计、成就勋章与桌面卡片等功能。

## 1. Tech Stack

- **HarmonyOS SDK 6.0.1(21)** (from build-profile.json5 `compatibleSdkVersion` / `targetSdkVersion`)
- **Language**: ArkTS (HarmonyOS TypeScript 方言，文件后缀 `.ets`)
- **Runtime / Framework**: HarmonyOS ArkUI 声明式 UI 框架
- **Build tool**: Hvigor (HarmonyOS 官方构建工具，配置见 hvigor/hvigor-config.json5)
- **Package manager**: ohpm (OpenHarmony Package Manager，配置见 oh-package.json5)
- **Testing**: @ohos/hypium 1.0.25 (单元测试框架), @ohos/hamock 1.0.0 (mock 框架)
- **Target devices**: phone, tablet (from entry/src/main/module.json5 `deviceTypes`)
- **Permissions**: VIBRATE (震动提醒), PUBLISH_AGENT_REMINDER (后台提醒代理)

## 2. Project Directory Structure

> 💡 本项目为单模块 HarmonyOS 应用，主源码位于 `entry/src/main/ets/`，使用 ArkTS 编写。

```
KnowTime/
├── AppScope/                          # 应用级全局配置与资源（app.json5、全局 string/media 资源）
├── entry/                             # 主 HAP 模块，应用入口与全部业务代码
│   ├── src/
│   │   ├── main/
│   │   │   ├── ets/                   # ArkTS 业务源码根目录
│   │   │   │   ├── analytics/         # 数据分析服务，埋点与使用统计上报
│   │   │   │   ├── common/            # 公共常量与主题定义（颜色、间距等设计令牌）
│   │   │   │   ├── components/        # 可复用 UI 组件（如 TimerRing 计时圆环）
│   │   │   │   ├── database/          # 本地数据库访问层，专注会话与统计持久化
│   │   │   │   ├── entryability/      # 应用入口 Ability，生命周期与全局初始化
│   │   │   │   ├── entrybackupability/# 应用备份扩展 Ability
│   │   │   │   ├── formability/       # 桌面卡片（Form）扩展 Ability
│   │   │   │   ├── models/            # 数据模型定义（如 FocusSession 专注会话实体）
│   │   │   │   ├── pages/             # 应用页面：专注计时、统计、我的、设置、首页导航
│   │   │   │   ├── viewmodel/         # 视图模型与业务服务层（专注计时逻辑、统计服务）
│   │   │   │   └── widget/            # 桌面卡片 UI 页面（2x2 / 2x4 / 4x4 三种规格）
│   │   │   │       └── pages/         # 卡片具体页面实现
│   │   │   ├── resources/             # 资源文件：string、color、media、profile 等多限词资源配置
│   │   │   └── module.json5           # 模块配置：abilities、权限、页面路由等
│   │   ├── mock/                      # mock 资源目录
│   │   ├── ohosTest/                  # OHOS 测试代码目录
│   │   └── test/                      # 单元测试代码目录
│   ├── build-profile.json5            # 模块级构建配置
│   └── oh-package.json5               # 模块级依赖配置
├── cloud-function/                    # 云函数目录（服务端配套逻辑）
├── hvigor/                            # Hvigor 构建工具配置
│   └── hvigor-config.json5            # 构建执行与依赖配置
├── build-profile.json5                # 应用级构建配置（签名、SDK 版本、产物）
├── oh-package.json5                   # 应用级依赖配置（hypium、hamock 测试依赖）
└── hvigorfile.ts                      # Hvigor 构建脚本入口
```

## 3. Dev Commands (Core)

> ⚠️ 本项目为 HarmonyOS ArkTS 工程，构建与运行依赖 DevEco Studio IDE 或 Hvigor 命令行工具。命令源自项目构建配置文件。

### Build Commands
```bash
# 构建HAP包（Source: HarmonyOS 工程标准构建命令，基于 hvigor/hvigor-config.json5 与 build-profile.json5）
hvigorw assembleHap

# 构建HSP包（Source: HarmonyOS 工程标准构建命令）
hvigorw assembleHsp
```

### Test Commands
```bash
# 单元测试（Source: oh-package.json5 > devDependencies.@ohos/hypium 1.0.25；测试代码位于 entry/src/test 与 entry/src/ohosTest）
hvigorw ohosTest
```

### Run / Start Commands
```bash
# 运行/调试应用（Source: HarmonyOS 工程标准流程，需通过 DevEco Studio IDE 连接真机或模拟器运行）
# 在 DevEco Studio 中选择 Run > Run 'entry'，或使用 hdc 命令安装构建产物
hdc install entry-default-signed.hap
```

## 4. Dev Environment (Brief)

### Prerequisites

- HarmonyOS SDK 6.0.1(21) (compatibleSdkVersion)
- DevEco Studio IDE（推荐用于构建、运行与调试）
- Node.js（Hvigor 构建工具运行时依赖）
- ohpm（OpenHarmony 包管理器）
- hdc（HarmonyOS 设备调试命令行工具，用于真机部署）

### Configuration Notes

- `build-profile.json5`：应用级签名配置（default 签名材料）、SDK 版本、产物与构建模式（debug/release）
- `entry/src/main/module.json5`：模块配置，声明 EntryAbility 入口、桌面卡片扩展、备份扩展，以及 VIBRATE 与 PUBLISH_AGENT_REMINDER 权限
- `hvigor/hvigor-config.json5`：Hvigor 构建工具执行与依赖配置
- `oh-package.json5`：应用级依赖，含测试框架 hypium 与 hamock