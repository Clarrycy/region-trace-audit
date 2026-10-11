# region-trace-audit — 陆港澳用户环境痕迹检测器 设计计划 v4

> **定位**:独立的只读检测工具(类似 Android 环境检测工具的思路),审计一台机器,
> 找出「使用者是中国大陆/香港/澳门用户」的痕迹,或「伪装非陆港澳用户但留下了马脚」。
> 覆盖平台:Linux(物理/VM/**容器**)、WSL、macOS;依赖不满足的检测项自动降级 SKIP 并注明原因。
>
> v4 变更:并入 Codex 审计意见(`reviews/codex-audit-2026-10-09.md`)的采纳项——
> 采集模式分层、结果元数据与来源归因、四态分离、上下文层新类别(C16–C19)、
> 覆盖网络角色识别、C20 实际操作者会话链;逐条处置见 §9。
>
> 源码结构(v0.2 起):`src/` 按两位数字前缀分模块(00-header … 90-main),
> `build.sh` 按序拼接为单文件 `dist/region-trace-audit.sh`(发布到 Gist 时用 dist 产物)。

---

## 1. 判定语义(五态)、元数据与分级哲学

| 结果 | 语义 |
|---|---|
| **暴露 EXPOSED** | **位置/链路实锤**:网络路径、物理射频、活动控制链路、或硬配置直接表明位于陆港澳 |
| **可疑 SUSPICIOUS** | ① 身份/习惯软信号(留子/海外华人正常具备);② 刻意隐藏/伪造痕迹(马脚);③ 自相矛盾 |
| **正常 CLEAN** | 无地域特征、无异常 |
| **信息 INFO** | 中性上下文,或有用但不定罪的事实(如中资 IDC 海外节点) |
| **跳过 SKIP / N/A** | 依赖(工具/权限/路径/平台)不满足,输出注明所缺依赖 |

**结果元数据**(JSON 全量,文本输出按需简写):`scope`(host/root-netns/container/netns-id/current-user/session)、`origin`(image-builder / host-admin / current-user / other-user / unknown)、`freshness`(active 运行中 / enabled 已启用 / installed 已安装 / residue 静态残留)、`confidence`(低/中/高)、`redact`(是否脱敏)。
**归因原则**:镜像/云初始化/管理员注入的痕迹(locale、镜像源、agent、隧道)标注 origin,不默认归因给交互用户;容器内命中注明「可能来自镜像构建者」。
**四态分离**:软件/服务/远控/隧道统一区分 installed → enabled → listening → active(活动),只证明安装与正在运行分开报告;「正在被远控」需 socket、会话、输入/捕获路径同时活跃。

**留子原则**:文化习惯类信号(locale、键盘、输入法、字体、中文文件名、QQ/微信、国内镜像、qq/163 邮箱、作息统计……)只到**可疑**。
**中资 IDC 原则**:中资云(含海外节点)→ **信息**;普通 VPS/IDC 不作为检测点,机房 IP 不判可疑。

**暴露级证据(收敛清单)**:
| 证据 | 理由 |
|---|---|
| 出口 IP 地理 ∈ CN/HK/MO(双源 GeoIP 交叉提高 confidence;标注观测 netns 与是否经 exit node/代理) | 网络位置实锤 |
| v4 与 v6 出口国家不一致且其一 ∈ CN/HK/MO | 双栈分流马脚 |
| 路由沿途含 CN 骨干 hop(AS4134/4837/9808/9929/58453…、202.97.* 等;多锚点探测) | 物理链路经中国 |
| 首跳/出口 rDNS 含 CN ISP 命名(China Telecom/Unicom/CMCC、bj/sh/gd 城市码) | 链路归属实锤 |
| DNS 污染探测阳性(**≥2 个已知域名**返回已知假 IP 段) | 解析链路实际经过中国出口 |
| 系统时区 ∈ 陆港澳确定时区(Asia/Shanghai 及链接、Asia/Hong_Kong、Asia/Macau、Asia/Urumqi) | 长期在其他时区不会保留这些时区(既定规则,不因「配置可改」降级) |
| 非陆港澳**东八**时区(Singapore/KL/Manila/Taipei/Perth/Makassar/Irkutsk…)+ 出口地区非东八 | 伪装不彻底的典型马脚;仅东八区适用 |
| **活动的直接远程控制端 ∈ CN/HK/MO**(direct SSH/Mosh/RDP/VNC/可信 web terminal 的活跃 socket 对端) | 操作者网络实锤(C20 会话链;中继/跳板后不可观察时按链断点处理,不强行归因) |
| 活动 local seat + 物理接入证据(WWAN PLMN、GNSS、opt-in Wi-Fi 地理)∈ CN/HK/MO | 物理在场实锤(--radio,物理机桌面场景) |

每条结果附一句话理由;规则透明可复核。

---

## 2. 采集模式与输出

### 采集模式分层(每条结果标记所属模式)
| 模式 | 内容 | 默认 |
|---|---|---|
| **passive** | 只读本机 proc/sys/run/配置元数据,不修改任何状态 | ✅ |
| **local-daemon** | 对本机 Unix socket/CLI 只读查询(如 tailscale status;失败降级,绝不触发登录/重连/刷新) | ✅ |
| **active-probe** | 出口 GeoIP、traceroute、DNS 污染探测、STUN(显式) | ✅(`--offline` 全关) |
| **sensitive** | 批量 GeoIP 用户连接图谱(known_hosts/ESTABLISHED 对端/git remote)、历史深扫、Wi-Fi 地理库 | ❌ 需 `--deep-geo`/`--wifi-geo` 显式开启 |

**外联最小集(默认)**:仅本机自身出口 v4/v6 + 生效解析器地址。known_hosts、连接对端、git remote 等用户连接图谱发往第三方 API 属于敏感操作,一律归入 `--deep-geo`。

### 输出
1. **逐项实时输出**:`[标记] [类别/检测项] 描述 → 结果`(关键项附 scope/origin 简写)
2. **结尾逆序汇总**:全部「暴露」→ 全部「可疑」→ **实际使用地区视图**(C20)→ 统计行
3. 退出码:暴露>0 → 2;可疑>0 → 1;否则 0
4. 默认**轻度脱敏**(IP 显示前两段、邮箱/userID 哈希化;`--reveal` 显式全量)
5. 选项:`--offline`、`--section <cat>`、`--brief`、`--reveal`、`--deep-geo`、`--radio`、`--session <id|uid|self>`、`--json`(v0.5)

---

## 3. 类别与检测项清单(20 类)

### C1 sysinfo — 系统与平台(几乎全 INFO)
- **采集者边界(u0)**:脚本自身 PID/UID/TTY/父进程链、PID/mount/net/user namespace、容器/VM/WSL 身份、可见进程集合 —— 所有后续结果继承此 scope
- 发行版/os-release、内核架构、uptime、系统安装时间(root fs 创建时间/machine-id ctime,与 C11 交叉)
- **平台判定**:物理 / VM(systemd-detect-virt+dmesg)/ 容器(§5)/ WSL / macOS;cloud-init datasource、Ignition、firstboot 存在性(归因 origin)
- **连接方式**(INFO):`SSH_CONNECTION` → SSH(含来源 IP/pts);`who am i` 交叉;否则 tty/本机/console
- 内核 TCP 拥塞控制(bbr → INFO 提示);当前用户、登录用户列表、已装 shell/包管理器

### C2 cloud — 云平台与定制系统(中资 IDC,全 INFO 级)
- DMI/SMBIOS:`/sys/class/dmi/id/{sys_vendor,product_name,bios_vendor}`(容器内常无 → SKIP)
- 云 agent:进程 + systemd unit + 目录(阿里 aegis/AliYunDun/aliyun-service、腾讯 yunjing/barad//usr/local/qcloud、华为 telescope、火山);容器内进程仍在 → 保留
- 内网镜像源(mirrors.cloud.aliyuncs.com、mirrors.tencentyun.com)
- 定制痕迹:/etc/motd、/etc/issue、os-release 定制字段、预装包 grep
- ASN 归属(AS37963/134963/45090/132203/55990/136907/139190…)
- **云 console 线索**:SSM/IAP/Bastion/guest agent 进程 → 交 C18 标记 cloud-console 入口
- 判定:中资云(无论节点)→ **信息**(标注节点位置;agent 回传中资厂商加备注);普通 IDC → 不作检测点

### C3 egress — 出口与 GeoIP(active-probe)
- IPv4 出口:国家/城市/时区/ASN/组织/家宽 vs 机房(ip-api `hosting,proxy,reverse`;ipinfo 备源,**双源交叉**写入 confidence)
- IPv6 出口(双栈遗漏是经典暴露);v4/v6 国家不一致 → 其一 CN/HK/MO = 暴露,其他不一致 = 可疑
- **每条出口附注记**:观测 netns、是否经代理/exit node、查询时间 —— 出口是「当前网络边缘」的证据,不表述为「用户位于」
- 出口 rDNS 含 CN ISP 名/.cn 后缀 → 暴露
- 判定:CN/HK/MO → 暴露;机房 ASN 不判;家宽与声明地区一致 → 正常

### C4 path — 链路、路由与本地网络(active-probe;消费 C17 数据面结果)
- traceroute/tracepath 多锚点(1.1.1.1、8.8.8.8、目标区站),沿途 IP batch GeoIP(含 reverse);CN 骨干 hop → 暴露;首跳 rDNS 城市码 → 暴露/可疑
- 默认网关归属;**网关 MAC OUI**(国内网络设备厂商表 → 可疑:人在国内局域网;虚拟网关自然不命中)
- MTU 1492(PPPoE 暗示)、CGNAT 100.64/10(可疑:常见国内移动网络)
- 当前 ESTABLISHED 连接的 CN 对端统计(**--deep-geo**,sensitive)
- TTL 初值(OS 推断,INFO)

### C5 proxy — 代理、隧道、分流与**覆盖网络**(拓扑角色全 INFO)
- env 代理变量 → INFO(提示对子进程可见)
- **透明代理/分流**:nftables/iptables REDIRECT/TPROXY 规则;**分层检查**(nft/iptables/ipset/TC/XDP-eBPF 任一层都可能实现);CN 段直连表(chnroute/CN geoip 集合名)→ 可疑
- tun/wg 接口;PPPoE 会话 → 可疑;默认路由指向 tun/ppp → INFO
- 传统代理栈进程/服务/配置(clash/v2ray/xray/ss/hysteria/trojan)→ INFO;clash/mihomo 订阅节点名含地名关键词(沪/港/IPLC/家宽)→ 可疑;DNS 分流(dnsmasq/smartdns 国内域名走 114/223.5.5.5)→ 可疑
- **覆盖网络与私有连接器**(local-daemon 只读;凭据文件只测存在性绝不读取):
  - Tailscale/Headscale:tailscaled/tailscale0、`tailscale status` 本地只读 JSON;角色分立——exit node(承载默认路由)/ subnet router / Tailscale SSH(会话入口)/ DERP relay,**四种角色独立编码**;userspace networking 模式(无 tailscale0 接口、SOCKS5 listener)亦检出
  - cloudflared Tunnel:出站 connector(不改变默认出口,不当 VPN 证据);ingress 条目数、credentials 存在性
  - Cloudflare WARP/Mesh:warp-svc/warp-cli、enrollment 存在性;WARP 改变出口(host-egress 注记),Mesh = 双向私网角色
  - 通用 mesh:WireGuard/OpenVPN/IPsec/ZeroTier/Nebula/NetBird/Tinc 等 daemon/接口/路由
  - 反向隧道:autossh/ssh -R/frp/ngrok
  - 云 VPC/CNI:overlay 地址、100.64/10、虚拟网关 → 平台归类,不解释为地域
- proxychains/tsocks → INFO;监听端口归属(7890/10808/8388/8118)→ 交 C14

### C6 dns — DNS 卫生
- 实际生效解析器:resolv.conf + systemd-resolved status + **per-link DNS/search domain**(NM/networkd);容器/k8s cluster DNS → INFO;MagicDNS/WARP DNS 接管 → INFO(拓扑注记)
- 解析器 IP GeoIP(默认外联最小集内):114/223.5.5.5/119.29.29.29 → 可疑(配置习惯);解析器 GeoIP ∈ CN/HK/MO → 可疑
- **DNS 污染探测**(active-probe)→ 暴露:**≥2 个**已知污染域名命中已知假 IP 段才判阳性(防误报);结果表述为「解析路径经过会注入的链路」
- EDNS Client Subnet → TODO(受控域名接口预留);DoH/DoT/stubby → INFO;FallbackDNS 残留国内地址 → 可疑;/etc/hosts 国内域名硬解析 → 可疑

### C7 webrtc — WebRTC 泄露
- 已装浏览器 + profile → INFO 提示 + TODO;浏览器分「profile 静态配置 / 当前运行 / 主动 probe」三态
- STUN:装了 stuntman/turnutils → 查询比对出口(不一致 → 可疑);纯 sh `/dev/udp` STUN 与浏览器内检测 → **显式开关下** v0.5+

### C8 locale — 地域配置与**应用栈时区**(马脚核心)
**系统层**:
- `LANG`/`LC_*`:zh_CN/zh_HK/zh_MO → 可疑;zh_TW → INFO;**会话环境与全局配置分开读**(RDP/SSH 客户端披露的 LANG/键盘/时区绑定到会话,交 C20)
- 时区(三源:/etc/localtime、/etc/timezone、TZ env)判定分档(既定规则,不降级):
  1. 陆港澳确定时区(Asia/Shanghai|Chongqing|Harbin|PRC 链接、Hong_Kong、Macau、Urumqi)→ **暴露**
  2. 非陆港澳东八时区 + 出口非东八 → **暴露**(仅东八适用)
  3. 非陆港澳东八 + 出口在东八 → 正常
  4. 其他时区与出口地区不符 → 可疑
  5. 一致 → 正常;`TZ` env 与 localtime 不一致 → 可疑(伪造/混乱)
  - 时区命中时附 scope 注记(观测出口的 netns/exit-node 状态),供读者复核
- localedef 生成列表含 zh_* → 可疑;zh man 页 → 可疑;键盘中文布局 → 可疑;hostname 拼音/姓名/CN 字样/.cn 后缀 → 可疑;RTC local time → INFO
**应用栈时区**(容器/服务器重点;标注 origin):
- php.ini `date.timezone=PRC|Asia/Shanghai…`(PRC = 强马脚)、JVM `-Duser.timezone`/JAVA_TOOL_OPTIONS、my.cnf/pg/mongo 时区配置、k8s/compose TZ env、应用日志时间戳时区 → 可疑(部署者痕迹)

### C9 mirror — 软件源与开发工具镜像
- 发行版:apt/dnf/pacman/apk/zypper 源 → aliyun/tuna/ustc/163/华为云/腾讯云 → **可疑**;云内网域 → 交 C2;**配置来源归因**(镜像默认源 ≠ 用户改的源,读 cloud-init/firstboot 痕迹)
- 语言生态:pip/npm/cargo/go(GOPROXY)/maven/composer/gem/nuget/conda/poetry/flutter/HOMEBREW_BOTTLE_DOMAIN → 国内镜像 → 可疑
- 开发镜像 env 表(ELECTRON_MIRROR、NVM_NODEJS_ORG_MIRROR、SASS_BINARY_SITE、PUPPETEER_DOWNLOAD_HOST…)→ 可疑
- docker/containerd 镜像 mirror(registry.cn-*.aliyuncs.com、ccr.ccs.tencentyun.com)→ 可疑
- 已装软件:中文输入法、微信/QQ/WPS/钉钉/百度网盘/迅雷 → 可疑;CJK 字体 → 可疑(弱);语言包 → 可疑

### C10 fs — 文件系统与人类痕迹(全可疑级)
- 家目录中文文件名/目录名计数;**/proc/mounts 挂载点中文名** → 可疑
- `~/.gitconfig`:qq/163/126/foxmail 邮箱、拼音名、url.insteadOf(ghproxy)→ 可疑;git 仓库 remote 指向 gitee.com → 可疑(四态:安装/克隆/最近活动)
- `~/.ssh/known_hosts` CN IP 段、`~/.ssh/config` 国内 HostName/ProxyJump、authorized_keys 注释拼音/国内邮箱、GPG uid → 可疑(known_hosts 的 GeoIP 查询归 **--deep-geo**)
- **/etc/passwd**:拼音用户名、GECOS 中文名 → 可疑
- shell history 中文/国内域名计数、ssh 目标国内 IP → 可疑(计数不展示内容)
- 蓝牙中文设备名、WiFi 中文 SSID、**国内软件数据目录名表**(~/.xwechat_files、BaiduNetdiskDownload)→ 可疑;rc 文件 proxy 函数/gitee 引用 → 可疑
- rclone/网盘配置指向国内网盘 → 可疑

### C11 time — 时间行为统计(独立大类,防 AI 污染)
**原则:只统计「人主动动作」;AI 后台工作不代表人**。数据源分检测项(N<30 → SKIP;结果标样本归属 UID/session 与时钟来源):

| # | 检测项 | 数据源 | 防污染处理 |
|---|---|---|---|
| t1 | 登录时刻 | wtmp/last、lastlog | 过滤自动化(同源高频/固定间隔) |
| t2 | 命令输入时刻 | bash/zsh/fish history 时间戳行 | 天然人工 |
| t3 | AI 会话**用户输入**时刻 | ~/.claude/projects/**.jsonl(role=user 且非 tool_result/isMeta/sidechain)、~/.codex/sessions 同理 | 过滤 tool_result |
| t4 | 簇化降噪(通用) | t1–t3 做 5 分钟簇聚合取簇首 | 人簇发,AI 平铺 |
| t5 | 交互文件 mtime | ~/Downloads、dotfiles、~/Documents 白名单 | 排除 AI 写入区 |
| t6 | 启动/关机时刻 | last reboot、uptime | INFO 级 |
| t7 | git commit 时刻+时区 | git log author date:**tz offset 直方图**(+0800 残留而系统非 +8 → 可疑)+ 时间分布 | 部署行为低权重标注 |
| t8 | 应用/服务日志时间戳 | /var/log 可读日志行时间戳 | 部署/自动行为,低权重 |
| t9 | 包安装时刻 | dnf history、apt history.log、pacman.log | 过滤 unattended 自动更新 |
| t10 | 桌面交互源(可选) | 输入法词库 mtime、浏览器历史时间戳、tmux/screen 会话创建、**锁屏/解锁、GUI idle** | 桌面场景才可用 |

**方法(awk)**:各检测项独立 → UTC 24h 直方图 → 循环均值 → offset 扫描(−12…+14,0.5h 步):得分 = P(08:00–24:00 本地) − P(01:00–06:00) → 推断时区(并列区间全报,不取单点)+ 置信度(≥0.55 高/≥0.35 中)+ 直方图 ASCII(--brief 省略)。git 提交按当前用户 email 过滤(防协作者/AI 代理提交污染);AI 会话取用户输入行(滤 tool_result/isMeta/sidechain/function_call_output)。
**判定 v0.4 实现**(两级):
1. **时区一致性**(统一规则,取代单一「指向东八」判定):作息区间 vs 系统时区偏移 —— 区间覆盖 → CLEAN 佐证;偏差 ≥1h → 可疑(东八相关加「长居东八者特征」措辞;系统时区为陆港澳而作息反向 → 「时区声明与使用节奏矛盾」伪装向措辞);0.5–1h → INFO 轻微(夜猫型前移);置信低 → INFO 关联性弱不判定(防多用户/自动化服务器误报)。
2. **内地日历检验**(t11,强特征):法定假日/调休补班官方表(2024–2026,国办发明电;2027 待公布)按东八候选偏移换算本地日期 —— **调休补班日(周末上班)活跃 ≥2 天且法定假日(工作日部分)零活动 → 作息遵循内地工作日历**:机器环境非东八 → 可疑(调休为内地特有,港澳/海外无此实践);系统时区东八 → INFO 佐证;单日样本 → INFO 弱注记。反向(假日工作日活跃 ≥3 天)→ INFO 反证注记(留子/海外节奏)。窗口覆盖不足(补班日 0 个或假日工作日 <3 天)→ SKIP。
与 C18 会话/UID 关联后交 C20 融合;周中/周末分布 INFO。
**判定 v0.5 精化(作息是否升暴露的裁决)**:单条作息不升暴露 —— 悉尼实测区间 6.0–7.5 不含 8.0(活动至当地 24:00 把真偏移挤出并列集),且 +7 时区(曼谷/雅加达/河内/珀斯 ≈3 亿人)与 +8 原理性不可分;改为三档关联度(contains 区间含 8.0 / near 东亚段 5–8.5 上缘、措辞如实注明 +7 可解释 / none)+ **复合升级 time/tz-consist-strong(EXPOSED)**:强统计矛盾(偏差≥1.5h、得分≥0.85、N≥60、置信高)+ 独立记录性旁证(git 作者时区 +0800≥3 条提交,或调休遵循)→ 暴露,残余误报为 +8 非陆港澳用户(与既定 E8 政策同权);**C20 融合升级**:≥2 非纯文化家族一致 → usegeo/fusion EXPOSED。合成正/负例验证:东京时区+东八作息+git+0800 → 触发复合暴露;同样作息+git+0700 → 仅可疑。git-tz 计数改为提交级。

### C12 anti — 隐藏与伪造痕迹(马脚检测,全可疑级;带上下文修正)
- wtmp/utmp/lastlog/btmp 对当前用户不可读 → **可疑**;上下文修正:容器/最小系统 → SKIP;系统安装 <30 天且日志自安装即缺失 → INFO(新装);正常老化系统不可读 → 可疑(刻意)
- **交互 shell 无 SSH_* 判可疑的前置条件**:进程链确为 sshd 直接派生(SSH_TTY/父进程)而 env 缺 SSH_* 才判;tmux/su/sudo/systemd user service/cron 上下文中缺失属正常差异 → INFO(采纳审计修正)
- rc 文件出现 SSH_CLIENT/SSH_CONNECTION 赋值或按日期哈希生成 IP 的函数 → 可疑(伪造)
- systemd unit/systemd-run 含 `InaccessiblePaths=/var/log/wtmp…` → 可疑;landlock/bwrap wrapper、env -u SSH_* 别名 → 可疑
- wtmp 空但 uptime 长、history 0 字节但 HISTSIZE 巨大 → 可疑
- shell snapshot / agent 目录 SSH_CLIENT 值与当前 env 不一致 → 可疑(穿帮/残留)
- chrony/ntp 国内 NTP → 可疑
- 进程 TZ/LANG 与系统声明不一致:service manager 注入的正常差异 → INFO 注记;交互进程/用户 unit 不一致 → 可疑
- claude/codex settings 的 ANTHROPIC_BASE_URL 指向国内中转域名 → 可疑
- **采集完整性旁证**:hidepid、procfs bind mount、seccomp/SELinux/AppArmor 拒绝、capability drop → 输出「当前作用域可见性受限」注记,区分「没有」与「不可见」

### C13 hw — 硬件、驱动与无线/蜂窝(视权限)
- lspci/lsusb(容器常 SKIP):无线网卡存在(VPS 不该有)→ INFO;国内品牌外设 → 可疑
- DMI 品牌(Lenovo/Huawei/Honor/Xiaomi)→ 可疑(弱);CPU 龙芯/兆芯/飞腾/海光 → 可疑;电池/传感器 → INFO
- **--radio 模式**(物理机桌面场景):`iw reg get` 监管域、已连接 WiFi 接口(SSID/BSSID 只本地比对、不输出)、WWAN 注册状态 **MCC/MNC 国家映射**(→ C20 local-access-net 证据)、GNSS(gpsd/GeoClue)存在性与地区(不输出坐标);IMSI/IMEI/ICCID/WiFi 密码绝不读取;外部 Wi-Fi 地理库 → --wifi-geo 显式且逐项提示发送内容
- 接入变体:USB 网卡/手机 USB tethering/蓝牙 PAN/WWAN dongle 接口类型 → INFO(交 C20 关联)

### C14 services — 进程、端口与服务(四态)
- 运行进程:国内软件进程、中文路径 → 可疑;代理栈/mesh daemon → INFO(交 C5 角色)
- 监听端口 + 归属表(7890 clash、10808 v2ray、8388 ss、8118 privoxy、3128 squid)→ INFO/可疑
- systemd 系统与 user 服务、**socket/path/timer unit、DBus activation、XDG autostart**(容器无 systemd → SKIP);cron 国内域名/中文 → 可疑
- k8s:SA token、KUBERNETES_* → pod 判定 → INFO;LaunchAgents(macOS)国内 plist → 可疑

### C15 browser — 浏览器痕迹(桌面场景;分 profile 静态/运行中/主动 probe 三态)
- 已装浏览器及 profile → INFO(联动 C7);默认搜索引擎(baidu/sogou/360)→ 可疑
- 书签/历史国内域名计数(places.sqlite/History,只计数)→ 可疑;界面语言/accept-language → 可疑;不读 URL 明文/查询词/书签标题/扩展内容

### C16 boot — 引导与初始化来源(上下文层,几乎全 INFO)
- 平台能力:UEFI/BIOS、bootloader(bootctl/efibootmgr/GRUB)、initramfs 存在性(缺 → SKIP)
- 当前启动事实:/proc/cmdline(分类提取 ip=/rd.*/systemd.setenv/console=,不读启动介质内容)、default target、启动失败 unit 摘要
- **持久化启动面与归因**:cloud-init datasource/user-data 存在性、Ignition、systemd-firstboot、rc.local、enabled units、timer、XDG autostart、DM —— locale/时区/DNS/代理/镜像源/隧道若来自镜像或 cloud-init,**标注 origin=image/admin**,不归因用户
- 作用:为 C8/C9/C12 的命中提供「谁设置的」解释

### C17 kernelnet — 内核、命名空间与网络数据面(上下文层,全 INFO)
- 内核与隔离:LSM(SELinux/AppArmor/landlock)、cgroup v1/v2、PID/mount/user/net namespace 关系、capability 边界、/proc/1 身份 —— 用于解释可见性与降级,**不把安全策略/namespace 本身判为隐藏**
- 接口类型枚举:lo/物理 NIC/veth/bridge/bond/VLAN/VRF/macvlan/tun-tap/WireGuard/CNI 虚拟接口(不凭接口名猜产品)
- **路由全貌**:IPv4/IPv6 所有 route table、ip rule、fwmark、source routing、默认路由 —— C3/C4/C5 的观测范围前提(只看 main table 会漏代理栈与多 WAN 分流)
- 数据面分层:nftables / iptables / ipset / TC qdisc / XDP·cgroup-eBPF 分开报告(透明代理可能在任一层)
- sysctl forwarding/rp_filter → 识别 router/subnet-router/exit-node 角色;转发开启不是地域信号
- VPC/overlay(Cilium/Calico/Flannel/OVS)→ 平台归类,私网段不解释为地域

### C18 session — 用户、会话与远程入口(上下层 + 部分可疑)
- **活跃会话图**:loginctl list-sessions/show-session、who、w、utmp(可读时)、sshd 子进程、进程树、PTY、UID、cgroup —— 合并同 UID/同 leader/同 pts 为一个 session
- **入口分类**(每会话打 path 标签):local-console(seat0/VT)/ direct-ssh / direct-mosh / direct-rdp-vnc / trusted-proxy(仅信任已配置前置的源地址字段,不信任意 XFF)/ jump-host(ProxyJump 配置或已知跳板)/ reverse-tunnel(autossh/frp/ngrok)/ relay(厂商中继)/ mesh(Tailscale SSH 等虚拟入口,虚拟地址不做地理归属)/ cloud-console(SSM/IAP/Bastion agent)/ web-terminal(ttyd/code-server/Jupyter)/ unknown
- 终端载体:terminal emulator、tmux/screen、sudo/su 链、X11 forwarding;只报类型与活动状态,不读终端标题/完整 env
- 用户级持久化:~/.config/systemd/user、autostart、shell rc 中与当前会话同 UID 的代理/隧道/远控 → 关联报告
- 判定:入口本身全 INFO(它们解释观察范围,不做风险判定);**活动的直接入口对端交 C20 判地域**

### C19 gui — 图形会话、输入与远程桌面(桌面场景)
- 会话判定:logind seat/Remote/Class/State、DISPLAY/WAYLAND_DISPLAY、XDG_SESSION_TYPE/CURRENT_DESKTOP、DM(gdm/sddm/lightdm);区分物理显示 vs SSH X11 forwarding vs WSLg vs nested/Xvfb/vkms 虚拟显示(DRM connector/EDID 存在性)
- 桌面环境与输入:XKB、IBus/Fcitx/Rime/搜狗(与 C8/C9 交叉,软信号);dconf/gsettings 只取键盘/输入法/语言/时区/代理字段
- **远程桌面四态**(installed/enabled/listening/**connected**):xrdp、VNC 系、GNOME Remote Desktop、NoMachine、RustDesk、AnyDesk、TeamViewer、Sunlogin(向日葵)、ToDesk、Chrome Remote Desktop、Parsec、Sunshine/Moonlight;VDI 网关(Guacamole/X2Go/Citrix/Horizon/DCV)→ 签名表可扩展
- **control-active 判定**:远控 daemon + 活动 socket + 桌面 session + 输入/捕获路径(PipeWire portal/uinput/XTest)同窗口活跃 → 才判「正在被远控」;产品签名表六类匹配(二进制/unit/包名/配置目录/socket/日志)
- 远程桌面产品本身 → **INFO**(环境上下文,不判可疑、不推导产品级风控结论)
- **边界红线**:不截图、不读剪贴板/按键/窗口内容/远控画面;客户端元数据(地址、键盘布局、时区、产品名)→ 交 C20

### C20 usegeo — 实际操作者会话链与地区融合(消费 C1–C19 结构化结果)
**主键 = live-session;每条证据标 subject**(host / host-egress / live-session / controller-net / local-access-net / relay-overlay / history-user)**、path、live(now/recent/history)、family(独立性分组)**。

| 子项 | 内容 |
|---|---|
| u0 | 采集者边界(见 C1);所有结果继承 scope |
| u1 | 活跃会话图(消费 C18);区分本地 seat、SSH、远程图形、service/cron/CI |
| u2 | **直接控制端**:活动 direct-ssh/mosh/rdp/vnc/可信 web-terminal 的 socket 对端 → GeoIP → CN/HK/MO = **暴露**(controller-net 实锤);default GeoIP 外联?——控制端 IP 属连接图谱,**归 --deep-geo**;但 active-probe 下可对当前**自身会话**的对端(SSH_CONNECTION 来源)查询 |
| u3 | 中继识别:direct/trusted-proxy/jump/relay/mesh/reverse-tunnel/cloud-console → 中继后不可观察 → 输出**链断点声明**(「实际操作者位置在此链路后不可直接观察」),保留全部旁证 |
| u4 | local seat 交叉:活动 seat0 + --radio 物理证据(PLMN/GNSS/opt-in WiFi geo)→ local-access-net;没有物理证据时仅 INFO |
| u5 | 会话披露元数据:sshd/RDP/VNC 客户端的 LANG/键盘/时区/客户端产品绑定到对应会话(来自 C18/C19,不读内容) |
| u6 | 时间融合:C11 交互簇 × 会话时间窗(实时 30min/近期 7d/历史 90d)按 UID 关联,避免镜像构建/CI/其他用户/陈旧痕迹归因给当前操作者 |
| u7 | 融合与矛盾:**family 去重**(同 IP 的 GeoIP/ASN/rDNS/BGP 一组;同产品日志一组;独立性来自不同接入层/会话层/时间);多独立家族同指陆港澳 → 提升 confidence;**冲突链保留**(海外出口 + CN 控制端、CN locale + 非 CN 会话)两端都报,不用单一「最终国家」覆盖 |

**输出「实际使用地区视图」**:
```
实际使用地区视图
- 当前本地交互会话:<地区/未知>,证据链 N 条,最高等级 …
- 当前远程交互会话:<按 session 分组,path 分类,地区/链断点>
- 被审计工作负载出口:IPv4 <地区(netns/exit-node 注记)>,IPv6 <地区>
- 物理接入网络(--radio):Wi-Fi/WWAN/GNSS <地区/不可用>
- 链路断点:Cloudflare Tunnel / jump host / relay / container netns / 云控制台
```

---

## 4. 公开 API 与外联边界

| 用途 | API | 模式 | 状态 |
|---|---|---|---|
| 出口 IPv4/GeoIP/rDNS/家宽机房 | ip-api.com/json(fields=…,reverse)、ipinfo.io/json | active-probe | ✅ 双源交叉 |
| 出口 IPv6 | v6.ipinfo.io、api64.ipify.org + 再查 | active-probe | ✅ |
| 路由沿途 IP(主动探测产生的路径,非用户图谱) | ip-api.com/batch | active-probe | ✅ |
| 解析器地址 GeoIP | ip-api(单发) | active-probe | ✅(外联最小集) |
| 用户连接图谱(known_hosts/对端/git remote/控制端) | ip-api batch | **--deep-geo** | ⚠️ 显式开关,开启时列出将发送的 IP 数量 |
| Wi-Fi BSSID 地理库 | 无可靠免费公开 API | **--wifi-geo** | TODO |
| MAC OUI | 本地内置表(华为/中兴/H3C/锐捷/小米/TP-Link) | passive | ✅ 本地表 |

`--offline` 关闭一切外联(转 SKIP);并发 ≤2;绝不绕过用户现有代理/路由去取「真实 IP」。

## 5. 平台矩阵与降级

**框架级依赖管理**:启动时一次探测能力集(curl/wget/dig/nslookup/ss/iptables/nft/traceroute/tracepath/mtr/lspci/lsusb/arp/loginctl/powershell.exe/systemd-detect-virt/git/sqlite3…+路径+权限),缓存全局;每个检测项声明 needs,不满足 → `SKIP(缺:xxx)`,绝不静默失败。

| 平台 | 判定 | 适配 |
|---|---|---|
| Linux 物理/VM | systemd-detect-virt、dmesg | 全量 |
| 容器 Docker/Podman | /.dockerenv、/run/.containerenv、/proc/1/cgroup | 无 systemd/wtmp/DMI/lspci → SKIP;重点保留出口/DNS/时区/locale/应用栈时区/镜像源(注明 origin=image)/env/日志时间戳/进程端口;rootless 容器同此 |
| K8s pod | cgroup kubepods、SA token、KUBERNETES_* | 同上 + cluster DNS → INFO;TZ env 注入;hostNetwork/sidecar 作用域注记 |
| LXC/LXD | /proc/1/environ container=lxc | 近 VM |
| WSL | /proc/version 含 Microsoft、WSLInterop | interop → powershell.exe(Get-Culture/Get-TimeZone/Get-WinSystemLocale 按时区规则判)、reg.exe 查 Windows 代理、Nls\Language=0804 → 可疑、Windows hosts 国内域名;WSLg 图形判定;关闭 → SKIP+提示 |
| macOS | uname -Darwin | AppleLocale/AppleLanguages、输入源、/Applications 国内 App、App Store storefront、LaunchAgents、蓝牙设备名、system_profiler |
| MSYS/Git Bash | uname MINGW/MSYS | 尽力降级(/proc 不全) |

## 6. 技术形态

- **POSIX sh**(dash/bash/busybox/zsh 兼容),统计 awk;可选增强:sqlite3、git、dig;**单文件**、自带 `--help`
- **严格只读**;模式分层(§2);`report` 函数族 + 元数据字段
- **采集红线**:绝不读取/输出私钥、密码、Cookie、token、auth key、凭据文件内容、Wi-Fi 密码、IMSI/IMEI/ICCID、完整命令历史明文、剪贴板、按键、屏幕/窗口内容、聊天文本、完整 peer 名单;掩码默认开
- **产品签名表(表驱动,可扩展)**:远程桌面族(核心 12 种先做,VDI 网关族 TODO)、ZTNA/企业 VPN 族(OpenConnect/GlobalProtect/FortiClient/Zscaler…TODO)、mesh 族(Tailscale/ZeroTier/WG 先做)、web terminal 族;六类匹配(二进制/unit/包名/配置目录/socket/日志)
- **内置数据表**:CN 骨干 AS 表、中资云特征表、国内公共 DNS 表、国内镜像域名表、污染假 IP 段表(小而保守)、陆港澳时区表+非陆港澳东八表、国内邮箱后缀表、网络设备 OUI 表、国内软件名/进程/目录/包名表、国内域名正则表、开发镜像 env 表、代理端口表、搜索引擎表、拼音用户名启发式
- **JSON schema**(v0.5):level/category/item/subject/scope/origin/freshness/path/live/family/region/confidence/redacted

## 7. 里程碑(按依赖顺序)

| 版本 | 内容 |
|---|---|
| **v0.1 ✅ 已完成** | 框架(五态/汇总/颜色/能力探测/降级/脱敏)+ C1(含 u0 采集者边界与父链探测)、C2、C8(系统层,含 TZ env 命中判定)、C9、C10、C12(btmp 默认不可读已作上下文修正)、C14 —— 实测通过(单节/brief/TZ 矛盾/模拟国内环境) |
| **v0.2 ✅ 已完成** | active-probe 四类:C3(双源交叉/rDNS/双栈一致性/--deep-geo 连接图谱)、C4(traceroute CN 骨干/网关 OUI/MTU/CGNAT;/proc/net/route 回退无 iproute2 环境)、C5(代理栈/透明代理/clash 节点命名/Tailscale/cloudflared/WARP 角色与注记)、C6(解析器识别含回环与 WARP 接管/污染探测含 Cloudflare Gateway 排除/hosts);--offline/--deep-geo;时区与出口交叉比对接入 C8;源码模块化(src/ + build.sh)—— 实测通过(本机:JP 出口双源一致、WARP DNS 接管识别、Gateway 拦截不误报) |
| **v0.3 ✅ 已完成** | 上下文层:C16 boot(引导模式/PID1/cmdline 注入检测含 TZ 判定/cloud-init 归因/rc.local/enabled 概览)、C17 kernelnet(LSM/cgroup/seccomp/netns 观测范围声明/接口物理性/路由全貌/policy routing/ip-forward)、C18 session(logind 会话图+who 回退/活跃 SSH 对端提取含 sshd_config.d 端口/自身会话对端 GeoIP/入口分类 IDE-remote·web·cloud-console/兼容 OpenSSH 9.8+ sshd-session 命名/wtmp 概览/用户级 unit);WSL interop 类(powershell 区域+时区/reg 代理与 Nls 0804/Windows hosts);ps_filtered 统一自匹配防护;tracepath 块缓冲问题用 stdbuf -oL + 后台看门狗解决 —— 实测通过(本机 5 个 logind 会话与来源识别、cloud-init 归因、VS Code/code-server 入口、全量 33s) |
| **v0.4 ✅ 已完成** | C11 时间统计全量落地(t1–t10 采集 + 簇化降噪 + 作息区间推断 + **时区一致性统一判定** + **内地法定假日/调休日历检验**,假日表 2024–2026 官方数据;git 按 email 过滤;AI 会话用户输入行滤污染);C19 gui(图形会话/XKB/IME 配置/CJK 字体/远程桌面 11 产品四态);C15 browser(7 浏览器 profile/搜索引擎/语言/国内域名计数,不读 URL 明文);C13 hw + --radio(DMI/CPU/无线/WWAN MCC/GNSS);C20 usegeo 融合视图(会话链/出口/链路断点/证据家族/冲突链,deep-geo 注册表联动);修真实 bug:进程快照防管道子进程自匹配(fcitx 假阳性)、tracepath 块缓冲、substr 偏移、--brief 直方图泄漏、单节运行跨类引用守卫 —— 实测:本机作欧 UTC+6–7.5 与 HK 时区偏差 0.5h、假日工作日活跃 213 次(混合模式判定)、deep-geo 7 对端无命中,全量 37s |
| **v0.5 ✅ 已完成(发布待用户指示)** | macOS 适配层(70-macos.sh:sw_vers/uptime、AppleLocale/首选语言/输入法、scutil --proxy、launchd 国内软件/代理栈、用户 CJK 字体、Homebrew 镜像;net_context 加 route -n get 分支;C15 双平台浏览器路径;C11 t1 加 last -F 守卫;时区/DNS/出口/会话由既有类别原生覆盖);--json(report 双写 JSON_LOG,单对象 meta{version,platform,mode}/summary{含 exit_code}/items[{level,category,item,message}]/usegeo_view[],stderr 零字节,退出码不变;修复 m4 引入的 banner 块吞掉 http_detect 的 bug);README.md(判定对照表+隐私边界+依赖降级+已知局限+免责);未实现:--session、STUN(后置)。**Gist 发布命令已就绪但未执行**(用户指示完成后先不上传):`gh gist create --public -d 'region-trace-audit v0.5 — 陆港澳用户环境痕迹检测器(只读 POSIX sh)' -f region-trace-audit.sh dist/region-trace-audit.sh -f README.md README.md` |
| 待发布 | 用户确认后执行上述 gh 命令(或先 secret 再改 public) |
| **实机验证(悉尼机,2026-10-09)** | 原始场景机器(远端 AU VPS,AlmaLinux 10.2;连接信息已脱敏):全量 195 行、退出码 1。命中(与原始会话情节完全对应):①anti/rc-ssh-fake — .bashrc 伪造 SSH_CLIENT/SSH_CONNECTION(当初的伪装本身成了马脚)②anti/sandbox-wrapper — xclaude-landlock ③time/tz-consist — 作息推断 UTC+6.0–7.5(得分 1.000,教科书级东八作息,AI 用户输入 101 条为主源)与 Australia/Sydney(UTC+11)偏差 3.5h → 长居东八者特征 ④中文 man/history(文化信号)。其余全干净:出口 AU 双源一致、en_AU、时区与出口自洽、无 CN DNS/镜像/骨干 → 伪装在实锤层成立,败在软信号+刻意痕迹层。time/cn-calendar 正确 SKIP(假日工作日仅覆盖 2 天<3)。修复:rc-ssh-fake 命中时抑制 CLEAN 冗余行;--json 远端验证通过 |

**验收 fixture 矩阵**(隔离测试机,不用真实用户数据):物理无 GUI / VM / 特权容器 / rootless 容器 / k8s pod / WSL(WSLg);systemd 与非 systemd PID1、SELinux 拒读、最小镜像、无 wtmp/journal;X11/Wayland/X11-forwarding/SSH/tmux/VS Code Remote/web terminal;远控四态(直连+relay);Tailscale 普通 peer/SSH/exit node client·server/subnet router/DERP/Headscale;cloudflared/WARP/Mesh;透明代理/policy route/CNI/双栈分流;多用户/CI/cloud-init 镜像。

## 8. 原则与边界

- 规则显式,README 附「检测项 → 判定条件」对照表;可 `--section` 单测
- 留子原则(软信号不判暴露)、中资 IDC 原则、时区三档规则(§1)、归因原则、四态分离
- 工具描述的是「本机当前可观测的网络边缘、链路、配置或历史痕迹」,输出不表述为操作人国籍/意图或平台风控结论
- 立场是**一致性体检**:不评判、不承诺规避效果
- 盲区写入 README:对话语言习惯、延迟侧信道、Windows 宿主深扫、VDI/ZTNA 扩展族(TODO 表)、Wi-Fi 地理库(opt-in TODO)、镜像构建者与运行者难区分(origin 注记缓解)

---

## 9. 附录:Codex 审计意见处置表

> 原文见 `reviews/codex-audit-2026-10-09.md`(两份报告)。处置如下:

| # | 意见(摘要) | 处置 | 说明 |
|---|---|---|---|
| 1 | 结果元数据 scope/origin/freshness/confidence/redact | ✅ 采纳 | §1;JSON 全量、文本简写 |
| 2 | origin 归因(image/admin/user/other) | ✅ 采纳 | 镜像/cloud-init 痕迹不归因用户(C16/C8/C9) |
| 3 | installed/enabled/listening/active 四态分离 | ✅ 采纳 | §1 + C14/C19/C20 |
| 4 | 采集模式分层 passive/local-daemon/active-probe/sensitive | ✅ 采纳(微调) | active-probe 默认开(本工具核心就是网络泄露检测)、`--offline` 可关;sensitive → `--deep-geo`/`--wifi-geo` |
| 5 | 默认外联最小集;连接图谱批量 GeoIP 需显式开关 | ✅ 采纳 | §4;known_hosts/对端/git remote → --deep-geo;路由沿途(主动探测产物)保留 active-probe |
| 6 | 掩码默认开 | ✅ 采纳 | 默认轻度脱敏,--reveal 显式 |
| 7 | 不读凭据/剪贴板/按键/内容红线 | ✅ 采纳 | §6 采集红线 |
| 8 | 新增 C16 boot / C17 kernel / C18 session / C19 gui | ✅ 采纳(精简) | §3;保留生命周期语义,细节并入 |
| 9 | C5 扩展 overlay/连接器角色(Tailscale 四角色、cloudflared/WARP/Mesh 区分) | ✅ 采纳 | C5;凭据只测存在性;userspace networking 检出 |
| 10 | C20 usegeo:会话图/控制端/中继/融合 | ✅ 采纳(裁剪) | 核心链 u0–u7;VDI/ZTNA/串流全家桶 → 签名表 TODO |
| 11 | 活动直接控制端 CN/HK/MO = actual-use 暴露 | ✅ 采纳 | §1 暴露清单 + C20-u2 |
| 12 | family 去重、冲突链保留、链断点声明 | ✅ 采纳 | C20-u3/u7 |
| 13 | SSH_* 缺失需先确认 sshd 会话上下文 | ✅ 采纳(技术修正) | C12:tmux/su/service 上下文 → INFO,不误报 |
| 14 | 日志不可读默认 SKIP/INFO | ⚠️ 部分采纳 | 保留「不可读=可疑」(既定决策),加上下文修正:容器 SKIP、新装 INFO、其余可疑 |
| 15 | 进程 TZ/LANG 差异多为正常 | ⚠️ 部分采纳 | 保留检测,service manager 正常差异 → INFO 注记 |
| 16 | GeoIP 单源默认 INFO、需交叉才升级 | ⚠️ 部分采纳 | 不降级别;采纳为实现要求:双源交叉、污染≥2 域名、路由多锚点,confidence 字段体现 |
| 17 | 时区/locale 不得 EXPOSED;东八错配仅「配置不一致」 | ❌ 不采纳 | 与既定规则冲突(用户拍板:陆港澳时区、东八错配=暴露);采纳其 scope 注记(出口观测 netns/exit-node 附注) |
| 18 | VDI 网关/企业 ZTNA/非传统图形路径(waypipe/Steam 串流/v4l2loopback)逐项检测 | ⚠️ 后置 | 产品签名表表驱动;核心集先做,扩展族 TODO |
| 19 | Wi-Fi 地理库/GNSS/PLMN | ⚠️ 后置 | --radio 物理桌面场景;地理库外联 --wifi-geo TODO |
| 20 | L2 企业接入(LLDP/CDP/802.1X/DHCP opt 43/121) | ⚠️ 后置 | 精简保留 DHCP 域/NTP 线索,其余 TODO |
| 21 | fixture/隔离测试机验收矩阵 | ✅ 采纳(精简) | §7 |
| 22 | 主目标改写为「实际使用地区优先」 | ⚠️ 部分采纳 | 工具定位不变(痕迹检测);usegeo 作为最强证据链并入(§1/C20),不改叙事 |

## 10. 审计处置(current-state-audit-2026-10-09)

| # | 审计发现 | 处置 | 实现与验证 |
|---|---|---|---|
| 1 | 高:--json 可被未转义环境值破坏;`\|` 分隔符丢数据 | ✅ 采纳 | report() 经 json_escape 预转义(反斜杠/引号/制表/回车、换行合并 `\n`、竖线→`\u007c`、tr 删控制字符);json_emit 不再二次转义;usegeo_view 同样转义。注入复现通过(值完整保留、JSON 合法);修复过程中另发现自己引入的 stdin 丢失 bug(awk 未喂参 → 全部 message 空)已修 |
| 2 | 高:--section 静默丢跨类上下文 | ⚠️ 部分采纳 | 单项模式输出全局警示行(main/section-mode,JSON 模式进 items);`c20` 别名;time/usegeo 单项运行时就地采集 TZ_NAME/TZ_CLASS/LOCALE_ZH(/etc/localtime + locale.conf)。不做依赖图禁止输出 —— 单项调试是合法用途,警示优于静默失败 |
| 3 | 高:SSH 对端未绑定会话、仅 IPv4、端口复用误判 | ⚠️ 部分采纳 | ① socket inode→自有 sshd 会话进程绑定(强归属;Yama/SELinux 加固机 fd 不可读时优雅降级为端口级并如实标注);② tcp6 支持:v4-mapped 归一为 IPv4、原生 v6 保留(展示/GeoIP 由 HTTPS 源支持);③ 端口自举:经 SSH_CONNECTION 对端反推 sshd 监听端口(应对 sshd_config 600 加固)。**顺带修出三个潜伏 bug**:/proc/net/tcp 小端字节序(v0.3 起对端 raw 打印为字节反转)、端口表十进制被 h2d 按十六进制解析(v0.3 起端口匹配从未工作过)、v4-mapped 检测条件错位 8 字符。mosh/RDP/VNC socket 绑定 → 后置(需 root/ptrace 宽松)。悉尼机实测:自举非标 SSH 端口 → 端口级对端(地址已脱敏)正确检出 |
| 4 | 高:GeoIP 明文 HTTP、双源不一致不降级 | ⚠️ 部分采纳 | geoip1 主源换 HTTPS(ipwho.is,支持 v4/v6),ip-api 回退;C3 出口暴露级判定改为**双源一致才 EXPOSED**,单源命中或双源不一致 → SUSPICIOUS(证据降级,结构化措辞)。deep-geo 批量仍走 ip-api HTTP(免费层无 HTTPS 批量)→ 已有外联注记,后置 |
| 5 | 高:headless 输入法/字体误报;UU/CRD/Parsec 遗漏 | ✅ 采纳 | IME/字体加 _gui 门控(headless 命中 → INFO 降级并注明可能为依赖/残留);远程桌面表补 UU远程(网易)/Chrome Remote Desktop/Parsec(UU 无固定端口 → binary/unit/目录/进程四重签名) |
| 6 | 中:C17 观测范围远小于计划 | ⚠️ 部分采纳 | 补 if_inet6 前缀数、iptables 表存在性、nftables 表计数(均非 root 可得;规则明细注记需 root);完整多表/VRF/TC/XDP/eBPF → 后置 |
| 7 | 中:mesh/tunnel 仅上下文非活动链路 | ⚠️ 部分采纳 | tailscale 补 peers 概要(direct/DERP 中继计数,地址不输出);cloudflared 连接状态需读凭据 → 后置;mesh 内位置不可观察已由链路断点声明覆盖 |
| 8 | 中:C16 两处实现错误 | ✅ 采纳 | `$_cli` 笔误 → `$_ci`;ignition `\|\|`/`&&` 优先级 → if/then 结构化 |
| 9 | 中:JSON 元数据(scope/origin/freshness/confidence)未落字段 | 后置 v0.6 | 需全 check 改造为结构化记录;当前由 message 中文承载,下游不可按字段消费 —— 已列入 v0.6 候选 |
| 10 | 低:C20 证据家族字符串协议扩展安全 | 后置 | 固定名称现状安全;随 #9 结构化一并 |
| 11 | 建议:回归夹具 | ✅ 部分采纳 | tests/test-json-injection.sh(注入复现)+ tests/test-time-compound.sh(复合升级正/负例)已入库并全部通过 |

**本轮净结果**:高危 5 项中 3 采纳 2 部分采纳;额外修复 4 个此前未知的潜伏 bug(小端字节序、端口 hex 解析、v4-mapped 条件、json_escape stdin)。全量回归 37s rc=2 无变化;headless 字体项正确降级(可疑 3→2);悉尼机会话对端检出能力从 0 → 端口级+自举。
