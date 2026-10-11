#────────────────────────────── WSL interop ──────────────────────────────
# 模块: 64-wsl-interop.sh
# 定位:仅 WSL 平台 —— 经 interop 只读查询 Windows 侧地域痕迹(区域/时区/代理/语言/hosts)

check_wsl() {
  hdr "WSL interop · Windows 侧地域痕迹"

  if [ "$PLATFORM" != "wsl" ]; then
    report SKIP wsl/all "(非 WSL 环境)"
    return
  fi

  # ── interop 可用性 + 区域/时区(单次 powershell 调用) ──
  _psout=""
  if have powershell.exe; then
    if have timeout; then
      _psout=$(timeout 12 powershell.exe -NoProfile -Command \
        "(Get-Culture).Name; ([System.TimeZoneInfo]::Local).Id; (Get-WinSystemLocale).Name" 2>/dev/null) || _psout=""
    else
      _psout=$(powershell.exe -NoProfile -Command \
        "(Get-Culture).Name; ([System.TimeZoneInfo]::Local).Id; (Get-WinSystemLocale).Name" 2>/dev/null) || _psout=""
    fi
  fi
  if [ -n "$_psout" ]; then
    _cul=$(printf '%s\n' "$_psout" | sed -n '1p' | tr -d '\r')
    _wtz=$(printf '%s\n' "$_psout" | sed -n '2p' | tr -d '\r')
    _sloc=$(printf '%s\n' "$_psout" | sed -n '3p' | tr -d '\r')
    case "${_cul}${_sloc}" in
      *zh-CN*|*zh-HK*|*zh-MO*) report SUSPICIOUS wsl/culture "Windows 区域 $_cul / 系统区域 $_sloc(简中/港澳,文化习惯类信号)" ;;
      *zh-TW*|*zh-SG*)        report INFO wsl/culture "Windows 区域 $_cul / 系统区域 $_sloc(TW/SG,不属陆港澳三地)" ;;
      *)                      report INFO wsl/culture "Windows 区域 $_cul / 系统区域 ${_sloc:-?}" ;;
    esac
    case "$(win_tz_class "$_wtz")" in
      CN) report EXPOSED wsl/tz "Windows 时区 $_wtz(陆港澳确定时区 —— 陆/港/澳共用该时区名)" ;;
      E8) report INFO wsl/tz "Windows 时区 $_wtz(东八非陆港澳;与出口比对见 locale 类)" ;;
      *)  report INFO wsl/tz "Windows 时区 $_wtz" ;;
    esac
  else
    report SKIP wsl/powershell "(interop 不可用或已禁用 —— Windows 侧无法核查)"
  fi

  # ── 注册表:系统代理与系统语言 ──
  _reg=""
  if have reg.exe; then
    if have timeout; then
      _reg=$(timeout 8 reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 2>/dev/null) || _reg=""
    else
      _reg=$(reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 2>/dev/null) || _reg=""
    fi
  fi
  if [ -n "$_reg" ]; then
    _pe=$(printf '%s' "$_reg" | sed -n 's/.*ProxyEnable.*REG_DWORD[[:space:]]*//p' | tr -d '\r ')
    _pv=$(printf '%s' "$_reg" | sed -n 's/.*ProxyServer.*REG_SZ[[:space:]]*//p' | tr -d '\r')
    if [ "${_pe:-0x0}" != "0x0" ] && [ -n "$_pv" ]; then
      case "$_pv" in
        127.0.0.1:*|localhost:*) report SUSPICIOUS wsl/win-proxy "Windows 系统代理已启用 → $_pv(本机代理端口,常见于国内代理客户端)" ;;
        *) report INFO wsl/win-proxy "Windows 系统代理已启用 → $(mask_ip "${_pv%%:*}"):${_pv#*:}" ;;
      esac
    else
      report CLEAN wsl/win-proxy "Windows 系统代理未启用"
    fi
  else
    report SKIP wsl/reg "(reg.exe interop 不可用)"
  fi
  _nls=""
  if have reg.exe; then
    if have timeout; then
      _nls=$(timeout 8 reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language' /v Default 2>/dev/null) || _nls=""
    else
      _nls=$(reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language' /v Default 2>/dev/null) || _nls=""
    fi
  fi
  if [ -n "$_nls" ]; then
    _lv=$(printf '%s' "$_nls" | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r ')
    case "${_lv:-}" in
      0804) report SUSPICIOUS wsl/win-lang "Windows 系统语言 = 0804(简体中文)" ;;
      0c04|0404) report INFO wsl/win-lang "Windows 系统语言 = $_lv(繁体中文,港台)" ;;
      *) report INFO wsl/win-lang "Windows 系统语言 = ${_lv:-未知}" ;;
    esac
  fi

  # ── Windows hosts 文件 ──
  _wh='/mnt/c/Windows/System32/drivers/etc/hosts'
  if [ -r "$_wh" ]; then
    _n=$(grep -vE '^\s*#|localhost' "$_wh" 2>/dev/null | grep -cE "$CN_DOMAIN_RE" || true)
    _n=${_n:-0}
    if [ "$_n" -gt 0 ]; then
      report SUSPICIOUS wsl/win-hosts "Windows hosts 含 $_n 条国内域名硬解析"
    else
      report CLEAN wsl/win-hosts "Windows hosts 无国内域名硬解析"
    fi
  else
    report SKIP wsl/win-hosts "(Windows hosts 不可读)"
  fi
}
