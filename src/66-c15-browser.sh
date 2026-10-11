#────────────────────────────── C15 browser ──────────────────────────────
# 模块: 66-c15-browser.sh
# 定位:浏览器痕迹 —— 已装浏览器/profile、默认搜索引擎、界面语言、历史国内域名计数
# 红线:只计数,不读取/不输出 URL 明文、查询词、书签标题、扩展内容、凭据

check_c15() {
  hdr "C15 browser · 浏览器痕迹(仅计数)"

  # ── 已装浏览器与 profile(目录存在即可判定) ──
  _nfound=0
  _br_check() { # $1=名称 $2=profile 目录 $3=附加二进制
    _p=""
    [ -d "$2" ] && _p="$2"
    [ -z "$_p" ] && [ -n "$3" ] && have "$3" && _p="bin-only"
    if [ -n "$_p" ]; then
      _nfound=$((_nfound+1))
      if [ "$_p" = "bin-only" ]; then
        report INFO "browser/$1" "已安装($3;无用户 profile —— 未使用或他人环境)"
      elif ls "$2"/Default "$2"/Profile* "$2"/profiles.ini >/dev/null 2>&1; then
        report INFO "browser/$1" "存在用户 profile($2)"
      else
        report INFO "browser/$1" "目录存在但无用户数据($2 —— 残留/未完成初始化)"
      fi
    fi
  }
  if [ "$PLATFORM" = macos ]; then
    # macOS 路径(应用二进制在 /Applications,profile 在 ~/Library)
    _br_check firefox "$HOME/Library/Application Support/Firefox" firefox
    _br_check chrome "$HOME/Library/Application Support/Google/Chrome" "Google Chrome"
    _br_check chromium "$HOME/Library/Application Support/Chromium" chromium
    _br_check brave "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" "Brave Browser"
    _br_check edge "$HOME/Library/Application Support/Microsoft Edge" "Microsoft Edge"
    _br_check vivaldi "$HOME/Library/Application Support/Vivaldi" vivaldi
  else
    _br_check firefox "$HOME/.mozilla/firefox" firefox
    _br_check chrome "$HOME/.config/google-chrome" google-chrome
    _br_check chromium "$HOME/.config/chromium" chromium
    _br_check brave "$HOME/.config/BraveSoftware/Brave-Browser" brave-browser
    _br_check edge "$HOME/.config/microsoft-edge" microsoft-edge
    _br_check vivaldi "$HOME/.config/vivaldi" vivaldi
    _br_check opera "$HOME/.config/opera" opera
  fi

  if [ "$_nfound" -eq 0 ]; then
    report SKIP browser/all "(无浏览器及 profile —— 服务器/无桌面场景常见)"
    return
  fi

  # 运行中状态
  if ps_filtered | grep -qE '(firefox|chrome|chromium|brave|msedge|vivaldi|opera)( |$)'; then
    report INFO browser/running "浏览器进程运行中(历史文件可能被锁,只读不受影响)"
  fi

  # ── Firefox:prefs.js(文本,逐 profile) ──
  _ffdir="$HOME/.mozilla/firefox"
  [ -d "$HOME/Library/Application Support/Firefox" ] && _ffdir="$HOME/Library/Application Support/Firefox"
  if [ -d "$_ffdir" ] && [ -r "$_ffdir/profiles.ini" ]; then
    _nprof=0; _zh=0; _cneng=0
    _prof_list=$(sed -n 's/^Path=//p' "$_ffdir/profiles.ini" 2>/dev/null)
    while read -r _pr; do
      [ -z "${_pr:-}" ] && continue
      case "$_pr" in \~/*) continue ;; esac
      _pf="$_ffdir/$_pr"
      [ -d "$_pf" ] || continue
      _nprof=$((_nprof+1))
      if [ -r "$_pf/prefs.js" ]; then
        _pj=$(cat "$_pf/prefs.js" 2>/dev/null)
        _eng=$(printf '%s' "$_pj" | sed -n 's/.*browser\.search\.\(default\|selected\)Engine", "\([^"]*\)".*/\2/p' | head -n 1)
        case "${_eng:-}" in
          *百度*|*Baidu*|*baidu*|*sogou*|*搜狗*|*360*|*so\.com*)
            report SUSPICIOUS browser/search "Firefox 默认搜索引擎: $_eng(国内引擎,文化习惯类信号)"; _cneng=$((_cneng+1)) ;;
        esac
        _loc=$(printf '%s' "$_pj" | sed -n 's/.*intl\.locale\.\(requested\)", "\([^"]*\)".*/\2/p' | head -n 1)
        [ -z "$_loc" ] && _loc=$(printf '%s' "$_pj" | sed -n 's/.*general\.useragent\.locale", "\([^"]*\)".*/\1/p' | head -n 1)
        case "${_loc:-}" in
          zh-CN*|zh-HK*|zh-MO*) report SUSPICIOUS browser/lang "Firefox 界面语言: $_loc(文化习惯类信号)"; _zh=$((_zh+1)) ;;
        esac
      fi
    done <<EOF
$_prof_list
EOF
    report INFO browser/firefox "Firefox profile $_nprof 个(搜索引擎命中 $_cneng/界面语言命中 $_zh)"
  fi

  # ── Chromium 系(Chrome/Chromium/Brave/Edge/Vivaldi):Preferences JSON ──
  if [ "$PLATFORM" = macos ]; then
    _cp_scan="Google/Chrome Chromium BraveSoftware/Brave-Browser 'Microsoft Edge' Vivaldi"
    _cp_root="$HOME/Library/Application Support"
  else
    _cp_scan="google-chrome chromium BraveSoftware/Brave-Browser microsoft-edge vivaldi opera"
    _cp_root="$HOME/.config"
  fi
  for _cp in $_cp_scan; do
    _bdir="$_cp_root/$_cp"
    [ -d "$_bdir" ] || continue
    _bname=$(printf '%s' "$_cp" | sed 's|.*/||')
    _nprof=0
    for _prof in "$_bdir"/Default "$_bdir"/Profile*; do
      [ -d "$_prof" ] || continue
      _nprof=$((_nprof+1))
      [ -r "$_prof/Preferences" ] || continue
      _pj=$(head -c 2000000 "$_prof/Preferences" 2>/dev/null)
      # 默认搜索引擎(Preferences 内 default_search_provider_data.short_name)
      _eng=$(printf '%s' "$_pj" | sed 's/.*"default_search_provider_data"[^S]*"short_name":"\([^"]*\)".*/\1/p' | head -c 40)
      case "${_eng:-}" in
        *百度*|*[Bb]aidu*|*[Ss]ogou*|*搜狗*|*360*|*so\.com*)
          report SUSPICIOUS "browser/$_bname-search" "$_bname 默认搜索引擎: $_eng(国内引擎,文化习惯类信号)" ;;
      esac
      # 界面语言 / accept-languages
      _al=$(printf '%s' "$_pj" | sed -n 's/.*"intl\.accept_languages":"\([^"]*\)".*/\1/p' | head -c 40)
      _ap=$(printf '%s' "$_pj" | sed -n 's/.*"application_locale":"\([^"]*\)".*/\1/p' | head -c 40)
      case "${_al:-}${_ap:-}" in
        *zh-CN*|*zh-HK*|*zh-MO*) report SUSPICIOUS "browser/$_bname-lang" "$_bname 界面/接受语言: ${_ap:-${_al:-?}}(文化习惯类信号)" ;;
      esac
    done
    [ "$_nprof" -gt 0 ] && report INFO "browser/$_bname" "$_bname profile $_nprof 个(已检查搜索引擎与语言设置)"
  done

  # ── 历史/书签国内域名计数(只计数;上限 30MB/文件,防大文件耗时) ──
  _hcount=0
  _h_scan() { # $1=文件 $2=浏览器名
    [ -f "$1" ] || return 0
    _c=$(head -c 30000000 "$1" 2>/dev/null | LC_ALL=C grep -aoE 'https?://[a-zA-Z0-9.-]+' \
         | sed 's|https\?://||' | grep -cE "$CN_DOMAIN_RE" || true)
    _c=${_c:-0}
    if [ "$_c" -gt 0 ]; then
      _lvl=INFO; [ "$_c" -ge 10 ] && _lvl=SUSPICIOUS
      report "$_lvl" "browser/$2-history" "$2 历史含国内域名记录 $_c 条(仅计数,不读取 URL 明文;≥10 判可疑)"
      _hcount=$((_hcount+1))
    else
      report CLEAN "browser/$2-history" "$2 历史无国内域名记录(或历史为空)"
    fi
  }
  if [ -d "$_ffdir" ]; then
    for _pr in $(sed -n 's/^Path=//p' "$_ffdir/profiles.ini" 2>/dev/null); do
      case "$_pr" in \~/*) continue ;; esac
      _h_scan "$_ffdir/$_pr/places.sqlite" firefox
    done
  fi
  if [ "$PLATFORM" = macos ]; then
    _cp_list="Google/Chrome Chromium BraveSoftware/Brave-Browser 'Microsoft Edge' Vivaldi"
    _cp_base="$HOME/Library/Application Support"
  else
    _cp_list="google-chrome chromium BraveSoftware/Brave-Browser microsoft-edge vivaldi opera"
    _cp_base="$HOME/.config"
  fi
  for _cp in $_cp_list; do
    for _prof in "$_cp_base/$_cp"/Default "$_cp_base/$_cp"/Profile*; do
      _h_scan "$_prof/History" "$(printf '%s' "$_cp" | sed 's|.*/||')"
    done
  done
}
