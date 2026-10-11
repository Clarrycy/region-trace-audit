#!/bin/sh
# 回归:JSON 注入(环境变量含换行/引号/竖线)不得破坏 --json 产物
# 背景:审计 2026-10-09 高① —— report 直拼 + awk -F'|' 可被注入
T=$(mktemp -d "${TMPDIR:-/tmp}/rta-json.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT HUP INT TERM
INJECTED_PROXY=$(printf 'http://127.0.0.1:8080\n"injected"|x')
D=$(dirname "$0")/../dist/region-trace-audit.sh
env -i PATH="$PATH" HOME="$HOME" \
  http_proxy="$INJECTED_PROXY" \
  sh "$D" --offline --json --section proxy > "$T/result.json" 2>"$T/stderr.txt"
rc=$?
[ -s "$T/stderr.txt" ] && { echo "FAIL: stderr 非空"; exit 1; }
python3 - "$T/result.json" <<'PYTEST'

import json,sys
d = json.load(open(sys.argv[1]))
msgs = [i['message'] for i in d['items'] if 'proxy/env' in i['item']]
assert msgs and msgs[0], 'proxy/env message 为空'
assert msgs[0] == 'http_proxy=http://127.0.0.1:8080\n"injected"|x', '注入值未完整保留'
print('PASS: 注入被转义,值完整保留:', repr(msgs[0])[:80])
PYTEST
[ "$?" = 0 ] || exit 1
[ "$rc" = 0 ] || { echo "PASS(JSON);退出码=$rc(section=proxy 无可疑属预期)"; }
exit 0
