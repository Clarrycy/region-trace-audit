#────────────────────────────── 内置数据表与判定谓词 ──────────────────────────────
# 模块: 30-tables.sh
# 说明:全部为静态数据与纯函数,不产生副作用

# 时区分类:CN=陆港澳确定时区(含历史链接名) HKMO E8=非陆港澳东八 OTHER
tz_class() {
  case "$1" in
    Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Chungking|Asia/PRC|PRC|\
    Asia/Urumqi|Asia/Kashgar) printf 'CN' ;;
    Asia/Hong_Kong|Asia/Hongkong|Hongkong|Asia/Macau|Asia/Macao|Macau|Macao) printf 'HKMO' ;;
    Asia/Singapore|Asia/Kuala_Lumpur|Asia/Kuching|Asia/Brunei|Asia/Makassar|\
    Asia/Manila|Asia/Taipei|Asia/Choibalsan|Asia/Ulaanbaatar|Asia/Irkutsk|\
    Australia/Perth) printf 'E8' ;;
    *) printf 'OTHER' ;;
  esac
}

# 时区 UTC 偏移(如 +0800;依赖 date 的 TZ 语义)
tz_offset() { TZ="$1" date +%z 2>/dev/null; }

cnname() { case "$1" in CN) printf '中国大陆';; HK) printf '香港';; MO) printf '澳门';; *) printf '%s' "$1";; esac; }

# 拼音姓名启发式:精确命中姓氏/名,或两段拼接均为表内词(保守,防误报)
PINYIN_SURNAME='wang li zhang liu chen yang huang zhao wu zhou xu sun ma zhu hu guo he gao lin luo zheng liang xie song tang deng feng han cao zeng peng xiao tian dong pan yuan yu ye du su wei cheng lu ding ren shen yao jiang cui zhong tan'
PINYIN_GIVEN='wei ming hong tao jun jing lei fang qiang yong hua yu tian xin yun fei yue hang chen xi zhe hao nan shuai bo chao peng yu jia qi lin yang cheng long xin jian guo qing xue ying juan min li na ting yan qin yue zhen rui ze kai lang jie'

is_pinyin_name() {
  _h=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '._-')
  case " $PINYIN_SURNAME " in *" $_h "*) return 0 ;; esac
  case " $PINYIN_GIVEN " in *" $_h "*) return 0 ;; esac
  if [ "${#_h}" -ge 4 ] && [ "${#_h}" -le 12 ]; then
    _i=2
    while [ "$_i" -lt "$(( ${#_h} - 1 ))" ]; do
      _a=$(printf '%s' "$_h" | cut -c1-"$_i"); _b=$(printf '%s' "$_h" | cut -c"$(($_i+1))"-)
      case " $PINYIN_SURNAME $PINYIN_GIVEN " in *" $_a "*) case " $PINYIN_GIVEN " in *" $_b "*) return 0 ;; esac ;; esac
      _i=$((_i+1))
    done
  fi
  return 1
}

# Windows 时区名分类(陆港澳共用 China Standard Time;E8=东八非陆港澳)
win_tz_class() {
  case "$1" in
    "China Standard Time") printf 'CN' ;;
    "Taipei Standard Time"|"Singapore Standard Time"|"Kuala Lumpur Standard Time"|\
    "W. Australia Standard Time"|"Irkutsk Standard Time"|"Ulaanbaatar Standard Time") printf 'E8' ;;
    *) printf 'OTHER' ;;
  esac
}

# 时区名 → 十进制小时偏移(Asia/Shanghai → 8.0;失败 → 空串)
tz_off_hours() {
  _o=$(tz_offset "$1" 2>/dev/null)
  case "$_o" in
    [+-][0-9][0-9][0-9][0-9]) ;;
    *) printf '' ; return ;;
  esac
  _s=${_o%????}; _hm=${_o#?}; _h=${_hm%??}; _m=${_hm#??}
  case "$_h" in 0?) _h=${_h#0} ;; esac
  case "$_m" in 0?) _m=${_m#0} ;; esac
  _v=$((_h * 60 + _m)); [ "$_s" = "-" ] && _v=$((- _v))
  awk "BEGIN{printf \"%.1f\", $_v/60}"
}

# ── 内地法定假日与调休补班日(国务院办公厅通知;2024–2026;2027 待公布) ──
# 调休补班日 = 内地特有的「周末上班日」;港澳及海外无此实践 → 遵循该日历是内地工作节奏的强特征
CN_HOLIDAYS="20240101 20240210 20240211 20240212 20240213 20240214 20240215 20240216 20240217 20240404 20240405 20240406 20240501 20240502 20240503 20240504 20240505 20240610 20240915 20240916 20240917 20241001 20241002 20241003 20241004 20241005 20241006 20241007 20250101 20250128 20250129 20250130 20250131 20250201 20250202 20250203 20250204 20250404 20250405 20250406 20250501 20250502 20250503 20250504 20250505 20250531 20250601 20250602 20251001 20251002 20251003 20251004 20251005 20251006 20251007 20251008 20260101 20260102 20260103 20260215 20260216 20260217 20260218 20260219 20260220 20260221 20260222 20260223 20260404 20260405 20260406 20260501 20260502 20260503 20260504 20260505 20260619 20260620 20260621 20260925 20260926 20260927 20261001 20261002 20261003 20261004 20261005 20261006 20261007"
CN_MAKEUP="20240204 20240218 20240407 20240428 20240511 20240914 20240929 20241012 20250126 20250208 20250427 20250928 20251011 20260104 20260214 20260228 20260509 20260920 20261010"

# ── 正则表 ──
CN_MIRROR_RE='mirrors\.aliyun\.com|mirrors\.tuna\.|mirrors\.ustc\.edu|mirrors\.163\.com|mirror\.sjtu\.edu|mirrors\.huaweicloud\.com|repo\.huaweicloud\.com|mirrors\.tencent\.com|mirrors\.cloud\.tencent\.com|mirrors\.bfsu\.edu|mirror\.nju\.edu|mirrors\.zju\.edu|mirrors\.cqu\.edu'
CLOUD_INT_MIRROR_RE='mirrors\.cloud\.aliyuncs\.com|mirrors\.tencentyun\.com|mirrors\.myhuaweicloud\.com|mirror\.tencentyun'
CN_EMAIL_RE='@(qq|163|126|foxmail|sina|sohu|yeah|139|189|aliyun)\.(com|cn|net)|@189\.cn'
CN_DOMAIN_RE='baidu\.com|taobao|tmall|aliyun|jd\.com|bilibili|qq\.com|163\.com|weibo|zhihu|douyin|csdn\.net|gitee\.com|cnblogs|51cto|aliyuncs|tencentcloud|huaweicloud|ghproxy|fastgit|gh-proxy|lanzn|moeyy'
CN_DEV_MIRROR_VAL_RE='taobao|aliyun|tencent|npmmirror|cnpmjs|goproxy\.cn|goproxy\.io|ustc|tuna|sjtu|nju|bfsu|huaweicloud|tencentyun|github\.cnpmjs|mirrors\.cloud'
CJK_FONT_RE='wqy|wenquanyi|noto.*cjk|cjk|source-han|opposans|misans|harmonyossans|alibaba.*puhui'
CN_NTP_RE='aliyun|tencent|cn\.pool\.ntp|ntp\.org\.cn|time\.edu|ntp\.aliyun'

# ── 进程 / 端口 / 云特征 ──
CLOUD_AGENT_PROC_RE='AliYunDun|aliyun-service|aegis|AliyunDunUpdate|barad|YDService|YDLive|yunjing|qcloud|telescope|VolcanoAgent|argus'
CLOUD_AGENT_DIRS='/usr/local/aegis /usr/local/qcloud /usr/local/telescope /usr/local/cloudmonitor /usr/local/sa /usr/local/ubt'
CN_CLOUD_DMI_RE='Alibaba|Tencent|HUAWEI CLOUD|Volcano|CTYUN|UCloud|Kingsoft|Baidu'
PROXY_PORT_LIST='7890 7891 7892 7897 10808 10809 8388 8118 3128 9090 7895 20170 20171'
PROXY_PROC_RE='clash|mihomo|v2ray|xray|ss-local|ssr-|hysteria|trojan|sing-box|naive|brook|snell'
CN_APP_PROC_RE='WeChat|weixin|linuxqq|dingtalk|wps|baidunetdisk|xunlei|netease-cloud|youku'
CN_SOFT_PKG_RE='^(fcitx|ibus-rime|rime|fcitx5|sogou|wechat|weixin|electronic-wechat|qq|linuxqq|dingtalk|wps|baidunetdisk|xunlei|baidupcs|netease-cloud-music|youku)'
CN_SOFT_DIRS='.xwechat_files .config/qq .config/QQ .config/dingtalk .config/baidunetdisk BaiduNetdiskDownload xunlei-download .config/netease-cloud-music .config/NetEase'
DEV_MIRROR_ENVS='ELECTRON_MIRROR ELECTRON_CUSTOM_DIR NVM_NODEJS_ORG_MIRROR NODEJS_ORG_MIRROR SASS_BINARY_SITE SASS_BINARY_PATH PHANTOMJS_CDNURL CHROMEDRIVER_CDNURL PUPPETEER_DOWNLOAD_HOST PUPPETEER_DOWNLOAD_BASE_URL SENTRYCLI_CDNURL PYTHON_INDEX_URL PIP_INDEX_URL GOPROXY HOMEBREW_BOTTLE_DOMAIN HOMEBREW_API_DOMAIN NPM_CONFIG_REGISTRY YARN_REGISTRY MAVEN_MIRROR'

# ── 网络类数据表(v0.2) ──
# 国内公共 DNS
CN_PUBLIC_DNS=" 114.114.114.114 114.114.115.115 223.5.5.5 223.6.6.6 119.29.29.29 119.28.28.28 180.76.76.76 1.2.4.8 210.2.4.8 182.254.116.116 182.254.118.118 123.125.81.6 140.207.198.6 "
# 已知 DNS 注入假 IP(公开文献记录的稳定集合,小而保守)
FAKE_IPS=" 8.7.198.45 46.82.174.68 59.24.3.173 78.16.49.15 93.46.8.89 159.106.121.75 203.98.7.65 243.185.187.39 37.61.54.158 4.36.66.178 "
# 国内网络设备厂商 OUI 前缀(华为/荣耀/TP-Link/小米/H3C 等常见段;启发式,弱证据)
GW_OUI_CN_LIST="00:18:82 34:6B:D3 48:46:FB 58:60:5F 88:28:B3 34:87:23 18:DE:D7 50:C7:BF 14:CC:20 5C:E9:31 AC:84:C6 30:B5:C2 54:C8:0F 64:09:80 64:64:4A 28:6C:07 0C:1D:AF 78:11:DC 3C:8C:98 D4:3A:E9"
