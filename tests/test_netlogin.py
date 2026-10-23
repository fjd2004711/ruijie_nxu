"""Credential-free regression tests; run with python3 -m unittest discover -s tests."""
import base64
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('netlogin.sh', 'netlogin_openwrt.sh')


def function(script, name):
    source = (ROOT / script).read_text()
    return re.search(r'(?:function )?' + name + r'\(\) \{.*?^\}', source, re.S | re.M)[0]


def run(code, *args, shell='sh'):
    return subprocess.run([shell, '-c', code, 'test', *args],
                          env=dict(os.environ, LC_ALL='C'), capture_output=True, text=True)


class NetLoginTests(unittest.TestCase):
    def test_base64_without_applet(self):
        vectors = ['', 'a', 'ab', 'abc', '校园密码!\\$"', 'a\nb\n', '\n', ' ',
                   ''.join(chr(i) for i in range(1, 128))]
        for script in SCRIPTS:
            code = function(script, 'base64_no_wrap').replace(
                'command -v base64 >/dev/null 2>&1', 'false')
            for shell in ('bash', 'sh'):
                for value in vectors:
                    with self.subTest(script=script, shell=shell, value=value):
                        result = run(code + '\nbase64_no_wrap "$1"', value, shell=shell)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout, base64.b64encode(value.encode()).decode())

    def test_shared_protocol_helpers(self):
        for name in ('base64_no_wrap', 'json_string', 'valid_ipv4', 'valid_mac',
                     'portal_status', 'get_terminal_info', 'check_connection', 'logout'):
            self.assertEqual(function(SCRIPTS[0], name), function(SCRIPTS[1], name))

    def test_online_result_boundary(self):
        code = function(SCRIPTS[1], 'check_connection')
        for result, expected in ((1, 0), (0, 1), (10, 1)):
            completed = run('portal_status(){ printf \'dr1({"result":%s})\' "$1"; }\n'
                            .replace('"$1"', str(result)) + code + '\ncheck_connection')
            self.assertEqual(completed.returncode, expected)

    def test_terminal_validators(self):
        code = function(SCRIPTS[1], 'valid_ipv4')
        for value, expected in [('10.1.2.3', 0), ('256.1.2.3', 1), ('0.0.0.0', 1), ('', 1), ('10.1.2', 1)]:
            self.assertEqual(run(code + '\nvalid_ipv4 "$1"', value).returncode, expected)
        code = function(SCRIPTS[1], 'valid_mac')
        for value, expected in [('aabbccddeeff', 0), ('000000000000', 1), ('bad', 1), ('ggbbccddeeff', 1)]:
            self.assertEqual(run(code + '\nvalid_mac "$1"', value).returncode, expected)

    def test_portal_identity_overrides_lan(self):
        code = '\n'.join(function(SCRIPTS[1], name) for name in
                         ('json_string', 'valid_ipv4', 'valid_mac', 'get_terminal_info'))
        mocks = '''
        uname(){ echo Linux; }
        ip(){ case "$*" in *route*) echo '10.10.129.197 via 172.22.0.2 dev test-nxu src 172.22.0.149';;
              *link*) echo 'link/ether aa:bb:cc:dd:ee:ff';; esac; }
        portal_status(){ printf '%s' 'dr1({"v46ip":"10.12.50.150","ss4":"000000000000","olmac":"bc2411821a39"})'; }
        log_debug(){ :; }
        log_error(){ echo "$1" >&2; }
        portal_ip=10.10.129.197
        '''
        result = run(mocks + code + '\nget_terminal_info || exit; printf "%s/%s" "$terminal_ip" "$terminal_mac"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '10.12.50.150/bc2411821a39')

    def test_login_quoted_online_code_and_empty_encoding(self):
        for script in SCRIPTS:
            code = function(script, 'connect')
            mock = """
            get_terminal_info(){ terminal_ip=10.1.2.3; terminal_mac=aabbccddeeff; }
            load_portal_config(){ portal_program=program; portal_page=page; }
            base64_no_wrap(){ printf encoded; }
            portal_key_from_ip(){ echo 1; }
            portal_encrypt(){ printf '%s' "$1"; }
            log_debug(){ :; }; log_info(){ :; }; log_error(){ :; }; log_warn(){ :; }
            username=test; password=test; service=campus
            curl(){ printf 'dr1({"result":0,"ret_code":"2"})\\n200'; }
            """
            shell = 'bash' if script == 'netlogin.sh' else 'sh'
            result = run(mock + code + '\nconnect', shell=shell)
            self.assertEqual(result.returncode, 0, result.stderr)
            # Encoding failure must stop before sending credentials to the server.
            guard = mock + code + '\nbase64_no_wrap(){ :; }; curl(){ echo SENT; }; connect'
            completed = run(guard, shell=shell)
            self.assertEqual(completed.returncode, 1)
            self.assertNotIn('SENT', completed.stdout)

    def test_logout_reports_failure(self):
        code = function(SCRIPTS[1], 'logout')
        for value, expected in [(1, 0), (0, 1), (10, 1)]:
            mock = 'get_terminal_info(){ :; }; load_portal_config(){ :; }; portal_key_from_ip(){ echo 0; }; portal_encrypt(){ printf %s "$1"; }; curl(){ echo \'dr1({"result":' + str(value) + '})\'; }; log_info(){ :; }; log_warn(){ :; }\n'
            self.assertEqual(run(mock + code + '\nlogout').returncode, expected)


OPENWRT = SCRIPTS[1]


def funcs(*names):
    return '\n'.join(function(OPENWRT, name) for name in names)


LOCK_CODE_NAMES = ('nap', 'lock_busy', 'acquire_action_lock', 'release_action_lock', 'run_locked')
LOCK_MOCKS = 'nap(){ :; }; log_warn(){ :; }; LOCK_HELD=0\n'


class AccountSwitchAndLockTests(unittest.TestCase):
    def lock_run(self, body, lock_dir, pause=None):
        code = ('LOCK_DIR="%s"; PAUSE_FILE="%s"\n' % (lock_dir, pause or lock_dir + '.paused')
                + LOCK_MOCKS + funcs(*LOCK_CODE_NAMES, 'clear_stale_pause') + '\n' + body)
        return run(code)

    def dead_pid(self):
        proc = subprocess.Popen(['true'])
        proc.wait()
        return proc.pid

    def test_lock_excludes_live_holder_and_is_reentrant(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = tmp + '/lock'
            holder = subprocess.Popen(['sleep', '30'])
            try:
                os.mkdir(lock)
                Path(lock, 'pid').write_text(str(holder.pid))
                self.assertEqual(self.lock_run('acquire_action_lock quiet', lock).returncode, 1)
                self.assertEqual(self.lock_run('run_locked true', lock).returncode, 75)
            finally:
                holder.kill()
                holder.wait()
            # 持有者已死：陈旧锁被回收；回收后可重入，释放后目录消失。
            Path(lock, 'pid').write_text(str(self.dead_pid()))
            result = self.lock_run('acquire_action_lock && acquire_action_lock && release_action_lock; '
                                   '[ ! -d "$LOCK_DIR" ]', lock)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_lock_with_unwritten_pid_is_recovered_when_abandoned(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = tmp + '/lock'
            os.mkdir(lock)  # 创建者在写 pid 前崩溃
            self.assertEqual(self.lock_run('acquire_action_lock quiet', lock).returncode, 0)

    def test_run_locked_releases_lock_and_returns_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = tmp + '/lock'
            result = self.lock_run('f(){ return 7; }; run_locked f; rc=$?; [ ! -d "$LOCK_DIR" ] && exit $rc', lock)
            self.assertEqual(result.returncode, 7, result.stderr)

    def test_online_session_keeps_pause_while_logout_in_progress(self):
        # 回归：注销进行中会话尚未下线，守护进程看到在线时不能清除暂停标志。
        with tempfile.TemporaryDirectory() as tmp:
            lock, pause = tmp + '/lock', tmp + '/paused'
            holder = subprocess.Popen(['sleep', '30'])
            try:
                os.mkdir(lock)
                Path(lock, 'pid').write_text(str(holder.pid))
                Path(pause).write_text('logout')
                self.lock_run('clear_stale_pause', lock, pause)
                self.assertTrue(os.path.exists(pause))
            finally:
                holder.kill()
                holder.wait()
            # 没有流程在进行：过期的暂停标志（logout 或 failures）应被清除。
            Path(lock, 'pid').write_text(str(self.dead_pid()))
            for reason in ('logout', 'failures'):
                Path(pause).write_text(reason)
                self.lock_run('clear_stale_pause', lock, pause)
                self.assertFalse(os.path.exists(pause), reason)

    def switch_run(self, body, uid='old', pause=''):
        code = '''
        username=new; switch_fail=0; switch_next=0; calls=0
        status_page='dr1({"result":1,"uid":"@@UID@@"})'
        PAUSE_FILE=$(mktemp); printf '%s' '@@PAUSE@@' > "$PAUSE_FILE"
        log_warn(){ :; }; log_state(){ :; }
        run_locked(){ calls=$((calls+1)); return "$FAKE_RC"; }
        '''.replace('@@UID@@', uid).replace('@@PAUSE@@', pause)
        return run(code + funcs('json_string', 'ensure_configured_account') + '\n' + body)

    def test_failed_switch_is_retried_with_backoff(self):
        body = '''
        FAKE_RC=1
        ensure_configured_account; first=$?
        ensure_configured_account; second=$?
        echo "$first $second $calls $switch_fail"
        switch_next=0; ensure_configured_account
        switch_next=0; ensure_configured_account
        echo "$calls $switch_fail $(( switch_next > $(date +%s) + 1000 ))"
        FAKE_RC=0; switch_next=0; ensure_configured_account; echo "$? $switch_fail"
        '''
        result = self.switch_run(body)
        # 退避期内不再尝试；退避过后重试；3 次失败后改为每 30 分钟一次；成功后清零。
        self.assertEqual(result.stdout.split('\n')[:3], ['1 0 1 1', '3 3 1', '0 0'], result.stderr)

    def test_busy_lock_is_not_counted_as_failure(self):
        result = self.switch_run('FAKE_RC=75; ensure_configured_account; echo "$? $switch_fail"')
        self.assertEqual(result.stdout.strip(), '1 0')

    def test_matching_or_unknown_account_does_nothing(self):
        for uid in ('new', ''):
            result = self.switch_run('FAKE_RC=1; ensure_configured_account; echo "$? $calls"', uid=uid)
            self.assertEqual(result.stdout.strip(), '0 0', uid)

    def test_no_switch_while_logout_in_progress(self):
        result = self.switch_run('FAKE_RC=0; ensure_configured_account; echo "$? $calls"', pause='logout')
        self.assertEqual(result.stdout.strip(), '0 0')

    def test_logout_effect_needs_two_consecutive_offline_checks(self):
        head = 'nap(){ :; }\n' + function(OPENWRT, 'wait_logout_effect') + '\n'
        tail = '\nwait_logout_effect; echo "$? $n"'
        # 序列：离线、在线、离线、在线……单次离线不算注销生效，直到 90 秒超时。
        flaky = 'n=0; check_connection(){ n=$((n+1)); case "$n" in 1|3) return 1;; *) return 0;; esac; }'
        self.assertEqual(run(head + flaky + tail).stdout.strip(), '1 30')
        steady = 'n=0; check_connection(){ n=$((n+1)); case "$n" in 1|2) return 1;; *) return 0;; esac; }'
        self.assertEqual(run(head + steady + tail).stdout.strip(), '0 2')

    def test_unbind_targets_online_account_not_configured_one(self):
        base = '''
        get_terminal_info(){ terminal_status='STATUS'; terminal_mac=aabbccddeeff; terminal_ip=10.1.2.3; }
        load_portal_config(){ portal_program=p; portal_page=g; }; portal_key_from_ip(){ echo 0; }
        portal_encrypt(){ printf %s "$1"; }; log_debug(){ :; }; log_info(){ :; }; log_warn(){ :; }
        logout(){ echo PLAIN; }; username=new; status_page=''
        curl(){ printf "%s " "$@" >&2; }
        '''
        code = funcs('json_string', 'logout_with_unbind') + '\nlogout_with_unbind'
        result = run(base.replace('STATUS', 'dr1({"uid":"old"})') + code)
        self.assertIn('user_account=old', result.stderr)
        self.assertNotIn('user_account=new', result.stderr)
        # 门户没有返回在线账号：不能拿新账号去解绑，改走普通注销。
        result = run(base.replace('STATUS', 'dr1({})') + code)
        self.assertEqual(result.stdout.strip(), 'PLAIN')

    def test_sigterm_restores_wan_and_releases_lock(self):
        # 重拉 WAN 中途被终止（保存配置触发重启）时，必须补上 ifup 并释放锁。
        with tempfile.TemporaryDirectory() as tmp:
            out = tmp + '/out'
            code = ('LOCK_DIR="%s/lock"; LOCK_HELD=0; wan_down=0; wan_if=wan9; nap_pid=""\n' % tmp
                    + funcs('nap', 'release_action_lock', 'cleanup') + '\n'
                    + 'ifup(){ echo "UP $1" > "%s"; }\n' % out
                    + "trap cleanup EXIT; trap 'exit 143' HUP INT TERM\n"
                    + 'mkdir "$LOCK_DIR"; echo $$ > "$LOCK_DIR/pid"; LOCK_HELD=1\n'
                    + 'wan_down=1; nap 30\n')
            proc = subprocess.Popen(['sh', '-c', code])
            time.sleep(0.7)
            started = time.time()
            proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=5)
            self.assertLess(time.time() - started, 3)
            self.assertEqual(Path(out).read_text().strip(), 'UP wan9')
            self.assertFalse(os.path.exists(tmp + '/lock'))


if __name__ == '__main__':
    unittest.main()
