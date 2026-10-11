#────────────────────────────── 平台与采集者上下文 ──────────────────────────────
# 模块: 41-context.sh

PLATFORM=""; PLATFORM_NOTE=""
IN_SSH_CHAIN=0; IN_MUX=0; PARENT_CHAIN=""; MY_PIDS=" "
CUR_USER=""; CUR_UID=""
ROUTE_IFACE=""; ROUTE_SRC=""; ROUTE_GW=""; NET_ANNOT=""
EGRESS_CC=""; EGRESS_TZ=""; EGRESS_CC6=""
# ── 结构化证据注册表(供 C20 usegeo 消费;各 check 写入) ──
TZ_NAME=""; TZ_CLASS=""; LOCALE_ZH=0            # C8
SESS_N=0; SESS_LOCAL_N=0; SESS_REMOTES=""       # C18
SESS_ENTRIES=""; SELF_PEER=""; SELF_PEER_CC=""  # C18
DG_IPCC=""                                      # C3 deep-geo(ip=CC 注册表)
NETNS_ISOLATED=0                                # C17
OVERLAY_BREAKS=""                               # C5(链路断点)
TZ_INFER_OFF=""; TZ_INFER_CONF=""; TZ_INFER_N=0; TZ_INFER_E8=no  # C11
RD_CONNECTED=""                                 # C19(远控活动会话)
RADIO_ACCESS=""; RADIO_ACCESS_CC=""             # C13 --radio
USEGEO_VIEW=""                                  # C20(汇总区视图)
PS_SNAP=""                                      # 进程快照(ps_filtered 数据源)

detect_platform() {
  PLATFORM="linux"; PLATFORM_NOTE=""
  case "$(uname -s)" in
    Darwin) PLATFORM="macos"; PLATFORM_NOTE="macOS(基础检测,完整适配 v0.5)" ;;
    MINGW*|MSYS*) PLATFORM="msys"; PLATFORM_NOTE="MSYS/Git Bash(/proc 不全,尽力降级)" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM="wsl"; PLATFORM_NOTE="WSL(Windows interop 检测 v0.3)"
      elif [ -f /.dockerenv ]; then
        PLATFORM="container-docker"; PLATFORM_NOTE="Docker 容器(wtmp/DMI/lspci 等项将 SKIP)"
      elif [ -f /run/.containerenv ]; then
        PLATFORM="container-podman"; PLATFORM_NOTE="Podman 容器"
      elif grep -q kubepods /proc/1/cgroup 2>/dev/null; then
        PLATFORM="container-k8s"; PLATFORM_NOTE="K8s pod(cluster DNS/SA 见 services 类)"
      elif cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep -q '^container=lxc'; then
        PLATFORM="container-lxc"; PLATFORM_NOTE="LXC(近 VM 处理)"
      else
        _v=""
        if have systemd-detect-virt; then
          _v=$(systemd-detect-virt --vm 2>/dev/null)
        fi
        case "$_v" in ""|none)
          if have dmesg && dmesg 2>/dev/null | head -n 200 | grep -qiE 'hypervisor|kvm|vmware|xen|virtual box|virtualbox'; then
            _v="dmesg-hint"
          elif [ -r /sys/class/dmi/id/sys_vendor ]; then
            case "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" in
              QEMU*|VMware*|Xen*|Microsoft\ Corporation|Amazon*|OpenStack*|innotek*) _v="dmi-hint" ;;
            esac
          fi ;;
        esac
        case "$_v" in
          ""|none) PLATFORM_NOTE="物理机/未识别虚拟化" ;;
          *)       PLATFORM_NOTE="虚拟机($_v)" ;;
        esac
      fi ;;
    *) PLATFORM_NOTE="未知内核 $(uname -s),尽力降级" ;;
  esac
}

# u0:采集者边界 —— 脚本自身的运行上下文(所有结果继承此 scope)
collector_context() {
  CUR_USER=$(id -un 2>/dev/null || printf '?')
  CUR_UID=$(id -u 2>/dev/null || printf '?')
  _p=$$; _i=0; MY_PIDS=" $$ "
  while [ "$_i" -lt 6 ]; do
    _pp=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
    if [ -z "$_pp" ] || [ "$_pp" = "0" ] || [ "$_pp" = "1" ]; then break; fi
    MY_PIDS="$MY_PIDS $_pp "
    _pn=$(ps -o comm= -p "$_pp" 2>/dev/null | awk 'NR==1{print $1}' 2>/dev/null)
    [ -z "$_pn" ] && break
    PARENT_CHAIN="${PARENT_CHAIN:+$PARENT_CHAIN → }$_pn"
    case "$_pn" in
      sshd)          IN_SSH_CHAIN=1 ;;
      tmux*|screen*) IN_MUX=1 ;;
    esac
    _p=$_pp; _i=$((_i+1))
  done
  # 进程快照(排除自身进程树;供 ps_filtered 使用,防管道子进程自匹配)
  PS_SNAP=$({ ps aux 2>/dev/null || ps -ef 2>/dev/null; } | awk -v pids="$MY_PIDS" 'index(pids, " " $2 " ") == 0')
}

# 网络上下文(出口注记用;本地操作,不外联)
net_context() {
  if have ip; then
    _rt=$(ip route get 1.1.1.1 2>/dev/null | head -n 1)
    ROUTE_IFACE=$(printf '%s' "$_rt" | sed -n 's/.* dev \([^ ]*\).*/\1/p')
    ROUTE_SRC=$(printf '%s' "$_rt" | sed -n 's/.* src \([0-9a-fA-F.:]*\).*/\1/p')
    ROUTE_GW=$(printf '%s' "$_rt" | sed -n 's/.* via \([0-9a-fA-F.:]*\).*/\1/p')
  elif [ "$PLATFORM" = macos ] && have route; then
    _rt=$(route -n get 1.1.1.1 2>/dev/null)
    ROUTE_IFACE=$(printf '%s' "$_rt" | sed -n 's/.*interface: //p')
    ROUTE_SRC=$(printf '%s' "$_rt" | sed -n 's/.*local address: //p')
    ROUTE_GW=$(printf '%s' "$_rt" | sed -n 's/.*gateway: //p')
  elif [ -r /proc/net/route ]; then
    # 回退:默认路由(Destination=00000000)的网关小端 hex + 接口名
    _line=$(awk '$2=="00000000"{print $1, $3; exit}' /proc/net/route 2>/dev/null)
    if [ -n "$_line" ]; then
      ROUTE_IFACE=$(printf '%s' "$_line" | awk '{print $1}')
      ROUTE_GW=$(hex2ip "$(printf '%s' "$_line" | awk '{print $2}')")
    fi
    have hostname && ROUTE_SRC=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  case "$ROUTE_IFACE" in
    tun*|tap*|wg*|ppp*|tailscale*) NET_ANNOT="经隧道接口 $ROUTE_IFACE" ;;
  esac
  if [ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${all_proxy:-}" ]; then
    NET_ANNOT="${NET_ANNOT:+$NET_ANNOT;}经环境代理"
  fi
  case "$PLATFORM" in
    container-*) NET_ANNOT="${NET_ANNOT:+$NET_ANNOT;}容器内观测(NAT 后出口)" ;;
  esac
}
