#────────────────────────────── C8 locale ──────────────────────────────
# 模块: 56-c8-locale.sh

check_c8() {
  hdr "C8 locale · 地域配置(系统层)"

  # ── locale ──
  _loc="${LC_ALL:-${LANG:-}}"
  [ -z "$_loc" ] && [ -r /etc/locale.conf ] && _loc=$(sed -n 's/^LANG=//p' /etc/locale.conf | head -n 1 | tr -d '"')
  _sysloc=""
  [ -r /etc/locale.conf ] && _sysloc=$(sed -n 's/^LANG=//p' /etc/locale.conf | head -n 1 | tr -d '"')
  case "${_loc:-unknown}" in
    zh_CN*|zh_HK*|zh_MO*) LOCALE_ZH=1
 report SUSPICIOUS locale/lang "locale=$_loc(zh_CN/HK/MO,文化习惯类信号)" ;;
    zh_TW*|zh_SG*)        report INFO locale/lang "locale=$_loc(TW/SG,不属陆港澳三地)" ;;
    *)                    report CLEAN locale/lang "locale=${_loc:-未设置}" ;;
  esac
  case "${_sysloc:-}" in
    zh_CN*|zh_HK*|zh_MO*) report SUSPICIOUS locale/sys-lang "/etc/locale.conf=$_sysloc(系统级,部署者痕迹)" ;;
  esac

  # ── 时区(三源) ──
  _tz=""
  if [ -L /etc/localtime ] || [ -e /etc/localtime ]; then
    _link=$(readlink /etc/localtime 2>/dev/null)
    if [ -n "$_link" ]; then
      _tz=$(printf '%s' "$_link" | sed 's|.*zoneinfo/||')
    fi
  fi
  [ -z "$_tz" ] && [ -r /etc/timezone ] && _tz=$(head -n 1 /etc/timezone)
  if [ -z "$_tz" ] && have timedatectl; then
    _tz=$(timedatectl show -p Timezone --value 2>/dev/null) || _tz=""
    [ -z "$_tz" ] && _tz=$(timedatectl 2>/dev/null | sed -n 's/.*Time zone: \([A-Za-z/_]*\).*/\1/p' | head -n 1)
  fi
  if [ -z "$_tz" ]; then
    _zz=$(date +%Z 2>/dev/null)
    case "$_zz" in
      CST) report INFO locale/tz "date +%Z=CST(歧义:中国标准时间/美国中部,无法定论)" ;;
      *)   report SKIP locale/tz "(时区不可探测)" ;;
    esac
  fi
  if [ -n "$_tz" ]; then
    TZ_MAIN=$_tz; TZ_NAME=$_tz
    _cls=$(tz_class "$_tz"); TZ_CLASS=$_cls
    case "$_cls" in
      CN)   report EXPOSED locale/tz "系统时区 $_tz(陆港澳确定时区,长期在其他时区的用户不会保留)" ;;
      HKMO) report EXPOSED locale/tz "系统时区 $_tz(港澳确定时区)" ;;
      E8)
        if [ -n "$EGRESS_TZ" ] && [ "$(tz_offset "$EGRESS_TZ")" = "+0800" ]; then
          report CLEAN locale/tz "系统时区 $_tz 与出口时区($EGRESS_TZ)同属东八,自洽"
        elif [ -n "$EGRESS_CC" ]; then
          report EXPOSED locale/tz "系统时区 $_tz(东八)与出口地区 $(cnname "$EGRESS_CC")(${EGRESS_TZ:-未知时区})不匹配 —— 时区与地区矛盾(东八区特判)"
        else
          report INFO locale/tz "系统时区 $_tz(东八、非陆港澳;出口数据缺失,无法比对)"
        fi ;;
      *)
        if [ -n "$EGRESS_TZ" ] && [ "$(tz_offset "$EGRESS_TZ")" != "$(tz_offset "$_tz")" ]; then
          report SUSPICIOUS locale/tz "系统时区 $_tz(UTC$(tz_offset "$_tz"))与出口地理时区 $EGRESS_TZ(UTC$(tz_offset "$EGRESS_TZ"))不一致(中转节点常见,仅作参考)"
        elif [ -n "$EGRESS_TZ" ]; then
          report CLEAN locale/tz "系统时区 $_tz 与出口时区 $EGRESS_TZ 一致"
        else
          report INFO locale/tz "系统时区 $_tz(出口数据缺失,无法比对)"
        fi ;;
    esac
    # TZ env:值本身命中陆港澳 → 暴露;与系统不一致 → 可疑
    if [ -n "$TZ" ]; then
      _tzc=$(tz_class "$TZ")
      case "$_tzc" in
        CN)   report EXPOSED locale/tz-env "TZ=$TZ(陆港澳确定时区)" ;;
        HKMO) report EXPOSED locale/tz-env "TZ=$TZ(港澳确定时区)" ;;
      esac
      if [ "$TZ" != "$_tz" ]; then
        report SUSPICIOUS locale/tz-env "TZ=$TZ 与系统时区 $_tz 不一致(伪造/混乱痕迹)"
      fi
    fi
  fi

  # ── localedef / man / 键盘 / hostname / RTC ──
  if have locale; then
    _lc=$(locale -a 2>/dev/null | grep -iE '^zh_(CN|HK|MO)' | head -n 4 | tr '\n' ' ')
    if [ -n "${_lc// /}" ]; then
      report SUSPICIOUS locale/localedef "已生成中文 locale: $_lc(文化习惯类信号)"
    else
      report CLEAN locale/localedef "未生成 zh_CN/HK/MO locale"
    fi
  else
    report SKIP locale/localedef "(locale 命令不可用)"
  fi

  if [ -d /usr/share/man/zh ] || ls -d /usr/share/man/zh* >/dev/null 2>&1; then
    report SUSPICIOUS locale/man-zh "存在中文 man 手册页(文化习惯类信号)"
  fi

  if [ -r /etc/default/keyboard ]; then
    _kb=$(sed -n 's/^XKBLAYOUT=//p' /etc/default/keyboard | tr -d '"')
    case "$_kb" in *cn*) report SUSPICIOUS locale/keyboard "XKB 键盘布局含 cn($_kb)" ;;
                     *) report INFO locale/keyboard "XKB 布局: ${_kb:-default}" ;;
    esac
  fi

  _hn=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || printf '?')
  case "$_hn" in
    *.cn|*.com.cn) report SUSPICIOUS locale/hostname "hostname=$_hn(.cn 后缀)" ;;
    *) case "$_hn" in
         *[Cc]hina*|*-cn-*|cn-*|*-cn) report SUSPICIOUS locale/hostname "hostname=$_hn(含 CN 字样)" ;;
         *) if is_pinyin_name "$_hn"; then
              report SUSPICIOUS locale/hostname "hostname=$_hn(疑似拼音姓名,启发式)"
            else
              report CLEAN locale/hostname "hostname=$_hn"
            fi ;;
       esac ;;
  esac

  if have timedatectl; then
    if timedatectl 2>/dev/null | grep -q 'RTC in local TZ: yes'; then
      report INFO locale/rtc "RTC 使用本地时间(常见于双系统安装)"
    fi
  fi
}
