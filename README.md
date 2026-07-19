# 我的待办

一个使用 Flutter 和 Material Design 构建的跨平台待办 App。支持每日一句、添加任务、设置截止日期、标记完成、删除与撤销，并通过 `shared_preferences` 将任务以 JSON 格式保存在本地，重新启动 App 后任务不会丢失。

## 功能

- AppBar 实时显示任务进度：`我的待办 (已完成/总数)`。
- AppBar 下方显示从每日一句接口获取的随机名言和作者，并可手动刷新。
- 名言请求超过 8 秒会进入自动重连，每隔 60 秒重试一次，连续三次失败后停止；手动刷新会重新开始一轮尝试。
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
- 输入内容会去除首尾空格；空内容或纯空格不会创建任务。
- 添加成功后显示 SnackBar 提示“已添加”。
- 每条任务使用可点击的 Checkbox 切换完成状态。
- 已完成任务显示灰色文字和删除线，顶部统计同步更新。
- 有截止日期的任务会在标题下方显示 `截止日期：YYYY-MM-DD HH:mm`。
- 截止时间早于当前分钟且任务尚未完成时，日期显示为红色；当前分钟内不算过期，已完成任务也不会标红。
- 支持两种删除方式：
  - 向左滑动任务卡片；滑动背景显示红色和白色垃圾桶图标。
  - 点击任务右侧原有的删除按钮。
- 删除后显示“已删除 xxx”，点击“撤销”可将任务恢复到删除前的位置。
- 当任务列表为空时，页面中央显示大图标和“还没有任务,添加一条吧”。
- 添加、勾选、删除和撤销操作都会自动保存。
- 使用柔和绿色主题；输入框获得焦点时显示绿色高亮边框。
- 任务使用带圆角和轻微阴影的 Card 展示，卡片之间保留间距。

## 数据结构

任务不使用单独的 `String` 保存，而是使用 `Task`：

```dart
class Task {
  final String id;
  final String title;
  bool isDone;
  final DateTime? dueDate;
}
```

- `id`：任务的唯一标识，由微秒时间戳和递增序号生成。
- `title`：任务文字。
- `isDone`：任务是否完成。
- `dueDate`：可空的截止日期；没有设置时为 `null`。

使用 `Task` 是因为字符串只能保存任务文字，无法同时表达完成状态、截止日期和唯一身份。`Task.toJson()` 和 `Task.fromJson()` 负责对象与 JSON Map 之间的转换。

JSON 没有原生 `DateTime` 类型，因此截止日期和时间使用标准 ISO8601 字符串保存，例如 `2026-07-31T18:30:00.000`。这种格式跨平台一致，并可通过 `DateTime.tryParse` 安全还原。没有截止日期时保存为 `null`。保存后的单条数据类似：

```json
{
  "id": "1752800000000000-0",
  "title": "买菜",
  "isDone": false,
  "dueDate": "2026-07-31T18:30:00.000"
}
```

每个任务卡片由 `Dismissible` 包裹，并使用 `ValueKey(task.id)`。这个 key 必须唯一，否则 Flutter 在列表更新和滑动动画期间可能复用、移动或删除错误的任务组件。

## 本地持久化

项目使用 [`shared_preferences`](https://pub.dev/packages/shared_preferences) 保存数据：

- 存储键：`tasks`
- 存储值：整个任务数组编码后的 JSON 字符串
- 排序偏好键：`task_sort_order`，值为 `added`、`dueDate` 或 `completion`
- 升降序偏好键：`task_sort_ascending`，`true` 为升序，`false` 为降序
- 启动读取：`TodoPage.initState()` 调用异步 `_loadTasks()`
- 自动写入：添加、切换完成状态、删除和撤销后调用 `_saveTasks()`
- 首次运行：没有 `tasks` 存档时，把三条示例任务立即写入本地

排序只影响显示：代码在 `build` 使用 `List<Task>.of(_tasks)` 创建副本后排序，从不直接修改 `_tasks`。原始列表始终保持添加顺序，因此删除任务记录的原始索引仍然可靠，撤销时可以恢复到正确位置。排序副本使用唯一任务 ID 查询原始索引，同一截止时间或相同完成状态的任务会继续按添加顺序显示，也不会依赖 `Task` 的对象相等规则。升序和降序会应用于当前排序字段；无截止日期任务会绕过方向翻转，始终排在最后。

## 每日一句

`QuoteService` 使用 `http` 包请求 `https://uapis.cn/api/v1/saying`，并把响应中的 `text` 转换为 `Quote`；该接口不返回作者，因此统一显示“佚名”。接口支持浏览器跨域访问，可用于 Flutter Web。页面通过 `FutureBuilder<Quote>` 展示单次请求的加载、成功和失败状态；定时重连由 `TodoPage` 的 `QuoteLoadStage` 状态枚举和 `Timer` 管理，不与展示逻辑混在一起。

- 单次请求超时：8 秒。
- 自动重连间隔：60 秒。
- 最大自动重连次数：3 次。
- 等待及重连期间可随时点击刷新，取消旧 Timer 并把计数清零。
- 页面销毁时会取消 Timer，避免延迟回调访问已经销毁的 State。

`initState` 是 `State` 创建后只执行一次的初始化方法，因此适合启动读取。它本身不能声明为 `async`，所以实际异步工作放在单独方法中，并使用 `async/await` 等待读写完成。

异步操作结束后，如果还需要访问页面或调用 `setState`，代码会检查 `mounted`，避免操作已经销毁的 State。撤销回调也在恢复任务前执行该检查。

### 旧数据兼容与迁移

修改数据结构时必须确认：**用户设备上的旧数据，新代码读得动吗？** 当前加载逻辑包含以下兼容处理：

- 兼容早期直接保存的 `List<String>`，读取后转换为 `Task`。
- 兼容只有 `title` 和 `isDone`、没有 `id` 的旧任务，并自动生成 ID。
- 兼容没有 `dueDate` 的既有任务，读取结果为 `null`，不会影响旧数据。
- 老版本没有排序偏好时默认“按截止日期 + 升序”；未知排序值也安全回退到按截止日期。
- 无效的截止日期字符串会安全降级为 `null`，不会导致启动崩溃。
- 空字符串 ID 会被视为缺失并重新生成。
- 重复 ID 会被修复，保证 `Dismissible` key 唯一。
- 缺少或无法提供有效 `title` 的损坏记录会被跳过。
- `isDone` 缺失或不是布尔值 `true` 时按未完成处理。
- 旧格式成功读取后会立即写回当前 JSON 结构，完成迁移。
- JSON 格式损坏或根节点不是数组时不会让 App 崩溃，会保留内存中的示例任务。

## 平台支持

项目包含以下 Flutter 平台目录，`shared_preferences` 会自动使用对应的平台实现：

- Android（手机和平板）
- iOS（iPhone 和 iPad）
- Web
- macOS
- Windows
- Linux

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

当前使用的主要依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  shared_preferences: ^2.5.5
  http: ^1.6.0
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
- 未完成过期任务日期标红，以及已完成任务不标红
- 三种排序方式、独立升降序、无截止日期排最后和完成状态顺序
- 排序方式与方向偏好持久化，以及显示排序不改变任务 JSON 的原始顺序
- 从本地存档恢复任务
- 空列表引导界面
- 添加、勾选和删除后的自动持久化
- 左滑删除、删除提示、撤销及恢复原位置
- `Dismissible` key 唯一性
- 旧 JSON 缺少 ID 时自动补全
- 旧字符串数组迁移和损坏记录容错
- 每日一句加载、成功、网络错误和手动刷新状态
- 8 秒请求超时、每隔 60 秒自动重连、连续三次失败后停止
- 手动刷新取消旧 Timer、重置重连计数，以及页面销毁时取消 Timer
- UAPI `text` 响应解析、作者回退为“佚名”和网络异常转换

## 项目结构

```text
lib/main.dart                 App 入口、Task 模型、页面、交互及状态管理
lib/quote_service.dart        名言模型、HTTP 请求、超时和异常转换
test/widget_test.dart         Widget、持久化、兼容与重连状态机测试
test/quote_service_test.dart  名言响应解析、超时和网络异常测试
pubspec.yaml                  Flutter 配置与依赖
android/                      Android 工程及正式网络权限
ios/                          iOS 工程
web/                          Web 工程
macos/                        macOS 工程及沙箱网络权限
windows/                      Windows 工程
linux/                        Linux 工程
```

当前页面状态由 `StatefulWidget` 和 `setState` 管理。所有会影响界面的任务变更都在 `setState` 中完成，随后异步写入本地存储。
