#!/bin/sh
#─────────────────────────────────────────────────────────────────────────────
# build.sh — 将 src/ 模块按序拼接为单文件 dist/region-trace-audit.sh
# 模块文件名以两位数字前缀排序(00-header → 90-main),shell 通配展开即拼接顺序。
# 用法: ./build.sh [--test]   --test 时额外做语法检查与 --help 冒烟测试
#─────────────────────────────────────────────────────────────────────────────
set -eu
cd "$(dirname "$0")"

OUT="dist/region-trace-audit.sh"
mkdir -p dist

# 拼接(注释掉空模块,保证模块间空行)
: > "$OUT"
_first=1
for _f in src/*.sh; do
  [ -s "$_f" ] || continue
  if [ "$_first" = 1 ]; then _first=0; else printf '\n' >> "$OUT"; fi
  cat "$_f" >> "$OUT"
done
chmod +x "$OUT"

# 语法检查
sh -n "$OUT"
echo "构建完成: $OUT($(wc -l < "$OUT" | tr -d ' ') 行,$(wc -c < "$OUT" | tr -d ' ') 字节)"

if [ "${1:-}" = "--test" ]; then
  "$OUT" --help >/dev/null && echo "冒烟测试(--help):通过"
  OUTMODE=$("$OUT" --offline --brief 2>&1 | head -n 1) || true
  echo "冒烟测试(--offline --brief 首行):$OUTMODE"
fi
