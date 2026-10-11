#!/usr/bin/env python3
"""Offline fixtures for Darwin adapters; stdlib only, no real user data/network."""
import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('TEST_SHELL', '/bin/sh')


class MacOSAudit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rta-macos-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home with spaces and 'quotes'"
        self.home.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C', TZ='UTC')
        for key in ('SSH_CONNECTION', 'SSH_CLIENT', 'SSH_TTY', 'LANG', 'http_proxy', 'https_proxy', 'all_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY'):
            self.env.pop(key, None)
        for name in ('last', 'loginctl', 'brew', 'dnf', 'git', 'crontab'):
            self.mock(name, 'exit 1')
        for name in ('curl', 'wget', 'dig', 'nslookup'):
            self.mock(name, 'echo "unexpected network call" >&2; exit 99')
        self.mock('uname', 'echo Darwin')
        self.mock('who', 'echo "fixture console Oct 11 10:00"')
        self.mock('ps', 'echo /sbin/launchd')
        self.mock('sw_vers', 'case "$1" in -productName) echo macOS ;; *) echo 26.1 ;; esac')
        self.mock('scutil', '''case "$1" in
--proxy) cat <<EOF
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
  HTTPSEnable : 1
  SOCKSEnable : 1
  ProxyAutoConfigEnable : 1
  ProxyAutoDiscoveryEnable : 1
}
EOF
;;
--dns) cat <<EOF
DNS configuration
resolver #1
  nameserver[0] : 192.168.1.1
resolver #2
  nameserver[0] : 192.168.1.1
  nameserver[1] : fe80::1%en0
EOF
;;
*) echo '  Name : fixture' ;;
esac''')
        self.mock('defaults', '''case "$*" in
'-g AppleLocale'| 'read -g AppleLocale') echo en_AU ;;
'read -g AppleLanguages') printf '(\\n    en-AU,\\n    "zh-Hans-AU"\\n)\\n' ;;
'read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID') echo com.apple.keylayout.US ;;
*) exit 1 ;;
esac''')
        self.mock('launchctl', "printf 'PID Status Label\\n- 0 com.todesktop.editor\\n' ")
        self.mock('sysctl', '''case "$*" in
'-n kern.boottime') echo '{ sec = 1700000000, usec = 987654 }' ;;
'-n hw.model') echo MacFixture ;;
'-n machdep.cpu.brand_string') echo 'Apple Fixture' ;;
'-n net.inet.ip.forwarding') echo 0 ;;
*) exit 1 ;;
esac''')
        self.mock('networksetup', "printf 'Hardware Port: Wi-Fi\\nDevice: en0\\nEthernet Address: hidden\\n'")
        self.mock('route', "printf ' gateway: 192.168.1.1\\n interface: utun4\\n'")
        self.mock('ifconfig', '''case "$1" in -l) echo 'lo0 en0 utun4' ;; *) echo ' inet 192.168.1.2 netmask 0xffffff00' ;; esac''')
        self.mock('netstat', "printf 'tcp4 0 0 127.0.0.1.7890 *.* LISTEN\\ntcp6 0 0 ::1.7890 *.* LISTEN\\n'")

    def mock(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/sh\n' + body + '\n')
        p.chmod(0o755)

    def run_checks(self, body, json_mode=True):
        setup = 'BRIEF=0; NOCOLOR=1; REVEAL=0; OFFLINE=1; DEEP_GEO=0; RADIO=0; JSON=%d; VERSION=test\n' % json_mode
        # Definitions only; avoid main and CLI argument parser.
        for p in sorted((ROOT / 'src').glob('*.sh')):
            if 20 <= int(p.name[:2]) < 90:
                setup += '. ' + shlex.quote(str(p)) + '\n'
        setup += 'PLATFORM=macos; CUR_USER=fixture; CUR_UID=501; PS_SNAP="fixture 123 0 /Applications/Editor.app/Contents/MacOS/Editor"; HTTP_TOOL=""\n'
        script = setup + body
        if json_mode:
            script += '\nEXIT_CODE=0; json_emit\n'
        out = subprocess.run([SHELL, '-c', script], env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr + out.stdout)
        self.assertEqual(out.stderr, '', out.stderr)
        return json.loads(out.stdout)['items'] if json_mode else out.stdout

    def item(self, items, name):
        return [i for i in items if i['item'] == name]

    def test_proxy_indentation_and_bundle_boundaries(self):
        items = self.run_checks('check_mac')
        proxies = self.item(items, 'macos/proxy')
        self.assertEqual(len(proxies), 5)
        self.assertTrue(all(i['level'] == 'INFO' for i in proxies))
        self.assertFalse(self.item(items, 'macos/cn-daemon'))
        self.assertIn('en-AU', self.item(items, 'macos/lang-first')[0]['message'])
        self.mock('launchctl', "printf 'PID Status Label\\n- 0 com.tencent.xinWeChat\\n- 0 com.todesktop.editor\\n'")
        hit = self.item(self.run_checks('check_mac'), 'macos/cn-daemon')[0]
        self.assertEqual(hit['level'], 'SUSPICIOUS')
        self.assertNotIn('todesktop', hit['message'])

    def test_disabled_and_unavailable_proxy(self):
        self.mock('scutil', "printf '<dictionary> {\\n HTTPEnable : 0\\n}\\n'")
        self.assertEqual(self.item(self.run_checks('check_mac'), 'macos/proxy')[0]['level'], 'CLEAN')
        self.mock('scutil', 'exit 1')
        self.assertEqual(self.item(self.run_checks('check_mac'), 'macos/proxy')[0]['level'], 'SKIP')

    def test_native_desktop_hardware_boot_and_network(self):
        items = self.run_checks('net_context; check_c1; check_c16; check_c17; check_c19; check_c13; check_c14')
        self.assertIn('macOS', self.item(items, 'sysinfo/os')[0]['message'])
        self.assertNotIn('[sshd]', self.item(items, 'sysinfo/collector')[0]['message'])
        self.assertNotIn('[mux]', self.item(items, 'sysinfo/collector')[0]['message'])
        self.assertIn('launchd', self.item(items, 'boot/pid1')[0]['message'])
        self.assertIn('utun4', self.item(items, 'kernel/routes')[0]['message'])
        self.assertEqual(self.item(items, 'gui/session')[0]['level'], 'INFO')
        self.assertEqual(self.item(items, 'gui/rd')[0]['level'], 'SKIP')
        self.assertIn('en0', self.item(items, 'hw/wireless')[0]['message'])
        self.assertIn('1 个端口', self.item(items, 'services/listen-ports')[0]['message'])
        self.assertIn('7890', self.item(items, 'services/proxy-ports')[0]['message'])
        self.assertNotIn('hidden', json.dumps(items))

    def test_permission_failures_are_not_clean(self):
        for name in ('scutil', 'sysctl', 'networksetup', 'netstat'):
            self.mock(name, 'exit 1')
        items = self.run_checks('check_c1; check_c13; check_c14; check_c19')
        for key in ('sysinfo/uptime', 'hw/model', 'hw/cpu', 'hw/wireless', 'services/listen-ports', 'gui/session'):
            self.assertEqual(self.item(items, key)[0]['level'], 'SKIP', key)

    def test_dns_dynamic_store_deduplicates_and_stays_offline(self):
        items = self.run_checks('HTTP_TOOL=curl; check_c6')
        dns = self.item(items, 'dns/resolvers')[0]['message']
        self.assertIn('scutil --dns', dns)
        self.assertEqual(dns.count('192.168.x.x'), 1)
        self.assertEqual(self.item(items, 'dns/pollution')[0]['level'], 'SKIP')
        self.assertIn('私网', self.item(items, 'dns/resolver-geo')[0]['message'])

    def test_bundled_locales_do_not_mean_selected_language(self):
        self.mock('locale', "printf 'en_AU.UTF-8\\nzh_CN.UTF-8\\n'")
        items = self.run_checks('check_c8')
        self.assertEqual(self.item(items, 'locale/localedef')[0]['level'], 'INFO')

    def test_who_fallback_keeps_local_and_remote_counts(self):
        self.mock('who', "printf 'fixture console Oct 11 10:00\\nremote ttys001 Oct 11 10:00 (203.0.113.7)\\n'")
        items = self.run_checks('check_c18; report INFO fixture/count "$SESS_LOCAL_N|$SESS_N|$SESS_REMOTES"')
        self.assertIn('1|2| 203.0.113.7', self.item(items, 'fixture/count')[0]['message'])
        if not Path('/proc/net/tcp').exists():
            self.assertEqual(self.item(items, 'session/ssh-peers')[0]['level'], 'SKIP')

    def test_edge_and_firefox_profiles_with_spaces(self):
        base = self.home / 'Library/Application Support'
        edge = base / 'Microsoft Edge/Default'
        edge.mkdir(parents=True)
        (edge / 'Preferences').write_text('{"application_locale":"zh-CN"}')
        (edge / 'History').write_text('https://www.baidu.com/private-query\n' * 12)
        ff = base / "Firefox/Profiles/person's profile"
        ff.mkdir(parents=True)
        (ff.parent.parent / 'profiles.ini').write_text("Path=Profiles/person's profile\n")
        (ff / 'places.sqlite').write_text('https://qq.com/private\n')
        items = self.run_checks('check_c15')
        self.assertIn('存在用户 profile', self.item(items, 'browser/edge')[0]['message'])
        self.assertEqual(self.item(items, 'browser/Microsoft Edge-lang')[0]['level'], 'SUSPICIOUS')
        self.assertIn('12 次', self.item(items, 'browser/Microsoft Edge-history')[0]['message'])
        self.assertIn('1 次', self.item(items, 'browser/firefox-history')[0]['message'])
        self.assertNotIn('private-query', json.dumps(items))

    def test_bsd_or_gnu_file_mtime_with_quotes(self):
        doc = self.home / "Documents/a 'quoted' file.txt"
        doc.parent.mkdir()
        doc.write_text('fixture')
        os.utime(doc, (1700000000, 1700000000))
        items = self.run_checks('report INFO fixture/mtime "$(find "$HOME/Documents" -type f | file_mtimes)"')
        self.assertEqual(self.item(items, 'fixture/mtime')[0]['message'], '1700000000')

    def test_january_february_timestamps_and_json_whitespace(self):
        path = self.home / ".claude/projects/project with spaces/session's file.jsonl"
        path.parent.mkdir(parents=True)
        dates = ['2026-01-15T12:30:00', '2024-02-29T12:30:00', '2026-09-15T12:30:00']
        path.write_text('\n'.join(json.dumps({'role': 'user', 'timestamp': t + 'Z'}) for t in dates))
        items = self.run_checks('check_c11; report INFO fixture/epochs "$_e3"')
        expected = '\n'.join(str(int(datetime.datetime.fromisoformat(t).replace(tzinfo=datetime.timezone.utc).timestamp())) for t in dates)
        self.assertEqual(self.item(items, 'fixture/epochs')[0]['message'], expected)

    def test_time_histogram_and_weekend_percentage(self):
        path = self.home / '.claude/projects/fixture/session.jsonl'
        path.parent.mkdir(parents=True)
        path.write_text('\n'.join(json.dumps({'role': 'user', 'timestamp': f'2026-09-{d:02}T{h:02}:30:00Z'}) for d in range(1, 21) for h in range(2, 17, 2)))
        text = self.run_checks('TZ_NAME=Asia/Tokyo; TZ_CLASS=OTHER; check_c11; :', json_mode=False)
        self.assertRegex(text, r'周末占比 [0-9]+%')
        self.assertNotIn('\ufffd', text)
        self.assertIn('AI用户输入=160', text)

    def test_git_uses_epoch_and_preserves_negative_author_offset(self):
        (self.home / 'repo with spaces/.git').mkdir(parents=True)
        self.mock('git', '''case "$*" in
*--pretty=*) echo '1768509000 2026-01-15 09:30:00 -0800' ;;
*) exit 1 ;;
esac''')
        items = self.run_checks('check_c11; report INFO fixture/git "$_e7|$_tz7"')
        msg = self.item(items, 'fixture/git')[0]['message']
        self.assertIn('1768509000|', msg)
        self.assertIn('-0800', msg)


if __name__ == '__main__':
    unittest.main(verbosity=2)
