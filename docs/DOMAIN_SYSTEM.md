# Freebooz Studio 域名规划

以 `freeboozstudio.com` 为拟用根域名，先确认工作室拥有控制权，再写入发行版。`xbd` 代表小板凳系列，`sslm` 代表神兽联盟。产品落地页用产品域名；服务入口用 `服务.产品.根域名`。

| 正式域名（拟定） | 用途 | 访问范围 |
| --- | --- | --- |
| `freeboozstudio.com` | 工作室官网 | 公网 HTTPS |
| `xbd.freeboozstudio.com` | 小板凳系列与下载页；子页 `/chess`、`/mahjong`、`/landlord`、`/guandan` | 公网 HTTPS |
| `api.xbd.freeboozstudio.com` | 象棋、麻将、斗地主、掼蛋共用的登录、目录、匹配和对局 | 公网 HTTPS/WSS，443 |
| `admin.xbd.freeboozstudio.com` | 小板凳运营后台和管理接口 | VPN 或私有网络，独立登录 |
| `sslm.freeboozstudio.com` | 神兽联盟官网与下载页 | 公网 HTTPS |
| `api.sslm.freeboozstudio.com` | 神兽联盟登录、角色、组队、匹配、关卡分配 | 公网 HTTPS，443 |
| `admin.sslm.freeboozstudio.com` | 神兽联盟运营后台，需要时启用 | VPN 或私有网络，独立登录 |
| `cdn.freeboozstudio.com` | 公共补丁、下载和静态资源，需要时启用 | 公网 HTTPS |

新增小板凳游戏时，沿用统一网关，以现有 `game_id` 和规则标识区分游戏。网站需要新介绍页时，添加对应路径。现有对局路由为 `/api/v1/mahjong/ws`（麻将）与 `/ws`（象棋、斗地主、掼蛋）；协议路径在本地与云端保持一致。开放公网前，匹配和入座应校验登录会话及房间权限。

神兽联盟客户端通过固定域名进入控制面。进入或切换新手村、竞技场时，由分配服务下发目标实例实际可达的地址、UDP 端口和短时入场凭证。公网玩家需可达的 IP 或区域中继域名；内网跳转可下发私网地址。动态映射时，以实际分配的宿主端口为准。数据库、缓存、内部调度和容器间服务使用内网地址或平台服务名。

## 从本地到云端沿用同一份制品

1. 控制正式域名后，客户端统一使用 `https://api.xbd.freeboozstudio.com` 或 `https://api.sslm.freeboozstudio.com`。本机和云入口都监听 `443`，使用相同 API 路径。Godot 从 HTTPS 基址生成 WSS 地址。
2. 开发设备使用 AdGuard Home 的精确域名重写。同一台 Windows 开发机可指向 `127.0.0.1`；手机或其他开发机需使用开发网关的局域网地址，并用局域网可访问的监听端口。公共 DNS 将相同正式名称解析到云负载均衡入口。DNS 只做名称解析，端口统一由网关实现。参见 [RFC 9499：Split DNS](https://datatracker.ietf.org/doc/html/rfc9499#section-6)。
3. 本地和云网关各自持有匹配域名的受信任证书与独立私钥。可用 [ACME DNS-01](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) 为本地网关签发证书，开发机无需开放公网。证书按实际主机签发；若使用通配符，`*.freeboozstudio.com` 不覆盖 `api.xbd.freeboozstudio.com` 这类两级子域名。参见 [RFC 9525：主机名匹配](https://datatracker.ietf.org/doc/html/rfc9525#section-6.3)。
4. 一次构建并复用同一客户端包和服务端镜像。数据库、缓存、密钥和证书由各环境的部署系统注入，开发与生产各自保留独立的数据和会话。在同一台机器切换同名环境时，使用独立的本机测试资料目录，避免复用该域名下缓存的游客会话。发布包不携带本地 DNS 重写、`.test` 地址或测试 CA。
5. 发布前分别从开发网络和外部网络验收 DNS 与证书、登录、真实入座与对局连接；神兽联盟还要验证真实地图准入及客户端与目标专服的版本一致性。

## 当前本机联调

| 本机入口 | 当前状态 |
| --- | --- |
| `https://api.xbd.freeboozstudio.test` | 已在 `127.0.0.1:443` 通过 HTTPS/WSS。Windows 导出包的 PCK 在同版 Godot 测试运行时，以象棋 2、麻将 4、斗地主 3、掼蛋 4 个测试席登录入座并收到服务端对局状态；逐款记录 EXE/PCK SHA-256。原 `:32828` 入口仍可用。 |
| `https://admin.xbd.freeboozstudio.test/monitor` | 页面对本机 HTTPS `443` 返回 200；原 `:32829` 入口仍可用。 |
| `https://api.sslm.freeboozstudio.test` | 本机 `443` 的 `/v1/online/probe` 返回 200，未登录玩家资料请求返回 401。Client 和 Server 完整构建、Cook、Stage 已通过。打包版客户端经 HTTPS 登录后进入新手村，客户端和专服日志均确认入场。主竞技场实例已启动并注册，本次游戏验收范围到新手村。原网关 `:28181` 仍可用。 |

2026-11-15 已将小板凳 `api.xbd.freeboozstudio.test` 的精确重写改为开发机 WLAN 地址 `192.168.0.167`，同时提供局域网 DNS 与 HTTPS 443。共享回环网关 `freebooz-local-https443` 的小板凳路由也已恢复到当前服务，其它项目路由保留。移动端沿用域名，使用正常 Wi-Fi DNS，无需 USB 转发；设备或路由器必须能通过开发 DNS 解析此名称。配置和验收要求见 [麻将 Wi-Fi 联调](MAHJONG_WIFI_DOMAIN.md)。`.test` 为保留测试域名，见 [RFC 6761](https://datatracker.ietf.org/doc/html/rfc6761#section-6.2)，不应当作公网发行域名。

2026-11-14：[Name.com](https://www.name.com/zh-cn/domain/search/freeboozstudio.com) 显示 `freeboozstudio.com` 可注册。现阶段尚未核实工作室已取得控制权，用户确认没有云网关。本机联调未写入 `.com` 的 AdGuard 重写，未配置公网证书，也未验收本地与云端使用同一客户端包。

正式切换先配置 `api.xbd` 和 `api.sslm` 两条精确名称。云网关具备就绪探针、正确证书及路由后，将公共记录指向云负载均衡器。开发侧在 AdGuard Home 将相同两个名称映射到开发网关。先从两侧网络分别核对 DNS 应答，再使用相同客户端包及 SHA-256 验证登录、入座和地图准入。管理入口通过私有 DNS 或 VPN 部署。
