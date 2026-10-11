# 当前实施审计报告

审计日期：2026-10-09  
审计对象：`env-trace-audit` 当前 `src/` 脚本组、`build.sh`、`dist/region-trace-audit.sh`、`README.md` 与 `PLAN.md`。  
审计目标：核对“实际使用地区/实际操作者地区”检测策略是否已经落到脚本和产物，检查从启动、内核、网络、会话到终端和 GUI 的漏检、误判及产物契约问题。

## 审计结论

当前版本已经形成可构建的 C1–C20 模块化检测器，`dist` 与源码拼接结果一致，常规离线 JSON 也能被解析。检测面已经覆盖启动、云初始化、网络出口、路径、代理/mesh、DNS、文件系统、服务、会话、WSL、GUI、浏览器、硬件、时间和实际使用地区融合。

但“已接入”与“可据此稳定判断实际操作者地区”之间仍有明显差距。下面的高优先级问题会导致机器可读产物失效、单项运行时静默漏掉前置证据，或把普通网络连接误当成控制端；这些问题应优先补强。报告只记录审计结果，没有修改脚本、构建产物或 `PLAN.md`。

## 发现

### 高：`--json` 可被本机未转义值破坏，且管道分隔符会丢数据

位置：[src/20-framework.sh](/home/steven/pi-cwd-default/env-trace-audit/src/20-framework.sh:18)、[src/20-framework.sh](/home/steven/pi-cwd-default/env-trace-audit/src/20-framework.sh:46)

`report()` 将原始描述直接拼入 `level|item|desc`，`json_emit()` 再用 `awk -F'|'` 拆分。JSON 转义只处理反斜杠和双引号，没有处理换行、制表符、回车等控制字符；描述中出现 `|` 时也会被截断。由于描述包含代理、环境变量、配置文件和外部响应的内容，这不是理论上的固定字符串问题。

复现：

```sh
env -i PATH="$PATH" HOME="$HOME" \
  http_proxy=$'http://127.0.0.1:8080\n"injected"' \
  ./dist/region-trace-audit.sh --offline --json --section proxy | jq .
```

命令退出码仍为 0，但 `jq` 报 JSON 解析错误。带 `|` 的值可以解析，却会在 `awk -F'|'` 处丢失后半段。README 和 CLI 都承诺 `--json` 输出单一机器可读 JSON 对象，因此这属于产物契约级问题。

### 高：`--section` 会静默删除跨类别上下文，导致 C20、C11、C18 得出不完整结论

位置：[src/90-main.sh](/home/steven/pi-cwd-default/env-trace-audit/src/90-main.sh:65)、[src/90-main.sh](/home/steven/pi-cwd-default/env-trace-audit/src/90-main.sh:69)、[src/10-options.sh](/home/steven/pi-cwd-default/env-trace-audit/src/10-options.sh:17)

完整运行会先执行 `detect_platform`、`collector_context`、`http_detect`、`net_context`，再顺序运行所有类别；指定 `--section` 时只运行目标函数。`usegeo` 依赖 `SELF_PEER_CC`、`EGRESS_CC`、`TZ_CLASS`、`LOCALE_ZH`、`TZ_INFER_E8`、`RADIO_ACCESS_CC` 等其他类别设置，`time` 依赖 locale/时区上下文，`session` 的会话图也依赖前置采集。单独运行这些类别不会报“依赖未运行”，而是以退出码 0 生成看似完整的低证据结论。

实际验证：`--offline --json --section usegeo` 返回 0，视图显示没有会话、出口和证据家族；`--offline --json --section time` 把本可由 locale 类提供的时区上下文报告为跳过；`--section c20` 又因公开类别名只有 `usegeo` 而返回 64。CLI 的类别名、计划中的 C20 编号和跨类别依赖需要统一，至少应在单项运行时显式标明“上下文不完整”。

### 高：活动 SSH 对端没有绑定到实际 sshd 会话，且只覆盖 IPv4

位置：[src/63-c18-session.sh](/home/steven/pi-cwd-default/env-trace-audit/src/63-c18-session.sh:53)、[src/63-c18-session.sh](/home/steven/pi-cwd-default/env-trace-audit/src/63-c18-session.sh:63)、[src/63-c18-session.sh](/home/steven/pi-cwd-default/env-trace-audit/src/63-c18-session.sh:79)

代码通过 `/proc/net/tcp` 中“本地端口等于 sshd 监听端口且状态为 ESTABLISHED”来收集对端，但没有把 socket inode 映射到 sshd 子进程、UID、TTY 或会话。端口被其他服务复用、代理转发或容器内监听时，结果不能证明该地址是交互操作者。`SSH_CONNECTION` 只对当前 shell 的第一个来源地址做 GeoIP；其它对端仅留在 `--deep-geo`，而后者同样只读 `/proc/net/tcp`，不读 `tcp6`、UDP/mosh 或 RDP/VNC/web-terminal 的会话 socket。

这与计划中“活动 direct-ssh/mosh/rdp/vnc/web-terminal 控制端”的强语义不一致。当前结果适合表示“发现疑似 SSH 端口对端”，不宜直接作为实际操作者地区实锤，除非补上 socket/进程/会话归属和 IPv6/其他入口覆盖。

### 高：GeoIP 主路径使用明文 HTTP，双源不一致也不会降低结论等级

位置：[src/40-netlib.sh](/home/steven/pi-cwd-default/env-trace-audit/src/40-netlib.sh:11)、[src/40-netlib.sh](/home/steven/pi-cwd-default/env-trace-audit/src/40-netlib.sh:48)、[src/52-c3-egress.sh](/home/steven/pi-cwd-default/env-trace-audit/src/52-c3-egress.sh:18)

出口 IPv4、单 IP GeoIP 和 `--deep-geo` 批量查询使用 `http://ip-api.com`；通用 `http_get()` 没有证书、代理绕过或响应完整性校验。网络代理或中间设备可篡改国家码、组织名和 reverse 字段，直接影响 EXPOSED/SUSPICIOUS 判定。

C3 虽然同时查询 `https://ipinfo.io/json`，但 `双源不一致` 只写进 INFO 文本，出口国家的 EXPOSED 仍完全由 ip-api 主源决定；没有结构化冲突状态、重试策略或置信度降级。`--deep-geo` 还会把活跃 IPv4 对端和 `known_hosts` 地址发送到 ip-api，隐私和传输完整性风险应在产物中明确分级。

### 高：GUI 检测存在无 GUI 环境下的中文输入法误报，且遗漏用户明确关心的 UU 远程控制

位置：[src/65-c19-gui.sh](/home/steven/pi-cwd-default/env-trace-audit/src/65-c19-gui.sh:52)、[src/65-c19-gui.sh](/home/steven/pi-cwd-default/env-trace-audit/src/65-c19-gui.sh:57)、[src/65-c19-gui.sh](/home/steven/pi-cwd-default/env-trace-audit/src/65-c19-gui.sh:77)、[PLAN.md](/home/steven/pi-cwd-default/env-trace-audit/PLAN.md:232)

注释写明输入法配置“仅图形/桌面上下文才判软信号；headless 下存在即 INFO”，但实际读取配置文件命中拼音/双拼/五笔后无条件报告 `SUSPICIOUS gui/ime`，没有检查 `_gui`。同一模块对 CJK 字体也无 GUI 条件，因而纯服务器镜像或构建残留可能产生可疑项。

远程桌面表目前只有 xrdp、VNC、x11vnc、RustDesk、AnyDesk、TeamViewer、ToDesk、向日葵、NoMachine、Sunshine、GNOME Remote Desktop；没有 `UU`，也没有计划中列出的 Chrome Remote Desktop、Parsec 等。产品状态也只按端口表判断 listening/connected，没有把端口绑定到产品 PID 或实际会话。用户此前提到的“UU 远程被检测到”目前没有对应检测项。

### 中：C17 内核网络观测范围远小于计划中的“全信息级”

位置：[src/62-c17-kernelnet.sh](/home/steven/pi-cwd-default/env-trace-audit/src/62-c17-kernelnet.sh:36)、[src/62-c17-kernelnet.sh](/home/steven/pi-cwd-default/env-trace-audit/src/62-c17-kernelnet.sh:60)

当前只比较当前进程和 PID 1 的网络命名空间，只统计 `/proc/net/route` 主表行数和非默认 `ip rule` 数量。没有输出或比较 PID/mount/UTS/IPC/user namespace，未覆盖 IPv6 路由、完整多表/VRF 归属、nftables/iptables、TC/XDP/eBPF、cgroup 网络或每个会话实际使用的 netns。计划对 C17 的“观测范围声明”是合理的，但实现应明确是“当前进程 netns 的低层摘要”，不能让用户误解为完整内核网络取证。

### 中：Tailscale、Cloudflare Tunnel/WARP 和通用 mesh 目前是上下文信息，不是活动链路证明

位置：[src/54-c5-proxy.sh](/home/steven/pi-cwd-default/env-trace-audit/src/54-c5-proxy.sh:78)、[src/54-c5-proxy.sh](/home/steven/pi-cwd-default/env-trace-audit/src/54-c5-proxy.sh:90)、[src/54-c5-proxy.sh](/home/steven/pi-cwd-default/env-trace-audit/src/54-c5-proxy.sh:106)

现有检测能发现 `tailscale0`/`tailscaled`、`exit node` 文本、cloudflared/WARP 进程及配置、常见 mesh/反向隧道进程，并把它们报告为 INFO 或链路断点。这满足“提供信息”的要求，但没有读取 Tailscale peer/DERP/direct 状态、Cloudflare Tunnel 连接状态、实际 socket 路径、UID/会话绑定或默认路由之外的分流规则。因此不能据此判断实际操作者来自哪个地区，也不能证明某个交互会话确实经由该 mesh/隧道进入。

### 中：C16 引导来源有两个确定的实现错误

位置：[src/61-c16-boot.sh](/home/steven/pi-cwd-default/env-trace-audit/src/61-c16-boot.sh:66)、[src/61-c16-boot.sh](/home/steven/pi-cwd-default/env-trace-audit/src/61-c16-boot.sh:80)

1. 同时存在 `/etc/cloud` 和 `/var/lib/cloud` 时，第 69 行使用未定义的 `$_cli`，会丢掉前一个路径，导致 cloud-init 来源展示不完整。
2. 第 80 行的 `||`/`&&` 未加括号。按 shell 运算优先级，若 `/var/lib/ignition` 存在而 `/usr/lib/ignition` 不存在，条件整体为真但不会执行 `report`，会漏报一个有效 Ignition 来源。

这两个问题主要影响启动来源归因，不会直接改变出口 GeoIP，但会削弱“镜像/管理员注入还是当前用户行为”的解释链。

### 中：计划声明的结果元数据尚未落到 JSON 项目

位置：[PLAN.md](/home/steven/pi-cwd-default/env-trace-audit/PLAN.md:16)、[src/20-framework.sh](/home/steven/pi-cwd-default/env-trace-audit/src/20-framework.sh:30)

计划要求 JSON 全量携带 `scope`、`origin`、`freshness`、`confidence`、`redact`。当前 JSON 的 `meta` 只有版本、平台、生成时间和模式；每个 item 只有 `level/category/item/message`。来源归因、当前 netns、活动/已启用/已安装状态等信息被嵌在中文 message 中，不能稳定供下游按字段消费。C16、C17、C18、mesh 和 GUI 的解释尤其依赖这些缺失的结构化上下文。

### 低：C20 融合实现仍偏向字符串协议，难以保证长期扩展安全

位置：[src/69-c20-usegeo.sh](/home/steven/pi-cwd-default/env-trace-audit/src/69-c20-usegeo.sh:87)

证据家族和链路断点目前以空格分隔的字符串传递，再通过 `tr`/`grep` 计数。现有固定名称可以工作，但新增带空格、括号或分隔符的家族时容易改变计数或排除逻辑。随着 C20 增加 UU、mesh、web-terminal、IPv6 等入口，建议把家族、来源、强度和断点改成不会依赖描述文本分词的内部记录格式；这属于扩展可靠性问题，不是当前固定样例必现的误判。

## 覆盖状态

| 范围 | 当前状态 | 审计判断 |
|---|---|---|
| 引导/启动/云初始化/显示管理器 | 已实现 C16 | 有来源归因，但存在 cloud-init 路径和 Ignition 条件错误 |
| 内核/容器/netns/路由 | 已实现 C17 | 只覆盖当前进程 netns 的摘要，远未达到完整内核网络面 |
| 出口、IPv6、路径、DNS、代理、Tailscale、Cloudflare | 已实现 C3–C6 | 具备信息输出；GeoIP 传输与双源冲突处理需补强，mesh 仅作上下文 |
| 用户/终端/SSH/SSM/web terminal | 已实现 C18 | 入口识别较全，但活动控制端的 socket、进程、用户绑定不足 |
| GUI/远程桌面/输入法/字体 | 已实现 C19 | 有四态框架，但 headless 输入法判定和产品覆盖需要修正/增加 |
| 时间、作息、浏览器、文件、服务、硬件 | 已实现 C8–C15 | 以软信号和上下文为主，符合“只做加法”的策略；结构化来源元数据不足 |
| 实际使用地区融合 | 已实现 C20 | 能融合出口、时区、locale、会话和 radio；独立运行时会缺上下文，部分会话证据仍不完整 |

## 已验证通过

- `sh -n` 对全部 `src/*.sh`、`dist/region-trace-audit.sh`、`build.sh` 通过。
- 按 `build.sh` 的顺序拼接源码与当前 `dist/region-trace-audit.sh` 做字节比较，通过；当前产物为 3374 行、可执行。
- `--help` 和未知类别退出码行为正常；`--offline --brief` 能按本机证据返回非零判定码。
- 普通数据下 `--offline --json` 输出单个可被 `jq` 解析的 JSON，`summary.exit_code` 与 shell 退出码一致。
- `--deep-geo` 默认关闭，README 和 CLI 已告知会向 ip-api 发送对端 IP；`--offline` 能跳过外联项。
- 未发现自动化测试/fixture 目录；当前验证主要是语法、构建一致性、CLI 冒烟和 JSON 解析，尚无覆盖 C20 跨类别依赖、恶意环境值、IPv6 会话和 GUI 变体的回归测试。

## 后续审查重点

按用户要求保留现有检测策略并做加法时，建议优先补以下验证和字段：

1. 先固定 JSON 编码器/转义和内部记录格式，再把所有报告字段结构化，避免描述文本同时承担数据协议。
2. 为 `--section` 建立依赖图；目标类别缺前置上下文时返回 SKIP/不完整标记，不输出看似完整的 0 证据结论。
3. 将 SSH、RDP/VNC、web-terminal、mosh、mesh 的 socket 映射到 PID/UID/会话，并补 IPv6；把“端口存在”“服务活动”“交互控制端”分开。
4. 增加 UU、Chrome Remote Desktop、Parsec 及可扩展签名表，同时让输入法/字体文化信号遵守 GUI/headless 上下文条件。
5. 对 GeoIP 主源改用 HTTPS 或增加可验证的响应策略；双源不一致时输出结构化冲突并降低置信度，深 GeoIP 明确 IPv4/IPv6、来源类别和隐私范围。
6. 为 C16、C17、C18、C19、C20 和 JSON 注入场景加入最小 shell 回归夹具，覆盖容器、WSL、无 GUI、IPv6、代理变量换行/引号/分隔符等输入。

