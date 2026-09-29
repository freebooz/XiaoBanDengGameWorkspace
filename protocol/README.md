# Protocol（公共协议）

一期 HTTP/WSS 使用结构化 JSON 以便快速联调，后续在不改变业务语义的前提下逐步引入 Protobuf。

所有游戏消息都必须携带或可解析出 ProductId、GameId、RuleSetId、RuleVersion、RoomId/MatchId 与 Sequence。

正式游戏命令必须遵循“客户端提交意图、服务端规则校验、服务端产生事件”的权威模式。