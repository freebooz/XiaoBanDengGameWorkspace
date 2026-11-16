# 对局操作资格审查（2026-11-16）

## 结论与证据边界

当前本地 Go 规则源码没有发现正常牌局会生成错误杠选项的问题。客户端原先仅判断对局状态，并直接接受除打出以外的选项，缺少动作与阶段、实体牌、已有副露之间的一致性检查。合成错误快照可以稳定复现“不具备杠条件仍显示并提交杠”；本次已修复这一防御缺口。

没有取得用户报告那次现网错误的私有快照，因此不能认定这是该次现网现象的唯一根因。运行中 API 的只读核验保存在 `.tmp/mahjong-soft-lighting-20261116/live-action-readonly.json`：仍是原镜像 `1bdafe333c2c899bdd0e40856016202d9906c653ec01705ca4a419ab349aef40`，进程健康且未重启。近 48 小时日志仅有两行启动记录，没有具体 `options` 或杠牌动作记录。已有恢复记录关联此镜像与先前的四席钱包联调，但没有完整逐源哈希清单，不能据此宣称当前源码每一行等同于运行中的二进制。

## 修改

- `client/games/mahjong/guiyang/guiyang_3d_screen.gd`：统一由当前已接受的私有快照筛选按钮和提交动作。只有自己的出牌阶段可暗杠、补杠；只有别人的弃牌响应阶段可碰、明杠。暗杠须四个不同实体 ID 的同类暗手牌；补杠须本人暗手第四张及已有三张碰牌；明杠须本人三张暗手牌和最新未被认领的公开弃牌。三类杠均要求可补牌。
- `gang` 仅作 UI 分组，不能成为网络动作。暗杠、补杠使用服务端指定的精确实体 ID；明杠、碰、胡、过沿用现有反应动作的 ID 0 合同。非整数、负数、缺失必要实体、错误阶段和不在手中的 ID 均被拒绝。
- 胡牌资格仍由 Go 规则权威判定，客户端不另写判胡算法。响应时隐藏不能打出的“打出”按钮，真正的“过”保留独立入口。首次只剩过按钮也会重新寻找可点击位置，不覆盖 Logo 和玩家卡。
- 多杠选择回调绑定已接受快照的本地代次及房间、牌局、epoch、阶段、座位。即使服务器 epoch 相同，替换快照和重连也会使旧回调失效；断线立即禁用，待确认命令不能重复提交。
- `client/tests/mahjong_reference_buttons_smoke.gd` 修正此前“反应阶段同时提供暗杠/补杠”的无效测试夹具，将明杠反应与本人多杠选择分开测试。
- 密集布局测试明确覆盖 `_legal_options`，仅用于构造现实牌局无法同时出现的最大压力布局；真实资格由专门动作回归测试覆盖，生产代码没有该覆盖。

## 回归

`client/tests/mahjong_action_legality_smoke.gd` 通过真实入座与私有快照处理链驱动界面，仅替换网络发送边界。覆盖 43 组动作边界，包括三类合法杠的实际触控提交、空选项、无牌墙、重复实体 ID、阶段/座位不符、已碰后接他人第四张的非法杠、合法碰和胡、过的独立触控、旧 epoch、同 epoch 换快照、断线、多杠面板、已结束牌局和待确认动作去重。

修复前失败证据：`.tmp/mahjong-soft-lighting-20261116/action-legality-before.log`。仅过按钮初始位置的独立红灯：`action-pass-only-before.log`。扩展后的 headless 43 组全部通过：`action-legality-expanded-final.log`。另已通过原参考按钮、自动选牌和二次点击出牌回归；日志在同目录。

最新源码的 Godot 4.7.2 Mobile Vulkan 原生桌面 1440×810 回归也通过全部 43 组，退出码 0、脚本及渲染错误 0；触控由 Godot 原生输入事件注入，网络只在本地夹具中捕获。日志：`action-legality-expanded-native.log`。同目录 `action-screenshots/ordinary-no-kong.png` 显示普通手牌只有打出，`legal-discard-kong.png` 显示合法响应的碰、杠、胡和独立跳过，没有不可用的打出按钮。截图使用最新相机代码及带 mipmap 的原始胡桃木纹理；完整密集布局与四种比例由相机专项另行验证。这些不是手机或平板真机截图。

服务端仅新增 `server/internal/game/mahjong/guiyang/reaction_option_contract_test.go`，没有修改生产规则。它验证提交一份响应后，该席 `Options` 和私有快照立即为空；重复响应、无资格席位及错误阶段响应均被拒绝，整个 checkpoint 字节保持不变。独立只读源挂载运行的新测试和全包 32 个测试均通过，日志为 `.tmp/kong-source-audit-20261115/reaction-contract-independent-20261116.log`、`guiyang-independent-20261116.log`。

此次没有重启或部署 API，没有进入或修改真人房间，没有改账号余额，也没有打包安装客户端。原生桌面渲染和人工联机验收分别记录，不互相替代。

## 后续人工排查的诊断入口

增加调试构建专用的 `MAHJONG_ACTION_OPTIONS_FILTERED` 单行 JSON。它仅由已接受的私有快照事件触发：有选项被资格过滤时，每份快照最多输出一行；正常选项、旧快照以及重复查询 `_legal_options` 均不输出。字段固定为 `phase`、`turn`、`own_seat`、`epoch`、`received`、`accepted`，后两项仅列动作子类型。未知字符串统一替换为 `unknown`，不输出完整暗手、账号、token、实体牌 ID 或房间凭据。发行构建直接跳过这段诊断。

增加此诊断后的 headless 回归为 44 组，全部通过。实际日志的 24 条故意错误快照诊断均只有白名单字段，私密哨兵字符串未泄露，脚本错误为 0；证据位于 `.tmp/mahjong-soft-lighting-20261116/action-diagnostic/result.log` 和 `verification.json`。这次仅新增日志与字段测试，没有再次运行 GPU 回归；上述原生 43 组截图保留为动作行为证据。
