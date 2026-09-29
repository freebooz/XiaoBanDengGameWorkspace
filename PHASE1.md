# 第一期建设说明

## 建设目标

第一期形成可运行、可继续扩展的完整平台闭环：

1. XiaoBanDengGameServer（小板凳统一业务后端）。
2. XiaoBanDengAdmin（小板凳统一运营管理后台）。
3. XiaoBanDengChineseChess（小板凳象棋）：Windows + Android。
4. XiaoBanDengMahjong（小板凳麻将）：贵阳麻将规则集，Windows + Android。

## 验收主链路

`注册/登录 → 产品大厅 → 快速匹配/创建房间 → 进入游戏 → 服务端规则验证 → 事件同步 → 断线恢复 → 结算 → 战绩/回放`。

本轮实现可执行基线。微信 OpenSDK 真机接入、微信商户真实回调联调、短信供应商、生产证书、贵阳麻将最终地方番型、Android正式签名和真实 AI 模型需使用真实业务配置后继续完成，代码中只预留安全接口，不伪造密钥。