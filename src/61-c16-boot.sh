#────────────────────────────── C16 boot ──────────────────────────────
# 模块: 61-c16-boot.sh
# 定位:上下文层 —— 引导与初始化来源,为其他类别的命中提供「谁设置的」归因

check_c16() {
  hdr "C16 boot · 引导、初始化与持久化来源"

  case "$PLATFORM" in
    container-*)
      report SKIP boot/all "(容器环境,引导链与固件不可见)"
      return ;;
  esac

  # ── 引导模式 ──
  if [ -d /sys/firmware/efi ]; then
    report INFO boot/mode "UEFI 引导"
  elif [ -d /sys/firmware ]; then
    report INFO boot/mode "BIOS/Legacy 引导"
  else
    report SKIP boot/mode "(/sys/firmware 不可见 —— WSL/受限环境常见)"
  fi

  # ── PID 1 ──
  _pid1=$(cat /proc/1/comm 2>/dev/null | tr -d '[:space:]')
  if [ "$_pid1" = "systemd" ]; then
    report INFO boot/pid1 "PID 1 = systemd"
  else
    report INFO boot/pid1 "PID 1 = ${_pid1:-未知}(非 systemd —— 部分服务类检测将 SKIP)"
  fi

  # ── kernel cmdline:注入检测(只提取 TZ/LANG/ip= 类参数) ──
  _cm=$(cat /proc/cmdline 2>/dev/null)
  if [ -n "$_cm" ]; then
    _tzinj=$(printf '%s' "$_cm" | sed -n 's/.*systemd\.setenv=TZ=\([^ ]*\).*/\1/p' | head -n 1)
    if [ -n "$_tzinj" ]; then
      case "$(tz_class "$_tzinj")" in
        CN|HKMO) report EXPOSED boot/cmdline-tz "cmdline 注入 TZ=$_tzinj(陆港澳确定时区)" ;;
        E8)      report INFO boot/cmdline-tz "cmdline 注入 TZ=$_tzinj(东八非陆港澳;与出口比对见 locale 类)" ;;
        *)       report INFO boot/cmdline-tz "cmdline 注入 TZ=$_tzinj" ;;
      esac
    fi
    _langinj=$(printf '%s' "$_cm" | sed -n 's/.*systemd\.setenv=LANG=\([^ ]*\).*/\1/p' | head -n 1)
    case "${_langinj:-}" in
      zh_CN*|zh_HK*|zh_MO*) report SUSPICIOUS boot/cmdline-lang "cmdline 注入 LANG=$_langinj(文化习惯类信号)" ;;
    esac
    case "$_cm" in
      *" ip="*|*ip=dhcp*|*ip=dhcp6*) report INFO boot/cmdline-net "cmdline 含 ip= 网络参数(网络启动/PXE/云镜像)" ;;
    esac
    report INFO boot/cmdline "cmdline $(printf '%s' "$_cm" | wc -w | tr -d ' ') 个参数(已做分类提取,不记录完整内容)"
  else
    report SKIP boot/cmdline "(不可读)"
  fi

  # ── default target / 显示管理器 ──
  if have systemctl && systemctl get-default >/dev/null 2>&1; then
    report INFO boot/target "默认 target: $(systemctl get-default 2>/dev/null)"
  else
    report SKIP boot/target "(systemd 不可用)"
  fi
  if [ -L /etc/systemd/system/display-manager.service ]; then
    report INFO boot/dm "显示管理器: $(readlink /etc/systemd/system/display-manager.service 2>/dev/null | sed 's|.*/||')"
  else
    report INFO boot/dm "无显示管理器(headless)"
  fi

  # ── 初始化来源归因(cloud-init / Ignition) ──
  _ci=""
  [ -d /etc/cloud ] && _ci="/etc/cloud"
  [ -d /var/lib/cloud ] && _ci="${_ci:+$_ci }/var/lib/cloud"
  if [ -n "$_ci" ]; then
    report INFO boot/cloud-init "cloud-init 存在(配置可能来自镜像/云元数据,origin=cloud-init)"
    for _f in /etc/cloud/cloud.cfg /var/lib/cloud/instance/cloud-config.txt; do
      [ -r "$_f" ] || continue
      _cctz=$(sed -n 's/^[[:space:]]*timezone:[[:space:]]*//p' "$_f" 2>/dev/null | head -n 1)
      [ -n "$_cctz" ] && report INFO boot/cloud-init-tz "cloud-init 注入 timezone=$_cctz(origin=cloud-init;当前生效值判定见 locale 类)"
      _cclc=$(sed -n 's/^[[:space:]]*locale:[[:space:]]*//p' "$_f" 2>/dev/null | head -n 1)
      [ -n "$_cclc" ] && report INFO boot/cloud-init-locale "cloud-init 注入 locale=$_cclc(origin=cloud-init)"
    done
  fi
  if [ -d /var/lib/ignition ] || [ -d /usr/lib/ignition ]; then
    report INFO boot/ignition "Ignition 配置存在(不可变系统/容器节点,origin=image)"
  fi

  # ── rc.local(legacy 启动脚本) ──
  if [ -r /etc/rc.local ]; then
    if grep -qE 'SSH_CLIENT|SSH_CONNECTION' /etc/rc.local 2>/dev/null; then
      report SUSPICIOUS boot/rc-local "rc.local 含 SSH_* 引用(伪造/剥离痕迹)"
    else
      report INFO boot/rc-local "rc.local 存在($(wc -l </etc/rc.local 2>/dev/null | tr -d ' ') 行)"
    fi
  fi

  # ── 持久化启动面概览 ──
  if have systemctl && systemctl list-unit-files >/dev/null 2>&1; then
    _en=$(systemctl list-unit-files --type=service 2>/dev/null | awk '$2=="enabled"{n++} END{print n+0}')
    _tm=$(systemctl list-unit-files --type=timer 2>/dev/null | awk '$2=="enabled"{n++} END{print n+0}')
    report INFO boot/enabled "enabled 服务 $_en 个 / timer $_tm 个(服务级地域命中见 services 类)"
  fi
  if [ -d "$HOME/.config/autostart" ]; then
    _au=$(ls "$HOME/.config/autostart" 2>/dev/null | head -n 6 | tr '\n' ' ')
    [ -n "${_au// /}" ] && report INFO boot/autostart "XDG autostart: $_au(用户级持久化)"
  fi

  # ── initramfs ──
  if ls /boot/init* >/dev/null 2>&1; then
    report INFO boot/initramfs "initramfs 存在($(ls /boot/init* 2>/dev/null | wc -l | tr -d ' ') 个;内容参数不解析)"
  else
    report SKIP boot/initramfs "(/boot 不可读或无 initramfs)"
  fi
}
