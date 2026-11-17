# 麻将管理端实时监视与房间操作

## 联机游戏后台调研

| 平台 | 官方机制 | 小板凳的实现 |
| --- | --- | --- |
| Nakama Console | 可查看权威对局、连接中的玩家及实时对局数据。后台为只读、维护及管理角色分配不同权限。 | 房间详情由麻将服务端投影，单独授予监视和房间操作权限。 [Nakama Console](https://heroiclabs.com/docs/nakama/getting-started/console/) |
| Colyseus Admin | 房间列表与详情展示占用和锁定状态。锁定和解锁有专门命令与审计记录。多进程部署需要共享房间目录和进程间通知。 | 房间详情展示四席状态，提供两项明确的入座命令。操作记录归属于具体的一次房间创建。 [Colyseus Live rooms](https://docs.colyseus.io/admin/rooms) |
| Amazon GameLift Servers | 房间有独立的新玩家接入策略。玩家会话区分已预留、已连接、超时和结束。 | 好友房接入策略与座位占用、准备、连接状态独立。关闭接入后，已入座的玩家仍可准备和重连。 [UpdateGameSession](https://docs.aws.amazon.com/gameliftservers/latest/apireference/API_UpdateGameSession.html) · [客户端与服务端会话处理](https://docs.aws.amazon.com/gameliftservers/latest/developerguide/gamelift-sdk-interactions.html) |
| HTML Server-Sent Events | 事件流支持独立消息边界、心跳注释和断线重连。 | 保留带管理员授权头的 SSE。连接建立及恢复时读取最新快照，之后由房间与玩家状态变化触发推送。 [WHATWG SSE 规范](https://html.spec.whatwg.org/multipage/server-sent-events.html) |

麻将监视采用公开牌局字段白名单。运营可查看房间、局数、对局和保存阶段、连接与准备状态、观战人数、庄家、当前行动和截止时间、余牌及最新弃牌。后台余牌读自实际牌墙计数，在线人数按玩家账号去重，观战人数单独显示。房间满员、等待入桌、对局中和结算按服务端状态显示。好友房、快速匹配与训练房共用监视入口。

## 使用方式

1. 使用有 `platform:read` 权限的账号打开「实时监视」，点房间号查看详情。网页顶部显示连接状态，房间详情随 SSE 同步。
2. 给负责开关入座的运营账号额外配置 `mahjong:manage_rooms`。独立凭据的生成、挂载和轮换见 [管理员凭据配置](MAHJONG_MODERATION_OPERATIONS.md)。
3. 对仍有空位、处于等待状态的好友房，填写操作原因并提交「暂停入座」或「恢复入座」。同一间房的玩家和打开房间列表的玩家通过大厅 WebSocket 即时看到新状态。正常观战继续服从房间及每席许可。
4. 详情显示最近操作的时间、操作员、原因和结果。房间号再次分配时，新旧房间由创建代次区分。网页连接中断时保留已接收数据供查看，恢复连接后用新快照更新可操作状态。

## 鸡蛋管理

从侧栏打开「鸡蛋管理」，输入玩家的完整昵称并核对账号和余额。提交发放时校验已核对的账号，账号归属发生变化时重新核对。成功后显示带请求编号的发放回执和到账余额。此入口需要 `wallet:grant_eggs` 权限。

鸡蛋余额与发放流水一同提交到数据库。提交成功后，目标玩家的大厅连接收到余额变更通知，使用本人的会话立即读取余额。大厅和等候房会更新余额文字。在对局中的座位余额由牌桌服务按最新数据库余额刷新。大厅重连时重新读取当前余额。

## 接口和一致性

| 请求 | 权限 | 用途 |
| --- | --- | --- |
| `GET /api/v1/admin/monitor/stream` | `platform:read` | 初始快照和后续通知。网页工作台与内嵌监视共用一条连接。 |
| `POST /api/v1/admin/mahjong/rooms/{id}/admission` | `mahjong:manage_rooms` | 提交房间代次、期望版本、目标状态、原因和请求 ID。 |
| `GET /api/v1/admin/mahjong/rooms/{id}/operations?room_generation=…` | `platform:read` | 查询指定代次最新 20 条入座操作记录。 |
| `GET /api/v1/admin/wallet/eggs/player?display_name=…` | `wallet:grant_eggs` | 核对唯一有效的玩家昵称、账号和余额。 |
| `POST /api/v1/admin/wallet/eggs/grant` | `wallet:grant_eggs` | 按昵称和已核对账号发放鸡蛋，按请求编号查重。 |

房间状态和操作凭证写入同一个 PostgreSQL 事务。服务端确认提交后，更新房间接入资格并通知 SSE 与大厅 WebSocket。重复投递相同请求可取回原凭证，过期房间或版本要求按最新快照重新操作。原始房间代次应按字符串传递，以保留纳秒精度。

监视连接应路由至持有实时房间的麻将 API。沿用现有数据库迁移与麻将单写者机制，启用管理操作需要新版 API、Web 管理端与具备相应权限的凭据。新版 Godot 客户端支持入座状态提示和大厅余额到账通知。
