# 小板凳麻将域名与 Wi-Fi 联调

当前开发入口固定为 `https://api.xbd.freeboozstudio.test`，对局通过同一域名的 `/api/v1/mahjong/ws` 使用 WSS。客户端不依赖 USB 端口转发。

## 2026-11-15 修复

- 修复临时验证包将服务地址覆盖为 `https://127.0.0.1:32777` 的交付问题。
- 恢复既有 `api.xbd.freeboozstudio.test` 网关，转发至当前麻将服务，保留原数据库与房间。
- AdGuard Home 为局域网提供精确域名解析：`api.xbd.freeboozstudio.test` → `192.168.0.167`。其它项目的域名记录与网关路由保留。
- TLS 使用匹配该开发域名的新证书，客户端显式包含公共测试 CA，继续校验域名与证书链。旧证书私钥已丢失，未关闭验证作为替代。
- Windows 防火墙开放范围仅为 WLAN、本机指定地址与 LocalSubnet 的 HTTPS 443 和 DNS TCP/UDP 53。

## 华硕 RT-AX86U Pro

DHCP 可以继续向手机、平板下发路由器地址 `192.168.0.1` 作为 DNS。路由器需要把查询交给开发机的 DNS，或单独配置该开发域名的本地映射/转发。

现有固件可在「外部网络（WAN）→互联网连接→互联网 DNS 设置」点击「指定」，选择手动 DNS，首选填写 `192.168.0.167`，第二项留空，保存并应用。DHCP 的 DNS 继续使用 `192.168.0.1`。参见 [华硕官方说明](https://www.asus.com/support/faq/1045253/)。

开发机 AdGuard 的上游使用独立的 Quad9 DoH，不回送路由器，避免 DNS 转发循环。此环境要求开发机及其 DNS、游戏服务保持运行；应在路由器为开发机保留 `192.168.0.167` 租约。

## 构建与验收

`tools/export-mahjong-candidate.ps1` 的 `-DevelopmentDomainTest` 分支仅允许既定开发域名及 HTTPS 443，必须提供公共 CA；Android 使用明确的测试包后缀。持久开发签名保存在项目限定目录，随机口令用 Windows 当前用户 DPAPI 保护，不纳入版本库。

设备验证需要使用正常域名解析，记录 HTTPS 返回码、远端地址及 TLS 校验结果，并核对实际登录、大厅和房间连接。安装成功与人工游戏验收分开记录。当前 `.test` 是开发域名，不代表公网正式发布已经完成。
