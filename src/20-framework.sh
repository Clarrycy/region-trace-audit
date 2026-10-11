#────────────────────────────── 框架:颜色 / 报告 / 脱敏 / 通用工具 ──────────────────────────────
# 模块: 20-framework.sh

if [ "$NOCOLOR" = 0 ] && [ -t 1 ] && [ -z "$NO_COLOR" ]; then
  C_EXP=$(printf '\033[1;31m'); C_SUS=$(printf '\033[33m')
  C_CLN=$(printf '\033[32m');   C_INF=$(printf '\033[36m')
  C_SKP=$(printf '\033[90m');   C_HDR=$(printf '\033[1m')
  C_RST=$(printf '\033[0m')
else
  C_EXP=""; C_SUS=""; C_CLN=""; C_INF=""; C_SKP=""; C_HDR=""; C_RST=""
fi

CNT_EXP=0; CNT_SUS=0; CNT_CLN=0; CNT_INF=0; CNT_SKP=0
LOG_EXP=""; LOG_SUS=""; JSON_LOG=""
TZ_MAIN=""; INSTALL_AGE_DAYS=0

# report <LEVEL> <cat/item> <desc>   —— desc 必须单行
report() {
  _rl="$1"; _rc="$2"; _rd="$3"
  case "$_rl" in
    EXPOSED)    CNT_EXP=$((CNT_EXP+1)); LOG_EXP="${LOG_EXP}${_rc}|${_rd}
"; _m='✗'; _c="$C_EXP"; _w='暴露' ;;
    SUSPICIOUS) CNT_SUS=$((CNT_SUS+1)); LOG_SUS="${LOG_SUS}${_rc}|${_rd}
"; _m='!'; _c="$C_SUS"; _w='可疑' ;;
    CLEAN)      CNT_CLN=$((CNT_CLN+1)); _m='✓'; _c="$C_CLN"; _w='正常' ;;
    INFO)       CNT_INF=$((CNT_INF+1)); _m='*'; _c="$C_INF"; _w='信息' ;;
    SKIP)       CNT_SKP=$((CNT_SKP+1)); _m='-'; _c="$C_SKP"; _w='跳过' ;;
    *) return 0 ;;
  esac
  if [ "${JSON:-0}" = 1 ]; then
    JSON_LOG="${JSON_LOG}${_rl}|${_rc}|$(json_escape "$_rd")
"
    return 0
  fi
  if [ "$BRIEF" = 0 ] || [ "$_rl" = "EXPOSED" ] || [ "$_rl" = "SUSPICIOUS" ]; then
    printf '%s[%s]%s %-20s %s %s→ %s%s%s\n' \
      "$_c" "$_m" "$C_RST" "[$_rc]" "$_rd" "$C_SKP" "$_c" "$_w" "$C_RST"
  fi
}

hdr() {  # 类别标题
  [ "${JSON:-0}" = 1 ] && return 0
  [ "$BRIEF" = 0 ] && printf '\n%s── %s ──%s\n' "$C_HDR" "$1" "$C_RST"
}

# JSON 字符串转义:反斜杠/引号/制表/回车转义,换行合并为 \n,
# 竖线转 \u007c —— 保证转义后不含字段分隔符与裸控制字符(防环境值注入破坏 JSON)
json_escape() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    { if (NR>1) buf = buf "\\n"
      line = $0
      gsub(/\\/, "\\\\", line); gsub(/"/, "\\\"", line)
      gsub(/\t/, "\\t", line); gsub(/\r/, "\\r", line)
      gsub(/\|/, "\\u007c", line)
      buf = buf line }
    END { printf "%s", buf }' | LC_ALL=C tr -d '\001-\011\013\014\016-\037'
}

# JSON 输出(--json):items 全量 + 汇总 + usegeo 视图;单对象输出到 stdout
json_emit() {
  _esc='s/\\/\\\\/g; s/"/\\"/g'
  printf '{'
  printf '"meta":{'
  printf '"version":"%s","platform":"%s","generated":"%s"' "$VERSION" "$PLATFORM" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf ',"mode":{'
  printf '"offline":%s,"deep_geo":%s,"radio":%s,"reveal":%s' \
    "$([ "$OFFLINE" = 1 ] && printf true || printf false)" \
    "$([ "$DEEP_GEO" = 1 ] && printf true || printf false)" \
    "$([ "$RADIO" = 1 ] && printf true || printf false)" \
    "$([ "$REVEAL" = 1 ] && printf true || printf false)"
  printf '}}'
  printf ',"summary":{"exposed":%d,"suspicious":%d,"clean":%d,"info":%d,"skip":%d,"exit_code":%d}' \
    "$CNT_EXP" "$CNT_SUS" "$CNT_CLN" "$CNT_INF" "$CNT_SKP" "$EXIT_CODE"
  printf ',"items":['
  printf '%s' "$JSON_LOG" | awk -F'|' '
    NR>1 { printf "," }
    {
      item=$2; msg=$3
      cat = item; sub(/\/.*$/, "", cat)
      # msg 已在 report() 预转义(json_escape),不再二次转义
      printf "{\"level\":\"%s\",\"category\":\"%s\",\"item\":\"%s\",\"message\":\"%s\"}", $1, cat, item, msg
    }'
  printf ']'
  printf ',"usegeo_view":['
  printf '%s' "${USEGEO_VIEW:-}" | LC_ALL=C awk '
    NF>0 { if (n++) printf ","
      t=$0
      gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); gsub(/\|/, "\\u007c", t)
      printf "\"%s\"", t }'
  printf ']'
  printf '}\n'
}

mask_ip() {
  [ "$REVEAL" = 1 ] && { printf '%s' "$1"; return; }
  case "$1" in
    *:*) printf '%s' "$1" | awk -F: '{print $1":"$2"::(v6)"}' ;;
    *.*) printf '%s' "$1" | awk -F. '{print $1"."$2".x.x"}' ;;
    *)   printf '%s' "$1" ;;
  esac
}
mask_mail() {
  [ "$REVEAL" = 1 ] && { printf '%s' "$1"; return; }
  printf '%s' "$1" | awk -F@ '{ if (NF==2) printf "%c**@%s", substr($1,1,1), $2; else print "***" }'
}
_m_url() {
  [ "$REVEAL" = 1 ] && { printf '%s' "$1"; return; }
  printf '%s' "$1" | sed 's|\(https\?://[^/]*\).*|\1/…|'
}

have() { command -v "$1" >/dev/null 2>&1; }

has_text() { printf '%s' "$1" | grep -q '[^[:space:]]'; }

# GNU/BSD stat: validate numeric output (GNU stat -f prints filesystem metadata).
fs_mtime() (
  _mt=$(stat -c %Y "$1" 2>/dev/null) || _mt=""
  case "$_mt" in ''|*[!0-9]*) _mt=$(stat -f %m "$1" 2>/dev/null) || _mt="" ;; esac
  case "$_mt" in ''|*[!0-9]*) return 1 ;; *) printf '%s\n' "$_mt" ;; esac
)

# Consume newline-delimited paths without splitting spaces, quotes or backslashes.
# Filenames containing a newline remain outside this bounded sampling format.
file_mtimes() (
  while IFS= read -r _mf; do
    [ -f "$_mf" ] && fs_mtime "$_mf"
  done
  :
)

# 文件时间戳(birth 优先,回退 mtime;GNU/BSD 兼容;空=不可得)
fs_btime() {
  _t=""
  _t=$(stat -c %W "$1" 2>/dev/null) || _t=""
  case "$_t" in ""|0)
    _t=$(stat -f %B "$1" 2>/dev/null) || _t=""
  esac
  case "$_t" in ""|0)
    _t=$(stat -c %Y "$1" 2>/dev/null) || _t=""
    case "$_t" in ""|0) _t=$(stat -f %m "$1" 2>/dev/null) || _t="" ;; esac
  esac
  case "$_t" in ""|0|*[!0-9]*) printf '' ;; *) printf '%s' "$_t" ;;
  esac
}

_r_basename() { printf '%s' "$1" | sed 's|.*/||'; }

# 进程表(快照优先 —— 在 collector_context 采集并排除自身进程树;
# 实时采集会抓到本脚本自己的管道子进程(如 grep -q fcitx 的 argv),造成自匹配)
ps_filtered() {
  if [ -n "${PS_SNAP:-}" ]; then
    printf '%s\n' "$PS_SNAP"
  else
    { ps aux 2>/dev/null || ps -ef 2>/dev/null; } | awk -v pids="${MY_PIDS:- }" 'index(pids, " " $2 " ") == 0'
  fi
}
