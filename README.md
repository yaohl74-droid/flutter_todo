# 我的待办

一个使用 Flutter 和 Material Design 构建的跨平台待办 App。支持每日一句、添加与编辑任务、设置截止日期、到期通知提醒、标记完成、删除与回收站恢复，并通过 `shared_preferences` 将任务以 JSON 格式保存在本地，重新启动 App 后任务不会丢失。

## 功能

- AppBar 实时显示任务进度：`我的待办 (已完成/总数)`。
- AppBar 下方显示从每日一句接口获取的随机名言和作者，并可手动刷新。
- 名言请求超时、断网、DNS 或 TLS 异常时会进入自动重连，每隔 60 秒重试一次，连续三次失败后停止；手动刷新会重新开始一轮尝试。
- 名言加载、重连和失败状态都有明确提示，网络异常不会影响待办功能使用。
- 顶部排序工具栏提供三种显示顺序：
  - 按添加顺序。
  - 按截止日期（默认），没有截止日期的排在最后。
  - 按完成状态，未完成任务排在已完成任务之前。
- 排序菜单旁有独立的升序/降序按钮；默认升序，无日期任务在两个方向下都排在最后。
- 排序方式和升降序偏好都会保存到本地，下次启动自动恢复。
- 首次启动显示“买菜、写代码、跑步”三条示例任务，并立即保存到本地。
- 支持点击“添加”按钮或按键盘回车提交任务。
- 输入框旁提供日历图标按钮，依次通过日期选择器和时间选择器设置截止时间，精确到分钟。
- 选中日期和时间后会显示在输入框旁；任务添加完成后，本次选择会自动清空。
- 新任务选择未来截止时间后，“到期提醒”默认开启；无截止时间或时间已过时不可开启提醒。
- 点击任务卡片可编辑任务名称、截止时间和提醒开关；已开启提醒的任务显示绿色铃铛。
- Android、iOS 和 macOS 会在任务到期时发送标题为“任务到期”、正文为任务名称的系统通知，并播放系统默认提示音。
- 首次开启提醒时才申请通知权限；拒绝权限不会阻止任务保存，提醒自动回退为关闭，并可从提示中前往系统设置。
- 完成或删除任务会取消提醒；重新设为未完成或从回收站恢复时，仅为尚未到期的任务重新调度。
- 点击通知会打开待办首页、滚动到对应任务并短暂高亮；任务已经不存在时正常停留首页。
- 输入内容会去除首尾空格；空内容或纯空格不会创建任务。
- 添加成功后显示 SnackBar 提示“已添加”。
- 每条任务使用可点击的 Checkbox 切换完成状态。
- 已完成任务显示灰色文字和删除线，顶部统计同步更新。
- 有截止日期的任务会在标题下方显示 `截止日期：YYYY-MM-DD HH:mm`。
- 截止时间早于当前分钟且任务尚未完成时，日期显示为红色；当前分钟内不算过期，已完成任务也不会标红。
- 支持两种删除方式：
  - 向左滑动任务卡片；滑动背景显示红色和白色垃圾桶图标。
  - 点击任务右侧原有的删除按钮。
- 删除后不再显示遮挡输入框的撤销条，任务会进入底部左侧的回收站。
- 回收站任务保留 7 天，可恢复到删除前的位置；过期任务会自动清理。
- 当任务列表为空时，页面中央显示大图标和“还没有任务,添加一条吧”。
- 添加、编辑、勾选、删除和从回收站恢复操作都会自动保存。
- 使用柔和绿色主题；输入框获得焦点时显示绿色高亮边框。
- 任务使用带圆角和轻微阴影的 Card 展示，卡片之间保留间距。

## 数据结构

任务不使用单独的 `String` 保存，而是使用 `Task`：

```dart
class Task {
  final String id;
  String title;
  bool isDone;
  DateTime? dueDate; // 内存中统一为 UTC
  bool reminderEnabled;
}
```

- `id`：任务的唯一标识，由微秒时间戳和递增序号生成。
- `title`：任务文字。
- `isDone`：任务是否完成。
- `dueDate`：可空的截止绝对时刻；内存和存档中统一使用 UTC，没有设置时为 `null`。
- `reminderEnabled`：是否在截止时刻发送系统通知。

使用 `Task` 是因为字符串只能保存任务文字，无法同时表达完成状态、截止日期和唯一身份。`Task.toJson()` 和 `Task.fromJson()` 负责对象与 JSON Map 之间的转换。

JSON 没有原生 `DateTime` 类型，因此截止时刻使用带 `Z` 的 UTC ISO8601 字符串保存，例如 `2026-07-31T10:30:00.000Z`。固定绝对时刻不会因设备旅行或切换时区而改变；界面展示时再转换成设备当前本地时间。没有截止日期时保存为 `null`。保存后的单条数据类似：

```json
{
  "id": "1752800000000000-0",
  "title": "买菜",
  "isDone": false,
  "dueDateUtc": "2026-07-31T10:30:00.000Z",
  "reminderEnabled": true
}
```

每个任务卡片由 `Dismissible` 包裹，并使用 `ValueKey(task.id)`。这个 key 必须唯一，否则 Flutter 在列表更新和滑动动画期间可能复用、移动或删除错误的任务组件。

回收站使用 `DeletedTask` 保存完整任务、删除时间和原始索引：

```dart
class DeletedTask {
  final Task task;
  final DateTime deletedAt;
  final int originalIndex;
}
```

## 本地持久化

项目使用 [`shared_preferences`](https://pub.dev/packages/shared_preferences) 保存数据：

- 存储键：`tasks`
- 存储值：整个任务数组编码后的 JSON 字符串
- 回收站键：`deleted_tasks`，保存任务、删除时间和原始索引，超过 7 天自动清理
- 排序偏好键：`task_sort_order`，值为 `added`、`dueDate` 或 `completion`
- 升降序偏好键：`task_sort_ascending`，`true` 为升序，`false` 为降序
- 启动读取：`TodoPage.initState()` 通过 `TaskStorage.load()` 异步读取
- 自动写入：添加、编辑、切换完成状态、删除、回收站恢复和排序偏好变化后调用 `TaskStorage.save()`
- 首次运行：没有 `tasks` 存档时，把三条示例任务立即写入本地

`TaskStorage` 负责全部 `shared_preferences` 访问、JSON 编解码、旧数据迁移和首次示例写入；页面 State 只消费 `load()` 返回的快照，并通过 `save()` 保存任务或排序偏好，不直接依赖存储实现。

排序只影响显示：代码在 `build` 使用 `List<Task>.of(_tasks)` 创建副本后排序，从不直接修改 `_tasks`。原始列表始终保持添加顺序，因此删除任务记录的原始索引仍然可靠，从回收站恢复时可以回到正确位置。排序副本使用唯一任务 ID 查询原始索引，同一截止时间或相同完成状态的任务会继续按添加顺序显示，也不会依赖 `Task` 的对象相等规则。升序和降序会应用于当前排序字段；无截止日期任务会绕过方向翻转，始终排在最后。

## 每日一句

`QuoteService` 使用 `http` 包请求 `https://uapis.cn/api/v1/saying`，并把响应中的 `text` 转换为 `Quote`；该接口不返回作者，因此统一显示“佚名”。接口支持浏览器跨域访问，可用于 Flutter Web。页面通过 `FutureBuilder<Quote>` 展示单次请求的加载、成功和失败状态；定时重连由 `TodoPage` 的 `QuoteLoadStage` 状态枚举和 `Timer` 管理，不与展示逻辑混在一起。

- 单次请求超时：8 秒。
- 自动重连间隔：60 秒。
- 最大自动重连次数：3 次。
- 等待及重连期间可随时点击刷新，取消旧 Timer 并把计数清零。
- 页面销毁时会取消 Timer 并关闭 `http.Client`，避免延迟回调访问已经销毁的 State，同时释放网络连接。

`initState` 是 `State` 创建后只执行一次的初始化方法，因此适合启动读取。它本身不能声明为 `async`，所以实际异步工作放在单独方法中，并使用 `async/await` 等待读写完成。

异步操作结束后，如果还需要访问页面或调用 `setState`，代码会检查 `mounted`，避免操作已经销毁的 State。回收站恢复操作也会先执行该检查。

## 到期提醒

`TaskNotificationService` 使用 `flutter_local_notifications` 管理系统通知，并通过 `TaskNotificationScheduler` 接口与页面解耦。页面在启动、恢复前台以及任务发生变化后调用 `reconcile()`；服务会取消本功能尚未触发的旧调度，再按当前任务状态重建队列。

- 仅调度 `reminderEnabled == true`、未完成、有截止时间且尚未到期的任务。
- Android 使用 `inexactAllowWhileIdle`，允许系统为省电做小幅延迟，不申请精确闹钟权限。
- iOS 和 macOS 最多登记最近 64 条有效提醒；其余提醒保留在任务数据中，下次对账时自动补齐。
- 通知载荷保存任务 ID，点击通知后可定位任务；数字通知 ID 使用稳定散列生成，并在极少数碰撞时避让。
- 使用 UTC `TZDateTime` 调度固定绝对时刻，不会在切换时区后按新的墙上时间重算。
- 同一分钟到期的多个任务分别通知，并通过同一通知组归类。
- App 在前台时也展示通知并播放默认提示音。
- Android 清单注册开机广播接收器，设备重启或应用更新后由插件恢复待处理通知。
- 调度和插件异常会被捕获，不影响任务保存；App 再次恢复前台时会重新对账。

### 旧数据兼容与迁移

修改数据结构时必须确认：**用户设备上的旧数据，新代码读得动吗？** 当前加载逻辑包含以下兼容处理：

- 兼容早期直接保存的 `List<String>`，读取后转换为 `Task`。
- 兼容只有 `title` 和 `isDone`、没有 `id` 的旧任务，并自动生成 ID。
- 兼容没有 `dueDate` 的既有任务，读取结果为 `null`，不会影响旧数据。
- 旧版不带时区的 `dueDate` 按首次升级时设备的本地时区解释，并立即转换为 `dueDateUtc`；迁移后始终表示固定绝对时刻。
- 旧任务没有 `reminderEnabled` 时默认关闭提醒，避免升级后突然发送未经用户确认的通知。
- 老版本没有排序偏好时默认“按截止日期 + 升序”；未知排序值也安全回退到按截止日期。
- 无效的截止日期字符串会安全降级为 `null`，不会导致启动崩溃。
- 空字符串 ID 会被视为缺失并重新生成。
- 重复 ID 会被修复，保证 `Dismissible` key 唯一。
- 缺少或无法提供有效 `title` 的损坏记录会被跳过。
- `isDone` 缺失或不是布尔值 `true` 时按未完成处理。
- 旧格式成功读取后会立即写回当前 JSON 结构，完成迁移。
- 回收站中的旧任务也执行相同的 UTC 和提醒字段迁移。
- JSON 格式损坏或根节点不是数组时不会让 App 崩溃，会保留内存中的示例任务。

## 平台支持

项目包含以下 Flutter 平台目录，`shared_preferences` 会自动使用对应的平台实现：

- Android（手机和平板）
- iOS（iPhone 和 iPad）
- Web
- macOS
- Windows
- Linux

到期提醒首版支持 Android、iOS 和 macOS；Web、Windows 与 Linux 暂不调度提醒：

- Android 声明 `RECEIVE_BOOT_COMPLETED`，注册定时通知与开机恢复 Receiver，并启用 Java 17 core library desugaring。
- Android 13 及以上、iOS 和 macOS 会在用户第一次开启提醒时请求通知权限。
- iOS 配置 `UNUserNotificationCenter` delegate，使前台通知能够正常展示。
- macOS 由通知插件注册通知中心 delegate，并沿用现有 App Sandbox 配置。

每日一句需要各平台允许出站 HTTPS 请求：

- Android 主清单声明 `android.permission.INTERNET`，确保正式构建可以联网。
- macOS 的 Debug/Profile 与 Release entitlement 都启用 `com.apple.security.network.client`；只配置 `network.server` 不能授权 App 主动访问接口。
- Web 使用支持 CORS 的 UAPI 接口，可从 `localhost` 等浏览器来源直接请求。

数据保存在当前设备和当前应用的本地存储中，不是云同步：

- 不同设备之间不会自动共享任务。
- 卸载 App、清除应用数据或清除浏览器站点数据后，本地任务可能丢失。

## 环境与安装

项目当前要求 Dart SDK `^3.12.2`，Flutter 版本需要提供兼容的 Dart SDK。

克隆项目后安装依赖：

```bash
flutter pub get
```

如果在其他项目中单独安装持久化依赖，可运行：

```bash
flutter pub add shared_preferences
```

每日一句使用 `http` 包：

```bash
flutter pub add http
```

到期提醒使用本地通知、时区和系统设置依赖：

```bash
flutter pub add flutter_local_notifications timezone app_settings
```

当前使用的主要依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  shared_preferences: ^2.5.5
  http: ^1.6.0
  flutter_local_notifications: ^22.1.0
  timezone: ^0.11.1
  app_settings: ^7.0.0
```

## 运行

查看可用设备：

```bash
flutter devices
```

在已选择或默认设备上运行：

```bash
flutter run
```

也可以指定目标，例如：

```bash
flutter run -d chrome
flutter run -d macos
```

其他平台需先完成对应的 Flutter 桌面或移动端开发环境配置。

## 测试与代码检查

运行组件和数据兼容测试：

```bash
flutter test
```

运行静态分析：

```bash
flutter analyze
```

当前测试覆盖：

- 首次启动显示并保存三条示例任务
- 添加任务、清空输入框和拦截空输入
- 点击按钮与按回车添加任务
- 添加成功 SnackBar
- Checkbox 完成状态、删除线、灰色样式及任务统计
- 日期与时间选择器、精确到分钟的提示和新任务截止时间持久化
- `DateTime?` 的 ISO8601 序列化、反序列化及旧数据缺字段兼容
- 旧截止时间迁移到 UTC、新任务提醒默认值和旧任务提醒默认关闭
- 提醒资格过滤、按到期时间排序以及 Apple 最近 64 条队列上限
- 编辑任务名称、截止时间和提醒开关并持久化
- 通知权限拒绝后回退关闭、系统设置跳转和通知点击任务高亮
- 未完成过期任务日期标红，以及已完成任务不标红
- 三种排序方式、独立升降序、无截止日期排最后和完成状态顺序
- 排序方式与方向偏好持久化，以及显示排序不改变任务 JSON 的原始顺序
- 从本地存档恢复任务
- 空列表引导界面
- 添加、勾选和删除后的自动持久化
- 左滑或按钮删除后进入回收站，不再显示遮挡输入框的撤销条
- 回收站持久化、七天过期清理及恢复原位置
- `Dismissible` key 唯一性
- 旧 JSON 缺少 ID 时自动补全
- 旧字符串数组迁移和损坏记录容错
- 每日一句加载、成功、网络错误和手动刷新状态
- 8 秒请求超时，以及超时、断网和 DNS 等异常触发自动重连
- 手动刷新取消旧 Timer、重置重连计数，以及页面销毁时取消 Timer
- UAPI `text` 响应解析、作者回退为“佚名”和网络异常转换

## 项目结构

```text
lib/main.dart                    App 入口与 MyApp 根组件
lib/models/task.dart             Task 数据模型与 JSON 转换
lib/models/deleted_task.dart     回收站任务、删除时间与原始索引
lib/pages/todo_page.dart         TodoPage 页面、交互与界面状态
lib/services/task_storage.dart   任务持久化、排序偏好与旧数据迁移
lib/services/quote_service.dart  名言模型、HTTP 请求、超时和异常转换
lib/services/task_notification_service.dart  通知权限、调度对账、64 条队列和点击载荷
lib/widgets/quote_card.dart      每日一句 FutureBuilder、状态展示与刷新入口
lib/widgets/task_tile.dart       单条任务的滑动删除、卡片、勾选与编辑入口
lib/widgets/task_input_bar.dart  底部输入框、日期、提醒、回收站与添加入口
test/widget_test.dart            Widget、持久化、兼容与重连状态机测试
test/quote_service_test.dart     名言响应解析、超时和网络异常测试
test/task_notification_service_test.dart  提醒资格与队列上限测试
pubspec.yaml                     Flutter 配置与依赖
android/                         Android 工程及正式网络权限
ios/                             iOS 工程
web/                             Web 工程
macos/                           macOS 工程及沙箱网络权限
windows/                         Windows 工程
linux/                           Linux 工程
```

当前页面状态由 `StatefulWidget` 和 `setState` 管理。所有会影响界面的任务变更都在 `setState` 中完成，随后通过 `TaskStorage` 异步写入本地存储。`QuoteCard`、`TaskTile` 和 `TaskInputBar` 都是 `StatelessWidget`，只接收页面传入的数据并通过回调上报刷新、勾选、删除、编辑、选日期和添加等事件，不持有业务状态。
