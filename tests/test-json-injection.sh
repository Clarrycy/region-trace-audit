#!/bin/sh
# 回归:JSON 注入(环境变量含换行/引号/竖线)不得破坏 --json 产物
# 背景:审计 2026-10-09 高① —— report 直拼 + awk -F'|' 可被注入
D=$(dirname "$0")/../dist/region-trace-audit.sh
env -i PATH="$PATH" HOME="$HOME" \
  http_proxy=$'http://127.0.0.1:8080\n"injected"|x' \
  sh "$D" --offline --json --section proxy > /tmp/rta-t1.json 2>/tmp/rta-t1.err
rc=$?
[ -s /tmp/rta-t1.err ] && { echo "FAIL: stderr 非空"; exit 1; }
python3 -c "
import json,sys
d = json.load(open('/tmp/rta-t1.json'))
msgs = [i['message'] for i in d['items'] if 'proxy/env' in i['item']]
assert msgs and msgs[0], 'proxy/env message 为空'
assert '|' in msgs[0] or '\\\\n' in msgs[0], '注入值未保留'
print('PASS: 注入被转义,值完整保留:', repr(msgs[0])[:80])" || exit 1
[ "$rc" = 0 ] || { echo "PASS(JSON);退出码=$rc(section=proxy 无可疑属预期)"; }
exit 0
