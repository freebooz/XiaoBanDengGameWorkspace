# 贵阳捉鸡麻将玩法审查

2026-11-16 核对小板凳当前工作区的 Go 对局引擎、房间规则和结算。贵阳预设实行严格先杠。不能吃牌，接炮者本人在本局至少完成一个杠才可胡，自摸无此限制。开启抢补杠时也要求胡牌者本人先完成一个杠。

## 房间使用的规则

| 入口 | 实际规则 |
| --- | --- |
| `guiyang@2.0.0` | 四人、108 张、不可吃。默认开启先杠、抢补杠、鸡分、冲锋鸡和黑八。选择贵阳预设的快速匹配和训练使用这些默认值。 [规则预设](../server/internal/game/mahjong/guiyang/rules.go#L47) [大厅入口](../server/internal/httpapi/mahjong_lobby.go#L242) |
| 新建贵阳好友房 | 可设置鸡分、冲锋鸡、黑八和抢补杠。即使创建请求提交 `requires_kong_to_claim=false`，服务端也会锁为 `true`。关闭鸡分时同时关闭冲锋鸡和黑八。加入房间只能沿用房间确定的版本和开关。 [建房锁定](../server/internal/platform/matchmaking/mahjong.go#L177) [开关归一](../server/internal/game/mahjong/guiyang/rules.go#L67) |
| 恢复已保存的房间 | 好友房恢复时核对并沿用创建时保存的有效配置。对局初始化使用房间给出的规则。因此核对存续旧房是否先杠时需读取该房保存的开关。 [房间恢复](../server/internal/platform/matchmaking/mahjong_restore.go#L122) [对局启动](../server/internal/httpapi/mahjong_realtime.go#L163) |
| `basic_108@1.0.0` | 独立预设，同样不可吃。默认关鸡分，开抢补杠，无杠可点炮胡和抢补杠。 [规则预设](../server/internal/game/mahjong/guiyang/rules.go#L47) |

## 公开规则与版本差异

- 同城游的贵阳规则明确四人、万筒条 108 张和不可吃。平胡接炮通常须有豆，大牌可免豆。2018 年的详表还允许无豆平胡抢补杠、胡杠上炮和报听相关胡牌。2022 年的说明明确支持一炮多响、过碰限制和黄庄查叫。 [同城游玩法详表](https://m.tcy365.com/news/d1558.html) [胡牌规则](https://m.tcy365.com/news/d30722.html) [对局及黄庄](https://m.tcy365.com/news/d25942.html)
- 多乐运营团队同样写明平胡接炮要豆、大胡可免豆，以及无豆平胡可抢补杠或胡热炮。其规则稿将抢补杠按自摸由被抢者一人包三家，另给杠上花和热炮计分，并说明热炮、抢杠和黄庄取消鸡、豆分。应用介绍另外列出摇摆鸡、满堂鸡、二丁拐、三丁拐和遵义玩法。 [多乐胡牌与结算](https://game.xiaomi.com/viewpoint/1291962525_1595497217167_11) [多乐豆分](https://game.xiaomi.com/viewpoint/1291962525_1595496712801_11) [开发者应用介绍](https://app.mi.com/details?id=com.duole.zhuojimjhd.mi)
- 双赢规则正文采用独胜，支持大牌免豆点胡及无豆自摸。其鸡分有金幺鸡、金乌骨鸡和听牌资格。独胜与同城游的一炮多响是两种桌规。 [双赢规则第 2–6 节](https://doublewin.me/guides/mahjong-gz)
- 同城游列暗杠三家各付 2 番、补杠三家各付 3 番。多乐和贵阳麻将桌专利背景列暗杠三家各付 2 番、补杠三家各付 1 番。点豆支付的两种写法使用相反的付款方称谓，双赢明确按动作定义为放杠者单付 1 倍底分。同城游详表的七对是 7 番，专利背景是 8 番。 [同城游豆分](https://m.tcy365.com/news/d35239.html) [同城游牌型表](https://m.tcy365.com/news/d1558.html) [多乐豆分](https://game.xiaomi.com/viewpoint/1291962525_1595496712801_11) [双赢规则第 5 节](https://doublewin.me/guides/mahjong-gz) [CN105709414A 说明书背景技术](https://patentimages.storage.googleapis.com/0c/a3/24/fd8376ffc2c948/CN105709414A.pdf)
- T/TFMJ 3—2024《麻将赛事组织管理规范》6.1 将贵州捉鸡麻将列为原始地方麻将规则。该条文规定赛事选用规则的层级，未制定贵阳捉鸡的统一计分表。 [团体标准 6.1](https://www.ttbz.org.cn/Home/PdfFileStreamGet/c3QsMTE4NDEx)

## 与当前实现逐项核对

| 规则 | 当前项目行为 | 与项目桌规或公开版本的关系 |
| --- | --- | --- |
| 牌张与吃牌 | 万、筒、条各 36 张，庄家 14 张、其他三家各 13 张，发牌后余 55 张。出牌响应只产生胡、碰、明杠和过。行动提交也检查服务端候选，不能吃牌。胡牌判型仍可以使用顺子。 [牌墙](../server/internal/game/mahjong/guiyang/rules.go#L113) [发牌](../server/internal/game/mahjong/guiyang/game.go#L91) [出牌响应](../server/internal/game/mahjong/guiyang/game.go#L261) [提交校验](../server/internal/game/mahjong/guiyang/game.go#L294) | 符合小板凳的四人、108 张、不吃规则。 |
| 点炮先杠 | 服务端检查接牌者本人已有明杠、暗杠或补杠，再检查牌型。别人杠、本人碰和尚未成立的补杠都不能取得资格。 [候选判定](../server/internal/game/mahjong/guiyang/game.go#L269) [已完成的杠](../server/internal/game/mahjong/guiyang/game.go#L494) | 符合严格桌规。公开版的大牌、热炮或报听免豆条件在此桌规下不适用。 |
| 自摸与杠上花 | 当前回合玩家的实际摸牌仍在手中且成牌时，可以自摸。碰完未摸牌不能自摸。杠后补牌同样可以自摸，按普通自摸给分。 [自摸判定](../server/internal/game/mahjong/guiyang/game.go#L204) [补牌](../server/internal/game/mahjong/guiyang/game.go#L511) | 无杠自摸符合项目桌规。多乐等资料另计杠上花。 |
| 明杠、暗杠、补杠 | 明杠要三张手牌加他人弃牌。暗杠要四张同牌。补杠用手中第四张升级已有的碰，无法拿第二次弃牌升级已碰的牌。三种杠都需有余牌可补，补牌取当前牌墙的下一张。每个完成的杠由其他三家各付 1 分。 [动作入口](../server/internal/game/mahjong/guiyang/game.go#L191) [明杠](../server/internal/game/mahjong/guiyang/game.go#L363) [暗杠和补杠](../server/internal/game/mahjong/guiyang/game.go#L406) [杠分](../server/internal/game/mahjong/guiyang/game.go#L503) | 操作区分三种豆。积分和点豆支付方与上述公开版本有差异。 |
| 抢补杠与热炮 | 开启抢杠时，收到补杠申请后、补杠成立前开放胡或过。抢杠者须已有自己的杠并成牌。抢中后原碰保留，拟补的第四张成为胡牌张，拟补杠无杠分也无补牌。抢杠按 `dian_pao` 结算，每位赢家由补杠者单独支付 3 分。杠后第一张弃牌走普通点炮。 [补杠候选](../server/internal/game/mahjong/guiyang/game.go#L421) [响应结算](../server/internal/game/mahjong/guiyang/game.go#L319) [胡牌计分](../server/internal/game/mahjong/guiyang/game.go#L539) | 先杠资格符合项目桌规。与公开版免豆抢杠、按自摸包三家、热炮加分及烧鸡烧豆等有差异。 |
| 牌型与胡分 | 识别四组一将及七对。大对子、清一色及龙七对可按各自结构成牌，结算仍固定自摸三家各付 2 分、点炮者付 3 分。七对要求零副露，三种已完成的杠都占用一组，因此严格先杠版的七对类只能自摸。 [胡牌结构](../server/internal/game/mahjong/guiyang/rules.go#L179) [固定胡分](../server/internal/game/mahjong/guiyang/game.go#L559) | 支持成牌结构。各大牌的独立牌型、番数、倍率和天胡地胡计分与公开版有差异。 |
| 争牌顺序与多响 | 同一窗口待候选人响应完毕或超时后结算。胡优先于杠和碰，同一窗口内提交胡的合资格玩家都胡，按与出牌者或补杠者的座次距离排序。本局随后结束。无胡时明杠优先于碰，同级取近者。 [响应结算](../server/internal/game/mahjong/guiyang/game.go#L294) [超时](../server/internal/game/mahjong/guiyang/game.go#L645) | 同城游公布一炮多响，双赢公布独胜。当前支持一炮多响。 |
| 翻鸡与黑八 | 有人胡且仍有余牌时翻下一张，同花色顺位加一，9 回到 1。幺鸡 1 分，启用黑八时八筒 2 分，翻中已有固定鸡时维持固定鸡值。四座统计手牌、副露和未认领弃牌，接炮或抢杠的胡牌张计入各赢家。鸡分随后两两结差，无听牌条件。 [鸡分结算](../server/internal/game/mahjong/guiyang/game.go#L592) [鸡值](../server/internal/game/mahjong/guiyang/game.go#L716) | 有翻鸡、幺鸡和可选黑八。金鸡加倍、收鸡资格以及手上鸡与内外鸡的选择视公开版本而异。 |
| 冲锋鸡与责任鸡 | 开启后共用一个首张记录，取全桌最先打出的幺鸡或启用的黑八，打出者分别计 2 或 4 分的冲锋鸡值。首张被碰或被明杠时，冲锋鸡值仍算打出者，鸡牌计入接牌者的副露，且打出者向接牌者额外给 1 分。 [冲锋鸡](../server/internal/game/mahjong/guiyang/game.go#L252) [责任鸡](../server/internal/game/mahjong/guiyang/game.go#L363) [鸡分归属](../server/internal/game/mahjong/guiyang/game.go#L611) | 同城游详表以首张幺鸡为冲锋鸡、碰走时另计责任，双赢写有不同的责任处理。当前用固定的首张与支付规则。 |
| 过胡、过碰、报听与黄庄 | 过只结束当前响应。没有同巡过胡或过碰限制，也没有亮牌报听与锁牌。牌墙耗尽且无人胡时进入 `wall_exhausted`，保留已经发生的杠分及责任鸡转分，跳过翻鸡结算。 [响应记录](../server/internal/game/mahjong/guiyang/game.go#L294) [流局](../server/internal/game/mahjong/guiyang/game.go#L520) | 同城游所述过胡、过碰、报听和黄庄查叫未覆盖。多乐和专利背景另有黄庄取消部分积分的规则。 |
| 庄家、骰子和续局 | 每局固定座 0 为庄，三颗骰子决定牌墙开门。好友房可同座续局并记录完局数，支持设置 8、16、24 局上限，达到上限关房。结算保留每局四席分差。 [庄家与骰子](../server/internal/game/mahjong/guiyang/game.go#L91) [局数设置](../server/internal/platform/matchmaking/mahjong.go#L46) [续局状态](../server/internal/platform/matchmaking/mahjong_friend_snapshot.go#L35) | 同城游和专利有换庄、连庄及两颗骰子的描述。当前好友房具备局数管理，尚无按胡牌或黄庄换庄、连庄加番及整桌累计分榜。 |
| 结算分项 | 规则分拆为胡、杠、鸡。引擎检查各座三项合计等于该座总分，且每项四座之和为零，随后发布。旧快照缺少分项时只发布总分。 [分项结算](../server/internal/game/mahjong/guiyang/score_breakdown.go#L18) | 分项与总分可核对。 |

## 本次验证

使用 `golang:1.23-alpine` 本地镜像，运行时为 Go 1.23.12。两次运行均以只读方式挂载当前 `server` 源码，临时容器退出后销毁。

- 使用禁网容器运行 `go test -mod=readonly -count=1 -v ./internal/game/mahjong/guiyang`，32 项顶层测试全部通过。其中 [点炮和抢补杠门槛测试](../server/internal/game/mahjong/guiyang/game_test.go#L113) 各覆盖六种情形：无副露、仅出牌者有杠、胡牌者只有碰、胡牌者已完成暗杠、明杠或补杠。 [无杠自摸](../server/internal/game/mahjong/guiyang/game_test.go#L181) [杠的牌源](../server/internal/game/mahjong/guiyang/kong_source_test.go#L10) [分项及恢复](../server/internal/game/mahjong/guiyang/score_breakdown_test.go#L8)
- `go test -mod=readonly -count=1 -v` 定向运行 `matchmaking` 的 4 项测试和 `httpapi` 的 3 项测试，全部通过。WebSocket 测试从创建、加入、准备到游戏快照确认贵阳好友房的先杠开关始终为真，且加入时无法覆盖。另核验自定义选项版本、好友房续局、局数上限和房间恢复。 [房规锁定测试](../server/internal/httpapi/mahjong_lobby_test.go#L200) [局数上限测试](../server/internal/platform/matchmaking/mahjong_friend_snapshot_test.go#L87) [恢复测试](../server/internal/platform/matchmaking/mahjong_restore_test.go#L14)

上述证据来自当前源码及隔离测试。实际部署服务使用的版本与客户端人工对局尚未核验。
