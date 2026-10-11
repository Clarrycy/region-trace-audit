#────────────────────────────── macOS 适配层 ──────────────────────────────
# 模块: 70-macos.sh
# 定位:仅 macOS 平台 —— 补齐 Linux 检测覆盖不到的系统级地域痕迹
#       (系统区域/系统代理/launchctl 服务/输入法/用户字体/Homebrew 镜像)
# 原则:与 Linux 各类同语义同级别;时区/DNS/出口/浏览器/会话由既有类别原生覆盖
#       (/etc/localtime、scutil --dns、curl、who、~/Library 浏览器路径)

check_mac() {
  hdr "macOS · 系统级地域痕迹(scutil/defaults/launchctl,只读)"

  if [ "$PLATFORM" != "macos" ]; then
    report SKIP macos/all "(非 macOS 环境)"
    return
  fi

  # ── 系统区域/首选语言(defaults 只读;软信号) ──
  if have defaults; then
    _al=$(defaults read -g AppleLocale 2>/dev/null)
    case "${_al:-}" in
      zh_CN*|zh_HK*|zh_MO*|zh_Hans_CN*|zh-Hans-CN*) report SUSPICIOUS macos/locale "系统区域 AppleLocale=$_al(文化习惯类信号)" ;;
      "") : ;;
      *) report INFO macos/locale "系统区域 AppleLocale=$_al" ;;
    esac
    _alang=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '/^[[:space:]]*[()]$/d; s/^[[:space:]]*"*\([^", ]*\)"*,*[[:space:]]*$/\1/p' | head -n 1)
    case "${_alang:-}" in
      zh-Hans*|zh-Hant-HK*|zh-Hant-MO*|zh-Hans-CN*) report SUSPICIOUS macos/lang-first "首选语言 $_alang(文化习惯类信号)" ;;
      "") : ;;
      *) report INFO macos/lang-first "首选语言 $_alang" ;;
    esac
    # 输入法(HIToolbox;系统自带拼音/五笔等中文输入源)
    _ime=$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)
    if printf '%s' "${_ime:-}" | grep -qiE 'SCIM|ITABC|WUBI|Pinyin|Shuangpin|Cangjie'; then
      if printf '%s' "$_ime" | grep -qE '"Input Source Kind" = "Keyboard Input Method"|com.apple.inputmethod'; then
        report SUSPICIOUS macos/ime "启用了中文输入法(SCIM/ITABC 等;文化习惯类信号)"
      fi
    fi
    _kb=$(defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID 2>/dev/null)
    [ -n "${_kb:-}" ] && report INFO macos/xkb "当前键盘布局: $_kb"
  else
    report SKIP macos/defaults "(defaults 不可用)"
  fi

  # ── 系统代理:尊重缩进;HTTP/HTTPS/SOCKS/PAC/WPAD 分开报告 ──
  if have scutil && _sp=$(scutil --proxy 2>/dev/null) && [ -n "$_sp" ]; then
    _enabled=0
    for _kind in HTTP HTTPS SOCKS; do
      if printf '%s\n' "$_sp" | awk -v k="${_kind}Enable" '$1==k && $2==":" && $3==1 {found=1} END {exit !found}'; then
        _enabled=1
        # Scoped dictionaries may contain several endpoints; do not pair unrelated fields.
        report INFO macos/proxy "${_kind} 系统代理已启用(scutil;含按接口配置,不据代理端口推断地区)"
      fi
    done
    for _key in ProxyAutoConfigEnable ProxyAutoDiscoveryEnable; do
      if printf '%s\n' "$_sp" | awk -v k="$_key" '$1==k && $2==":" && $3==1 {found=1} END {exit !found}'; then
        _enabled=1
        report INFO macos/proxy "自动代理 $_key 已启用(不读取 PAC 内容或输出 URL)"
      fi
    done
    [ "$_enabled" = 0 ] && report CLEAN macos/proxy "系统代理未启用(scutil)"
  else
    report SKIP macos/proxy "(scutil --proxy 不可用/无权限/无数据)"
  fi

  # ── launchctl 服务(同 C14 语义:代理栈 INFO / 国内消费软件可疑) ──
  if have launchctl; then
    _lc_out=$(launchctl list 2>/dev/null)
    if [ -n "${_lc_out:-}" ]; then
      _px=$(printf '%s' "$_lc_out" | awk '{print $3}' | grep -iE '(^|\.)(clash|mihomo|v2ray|xray|sing-box|singbox|trojan|hysteria|surge|shadowrocket|quantumult)(\.|$)' | head -n 5 | tr '\n' ' ')
      has_text "$_px" && report INFO macos/proxy-daemon "launchd 代理栈: $_px(角色语义见 path/proxy)"
      _cn=$(printf '%s' "$_lc_out" | awk '{print $3}' | mac_cn_labels | head -n 5 | tr '\n' ' ')
      has_text "$_cn" && report SUSPICIOUS macos/cn-daemon "launchd 已加载国内软件标签: $_cn(含运行中/按需服务,不等同于活动会话;文化习惯类信号)"
      report INFO macos/services "launchd 用户服务 $(printf '%s' "$_lc_out" | wc -l | tr -d ' ') 条(已做国内软件/代理栈匹配)"
    else
      report SKIP macos/services "(launchctl list 不可用/无可见服务)"
    fi
  else
    report SKIP macos/services "(无 launchctl)"
  fi

  # ── 用户字体(~/Library/Fonts;系统自带 PingFang/华文不计) ──
  if [ -d "$HOME/Library/Fonts" ]; then
    _cf=$(ls "$HOME/Library/Fonts" 2>/dev/null | grep -iE 'LXGW|Sarasa|Noto.*CJK|SourceHan|思源|霞鹜|文泉|wqy|方正|汉仪|造字工房' | head -n 4 | tr '\n' ' ')
    if has_text "$_cf"; then
      report SUSPICIOUS macos/fonts "用户安装 CJK 字体: $_cf(文化习惯类信号)"
    else
      report CLEAN macos/fonts "用户字体目录无常见中文字体"
    fi
  else
    report SKIP macos/fonts "(无用户字体目录)"
  fi

  # ── Homebrew 镜像(同 C9 语义) ──
  if have brew; then
    _brd=$(brew --repository 2>/dev/null)
    if [ -n "$_brd" ] && [ -r "$_brd/.git/config" ]; then
      _burl=$(git -C "$_brd" config --get remote.origin.url 2>/dev/null)
      case "${_burl:-}" in
        *tsinghua*|*tuna*|*ustc.edu*|*aliyun*|*tencent*|*bfsu*|*bjtu*|*cqu*) report SUSPICIOUS macos/brew-mirror "Homebrew remote 命中国内镜像: $(printf '%s' "$_burl" | sed 's|.*//||; s|/.*||')(文化习惯类信号)" ;;
        ""|*github.com*) report CLEAN macos/brew-mirror "Homebrew remote 为官方/默认源" ;;
        *) report INFO macos/brew-mirror "Homebrew remote: $(printf '%s' "$_burl" | sed 's|.*//||; s|/.*||')" ;;
      esac
    fi
  else
    report SKIP macos/brew "(未安装 Homebrew)"
  fi

}
