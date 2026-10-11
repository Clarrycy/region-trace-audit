#────────────────────────────── C12 anti ──────────────────────────────
# 模块: 59-c12-anti.sh

check_c12() {
  hdr "C12 anti · 隐藏与伪造痕迹(带上下文修正)"

  # ── 登录日志权限矩阵 ──
  for _f in /var/log/wtmp /var/log/btmp /var/log/lastlog /run/utmp; do
    if [ ! -e "$_f" ]; then
      report SKIP anti/"$(printf '%s' "$_f" | tr / _ | tr -d '.')" "(不存在:容器/最小系统常见)"
      continue
    fi
    case "$_f" in
      /var/log/btmp)
        # btmp 各发行版默认即不可读(RHEL 600 / Debian 660 root:utmp)
        [ -r "$_f" ] && report INFO anti/btmp "btmp 可读(少数发行版默认)" \
                       || report INFO anti/btmp "btmp 不可读(RHEL/Debian 系默认,正常)"
        continue ;;
    esac
    if [ -r "$_f" ]; then
      report INFO anti/"$(printf '%s' "$_f" | tr / _ | tr -d '.')" "$_f 当前用户可读(默认权限)"
    else
      # 上下文修正:容器 SKIP;新装 INFO;正常老化系统不可读 = 刻意 → 可疑
      case "$PLATFORM" in
        container-*) report SKIP anti/"$(printf '%s' "$_f" | tr / _ | tr -d '.')" "$_f 不可读(容器环境)" ;;
        *)
          if [ "${INSTALL_AGE_DAYS:-0}" -gt 0 ] && [ "$INSTALL_AGE_DAYS" -lt 30 ]; then
            report INFO anti/"$(printf '%s' "$_f" | tr / _ | tr -d '.')" "$_f 不可读(系统安装 $INSTALL_AGE_DAYS 天,新装可能为部署基线)"
          else
            report SUSPICIOUS anti/"$(printf '%s' "$_f" | tr / _ | tr -d '.')" "$_f 对当前用户不可读(正常系统应为可读 —— 疑似刻意隐藏)"
          fi ;;
      esac
    fi
  done

  # wtmp 空但 uptime 长
  if [ -r /var/log/wtmp ] && [ ! -s /var/log/wtmp ]; then
    _up=$(cut -d. -f1 /proc/uptime 2>/dev/null || printf 0)
    if [ "${_up:-0}" -gt 2592000 ]; then
      report SUSPICIOUS anti/wtmp-empty "wtmp 为空但系统运行 $((_up/86400)) 天(日志被清)"
    fi
  fi

  # SSH_* 剥离判定(需 sshd 上下文;tmux/su/service 上下文为正常差异)
  if [ "$IN_SSH_CHAIN" = 1 ] && [ -z "$SSH_CONNECTION" ] && [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    report SUSPICIOUS anti/ssh-env-stripped "shell 由 sshd 派生但 env 无 SSH_* 变量(疑似 env 剥离)"
  elif [ "$IN_MUX" = 1 ] && [ -z "$SSH_CONNECTION" ] && [ -z "$SSH_CLIENT" ]; then
    report INFO anti/ssh-env "tmux/screen 环境下无 SSH_* 变量(正常差异:server 继承环境)"
  elif [ "$IN_SSH_CHAIN" = 0 ] && [ -z "$SSH_CONNECTION" ]; then
    report INFO anti/ssh-env "本地/service 上下文,无 SSH_* 属正常"
  fi

  # rc 文件 SSH_* 赋值 / 伪造函数
  _rc_any=0; _rc_hit=0
  for _r in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
    [ -r "$_r" ] || continue
    _rc_any=1
    if grep -qE '(^|[;}&])[[:space:]]*(export[[:space:]]+)?SSH_(CLIENT|CONNECTION)=' "$_r" 2>/dev/null; then
      report SUSPICIOUS anti/rc-ssh-fake "$(_r_basename "$_r") 含 SSH_CLIENT/SSH_CONNECTION 赋值(伪造痕迹)"; _rc_hit=1
    fi
    if grep -qE 'env[[:space:]]+-u[[:space:]]+.*SSH' "$_r" 2>/dev/null; then
      report SUSPICIOUS anti/rc-env-u "$(_r_basename "$_r") 含 env -u SSH_* 别名/函数(剥离痕迹)"
    fi
  done
  [ "${_rc_any:-0}" = 0 ] && report SKIP anti/rc-ssh-fake "(无 rc 文件)"
  [ "${_rc_any:-0}" = 1 ] && [ "${_rc_hit:-0}" = 0 ] && report CLEAN anti/rc-ssh-fake "rc 文件无 SSH_* 赋值/伪造/env -u 痕迹"

  # systemd unit InaccessiblePaths(用户级与系统级可读部分)
  _ia=""
  for _d in "$HOME/.config/systemd/user" /etc/systemd/system; do
    [ -d "$_d" ] && [ -r "$_d" ] || continue
    if grep -rl 'InaccessiblePaths' "$_d" 2>/dev/null | grep -qE '.' &&
       grep -rh 'InaccessiblePaths' "$_d" 2>/dev/null | grep -qE 'wtmp|utmp|lastlog|/proc/net'; then
      _ia="${_ia:+$_ia; }$_d"
    fi
  done
  if [ -n "$_ia" ]; then
    report SUSPICIOUS anti/unit-inaccessible "systemd unit 含 InaccessiblePaths(wtmp/utmp/proc-net):$_ia"
  else
    report CLEAN anti/unit-inaccessible "可读范围内无 InaccessiblePaths(wtmp/utmp/proc-net)命中"
  fi

  # 沙箱 wrapper(~/.local/bin 文本脚本含 landlock/bwrap 关键词)
  if [ -d "$HOME/.local/bin" ]; then
    _w=$(grep -rl -iE 'landlock|LANDLOCK|bwrap' "$HOME/.local/bin" 2>/dev/null | head -n 3 | tr '\n' ' ')
    if [ -n "${_w// /}" ]; then
      report SUSPICIOUS anti/sandbox-wrapper "~/.local/bin 存在沙箱 wrapper: $_w(Landlock/bwrap)"
    fi
  fi

  # history 截断痕迹
  if [ -f "$HOME/.bash_history" ] && [ ! -s "$HOME/.bash_history" ]; then
    report SUSPICIOUS anti/history-truncated ".bash_history 存在但为 0 字节(清空痕迹;HISTSIZE=${HISTSIZE:-未设})"
  fi

  # claude shell-snapshot 中 SSH_CLIENT 与当前 env 不一致
  _snap_dir="$HOME/.claude/shell-snapshots"
  if [ -d "$_snap_dir" ]; then
    _cur=$(printf '%s' "${SSH_CONNECTION:-$SSH_CLIENT}" | awk '{print $1}')
    _snapval=$(grep -rhoE 'SSH_CLIENT="[^"]*"' "$_snap_dir" 2>/dev/null | head -n 1 | sed 's/.*="//;s/ .*//')
    if [ -n "$_snapval" ] && [ -n "$_cur" ] && [ "$_snapval" != "$_cur" ]; then
      report SUSPICIOUS anti/snapshot-mismatch "shell 快照记录 SSH 来源 $(mask_ip "$_snapval") 与当前 $(mask_ip "$_cur") 不一致(与当前值矛盾,或为历史残留)"
    elif [ -n "$_snapval" ] && [ -z "$_cur" ]; then
      report INFO anti/snapshot-mismatch "shell 快照记录 SSH 来源 $(mask_ip "$_snapval")(当前会话无 SSH_*,仅记录)"
    fi
  else
    report SKIP anti/snapshot "(无 ~/.claude/shell-snapshots)"
  fi

  # NTP 指向国内
  _ntp_hit=""; _ntp_any=0
  for _f in /etc/chrony.conf /etc/chrony/chrony.conf /etc/chrony/sources /etc/ntp.conf /etc/systemd/timesyncd.conf; do
    [ -r "$_f" ] || continue
    _ntp_any=1
    grep -qiE "(server|pool)[[:space:]].*$CN_NTP_RE" "$_f" 2>/dev/null && _ntp_hit="$_f"
  done
  if [ -n "$_ntp_hit" ]; then
    report SUSPICIOUS anti/ntp-cn "NTP 配置指向国内服务器($_ntp_hit,使用习惯)"
  elif [ "$_ntp_any" = 1 ]; then
    report CLEAN anti/ntp-cn "NTP 配置未命中国内服务器"
  else
    report SKIP anti/ntp-cn "(无可读 NTP 配置)"
  fi

  # 运行中进程 TZ/LANG 与系统不一致(抽查;命中陆港澳值则可疑,否则 INFO 注记)
  _ptz=""
  if [ -d /proc ] && [ -n "$CUR_UID" ] && [ "$CUR_UID" != "?" ]; then
    for _pid in $(ps -o pid= -u "$CUR_UID" 2>/dev/null | head -n 60); do
      [ -d "/proc/$_pid" ] || continue
      _tzv=$(cat "/proc/$_pid/environ" 2>/dev/null | tr '\0' '\n' | sed -n 's/^TZ=//p' | head -n 1)
      [ -z "$_tzv" ] && continue
      if [ -n "${TZ_MAIN:-}" ] && [ "$_tzv" != "$TZ_MAIN" ]; then
        _ptz="$_pid:$_tzv"; break
      fi
    done
  fi
  if [ -n "$_ptz" ]; then
    _ptzval=${_ptz#*:}
    _pc=$(tz_class "$_ptzval")
    case "$_pc" in
      CN|HKMO) report SUSPICIOUS anti/proc-tz "进程 TZ=$_ptzval 与系统 ${TZ_MAIN:-?} 不一致且为陆港澳时区" ;;
      *) report INFO anti/proc-tz "进程 TZ=$_ptzval 与系统 ${TZ_MAIN:-?} 不一致(service manager 注入差异常见)" ;;
    esac
  else
    report CLEAN anti/proc-tz "抽查自有进程 TZ,与系统一致或未设置"
  fi

  # ANTHROPIC_BASE_URL 非官方
  for _src in "env:$(printf '%s' "${ANTHROPIC_BASE_URL:-}")" "settings:$HOME/.claude/settings.json"; do
    _v=${_src#*:}; _w=${_src%%:*}
    [ -z "$_v" ] && continue
    case "$_w" in
      env) case "$_v" in
             api.anthropic.com|"") : ;;
             *) if printf '%s' "$_v" | grep -qE "$CN_DOMAIN_RE"; then
                  report SUSPICIOUS anti/anthropic-baseurl "ANTHROPIC_BASE_URL=$(_m_url "$_v")(国内中转特征)"
                else
                  report INFO anti/anthropic-baseurl "ANTHROPIC_BASE_URL 非官方域 $(_m_url "$_v")"
                fi ;;
           esac ;;
      settings) if grep -q 'ANTHROPIC_BASE_URL' "$_v" 2>/dev/null; then
                  _sv=$(sed -n 's/.*ANTHROPIC_BASE_URL[^"]*"[^"]*"\([^"]*\)".*/\1/p' "$_v" 2>/dev/null | head -n 1)
                  case "$_sv" in
                    api.anthropic.com|"") : ;;
                    *) report INFO anti/anthropic-baseurl "settings.json ANTHROPIC_BASE_URL=$(_m_url "${_sv:-?}")(非官方;注意 2.1.91+ 该场景触发时区上报)" ;;
                  esac
                fi ;;
    esac
  done

  # 采集完整性旁证
  if have mount; then
    if mount 2>/dev/null | grep ' /proc ' | grep -q hidepid; then
      report INFO anti/hidepid "/proc 以 hidepid 挂载(其他用户进程不可见 —— 观察范围受限,非隐藏痕迹)"
    fi
  fi
  if [ -r /sys/fs/selinux/enforce ] && [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = "1" ]; then
    report INFO anti/selinux "SELinux enforcing(部分路径不可读属策略,非隐藏痕迹)"
  fi
}
