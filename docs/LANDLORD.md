# 小板凳斗地主

## 产品入口

- 产品清单：`products/landlord/product.json`。
- 使用 `tools/compose-godot.ps1 landlord` 生成 `client/.generated/landlord/project.godot`。
- 运行平台服务端后，在三个客户端分别游客登录、快速对局、准备；三人满座后进入实时牌桌。
- 大厅“单人训练”连接同一规则引擎，对手为两个基础电脑玩家。
- 登录页可设置服务端地址。手机、平板连接同一局域网服务端时使用服务端电脑的局域网地址。

## 三维资源

- `tools/build_landlord_models.py` 在 Blender 中创建牌桌和实心、圆角、有厚度的 63×88×1.3 毫米扑克牌；牌面、牌背各有独立 UV 面。
- 可编辑源文件：`artifacts/landlord_models/poker_card.blend`、`poker_table.blend`。
- Godot 资源：`client/games/landlord/assets/models/poker_card.glb`、`poker_table.glb`。
- `tools/build_landlord_card_faces.ps1` 生成 54 张牌面和 1 张牌背纹理；客户端将每张牌面纹理贴到独立的三维牌模型。
- `tools/validate_landlord_models.py` 重新打开 Blender 源文件和 GLB，检查尺寸、UV、对象层级及纹理数量。

## 玩法范围

- 标准三人 54 张牌；每人 17 张，底牌 3 张。依次叫 0 至 3 分，全员不叫则重新发牌。
- 地主拿底牌并先手；支持单张、对子、三张、三带一、三带二、顺子、连对、飞机及带翅膀、四带二、炸弹、王炸。
- 服务端检查轮次、牌所有权、牌型和压牌大小；底牌在叫地主结束前隐藏，其他玩家手牌始终隐藏到结算。
- 两家不出后归还出牌权；炸弹和王炸翻倍，包含春天和反春天结算。
- 正式对局掉线后可在服务进程存活期间回到原座位。房间和训练状态目前保存在内存，服务重启不恢复。
- 训练电脑玩家采用基础应对策略，正式规则判定仍与房间对局共用服务端引擎。

## 验证

- Go：在 `server/` 运行 `go test ./...`。
- Godot：生成工程后运行导入及 `res://modules/games/landlord/landlord_screen_smoke.gd`，检查三维模型节点和实际渲染。
- Blender：`blender -b --factory-startup --python tools/validate_landlord_models.py`；结果写入 `artifacts/landlord_models/validation.json`。
- Android 包和真实手机、平板设备仍需实际导出与设备验收；当前已验证桌面 Godot 渲染。
