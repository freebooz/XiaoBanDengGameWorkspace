# Protocol（公共协议）

一期 HTTP/WSS 使用结构化 JSON 以便快速联调，后续在不改变业务语义的前提下逐步引入 Protobuf。

所有游戏消息都必须携带或可解析出 ProductId、GameId、RuleSetId、RuleVersion、RoomId/MatchId 与 Sequence。

正式游戏命令必须遵循“客户端提交意图、服务端规则校验、服务端产生事件”的权威模式。

## 麻将房规与定缺

- `rule` 包含锁定的 `rule_set_id`、`rule_version`、`options` 和 `rule_key`。规则键由预设版本及规范化后的有效选项生成。大厅目录同时提供 `region`、`seat_count`、`tile_count`、`quick_match`、`dingque` 和 `mutable_options`。
- 贵阳和基础 108 的 `options.version` 为 `1.0.0`。贵阳接炮及抢补杠要求接牌者本人已完成杠。`zunyi_dingque@1.0.0` 的 `options.version` 为 `2.0.0`，好友房可提交 `chicken` 和 `rob_kong`，缺省均开启。遵义试行可在好友房和训练中选择。
- 开局定缺期间，`mahjong_state.phase` 为 `dingque`。本人可选花色通过 `options` 发送。`mahjong_action` 使用 `action` 为 `dingque`、`suit` 为 `wan`、`tong` 或 `tiao`，并携带当前对局和命令编号。四家共享截止时间。已提交者通过自己选项消失确认提交，四家完成后统一收到 `missing_suits`。
- `mahjong_state` 在操作窗口开放时发送 `action_window_id` 和绝对毫秒时间 `action_deadline_ms`。客户端从本次操作依据的快照回传 `action_window_id`。同一次弃牌或补杠的应答共享窗口和截止时间，保存、重连与中间应答均沿用原值。旧客户端可省略窗口编号，服务端仍按当前阶段、座位和截止时间校验操作。
- 行牌时以服务器提供的合法实体 `tile_id` 为准。遵义结算包含胡、豆、鸡与查叫分项，并附可核对收付席位和原因的 `score_transfers`。下一局庄位随好友房保存。
