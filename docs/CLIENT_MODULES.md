# Godot 客户端模块说明

- Foundation（基础层）：网络、账号、AI协议、支付/钱包接口和通用UI能力。
- GameFramework（游戏公共框架）：Board（棋盘类）、Tile（麻将牌张类）、后续Card（扑克牌类）。
- Games（具体游戏层）：象棋、贵阳麻将等产品差异逻辑。
- Product（产品壳）：产品名、App图标、包名、ProductId/GameId/RuleSetId/RuleVersion。

客户端规则只服务于交互提示。正式多人对局的合法性和结果以Go服务端权威RuleSet为准。