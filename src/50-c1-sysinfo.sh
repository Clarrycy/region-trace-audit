#────────────────────────────── C1 sysinfo ──────────────────────────────
# 模块: 50-c1-sysinfo.sh

check_c1() {
  hdr "C1 sysinfo · 系统与平台"

  # 发行版与内核
  _pretty="unknown"
  [ -r /etc/os-release ] && _pretty=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -n 1)
  report INFO sysinfo/os "$_pretty · $(uname -sr) · $(uname -m)"

  # 平台判定
  report INFO sysinfo/platform "平台: $PLATFORM${PLATFORM_NOTE:+ · $PLATFORM_NOTE}"

  # 采集者边界(u0)
  _tty=$(tty 2>/dev/null) || _tty=""
  case "$_tty" in ""|*"not a tty"*) _tty="无tty" ;; *) _tty="${_tty#/dev/}" ;; esac
  report INFO sysinfo/collector "采集者: uid=$CUR_UID($CUR_USER) · tty=$_tty · 父链: ${PARENT_CHAIN:-?}${IN_SSH_CHAIN:+ [sshd]}${IN_MUX:+ [mux]}"

  # uptime
  if [ -r /proc/uptime ]; then
    _up=$(cut -d. -f1 /proc/uptime)
    report INFO sysinfo/uptime "运行时长: $((_up/86400)) 天 $(((_up%86400)/3600)) 小时"
  else
    report SKIP sysinfo/uptime "(/proc/uptime 不可读)"
  fi

  # 系统安装时间(machine-id 时间估算,与 C12 新装判定共用)
  _it=$(fs_btime /etc/machine-id)
  [ -z "$_it" ] && _it=$(fs_btime /lost+found 2>/dev/null)
  if [ -n "$_it" ] && [ "$_it" != 0 ]; then
    _now=$(date +%s)
    INSTALL_AGE_DAYS=$(( (_now - _it) / 86400 ))
    [ "$INSTALL_AGE_DAYS" -lt 0 ] && INSTALL_AGE_DAYS=0
    report INFO sysinfo/install-age "系统约安装于 $INSTALL_AGE_DAYS 天前(machine-id 时间估算)"
  else
    report SKIP sysinfo/install-age "(无法取 machine-id/lost+found 时间)"
  fi

  # 连接方式
  if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    _src=$(printf '%s' "${SSH_CONNECTION:-$SSH_CLIENT}" | awk '{print $1}')
    report INFO sysinfo/session "连接方式: SSH(来源 $(mask_ip "${_src:-?}"), pts=${SSH_TTY#*/dev/})"
  elif [ "$IN_SSH_CHAIN" = 1 ]; then
    report INFO sysinfo/session "连接方式: SSH(父链含 sshd,但 env 无 SSH_* 变量 —— 见 anti 类)"
  elif have who; then
    _wai=$(who am i 2>/dev/null | awk '{print $NF}')
    case "$_wai" in
      "("*")") report INFO sysinfo/session "连接方式: 远程会话(who: $(mask_ip "$(printf '%s' "$_wai" | tr -d '()')"),来源工具未知)" ;;
      *) report INFO sysinfo/session "连接方式: 本机/非交互($([ "$IN_MUX" = 1 ] && printf '经 tmux/screen;')无 SSH 环境)" ;;
    esac
  else
    report INFO sysinfo/session "连接方式: 本机/非交互(who 不可用)"
  fi

  # TCP 拥塞控制
  if [ -r /proc/sys/net/ipv4/tcp_congestion_control ]; then
    _cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
    case "$_cc" in
      bbr) report INFO sysinfo/tcp-cc "拥塞控制 bbr(国内用户常用配置,海外亦常见,仅作提示)" ;;
      *)   report INFO sysinfo/tcp-cc "拥塞控制 ${_cc:-default}" ;;
    esac
  else
    report SKIP sysinfo/tcp-cc "(/proc/sys 不可读)"
  fi

  # 登录用户列表
  if have who && who 2>/dev/null | grep -q .; then
    _n=$(who 2>/dev/null | grep -c . )
    _rem=$(who 2>/dev/null | grep -cE '\([0-9a-fA-F.:]+\)')
    report INFO sysinfo/logins "在线会话 $_n 个(其中远程来源 $_rem 个,值已脱敏)"
  else
    report SKIP sysinfo/logins "(who 不可用/无会话记录)"
  fi
}
