#!/bin/sh
# 回归:C11 复合升级 —— 正例(+0800 提交)触发 EXPOSED;负例(+0700)仅 SUSPICIOUS
# 背景:2026-10-09 精化设计(作息单条不升暴露,+7 歧义;复合需记录性旁证)
set -e
D=$(cd "$(dirname "$0")/.." && pwd)
FH=/tmp/rta-t2-home
rm -rf "$FH"; mkdir -p "$FH/bin" "$FH/.claude/projects/p" "$FH/proj"
printf '#!/bin/sh\nexit 1\n' > "$FH/bin/last"; chmod +x "$FH/bin/last"
printf '#!/bin/sh\nexit 1\n' > "$FH/bin/dnf"; chmod +x "$FH/bin/dnf"
# 160 条 AI 用户输入:UTC 02–16(东八 10:00–24:00)→ 区间 [6.0,7.5]、得分 1.0
for d in $(seq -w 1 20); do for h in 2 4 6 8 10 12 14 16; do
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hi"}]},"timestamp":"2026-09-%sT%02d:30:00.000Z"}\n' "$d" "$h"
done; done > "$FH/.claude/projects/p/s.jsonl"
mkgit() { # $1 = 时区偏移
  rm -rf "$FH/proj/.git"; cd "$FH/proj"
  git init -q .; git config user.email t@t; git config user.name t
  for i in 1 2 3 4 5; do
    echo "c$i" > f.txt; git add -A
    GIT_AUTHOR_DATE="2026-09-1${i}T10:00:00$1" GIT_COMMITTER_DATE="2026-09-1${i}T10:00:00$1" \
      git commit -qm "c$i" --date="2026-09-1${i}T10:00:00$1"
  done
}
run() {
  sed -n '/^check_c11()/,/^}$/p' "$D/src/68-c11-time.sh" > /tmp/rta-c11fn.sh
  HOME=$FH PATH="$FH/bin:$PATH" sh -c '
    cd "'"$D"'"
    BRIEF=0; NOCOLOR=1; REVEAL=0; OFFLINE=0; DEEP_GEO=0; RADIO=0; JSON=0; SECTION=all; HTTP_TOOL=""
    VERSION=t; C_HDR=""; C_RST=""; C_DIM=""; C_EXP=""; C_SUS=""; C_CLN=""; C_INF=""; C_SKP=""; C_CAT=""
    CNT_CLN=0; CNT_SUS=0; CNT_EXP=0; CNT_INF=0; CNT_SKP=0; LOG_EXP=""; LOG_SUS=""; JSON_LOG=""; USEGEO_VIEW=""
    MY_PIDS=" $$ "; PLATFORM=linux-vm; PS_SNAP=""
    . ./src/20-framework.sh >/dev/null 2>&1
    . ./src/30-tables.sh    >/dev/null 2>&1
    . ./src/40-netlib.sh    >/dev/null 2>&1
    . ./src/41-context.sh   >/dev/null 2>&1
    have() { command -v "$1" >/dev/null 2>&1; }
    TZ_NAME=Asia/Tokyo; TZ_CLASS=OTHER; EGRESS_CC=JP
    . /tmp/rta-c11fn.sh
    check_c11' 2>&1
}
mkgit +0800
P1=$(run | grep -c 'tz-consist-strong.*暴露' || true)
mkgit +0700
N1=$(run | grep -c 'tz-consist-strong' || true)
[ "$P1" -ge 1 ] && [ "$N1" = 0 ] && echo "PASS: +0800 触发复合暴露($P1 行),+0700 不触发($N1 行)" || { echo "FAIL: P1=$P1 N1=$N1"; exit 1; }
rm -rf "$FH"
