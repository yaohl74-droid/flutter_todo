# my_todo

Flutter 待办清单 App,支持 Android / macOS / Web / Linux。

## 架构

lib/ 按职责分四层:

- `models/` —— 状态与业务事实。TodoModel 是 ChangeNotifier;Task 等数据类的业务判断(如 isOverdue、isEligibleForReminder)写成 getter 放这里
- `services/` —— 存储与系统能力。TaskStorage、ReminderService、TaskNotificationScheduler
- `pages/` —— 页面组装
- `widgets/` —— 纯展示 StatelessWidget,不持有业务状态,通过参数接收数据、回调上报事件

状态管理:Provider(MultiProvider 挂 TodoModel 和 ReminderService)。
build 里用 `context.watch`,回调里用 `context.read`。

## 编码约定

- **异常**:`on Exception catch`,不捕获 Error —— 程序 bug 该崩出来,别伪装成预期错误
- **依赖注入**:类不在内部写死依赖,构造函数留可选参数供测试注入(包括时间:`retryDelay`、`xxxAt(DateTime now)` 这类)
- **派生数据不落库**:排序、筛选、统计等生成副本,不修改 `_tasks` 本身;能算出来的值不单独存字段
- **业务规则收归模型**:同一条判断只写一处,Widget 只管展示
- **异步安全**:`await` 后调 setState 前检查 `mounted`;ChangeNotifier 里用 `_isDisposed` 守卫;Timer 必须在 dispose 里 cancel
- **列表 key**:用数据自身 id,不用 index
- **数据迁移**:改 Task 结构时,`fromJson` 必须兼容旧格式(`?.toString() ?? 默认值`、`tryParse` 而非 `parse`)
- 注释用中文

## 关键机制

- `_taskRevision`:提醒对账版本号,仅活动任务集合/内容变化时递增,回收站清理不递增
- ReminderService 通过 `addListener` 订阅 TodoModel,用 single-flight 合并并发对账请求
- 回收站:删除的任务保留 7 天可恢复

## 提交前

- flutter test # 必须全绿
- flutter analyze # 必须无问题

## 注意

- `node_modules/`、`android/key.properties`、`*.jks` 不进 git
- Web 端调试用固定端口:`flutter run -d chrome --web-port=8080`(不固定的话 localStorage 换端口即失效)
