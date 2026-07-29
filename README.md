# 我的待办 · my_todo

一个本地优先的 Flutter 待办应用。支持中文自然语言录入、到期提醒、回收站、
灵活排序与完成统计；本地规则无法识别的时间写法，可以选择交给兼容
OpenAI Chat Completions 的云端服务兜底。

> 任务数据始终保存在当前设备。云端识别默认关闭，也不提供任务同步。

<p align="center">
  <img src="screenshots/home.png" width="45%" alt="待办主界面" />
  &nbsp;&nbsp;
  <img src="screenshots/stats.png" width="45%" alt="完成统计页" />
</p>

## 功能

- **自然语言快速添加**：从一句中文里提取任务标题与截止时间
- **本地优先解析**：常见日期和时间完全在设备上处理
- **可选云端兜底**：仅在本地规则无法判断写法时请求用户配置的服务
- **到期提醒**：Android、iOS 和 macOS 使用系统通知
- **本地持久化**：任务、回收站和排序偏好保存在当前设备
- **安全存储密钥**：API Key 写入 Keystore/Keychain，不进入明文偏好设置
- **回收站**：删除后 7 天内可恢复，超期自动清理
- **排序与统计**：支持添加顺序、截止日期、完成状态和最近 7 天趋势
- **旧数据迁移**：兼容早期任务结构、旧时间格式和缺失字段

## 快速开始

### 环境

- Flutter SDK（项目当前使用 Dart `^3.12.2`）
- 对应平台的 Flutter 开发环境
- macOS 构建额外需要 Xcode 和 CocoaPods

```bash
git clone https://github.com/yaohl74-droid/flutter_todo.git
cd flutter_todo
flutter pub get
flutter run
```

常用命令：

```bash
flutter run -d macos
flutter run -d chrome
flutter build macos --debug
flutter build apk --release
```

Android Release 构建完成后，可分发产物位于：

```text
build/app/outputs/flutter-apk/AI_Todo.apk
```

## 中文时间解析

提交任务时，解析器会移除识别出的时间词，只把正文保留为标题。

| 类型 | 示例 |
|---|---|
| 相对日期 | 今天、明天、后天、大后天、3 天后、三天后 |
| 星期 | 周一、这周五、下周三、下个礼拜三 |
| 绝对日期 | 3 月 5 日、三月一号、2027 年 3 月 3 日 |
| 时间 | 上午 9 点、下午 3 点、15:00、15 点 30 |
| 口语时间 | 九点半、两点一刻、晚上八点三刻 |
| 日期与时间 | 明早九点、今晚 8 点、下周一上午 9 点 30 分 |

核心规则：

- 只有日期时，截止时间默认为当天 `23:59`。
- 只有时间且今天已经过去时，顺延到明天；明确写“今天”时允许得到过去时间。
- 未写年份的月日优先取今年；若对应时刻已过，则顺延到明年。
- 裸周几取最近一个尚未过去的日期；“下周”按下一个自然周计算。
- 手动选择的日期时间优先于自然语言结果，但时间词仍会从标题中移除。
- 多个日期/时间候选、非法日期、重复任务和模糊表达不会被勉强猜测。

目前故意不解析：

- 重复计划：每天、每周一、每月等
- 模糊时段：明早开会、月底交付等没有精确时刻的写法
- 周/月粒度偏移：两周后、三个月后
- 多个相互竞争的日期或时间

无法解析时，任务仍会按原文保存为无期限任务，不会丢失输入。

## 可选云端识别

点击主界面右上角的云朵进入设置。统计入口独立位于左上角，不再和云端设置混在
一起。云端能力默认关闭，需要用户主动配置：

- API Key
- Base URL
- Model

设置页提供以下预设，选择后会自动填入 Base URL 与默认模型；模型 ID 仍可按各家
控制台实际开通情况修改：

| 服务商 | 默认模型 |
|---|---|
| DeepSeek | `deepseek-v4-pro` |
| 通义千问（阿里云百炼） | `qwen-plus` |
| 火山方舟（豆包） | `doubao-seed-1-6-251015` |
| 腾讯混元 TokenHub | `hy3-preview` |
| Kimi | `kimi-k2.6` |
| 智谱 GLM | `glm-4.7` |
| 自定义 OpenAI 兼容服务 | 用户填写 |

默认 Base URL 为 `https://api.deepseek.com`。请求使用
`{Base URL}/chat/completions`，因此也可连接其他兼容 OpenAI Chat Completions
格式的服务。

云端调用遵循以下边界：

1. 本地能解析的输入不会联网。
2. 重复任务、非法日期、多个候选等本地已经能拒绝的输入不会联网。
3. 只有本地规则确实不认识的写法，且云端功能已启用时，才发送该条任务文本。
4. 超时、认证失败、限流、服务异常或响应不合规时，原任务照常保存。
5. API Key 使用 `flutter_secure_storage`；日志不会打印密钥。

任务列表不会发送到云端，也没有账号体系或跨设备同步。

## macOS：构建、签名与 Keychain

macOS 版需要 CocoaPods，因为当前 `flutter_secure_storage_macos` 尚未支持 Swift
Package Manager：

```bash
brew install cocoapods
pod --version
flutter pub get
flutter build macos --debug
open build/macos/Build/Products/Debug/my_todo.app
```

构建日志中的以下内容目前只是兼容性提示：

```text
flutter_secure_storage_macos does not support Swift Package Manager
```

### 首次签名配置

Keychain access group 必须由真实 Apple 开发团队签名。免费 Apple ID 的 Personal
Team 足够本机开发：

1. 打开 `macos/Runner.xcworkspace`，不要只打开 `.xcodeproj`。
2. 在 **Xcode → Settings → Accounts** 登录 Apple ID。
3. 选择 **Runner → TARGETS / Runner → Signing & Capabilities**。
4. 勾选 **Automatically manage signing**。
5. 在 **Team** 中选择自己的 Personal Team。
6. 如果 Bundle Identifier 被占用，改成自己长期使用的唯一反向域名标识。

本项目的 macOS Bundle Identifier 当前为：

```text
com.jideadmin.myTodo
```

Bundle Identifier 是应用身份的一部分。发布或开始保存正式数据后不要随意修改，
否则系统会把它视为另一个应用，原有 Keychain 项和本地数据也不会自动迁移。

### 常见错误

#### Entitlements require signing

```text
"Runner" has entitlements that require signing with a development certificate
```

Runner 没有可用的开发团队或 Apple Development 证书。按上面的首次签名步骤配置，
不要通过删除 `keychain-access-groups` 来绕过。

#### Failed Registering Bundle Identifier

```text
Failed Registering Bundle Identifier
No profiles were found
```

当前 Bundle Identifier 已被其他开发者注册。换成自己的唯一标识，等待 Xcode 自动
生成 provisioning profile。

#### 保存云端设置时报 `-34018`

```text
errSecMissingEntitlement
```

应用没有带有效 Keychain entitlement 运行。确认：

- Runner 选择了正确的 Team；
- Debug/Release entitlement 都包含
  `$(AppIdentifierPrefix)$(CFBundleIdentifier)`；
- 启动的是重新构建后的 `.app`。

本仓库同时声明 `com.apple.security.network.client`，用于沙盒内的出站 API 请求。
不要把 API Key 降级保存到 `SharedPreferences`。

> Xcode 可能把个人 `DEVELOPMENT_TEAM` 写入 `project.pbxproj`。公开仓库或团队项目
> 提交前应确认是否接受该配置，或改为本地签名配置。

## 数据与隐私

| 数据 | 存储位置 |
|---|---|
| 任务、排序偏好、回收站 | `shared_preferences` |
| API Key | 系统 Keystore/Keychain |
| 截止时间、完成时间 | UTC ISO 8601 |

任务数据不做云同步。卸载应用、清除应用数据或清除浏览器站点数据可能导致任务丢失。

读取旧存档时会自动处理：

- 早期的 `List<String>` 任务
- 缺少 ID、截止时间、完成时间或提醒字段的记录
- 旧的本地时间格式
- 空 ID、重复 ID、损坏记录和非法日期

## 架构

```text
lib/
├── models/    任务模型、状态与业务规则
├── services/  持久化、提醒、云端配置与模型接口
├── pages/     主页面、设置页和统计页
├── widgets/   可复用展示组件
└── utils/     自然语言解析与无状态工具
```

状态管理使用 Provider。`TodoModel` 是任务事实来源，`ReminderService` 观察任务变化
并对账系统通知。排序、筛选和统计基于副本计算，不改变任务的原始存储顺序。

主要依赖：

- `provider`
- `shared_preferences`
- `flutter_secure_storage`
- `flutter_local_notifications`
- `timezone`
- `http`

## 测试与质量检查

```bash
flutter analyze
flutter test
```

修改 macOS entitlement 后额外运行：

```bash
plutil -lint macos/Runner/DebugProfile.entitlements \
  macos/Runner/Release.entitlements
flutter test test/macos_entitlements_test.dart
flutter build macos --debug
```

测试覆盖自然语言解析、拒绝原因、云端契约、安全存储、旧数据迁移、排序、提醒资格、
回收站、统计和主要 Widget 交互。

## 许可证

[MIT](LICENSE) © Mark Yao
