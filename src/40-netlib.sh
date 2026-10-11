#────────────────────────────── 网络探测设施(active-probe)──────────────────────────────
# 模块: 40-netlib.sh

HTTP_TOOL=""
http_detect() {
  have curl && { HTTP_TOOL="curl"; return 0; }
  have wget && { HTTP_TOOL="wget"; return 0; }
  HTTP_TOOL=""
}

http_get() { # $1=url
  case "$HTTP_TOOL" in
    curl) curl -s --max-time 8 "$1" 2>/dev/null ;;
    wget) wget -q -T 8 -O - "$1" 2>/dev/null ;;
  esac
}
http_get6() { # 强制 IPv6
  case "$HTTP_TOOL" in
    curl) curl -s -6 --max-time 8 "$1" 2>/dev/null ;;
    wget) wget -q -6 -T 8 -O - "$1" 2>/dev/null ;;
  esac
}
http_post() { # $1=url $2=JSON body
  case "$HTTP_TOOL" in
    curl) curl -s --max-time 10 -H 'Content-Type: application/json' -d "$2" "$1" 2>/dev/null ;;
    wget) wget -q -T 10 -O - --header='Content-Type: application/json' --post-data="$2" "$1" 2>/dev/null ;;
  esac
}

# 从单条 JSON 对象提取 "key":"value"(浅层,值中无嵌套转义)
jf() { # $1=key $2=json
  printf '%s' "$2" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

ip_is_private() {
  case "$1" in
    ::|::1|[fF][cCdD]*:*|[fF][eE][89aAbB]*:*|[fF][fF]*:*) return 0 ;;
    10.*|192.168.*|127.*|169.254.*|0.0.0.0|255.255.255.255|22[4-9].*|23[0-9].*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    100.6[4-9].*|100.7[0-9].*|100.8[0-9].*|100.9[0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
    *) return 1 ;;
  esac
}

hex2ip() { # /proc/net/tcp 小端 hex(8 位)→ 点分十进制
  printf '%s' "$1" | awk 'function d(x){v=0;for(i=1;i<=length(x);i++){v=v*16+index("0123456789abcdef",tolower(substr(x,i,1)))-1}return v}{printf "%d.%d.%d.%d", d(substr($0,7,2)), d(substr($0,5,2)), d(substr($0,3,2)), d(substr($0,1,2))}'
}

# ip-api 单 IP 查询 → "CC|country|as|reverse"(失败输出 ERR)
geoip1() {
  # 主源 HTTPS(ipwho.is,支持 IPv4/IPv6,抗传输篡改);失败回退 ip-api(HTTP,仅 IPv4)
  _b=$(http_get "https://ipwho.is/$1")
  case "$(jf success "$_b")" in true|1)
    _asn=$(printf '%s' "$_b" | sed -n 's/.*"asn":[ ]*\([0-9][0-9]*\).*/AS\1/p' | head -n 1)
    printf '%s|%s|%s|' "$(jf country_code "$_b")" "$(jf country "$_b")" "${_asn:-}"
    return ;;
  esac
  _b=$(http_get "http://ip-api.com/json/$1?fields=status,countryCode,country,as,reverse")
  if [ "$(jf status "$_b")" != "success" ]; then printf 'ERR'; return; fi
  printf '%s|%s|%s|%s' "$(jf countryCode "$_b")" "$(jf country "$_b")" "$(jf as "$_b")" "$(jf reverse "$_b")"
}

# 域名解析(经系统解析路径,取首个 A 记录)
dns_lookup() {
  if have dig; then dig +short +time=3 +tries=1 A "$1" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | head -n 1; return; fi
  if have getent; then
    _a=$(getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -n "$_a" ]; then printf '%s' "$_a"; return; fi
  fi
  if have nslookup; then
    nslookup "$1" 2>/dev/null | awk '/^Address/ && $2 !~ /#/{print $2}' | tail -n 1
  fi
}
