# Codex 审计意见存档(2026-10-09)

> 从 PLAN.md 拆出的两份审计报告**原文**,未做改动。逐条处置结论见 PLAN.md §9 附录。

## 附加报告：Linux 生命周期、GUI 与覆盖网络审计意见（2026-10-09）

> 本报告仅追加审计意见，不改写上方 v3 正文。建议下一次整理版本时，将其中标为“建议纳入”的内容转成正式规则、能力依赖和测试用例。

### A. 审计结论与判定校准

现有计划对用户态文件、软件源、出口、DNS、容器和时间行为的覆盖已经很深，但采集视角主要从“已登录的无头 shell”开始。下面几层仍缺少一等公民的检测面：

1. 引导链、初始配置和服务启动来源；
2. 内核、命名空间、策略路由、netfilter、TC/eBPF 对网络实际作用域的影响；
3. 当前登录会话、终端载体、远程控制链路和用户级自启动；
4. X11、Wayland、显示管理器、输入法、桌面代理和远程桌面；
5. 覆盖网络、零信任连接器、云 VPC 与容器 CNI 的角色区分。

这些补充应同时收紧现有证据语义。工具可以描述“本机当前可观测到的网络边缘、链路、配置或历史痕迹”，不能把它直接等同于操作人的实际地理位置、国籍、意图或某个平台会采取的风控结论。

| 现有类型 | 建议的解释和降级规则 |
|---|---|
| 出口 IP GeoIP | 可作为当前网络边缘的 EXPOSED，结果必须写明 scope=当前网络命名空间，不能写成“用户位于某地”。出口节点、企业网关或 Tailscale exit node 都可能改变它。至少两个独立 GeoIP 源一致时才提高置信度。 |
| 路由 hop、rDNS 城市码、ASN、单个 DNS 污染结果 | 属于链路或解析器线索。单个 anycast、BGP 中转、过时 rDNS、GeoIP 误库均很常见；默认 INFO，满足多锚点、近端 hop、重复观测及独立来源交叉时才升为 SUSPICIOUS。 |
| 时区、locale、输入法、镜像、中文文件名、应用时区 | 都是配置或习惯痕迹，应保持 SUSPICIOUS/INFO，不能作为 EXPOSED。东八区与出口不匹配同样只说明配置不一致。 |
| 不可读、缺失或为空的日志 | 默认 SKIP 或 INFO。容器、最小化系统、systemd journal、权限策略、日志轮转和新装系统均会造成这种状态。只有同一作用域中存在可复核的显式清理证据，且有多个独立来源支撑时，才能报告“日志完整性异常”。 |
| 镜像、云初始化、容器挂载和其他用户文件 | 必须标注 origin=image-builder、host-admin、current-user、other-user 或 unknown。构建者痕迹不能归因于运行时用户。 |
| 已安装的软件 | 只证明安装过。进程、已启用 unit、活动接口、路由、监听 socket 或最近握手才能说明当前运行状态；二者应分别报告。 |

每一条结果建议固定附带以下元数据，而不是只给颜色：scope（host/root-netns/container/current-user/session）、origin（live/config/history/image）、freshness（运行中/已启用/静态残留/时间未知）、confidence（低/中/高）和 redact（是否隐藏标识符）。这样同一个 Tailscale 或远程桌面信号在宿主机、容器和 SSH 会话中不会被误读为同一件事。

### B. 建议纳入的 Linux 生命周期检测面

推荐的采集顺序是：能力与边界判定 -> 引导与初始化 -> 内核与命名空间 -> 网络数据面 -> 系统/用户服务 -> 登录会话与终端 -> 图形桌面 -> 历史痕迹 -> 可选外联探测。这样 C3 的出口、C4 的路由和 C5 的隧道结果可以先知道自己看到的是哪一个网络命名空间。

| 生命周期层 | 建议检测面 | 输出原则 |
|---|---|---|
| 固件与引导 | UEFI/BIOS 启动模式、当前 boot entry、GRUB/systemd-boot 配置、/proc/cmdline、initramfs 是否存在及其网络/代理/时区注入参数、kernel command line 中的 console、ip=、rd.*、systemd.setenv 等。 | 主要 INFO；无 EFI、bootctl、efibootmgr、lsinitrd/lsinitramfs 时 SKIP。只提取分类和值类型，不读取密钥、完整 token 或启动介质内容。 |
| 首次配置与启动 | cloud-init、Ignition、systemd-firstboot、OEM provisioning、rc.local、systemd 默认 target、已启用的 system/user unit、drop-in、timer、cron、at、XDG autostart、显示管理器。 | 将设置归因于镜像/管理员/当前用户；自动启动远程工具、隧道和代理仅报告为活跃环境事实。 |
| 内核与隔离 | 内核版本和可用配置、LSM（SELinux/AppArmor/landlock）、cgroup v1/v2、PID/mount/user/net namespace、rootless 容器、capability 边界、/proc/1 身份和挂载传播。 | 用于解释可见性和降级，不把安全策略或 namespace 本身判为隐藏。 |
| 内核网络数据面 | 所在 netns 的接口类型（物理、veth、bridge、bond、VLAN、VRF、tun/tap、WireGuard、CNI）、IPv4/IPv6 route table all、ip rule、fwmark、sysctl forwarding、nftables/iptables、TC、XDP/TC/cgroup eBPF。 | 路由器、透明代理、分流或 VPC 角色应为 INFO；只有已有地域规则命中时才交给 C4/C5 做地域解释。 |
| 网络配置控制面 | NetworkManager、systemd-networkd、netplan、ifupdown、dhclient、PPP、ModemManager、resolved 的 per-link DNS/domain、DNS search domain、PAC/代理设置。 | SSID、连接 UUID、Wi-Fi 密码、DHCP client-id 和完整租约属于敏感数据，不输出；只报告网络类型、激活状态和脱敏后的域类别。 |
| 物理无线和蜂窝（可用时） | iw reg get、已连接无线接口类型、ModemManager 的服务小区/漫游状态、MCC/MNC 的国家映射。 | 仅物理机且权限允许时启用。漫游、错误监管域和离线 modem 很常见，因此只作为 INFO/SUSPICIOUS，不单独定位人。 |

建议新增四个正式类别，避免把上述内容散落进 C1、C4、C12、C13 和 C14 后失去生命周期语义。

### C. 建议新增类别

#### C16 boot — 引导、首次配置与服务启动

- 平台能力：UEFI/BIOS、bootloader、initramfs、cloud-init/Ignition/systemd-firstboot、systemd 是否为 PID 1，以及每项可读性。
- 当前启动事实：kernel command line、当前 target、启动失败 unit 摘要、网络和时间服务启动顺序。
- 持久化启动面：system unit、unit drop-in、user unit、timer、cron/anacron/at、rc.local、XDG autostart、display manager 的配置。
- 归因重点：镜像注入的 locale、时区、DNS、代理、镜像源、隧道和远程控制工具必须标为 image/admin provenance；不能默认归因给交互用户。
- 结果等级：绝大多数为 INFO；功能或路径不可用时 SKIP。只有已有的本地地域规则命中时才交给 C8/C9/C12 产生可疑提示。

#### C17 kernel — 内核、命名空间与网络数据面

- 采集当前进程、PID 1 和可见进程的 PID/mount/net/user namespace 关系；容器内要明确“当前结果仅代表此 netns”。
- 枚举接口和链路类型：lo、物理 NIC、veth、bridge、bond、VLAN、VRF、macvlan、ipvlan、tun/tap、WireGuard、CNI 与虚拟化接口；不要仅凭接口名推断产品。
- 读取 IPv4/IPv6 的所有路由表、ip rule、fwmark、默认路由、局部路由与 source-based routing。现有 C4 仅看默认网关会遗漏代理栈、出口 node 和多 WAN 分流。
- 将 nftables、iptables、ipset、TC qdisc/filter、XDP/TC/cgroup eBPF 分开报告。透明代理可能由任一层实现，不能只查 REDIRECT/TPROXY。
- 读取 net.ipv4.ip_forward、net.ipv6.conf.all.forwarding、rp_filter、IPv6 disable 等，只用于识别 router/subnet-router/exit-node 条件；转发开启不是地域信号。
- 对 bridge、veth、Cilium、Calico、Flannel、Weave、OVS 等 CNI/overlay 先做平台归类，避免把 Kubernetes VPC 路由误判为用户的 VPN。

#### C18 session — 用户、会话、终端与远程入口

- 使用 loginctl、who、w、utmp/wtmp（可读时）、sshd/sshd 子进程、进程树、TTY、环境变量和 socket，建立“当前交互会话”而不是只读取 SSH_CONNECTION。
- 会话来源建议至少区分：本地 VT/console、SSH、Mosh、Tailscale SSH、serial console、hypervisor console、AWS SSM、GCP IAP、Azure Bastion、VS Code Remote、JetBrains Gateway、Web terminal（ttyd/wetty/gotty/shellinabox/code-server/openvscode-server/Jupyter）和未知。
- 终端载体建议识别 terminal emulator、tmux/screen、shell、sudo/su、SSH forwarding、X11 forwarding、Wayland remote socket。只报类型和活动状态，不显示原始命令、代理目标、完整环境变量或终端标题。
- 用户级持久化应检查 ~/.config/systemd/user、~/.config/autostart、shell rc、tmux/screen 服务，以及与当前会话同 UID 的代理/隧道/远程工具。
- 所有远程入口本身均为 INFO。它们可以解释出口、GUI、时间行为和环境变量的观察范围，不能作为“规避”或某服务风险的判定。

#### C19 gui — 图形会话、输入与远程桌面

- 图形会话判定：logind seat/session、DISPLAY、WAYLAND_DISPLAY、XDG_SESSION_TYPE、XDG_CURRENT_DESKTOP、XAUTHORITY、XDG_RUNTIME_DIR、Xorg/Xwayland/Wayland compositor、gdm/sddm/lightdm；单独识别 SSH X11 forwarding 和 WSLg。
- 桌面环境：GNOME、KDE、XFCE、Cinnamon、MATE、i3/sway/hyprland 等的当前会话与用户配置。读取 dconf/gsettings/KDE 配置时只取键盘、输入法、语言、时区、代理模式等字段，不导出整个数据库。
- 输入层：XKB layout/variant、IBus/Fcitx/Rime/Sogou/系统输入源、桌面 locale、浏览器 accept-language。它们和 C8/C9 的静态包/字体信号交叉，但仍是软信号。
- 远程桌面/串流：区分已安装、已启用、正在监听、正在建立会话四种状态。候选包括 xrdp、GNOME Remote Desktop、Vino、wayvnc、x11vnc/TigerVNC、Krfb、NoMachine、RustDesk、AnyDesk、TeamViewer、Sunlogin、Chrome Remote Desktop、Parsec、Sunshine/Moonlight，以及 UU 远程的可维护产品别名表。
- 对“UU 远程被外部服务检测”的案例，工具只应把远程桌面/云机/串流客户端或服务端的存在与活动状态列为环境上下文。不要从该案例推导产品级封禁规则，也不要将远程控制软件本身标成可疑。
- 禁止启动浏览器、注入 WebRTC 脚本、截图、读取剪贴板、键盘事件、窗口内容或远程桌面画面。C7 的主动 STUN/WebRTC 只能在显式开关下运行。

### D. C5 应扩展为“代理、隧道、覆盖网络与私有网络连接器”

原 C5 已覆盖传统代理和 WireGuard 轮廓，但应把“是否使用覆盖网络”与“是否经其改变默认出口”明确分开。所有下面的发现默认 INFO，且必须隐藏 peer、tailnet、组织、token、证书、完整私网 CIDR 和控制端地址。

| 产品/层 | 被动或本地检测 | 可报告的角色 | 不能据此推断的事 |
|---|---|---|---|
| Tailscale / Headscale | tailscaled/tailscale0、systemd unit、路由、DNS、netfilter 链；可选调用本地 daemon 的只读 status JSON。配置文件只看是否被显式引用，绝不读取 state、auth key 或控制面凭据。 | 已安装、运行中、使用 exit node、声明 exit node、声明/接受 subnet route、MagicDNS/DNS 接管、Tailscale SSH。CIDR 只报数量或脱敏摘要。 | tailnet 成员身份、操作人位置、出口实际所在位置以外的个人位置。 |
| Cloudflare Tunnel | cloudflared 进程/unit、config 路径、credentials-file 是否存在、ingress/route 条目数、监听 metrics socket；不读取 tunnel credential JSON 或 token。 | 本机是发布应用/私网的 outbound connector，服务是否开机启动，是否存在 ingress 或 private route 配置。 | Cloudflare Tunnel 本身不改变服务器发起连接的默认路由，不能把它当 VPN 出口或地域证据。 |
| Cloudflare One Client / WARP / Mesh | warp-svc、warp-cli、相关 unit、虚拟接口、路由、DNS 与本地配置；识别 Cloudflare Mesh（旧称 WARP Connector）作为独立角色。 | 客户端、WARP、Mesh node、私网路由或设备间连接的环境事实。 | 不能据接口或 Cloudflare ASN 推断用户地理位置。 |
| 通用 mesh/VPN | WireGuard、OpenVPN、strongSwan/IPsec、SoftEther、ZeroTier、Nebula、NetBird、Netmaker、Tinc、Innernet、Headscale、Teleport 等进程、unit、接口、路由和最近本地状态。 | 安装、运行、数据面接口、默认路由是否受影响、subnet/router/connector 条件。 | tun0、wg0 或 UDP 端口单独不能准确说明具体产品或用途。 |
| 云 VPC、容器网络 | Cilium、Calico、Flannel、Weave、OVS、Docker/Podman/CNI、Kubernetes service account、云 metadata route。 | pod、节点、VPC、CNI 或 host-network 作用域；当前输出可能继承宿主或 sidecar 网络。 | 不得把 RFC1918、100.64.0.0/10 或 overlay 地址自动解释为中国网络或代理。 |

Tailscale 的 exit node 会承载客户端的互联网流量，subnet router 只提供指定私网可达性，二者不应混为一项。Cloudflare Tunnel 是从私网主机到 Cloudflare 的 outbound-only connector；Cloudflare Mesh 适合双向私网连通。这些角色差异是 C3、C4、C5 解释结果的前提。

### E. 对既有类别的补充建议

| 类别 | 建议补项 |
|---|---|
| C1/C2 | 把 boot source、cloud-init、Ignition、machine-id/hostname 的来源和 namespace scope 纳入平台信息。虚拟化 guest agent、hypervisor console、cloud metadata 可解释远程登录和配置归属。 |
| C3 | 分别记录 IPv4/IPv6 的请求所处 netns、是否经过当前环境代理和查询时间；不得为取得“真实 IP”而绕过用户现有代理、路由或策略。 |
| C4 | 增加 ip rule、route table all、VRF、network namespace、TC/eBPF、NetworkManager/networkd 的 per-link 配置。活跃对端、known_hosts 和 SSH 配置中的 IP 发送到第三方 GeoIP API 前，需单独显式 opt-in。 |
| C5 | 按上节扩展；“存在 VPN/mesh”固定为 INFO，“默认路由确实经 exit node/代理改变”也先是 INFO，再由 C3 观察真实网络边缘。 |
| C6 | 除 resolv.conf 外检查 resolved per-link DNS/domain、NetworkManager、dnsmasq/unbound、DoH/DoT、Tailscale MagicDNS、WARP DNS。污染探测须使用受控域名或已验证基线并标明其仅反映解析路径。 |
| C7/C15 | 将浏览器检查分为 profile 静态配置、当前运行浏览器和显式主动 probe；默认只统计，不读 URL、查询词、书签标题、扩展内容或 WebRTC 候选地址。 |
| C8/C9/C10 | 明确当前用户默认范围。跨用户家目录、完整 shell history、Git remote、浏览器历史和邮件/GPG 标识需通过明确开关，输出仅给计数与类别。 |
| C11 | 时间推断需标明样本归属、时钟来源和采样不足；历史、日志、Git 和 AI 会话都可能来自 CI、镜像、共享帐户或自动化，不能将其升级为位置证据。 |
| C12 | 将“不可读日志”“SSH 环境变量缺失”“服务进程 TZ/LANG 不同”改为 capability/上下文解释。sudo、su、tmux、容器、service manager 和 PAM 都可造成这些正常差异。 |
| C13 | 增加物理无线/蜂窝能力，但将监管域、MCC/MNC、蓝牙名称与硬件品牌保留在弱证据或信息层。 |
| C14 | 增加 socket activation、systemd user service、timer、XDG autostart、dbus service、远程桌面/云 console/overlay daemon 的活动状态。 |

### F. 采集、隐私和外联边界

建议把执行模式拆成以下层级，并将模式写入每一条结果：

1. passive（默认）：只读本机 proc/sys/run/配置元数据，绝不修改路由、DNS、服务、浏览器或登录状态。
2. local-daemon：对本机 Unix socket/CLI 做只读查询，例如 Tailscale 本地状态；查询失败降级，绝不触发登录、注册、重连、控制面枚举或配置刷新。
3. active-probe（显式开关）：公网出口 API、traceroute、DNS 污染、STUN/WebRTC 受控探测。报告外联目标、时间、所用 netns 和代理路径。
4. sensitive-history（显式开关）：历史记录、浏览器统计、跨用户目录、已建立连接/known_hosts 的第三方 GeoIP。默认关闭。

无论模式为何，均不得读取或输出私钥、密码、Cookie、浏览器页面内容、剪贴板、按键、聊天文本、完整命令历史、Tailscale state/auth key、cloudflared credential/token、WARP enrollment 数据、Wi-Fi 密码、DHCP client-id、完整 peer 名单或完整私网拓扑。掩码应默认开启；需要排障时只允许本地明确的 reveal 选项，并在输出中提醒其敏感性。

外联 API 的默认最小集合应仅为本机自身的公网出口地址。把 ESTABLISHED 对端、SSH known_hosts、Git remote 解析出的地址批量发送到 ip-api，会泄露用户正在连接的服务图谱；该能力即使保留，也应在独立开关和明确输出提示之后才执行。

### G. 测试矩阵与里程碑建议

新增规则应以 fixture 和隔离实验机测试，而不是以真实用户目录或真实 tailnet 作为测试数据。最少覆盖：

1. 物理无 GUI、VM、特权容器、rootless 容器、Kubernetes pod、WSL、WSLg；
2. systemd 与非 systemd PID 1、SELinux/AppArmor 拒绝读取、最小镜像、无 journal/无 wtmp；
3. X11、Wayland、SSH X11 forwarding、普通 SSH、tmux/screen、VS Code Remote、Web terminal；
4. 远程桌面客户端与服务端的 installed/enabled/listening/active 四态；
5. Tailscale 普通节点、exit-node client、advertised exit node、subnet router、Tailscale SSH、Headscale；
6. cloudflared published app/private route、Cloudflare WARP client、Cloudflare Mesh node；
7. policy route、透明代理、CNI overlay、双栈不同出口和多 network namespace。

落地顺序建议为：先实现 scope/origin/freshness/redact 通用字段和不可读即 SKIP 的框架修正；再做 C16/C17 的被动采集；随后扩展 C5 的 overlay/VPC 角色；最后实现 C18/C19 与显式 active-probe。这样 GUI、远程连接和 mesh 的解释会建立在正确的主机/容器/会话边界之上。

### H. 资料核验

- Tailscale CLI、subnet router、exit node 与本地配置：<https://tailscale.com/docs/reference/tailscale-cli>、<https://tailscale.com/docs/features/subnet-routers>、<https://tailscale.com/kb/1654/tailscaled-config-file>
- Cloudflare Tunnel 的 Linux service、私网 connector 与路由：<https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/as-a-service/linux/>、<https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/private-net/>
- Cloudflare Mesh（原 WARP Connector）的双向私网连接定位：<https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-mesh/>

---

## 附加报告二：以“实际使用地区”为目标的加法审计（2026-10-09）

> 本报告在现有 C1--C19、五态语义、已有 EXPOSED 规则和上一份附加报告之上继续增加检测面。既有规则全部保留；新增内容只增加证据来源、关联关系、输出字段和更强的命中路径，不删除或降低既有检查的覆盖范围。
>
> 本项目的主目标应明确为：尽可能判断当前或近期实际交互使用者是否在陆港澳，而不是只判断被审计 Linux 工作负载的公网出口在哪。两者重合时可相互增强；海外云机、跳板机、远程桌面、SSH、VPC、Tailscale、Cloudflare Tunnel/Mesh、企业代理和手机控制时，两者经常不同，必须分别采集后再关联。

### I. 新增的“实际使用地区”证据模型

建议保留现有五态作为单条规则的风险输出，再增加一条并行的 usegeo 证据链。每个结果都增加以下标签：

subject（证据对象）、scope（采集作用域）、path（链路形态）、live（当前/历史）、link（能否关联到交互会话）、family（独立性分组）。

| 证据对象 | 含义 | 典型来源 | 与实际使用者的关系 |
|---|---|---|---|
| host | 被审计的 OS/VM/容器 | DMI、内核、服务、文件、云 metadata | 只说明运行环境，不能自动等同于操作者。 |
| host-egress | 该网络命名空间当前对公网的出口 | C3 IPv4/IPv6、默认路由、代理/exit node | 保留现有 EXPOSED 规则；它是工作负载出口证据。 |
| live-session | 当前登录或控制本机的会话 | logind、sshd、RDP/VNC、PTY、进程树、socket | 能直接连接到人机交互，是实际使用地区的主证据对象。 |
| controller-net | 当前控制端在链路上可见的网络端点 | SSH/RDP/VNC/Mosh/远程工具的活跃 peer、可信代理头 | 直接链路时可作为操作者网络的强证据；经 relay/mesh 时单列为中继。 |
| local-access-net | 本机所在物理接入网络 | Wi-Fi、WWAN、GNSS、DHCP、PPPoE、家庭/企业网关 | 当存在本地 console/seat 会话时，是实际使用地区的重要补强。 |
| relay-overlay | 中继、VPN、mesh、VPC、反向隧道 | Tailscale、DERP、WARP、cloudflared、WireGuard、反向 SSH、CNI | 解释为什么 host-egress 或 socket peer 可能不是操作者网络。 |
| history-user | 当前用户或同一身份的历史痕迹 | C8--C11、应用状态、登录/交互时间 | 用于增强持续性，不与实时链路混淆。 |

输出时把同一个 live-session 作为主键。例如：

~~~text
[EXPOSED] [usegeo/session/S-42] subject=controller-net path=direct-ssh live=now
  活动 SSH 会话的 TCP 对端归属 CN；关联到 uid=1000 的 pts/1 与当前 shell。

[EXPOSED] [usegeo/local-seat/S-7] subject=local-access-net path=physical-wlan live=now
  seat0 图形会话处于活动状态；关联 Wi-Fi 接入、蜂窝 PLMN 或 GNSS 的地区证据指向 HK。

[INFO] [usegeo/topology/S-19] subject=relay-overlay path=cloudflare-tunnel live=now
  当前服务经 cloudflared 入站；本机 socket 对端是本地 connector，不能把它当作控制端地址。
~~~

这不是替代现有 C3/C4/C5，而是把它们纳入“操作者--中继--工作负载”的链路图。已有“出口在陆港澳”“DNS 污染”“路由经中国”的 EXPOSED 仍照常输出；新增链路让报告同时能发现“云机出口在美国、当前 RDP/SSH 控制端在香港”这一类实际使用场景。

### II. 新增 C20 usegeo — 实际操作者、会话链与地区融合

建议建立 C20，并允许它读取 C1--C19 已采集的结构化结果。C20 不重复低层采集，而是建立交互会话图、给所有信号绑定主体并产出“实际使用地区”结论。

| 子项 | 新增检测 | 关键关联条件 | 可增强的结论 |
|---|---|---|---|
| u0 采集者边界 | 记录脚本自身 PID、UID、TTY、父进程、PID/mount/net/user namespace、container/VM/WSL 身份、能力与可见进程集合。 | 所有后续项继承 scope；必须知道脚本是在宿主、容器、SSH shell 还是 user service 中运行。 | 防止把容器、跳板或受限 shell 的局部观察误判为整机事实。 |
| u1 活跃会话图 | 合并 loginctl list-sessions/show-session、who、w、utmp、sshd 子进程、PAM/journal、TTY、UID、session leader、cgroup。 | 同 UID、同 leader 或 parent/child、同 pts、同 socket inode 的记录合为一个 session。 | 确认“谁正在交互”，并区分本地 seat、SSH、远程图形、service/cron/CI。 |
| u2 直接远程入口 | 对 sshd、mosh-server、xrdp、VNC、NoMachine、RustDesk、AnyDesk、TeamViewer、Sunlogin、ToDesk、Chrome Remote Desktop、Parsec、Sunshine/Moonlight、web terminal 等运行进程，关联监听 socket、已建立 socket 和会话日志。 | socket -> daemon child -> uid/PTY/desktop session 的完整链才标作活动控制；仅安装或监听仍保留现有 INFO。 | 活动 direct peer 的 IP/ASN/GeoIP 可成为 controller-net 证据。 |
| u3 中继识别 | 为每个远程会话标记 direct、trusted-proxy、jump-host、relay、mesh、reverse-tunnel、cloud-console 或 unknown。 | 从接口、路由、进程参数、daemon 状态、socket 对端和日志共同判断。 | 避免把跳板、DERP、厂商 relay、CDN、Cloudflare connector 或 VPC 网关误认成操作者。 |
| u4 本地 seat 与物理交互 | 检查 logind Remote/Seat/Type/Class/State/IdleHint、VT、display manager、X11/Wayland session、当前 desktop leader、物理输入设备类别和虚拟输入设备存在性。 | seat0 + active GUI/VT + 同一 UID 的前台会话建立本地交互链；不读取键盘或鼠标事件内容。 | 让本地无线/蜂窝/GNSS 证据可以归因到当前操作者，而非只归因给闲置主机。 |
| u5 GUI 远控链 | 识别 ScreenCast、RemoteDesktop portal、PipeWire、uinput、XTest、Xvnc、Xpra、wayvnc、RDP/VNC session、virtual display、capture/encoder 进程。 | 远控服务、桌面 session、输入/捕获路径和活跃连接同一时间出现。 | 判断“当前 GUI 由远端操控”的可信度，并继续寻找控制端网络或客户端元数据。 |
| u6 终端与开发远控 | 识别 SSH/Mosh、tmux/screen、VS Code Remote、code-server/openvscode-server、JetBrains Gateway、Jupyter、ttyd/wetty/gotty/shellinabox、Teleport、AWS SSM、GCP IAP、Azure Bastion/serial-console agent。 | 进程树、PTY、监听/已建立连接、认证日志和目标用户一致。 | 识别用户实际在远端终端、浏览器终端、IDE 或云管理面操作。 |
| u7 本地接入地区 | 关联当前有交互的 local seat 与 Wi-Fi、WWAN、GNSS、DHCP/PPP、默认网关、DNS search domain、captive portal、NTP/DHCP option 等。 | 必须是当前已关联接口或当前 local seat 使用时段的近期记录；历史 lease 单列。 | 增加“人在本机前”的地区证据，不受云机出口影响。 |
| u8 会话披露元数据 | 在不读取交互内容前提下，从服务日志/协议元数据提取客户端地址、键盘布局、locale、时区、显示类型、客户端类型、RDP/VNC/SSH 产品名、窗口尺寸等可用字段。 | 元数据要绑定到正在活动的会话；SSH 的 LANG/LC_* 只在对应 sshd child 的环境中使用。 | 作为控制端地区的辅助线索，特别适合 RDP/SSH/远程桌面。 |
| u9 时间与身份延续 | 将 C11 交互簇、login session、GUI idle 状态、远控连接开始/结束、网络切换、屏幕锁定/解锁、最近用户服务活动按 UID 关联。 | 仅同一 UID/会话的时间窗口内融合，默认实时窗口 30 分钟、近期窗口 7 天、历史窗口 90 天。 | 避免把镜像构建、CI、其他用户或数月前的痕迹归给当前操作者。 |
| u10 融合与矛盾 | 同一主体的实时证据先融合，再以近期/历史痕迹补强；输出链路断点和冲突。 | IP GeoIP、ASN、rDNS、同一条 traceroute 属同一 network-family，只算一次独立网络来源。 | 多个独立证据都指向陆港澳时提高实际使用地区结论；代理、relay、不同用户/namespace 造成冲突时保留全部链。 |

建议在现有统计结尾额外输出：

~~~text
实际使用地区视图
- 当前本地交互会话：<地区/未知>，证据链数 N，最高等级 EXPOSED/SUSPICIOUS/INFO
- 当前远程交互会话：<按 session 分组的地区/未知>，direct/relay/mesh 分类
- 被审计工作负载出口：IPv4 <地区>，IPv6 <地区>
- 物理接入网络：Wi-Fi/WWAN/GNSS <地区/不可用>
- 无法跨越的链路断点：Cloudflare Tunnel / relay / jump host / container netns / 云控制台
~~~

### III. 从引导到交互的完整增量清单

下表按 Linux 实际运行链路展开。它补充此前以无头 shell 为主的思路；每一行既列出可采集面，也列出它如何服务于“实际使用者地区”而不是只服务于主机画像。

| 层次 | 建议新增采集面 | 作用于实际使用地区的方式 |
|---|---|---|
| 固件与启动入口 | UEFI/BIOS、Secure Boot/MOK、boot entry、GRUB/systemd-boot、kexec、/proc/cmdline、initramfs 网络/代理/时区参数、serial console、kernel console=。 | 识别云镜像、串口控制台、网络启动和早期注入来源；为“这是物理终端还是云主机/无人值守节点”提供背景。 |
| 初始配置 | cloud-init datasource、user-data/vendor-data、Ignition/Butane、systemd-firstboot、Anaconda/Kickstart、autoinstall、preseed、OEM/provisioning、ostree/immutable deployment。 | 归因 locale、时区、镜像、代理、SSH key、远控 agent、tunnel 和默认用户究竟来自镜像/管理员还是当前操作者。 |
| PID 1 与系统启动 | systemd/default target、unit/drop-in、generator、socket activation、timer、path unit、rc.local、init.d、cron/anacron/at、tmpfiles、udev rule、NetworkManager dispatcher、cloud-final。 | 找出会在启动时建立代理、隧道、远控、虚拟显示或网络重写的持久化入口。 |
| 内核与虚拟化 | DMI、CPUID/Hyper-V/KVM/Xen/VMware/VirtualBox/QEMU、virtio、WSL、内核 cmdline、模块、GPU/DRM、HID、Wi-Fi、WWAN、GPS 驱动。 | 建立物理机、云 VM、桌面 VM、WSL、容器的能力边界；无线/蜂窝/GNSS 硬件是本地实际接入的前提。 |
| namespace/cgroup/sandbox | PID/mount/net/user/UTS/IPC namespace、cgroup v1/v2、systemd PrivateNetwork=、bwrap/Flatpak/Snap、rootless 容器、mount overlay/bind mount、可见 /proc 范围。 | 防止在容器或沙箱中把宿主/其他 netns 的不可见网络和登录历史当成缺失或伪造。 |
| 路由与数据面 | 所有 IPv4/IPv6 route table、ip rule、fwmark、VRF、source route、default route、NAT/conntrack、nftables/iptables/ipset、TC、XDP、cgroup eBPF、forwarding/sysctl。 | 找到每个 session/UID/mark 实际走的出口，识别透明代理、分流、exit node、subnet router 和多 WAN，而不只看 main table。 |
| 网络控制面 | NetworkManager、systemd-networkd、netplan、ifupdown、wpa_supplicant/iwd、dhclient、PPP、ModemManager、resolved per-link DNS/domain、PAC/WPAD、DoH/DoT。 | 提取当前关联接口和地区线索；同一台设备可同时有 Wi-Fi、蜂窝、VLAN、VPN 和容器网络，必须按接口/会话绑定。 |
| 接入网络与射频 | 当前 Wi-Fi BSSID/SSID/频段/监管域、AP OUI、已关联状态、DHCP server/option、PPPoE AC name、WWAN 注册状态/MCC/MNC/roaming、GPSD/GeoClue/ModemManager location。 | Wi-Fi 地理库、蜂窝 PLMN 和 GNSS 是最接近物理位置的证据来源。IMSI、IMEI、ICCID、Wi-Fi 密码、完整扫描列表不得输出；外部 Wi-Fi 地理查询单独 opt-in。 |
| 云/VPC/容器网络 | 云 metadata route、instance identity、CNI、Cilium/Calico/Flannel/Weave/OVS、Docker/Podman bridge、Kubernetes hostNetwork/sidecar、service mesh。 | 识别私网地址、100.64/10、overlay 和虚拟网关为何出现；同时标出“host 网络位置”和“实际用户网络位置”未必相同。 |
| 入站身份认证 | PAM、sshd、mosh-server、xrdp-sesman、VNC、gdm remote、WebSocket terminal、Jupyter、code-server、Teleport、管理 agent 的成功会话和当前 child process。 | 以真实认证/控制会话为入口，连接 source socket、UID、TTY、桌面 session 和时间。 |
| 终端 | PTY/TTY、shell、sudo/su、tmux/screen、mosh、SSH forwarding、terminal emulator、TERM、SSH_TTY、SSH_CONNECTION、同一会话的环境。 | 区分本地 terminal、经 SSH/jump host 的 shell、Web terminal、IDE terminal 和后台服务；从正确的 shell 读取 locale/时区/客户端信息。 |
| GUI 会话 | logind seat、display manager、Xorg/Xwayland、Wayland compositor、DISPLAY、WAYLAND_DISPLAY、XDG_SESSION_TYPE、XDG_CURRENT_DESKTOP、XAUTHORITY、WSLg。 | 区分本机物理桌面、SSH X11 forwarding、嵌套桌面、无头合成器、WSLg 和远程 GUI。 |
| 显示、捕获与注入 | DRM connector、虚拟显示器、QXL/virtio-gpu/vkms、Xvfb/Xdummy/Xephyr/Xpra、weston headless、PipeWire、xdg-desktop-portal ScreenCast/RemoteDesktop、uinput、XTest、libei。 | 识别 GUI 是本地显示、虚拟显示、录像/串流还是远控；远程捕获与虚拟输入同时活跃可连接到远控会话。 |
| 远程桌面/串流 | xrdp、VNC 家族、GNOME Remote Desktop、Krfb、NoMachine、RustDesk、AnyDesk、TeamViewer、Sunlogin、ToDesk、Chrome Remote Desktop、Parsec、Sunshine/Moonlight、MeshCentral、DWService，以及 UU 相关进程、Wine prefix、uur/UUWay 等可维护别名。 | 每种产品分 installed/enabled/listening/connected/control-active 四态；只在已建立会话时尝试关联对端或 relay。 |
| 用户态持久化 | user unit、XDG autostart、DBus activation、shell rc、desktop entry、browser/native messaging host、Flatpak/Snap service、自动更新任务。 | 补齐不经 systemd system unit 启动的远控、代理、Tailscale、WARP、cloudflared、屏幕捕获与输入法组件。 |
| 用户交互与历史 | 屏幕锁定/解锁、desktop idle、session start/end、活动窗口管理器元数据、下载/文档/终端/AI/Git 时间簇、输入法/浏览器 profile 的非内容型配置。 | 将长期生活习惯和当前用户会话连接起来；不读取窗口标题、网页内容、剪贴板、按键或聊天内容。 |

### IV. 会话入口与链路类型的细化

实际使用地区的关键不在于“发现远程工具”，而在于识别控制路径终点在哪一跳可见。建议给每个活动会话分配 path：

| path | 识别点 | usegeo 处理 |
|---|---|---|
| local-console | seat0/VT、活动 shell/GUI、无 remote 标记、物理输入/显示链 | 以 local-access-net、Wi-Fi/WWAN/GNSS 和本机出口作为同一使用者的候选证据。 |
| direct-ssh | sshd child 的活动 TCP peer 与 pts/UID 相连 | 对端公网地址直接进入 C3 GeoIP/ASN/rDNS；SSH LANG/LC_*、客户端版本、时间与该会话绑定。 |
| direct-mosh | mosh-server 的活动 UDP peer、对应 pty/UID | 将 UDP 对端作为控制端网络证据；与 SSH 建立阶段和会话时间交叉。 |
| direct-rdp-vnc | xrdp/VNC/wayvnc/NoMachine 等 session + socket/log 关联 | 客户端 IP、键盘布局、时区、屏幕/客户端类型等协议或日志元数据进入该 session。 |
| trusted-proxy | 明确配置的本地反代、受信代理源网段、可验证的 PROXY protocol/服务端真实客户端字段 | 只接受来自可信前置的源地址字段，不能信任任意客户端注入的 X-Forwarded-For。 |
| jump-host | sshd 对端为已知跳板，或会话/配置显示 ProxyJump、bastion、端口转发 | 记录最近可见 hop 的地区，并保留“真实控制端在跳板后未知”的链断点。 |
| reverse-tunnel | autossh/ssh -R/frp/ngrok/cloudflared 等出站常驻连接与本地监听/转发 | 标记为入站来源被反向通道遮蔽；不能把隧道服务端地址当操作者。 |
| relay | RustDesk/AnyDesk/TeamViewer/UU 等经厂商 relay 的会话、TURN/DERP/中继流 | 将 relay 作为独立环境信息；优先读取产品提供的本地会话元数据或 direct peer，若没有则保留链断点。 |
| mesh | Tailscale/ZeroTier/Nebula/NetBird/Headscale 等虚拟接口与 peer/session 关联 | 记录 tailnet/mesh 内 peer 是控制链的一跳；检查是否 direct/DERP/relay，虚拟地址不直接做地理归属。 |
| cloud-console | SSM/IAP/Bastion/serial console/guest agent 子进程或审计记录 | 标记云控制面入口；本机通常没有操作者源 IP，追加外部审计日志适配器而非猜测。 |
| web-terminal | ttyd/wetty/gotty/shellinabox/code-server/Jupyter 等 HTTP/WebSocket 会话 | 从可信反代/应用审计日志关联 authenticated session 与客户端地址、语言、时区等非内容元数据。 |
| unknown | 找到交互进程但无足够 socket/日志 | 保留该交互存在及所有旁证，不强行归因。 |

### V. GUI、远程控制和本地物理使用的专项增量

无头系统里“当前用户”通常等于 SSH shell；桌面系统里它可能是本地人、RDP 客户端、手机远控、嵌套 Wayland、云游戏串流或一个没有任何人类交互的显示服务。C19 应增加如下细分：

1. seat0、其他 seat、Remote=yes/no、session class/type、display manager 登录和锁屏/解锁事件，形成桌面使用者的主会话 ID。
2. X11 与 Wayland 分别判断。SSH 的 DISPLAY=localhost:10.0 是 X11 forwarding；Wayland socket 位于运行目录不代表物理桌面；WSLg、Xwayland、nested compositor、Xpra、VNC 虚拟桌面应单独标识。
3. 将物理显示器和虚拟显示器分开：DRM connector 状态、EDID 是否存在、QXL/virtio-gpu/vkms、Dummy/Xvfb/Xephyr、Sunshine 的虚拟显示驱动等都作为图形运行环境信息。
4. 将“远控能力已存在”和“正在被远控”分开。PipeWire/portal/uinput/XTest、编码器、远控 daemon、活动 socket、实际桌面 session、屏幕捕获/输入授权必须在同一时间窗口汇合，才形成 control-active。
5. 维护产品签名表时保留产品家族、二进制名、systemd unit、包名、配置目录、socket 特征和 log adapter 六类匹配，不依赖单一文件名。UU 相关检测应包含原生、Wine prefix、uur、UUWay 和可更新别名，但只报告观测到的组件与会话状态。
6. 对 xrdp/RDP、VNC、NoMachine 和其他有日志的服务，优先抽取“当前客户端地址、会话号、键盘/语言/时区、连接/断开时间、direct/relay 标志”；不要读取屏幕、剪贴板、文件列表或输入内容。
7. 对手机远控或串流，手机自身位置在 Linux 主机通常不可见。若产品本地 API/日志给出客户端公网地址、直连/中继状态、设备平台、语言或时区，可作为 session metadata；没有时将其明确记为 relay/opaque，而不是把 Linux 主机位置当手机位置。
8. loginctl IdleHint、screensaver idle、屏幕锁定、物理键盘/鼠标/触摸板/触摸屏设备类别、ACPI lid/dock 事件可以提高“人在本地使用 GUI”的可信度；禁止为此读取 /dev/input/event* 的实际按键或鼠标数据。

### VI. Tailscale、Cloudflare 与 VPC/mesh 的专项增量

这些项目应作为 C5/C17/C20 的联动检测。它们既可能解释地域矛盾，也可能正是远程使用链的一部分；因此“安装了产品”与“会话流量经产品”必须分别输出。

| 体系 | 建议补充检查 | 对 usegeo 的意义 |
|---|---|---|
| Tailscale / Headscale | tailscaled/tailscale0、system/user unit、state 路径存在性、tailscale status --json 的本地只读状态、exit node/advertise exit node、accept/advertise routes、Tailscale SSH、MagicDNS、netfilter 链、policy route、peer direct/DERP 状态。 | 若当前 shell 是 Tailscale SSH 或服务 socket 在 tailscale0，控制端为 mesh peer；虚拟 100.x 地址不能直接地理定位。可将 direct endpoint、DERP/relay 状态和出口 node 作为拓扑证据，区分控制端、exit node 与 host-egress。 |
| WireGuard/OpenVPN/IPsec/SoftEther | 接口、peer、handshake age、allowed IP、route/rule、systemd/NetworkManager profile、进程和 netfilter。 | 判断本机是否是客户端、服务器、site-to-site gateway、出口 VPN 或仅有闲置配置；按连接的具体进程/namespace 关联。 |
| ZeroTier/Nebula/NetBird/Netmaker/Tinc/Innernet | daemon、接口、peer/route 状态、控制面 URL 类型、systemd/user unit、DNS 接管。 | 增加 overlay 拓扑事实，使虚拟 IP 和私网路由不被误判为物理地区。 |
| cloudflared Tunnel | system/user unit、进程参数、config 路径、ingress 数、private network/warp-routing 配置、metrics 监听、credential 文件仅检测存在性、不读取内容。 | Cloudflare Tunnel 是本机对外建立的 connector；入站到 origin 的 socket 往往不携带控制者地址。若应用层有经过可信 Cloudflare 前置的客户端地址字段，再由专门适配器关联，而不是用 cloudflared 出站地址推断操作者。 |
| Cloudflare WARP / Zero Trust / Mesh | warp-svc/warp-cli、相关接口/路由、DNS 接管、device enrollment 存在性、Mesh/WARP Connector 角色、private route 条目数、服务状态。 | WARP 可改变 host-egress；Mesh node/旧 WARP Connector 表示双向私网连接角色。两者都为拓扑/出口解释和会话路径提供信息。 |
| 云 VPC / Kubernetes | metadata endpoint/route、云 agent、ENI/virtio、CNI、hostNetwork、sidecar、service mesh、node/pod 身份、NAT gateway/egress proxy。 | 区分云区域、VPC 内地址、容器出口和操作者网络。云区域可增强 C2，但不应覆盖 session/controller 的地区结论。 |

对于 Tailscale，exit node 承载互联网默认路由，subnet router 提供指定私网段，Tailscale SSH 是直接会话入口，DERP 是中继；四种角色要独立编码。对于 Cloudflare，Tunnel、WARP client、Mesh node 和 HTTP reverse proxy 也要独立编码。只有正确识别角色，C3 的出口、C4 的路由、C5 的隧道和 C20 的会话源才能同时成立。

### VII. 现有类别的加法挂接点

| 现有类别 | 新增挂接，不替代现有项 |
|---|---|
| C1 sysinfo | 增加 scanner scope、PID 1、host/container/WSL、display/seat 能力、物理无线/WWAN/GPS 能力、cloud/virtual console 背景。 |
| C2 cloud | 增加 cloud-init datasource、metadata route、guest agent、cloud console/SSM/IAP/Bastion 线索和云地域与实际用户地区的双层输出。 |
| C3 egress | 为每条 v4/v6 出口附 netns/interface/route table/mark/proxy/exit-node/session，支持针对当前 session 所属路径的多出口检测。 |
| C4 path | 增加所有 route table、policy route、VRF、conntrack（权限允许）、链路状态、DHCP/PPP/Wi-Fi/WWAN 的当前接入上下文。 |
| C5 proxy | 增加 Tailscale/Headscale、Cloudflare Tunnel/WARP/Mesh、通用 mesh、反向隧道、远控 relay 的角色识别和 direct/relay/mesh 路径标记。 |
| C6 dns | 增加 per-link DNS、search domain、MagicDNS、WARP DNS、VPN/mesh DNS、DoH/DoT、DNS 与 session route 的绑定。 |
| C7 webrtc | 增加当前 GUI/浏览器/远控产品是否具备 capture/WebRTC/relay 路径；主动 STUN 结果绑定浏览器/namespace/代理路径，而非混入主机出口。 |
| C8 locale | 增加登录会话环境中的 LANG/LC_*/TZ、RDP/SSH/远控客户端披露 locale/keyboard/timezone，与宿主全局配置分开。 |
| C9 mirror | 保留原有镜像信号，并增加配置来源（image/cloud-init/system/user/CI）与最近活跃用户关联。 |
| C10 fs | 增加远控、IDE、overlay、terminal、桌面会话的用户态配置及时间；优先统计命中数、状态和时间，不导出内容。 |
| C11 time | 增加按 session/UID/GUI lock/unlock/remote connection/网络切换聚类，形成“同一使用者”时间线。 |
| C12 anti | 增加 mount namespace、overlay/bind mount、LD_PRELOAD、受限 /proc、bwrap/Flatpak、systemd sandbox、不可见 netns 等环境完整性线索；这些用于解释采集边界并与显式伪造信号并列。 |
| C13 hw | 增加 Wi-Fi、WWAN、GPS、DRM、物理/虚拟输入、显示器/虚拟显示和 modem 能力，作为 local-seat 实际使用链的支撑。 |
| C14 services | 增加 user service、DBus activation、socket/path/timer unit、cloud agent、远控/overlay/terminal/portal/pipewire 服务的四态。 |
| C15 browser | 增加浏览器是否是远控 Web client 或本机 interactive browser；浏览器 UI 语言和 profile 环境可归属当前 GUI session，WebRTC/内容采集仍独立开关。 |

### VIII. 证据融合、升级和输出规则（仅增量）

1. 保持现有单项 EXPOSED/SUSPICIOUS/INFO 的判定不变。C20 只额外输出同一条证据属于 host、host-egress、controller-net、local-access-net、relay-overlay 或 history-user。
2. 新增 actual-use EXPOSED 的直接路径：活动 direct SSH/Mosh/RDP/VNC/可信 Web terminal 控制端地址属于 CN/HK/MO；或活动 local seat 与当前蜂窝 PLMN、GNSS、经明确 opt-in 的 Wi-Fi 地理库等物理接入证据属于 CN/HK/MO。
3. 新增 actual-use SUSPICIOUS 的累积路径：同一 active session 的多个独立家族都指向陆港澳，例如远控会话元数据 + 控制端网络、local GUI + Wi-Fi/PPPoE/运营商、或当前用户交互时间簇 + 受会话约束的 locale/输入法/服务习惯。
4. host 出口、控制端地址、DNS、路由、ASN、rDNS、时区、locale 和历史痕迹都要保留原始命中；C20 只负责告诉报告读者“它们是否指向同一个人/同一会话/同一台物理设备”。
5. 以 family 防止重复计分：同一 IP 的 GeoIP、ASN、rDNS、BGP/route 属于一组；同一 Wi-Fi 位置库的多个 AP 属于一组；同一产品日志的 IP/locale 属于一组。独立性来自不同接入层、不同会话层或不同时间/来源。
6. 冲突本身新增为可疑链：例如海外 host-egress + CN direct RDP controller、美国 exit node + 香港 Wi-Fi local-seat、CN locale + 非 CN active session。报告保留两端，而不是用单一“最终国家”覆盖它们。
7. 明确阻断链：发现 relay、jump host、Cloudflare Tunnel、云控制台、container netns 或缺少会话日志时，输出“实际操作者位置在此链路后不可直接观察”，同时继续报告所有已有旁证。这是新增信息项，不删除任何命中。

### IX. 建议新增的开关、数据结构和测试矩阵

新增选项可以保持 POSIX sh 单文件实现方向：

- --usegeo：启用 C20 会话图与融合输出；默认随全量扫描启用。
- --sessions：只跑 C18/C19/C20，快速审计当前交互使用者。
- --gui：启用 GUI、门户、远控、DRM、输入设备类别检查。
- --radio：启用 Wi-Fi/WWAN/GNSS 元数据；默认本地脱敏，不调用外部位置库。
- --wifi-geo：显式启用外部 Wi-Fi/BSSID 地理查询，并逐项提示会发送什么标识符。
- --active-connections：启用当前 socket -> process -> session 关联；默认只本地解析。
- --deep-net：在有权限时采集 conntrack、TC、eBPF、所有 namespace、路由策略。
- --session <id|uid|self>：只输出指定会话/用户的链，避免多用户服务器互相污染。

结构化结果建议补充：

~~~json
{
  "level": "EXPOSED",
  "category": "usegeo",
  "item": "direct_ssh_peer",
  "subject": "controller-net",
  "scope": "host/netns:4026531993",
  "session": "S-42",
  "path": "direct-ssh",
  "live": "now",
  "family": "network:peer-1",
  "region": "HK",
  "link_confidence": "high",
  "redacted": true
}
~~~

最低验收矩阵应增加以下组合：

1. 海外 VM 被大陆/HK/MO 直连 SSH、Mosh、RDP、VNC、Web terminal、VS Code Remote 控制；
2. 海外 VM 被移动端/UU 类远控、RustDesk/AnyDesk/TeamViewer/Sunlogin/ToDesk、Chrome Remote Desktop、Sunshine/Moonlight 控制，分别覆盖直连与 relay；
3. 本地 Linux GUI 接入大陆/HK/MO Wi-Fi、蜂窝、以太网、PPPoE、VPN、Tailscale exit node、WARP，且同时存在 IPv4/IPv6 分流；
4. Tailscale 普通 peer、Tailscale SSH、direct peer、DERP relay、exit-node client、exit-node server、subnet router、Headscale；
5. cloudflared published application/private route、Cloudflare WARP client、Cloudflare Mesh node、可信 Cloudflare reverse proxy header 和不可观测 tunnel 入站；
6. Docker/Podman/rootless container、Kubernetes pod/hostNetwork/sidecar、VRF、policy routing、透明代理、TC/eBPF、NetBird/ZeroTier/WireGuard/OpenVPN；
7. X11、Wayland、WSLg、X11 forwarding、嵌套 compositor、Xvfb/vkms、物理 seat、远程 desktop、锁屏/解锁、虚拟输入；
8. 多用户服务器、CI、cloud-init 镜像、最小系统、无 systemd、SELinux/AppArmor 拒绝、日志轮转、权限不足与隔离 namespace。

建议实施顺序为：先为现有 report 加 subject/scope/path/live/family 字段；随后实现 u0--u3 的会话图和直接入口；再实现 GUI/远控链、Wi-Fi/WWAN/GNSS、Tailscale/Cloudflare/VPC adapter；最后加入融合、冲突视图、外部 Wi-Fi 地理查询和深层网络面。这样每增加一层都可直接增强既有规则，而无需修改或削弱原有策略。

### X. 末尾查漏补缺清单

以下项目也应进入能力表和产品签名表，避免在实现时因“典型无头主机”假设而漏检：

| 漏检面 | 应增加的具体检查 | 与实际使用地区的关系 |
|---|---|---|
| Tailscale userspace networking | 检查 tailscaled 的 tun=userspace-networking 参数、容器/非 root 运行方式、SOCKS5/HTTP proxy listener、local API、Kubernetes Operator sidecar/Connector；此模式可能没有 tailscale0、内核路由或标准 netfilter 链。 | 避免因缺少接口而漏掉 Tailscale SSH、exit node、subnet router 或经本地代理走的控制/出口流量。 |
| 远程桌面网关与 VDI | 增加 Apache Guacamole/guacd、X2Go、ThinLinc、Citrix Workspace/ICA、VMware Horizon、NICE DCV、HP Anyware/Teradici、FreeRDP/Remmina client、websockify、Kasm、MeshCentral、Guacamole reverse proxy 的进程、unit、socket、日志适配。 | 企业或云桌面场景中，Linux 看到的可能是 VDI gateway；应识别 client、gateway、desktop-host 三个角色，并寻找可信的原始 session 元数据。 |
| Layer 2 与企业接入 | 增加 LLDP/CDP、NetworkManager LLDP、802.1X/EAP 的非凭据属性、VLAN/bridge/bond、DHCP option 43/60/119/121、NTP server、domain search、captive portal 与已连接 AP/router OUI。 | 楼宇、园区、运营商或企业网络常在这些元数据中留下地区/组织线索；按当前接口、当前 local seat 和时间绑定，避免把旧 lease 当实时位置。 |
| 物理接入变体 | 识别 USB Ethernet、Android USB tethering、iPhone USB tethering、Bluetooth PAN、WWAN dongle、卫星/USB modem、LTE/5G modem 的 NetworkManager device type。 | 这类接口可能比虚拟网卡更接近使用者所在的实际接入网络；与 MCC/MNC、AP/网关、当前 local seat 交叉。 |
| 企业 VPN/ZTNA | 补入 OpenConnect/AnyConnect、GlobalProtect、FortiClient、Ivanti/Pulse、Zscaler、Netskope、Prisma Access、Twingate、Teleport、Boundary 等 daemon、接口、route/rule、DNS 和会话状态。 | 它们可能改变工作负载出口、承载远程控制或将客户端置于私网；作为 path/relay/exit 角色进入 C20，不覆盖原有出口结论。 |
| 协议前置与真实源地址 | 除 HTTP X-Forwarded-For 外，检查 HAProxy PROXY protocol、Nginx realip、Envoy/XFF、Traefik、Caddy、SSH ProxyJump、SO_ORIGINAL_DST、透明代理和 service mesh 的 trusted-source 配置。 | 对可信前置可恢复控制端/浏览器端来源；对未配置可信边界的 header 一律只保留原始 socket peer。 |
| 图形/交互的非传统路径 | 增加 waypipe、RDP over WebRTC、GNOME Remote Login、KDE KRDP、Steam Remote Play、OBS/FFmpeg/GStreamer capture、v4l2loopback、虚拟音频和 virtual HID。 | 补足 Wayland、游戏串流和浏览器化远控场景；capture、输入注入、socket 和 GUI session 同时活跃时可形成 control-active 链。 |
| 审计完整性与采集完整度 | 记录是否可见其他 PID/netns、是否受 hidepid、procfs bind mount、seccomp、SELinux/AppArmor、systemd sandbox、capability drop、rootless container、eBPF LSM 约束。 | 将“未发现”区分为“该作用域没有”与“当前采集者不可见”，为现有 anti 类新增完整性旁证。 |

这张清单同样只增加适配器和证据源。既有 C1--C20、既有输出等级和已规划的检测点不需要为此删除、合并或改弱。
