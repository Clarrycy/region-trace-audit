#────────────────────────────── 汇总与主流程 ──────────────────────────────
# 模块: 90-main.sh

run_section() {
  case "$1" in
    sysinfo)  check_c1 ;;
    macos)    check_mac ;;
    cloud)    check_c2 ;;
    boot)     check_c16 ;;
    kernelnet) check_c17 ;;
    session)  check_c18 ;;
    wsl)      check_wsl ;;
    egress)   check_c3 ;;
    path)     check_c4 ;;
    proxy)    check_c5 ;;
    dns)      check_c6 ;;
    locale)   check_c8 ;;
    mirror)   check_c9 ;;
    fs)       check_c10 ;;
    anti)     check_c12 ;;
    services) check_c14 ;;
    gui)      check_c19 ;;
    browser)  check_c15 ;;
    hw)       check_c13 ;;
    time)     check_c11 ;;
    usegeo|c20) check_c20 ;;
    *) return 1 ;;
  esac
  return 0
}

summary() {
  printf '\n%s══ 汇总 ══%s\n' "$C_HDR" "$C_RST"
  if [ "$CNT_EXP" -gt 0 ]; then
    printf '%s[✗] 暴露 (%d):%s\n' "$C_EXP" "$CNT_EXP" "$C_RST"
    printf '%s' "$LOG_EXP" | awk -F'|' -v c="$C_EXP" -v r="$C_RST" \
      '{printf "%s  %d. [%s] %s%s\n", c, NR, $1, substr($0, index($0,"|")+1), r}'
  else
    printf '%s[✗] 暴露 (0)%s\n' "$C_CLN" "$C_RST"
  fi
  if [ "$CNT_SUS" -gt 0 ]; then
    printf '%s[!] 可疑 (%d):%s\n' "$C_SUS" "$CNT_SUS" "$C_RST"
    printf '%s' "$LOG_SUS" | awk -F'|' -v c="$C_SUS" -v r="$C_RST" \
      '{printf "%s  %d. [%s] %s%s\n", c, NR, $1, substr($0, index($0,"|")+1), r}'
  else
    printf '%s[!] 可疑 (0)%s\n' "$C_CLN" "$C_RST"
  fi
  if [ -n "${USEGEO_VIEW:-}" ]; then
    printf '%s\n实际使用地区视图(C20 融合)%s\n' "$C_HDR" "$C_RST"
    printf '%s\n' "$USEGEO_VIEW"
  fi
  printf '统计: 正常 %d | 可疑 %d | 暴露 %d | 信息 %d | 跳过 %d\n' \
    "$CNT_CLN" "$CNT_SUS" "$CNT_EXP" "$CNT_INF" "$CNT_SKP"
  printf 'v%s · 判定规则见 PLAN.md · 本工具为一致性体检,不评判、不承诺规避效果\n' "$VERSION"
}

main() {
  if [ "${JSON:-0}" != 1 ]; then
    printf '%sregion-trace-audit v%s — 陆港澳用户环境痕迹检测器(只读)%s\n' "$C_HDR" "$VERSION" "$C_RST"
    printf '模式: %s · 脱敏: %s · 检测项降级将标注原因\n\n' \
      "$([ "$OFFLINE" = 1 ] && printf '本地检测(--offline,无外联)' || printf '本地 + active-probe(外联: ip-api/ipinfo/api64)')" \
      "$([ "$REVEAL" = 1 ] && printf '关闭(--reveal)' || printf '开启(默认)')"
  fi

  detect_platform
  collector_context
  http_detect
  net_context
  if [ "$SECTION" = "all" ]; then
    for _s in sysinfo macos cloud boot kernelnet session egress path proxy dns wsl locale mirror fs anti services gui browser hw time usegeo; do run_section "$_s"; done
  else
    # 轻量前置上下文:time/usegeo 依赖时区与 locale,单项运行时就地采集,避免结论静默失真
    case "$SECTION" in
      time|usegeo|c20)
        _tzl=$(readlink /etc/localtime 2>/dev/null)
        [ -n "$_tzl" ] && TZ_NAME=$(printf '%s' "$_tzl" | sed 's|.*zoneinfo/||')
        [ -n "${TZ_NAME:-}" ] && TZ_CLASS=$(tz_class "$TZ_NAME")
        if [ -r /etc/locale.conf ]; then
          case "$(sed -n 's/^LANG=//p' /etc/locale.conf | tr -d '"' | head -n 1)" in
            zh_CN*|zh_HK*|zh_MO*) LOCALE_ZH=1 ;;
          esac
        fi
        ;;
    esac
    report INFO main/section-mode "单项模式($SECTION):跨类别上下文未完整采集,融合/一致性结论可能不完整(完整结论请全量运行)"
    run_section "$SECTION" || { printf '未知类别: %s(可用: sysinfo macos cloud boot kernelnet session egress path proxy dns wsl locale mirror fs anti services gui browser hw time usegeo/c20)\n' "$SECTION" >&2; exit 64; }
  fi

  if   [ "$CNT_EXP" -gt 0 ]; then EXIT_CODE=2
  elif [ "$CNT_SUS" -gt 0 ]; then EXIT_CODE=1
  else EXIT_CODE=0
  fi
  if [ "${JSON:-0}" = 1 ]; then
    json_emit
  else
    summary
  fi
  exit "$EXIT_CODE"
}

main
