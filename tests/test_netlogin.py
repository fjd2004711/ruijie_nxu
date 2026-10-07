"""Credential-free regression tests; run with python3 -m unittest discover -s tests."""
import base64
import os
from pathlib import Path
import re
import subprocess
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


if __name__ == '__main__':
    unittest.main()
