"""Fixed desktop launch contract. Run under runtime-test on compute."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'home/dot_local/bin/domicile-terminal-open'
NATIVE = ROOT / 'home/dot_local/bin/domicile-open-terminal'


def load(path):
    loader = importlib.machinery.SourceFileLoader('native_launcher', str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class NativeLaunch(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / 'runtime'; self.runtime.mkdir(mode=0o700)
        self.log = self.root / 'calls.json'
        self.binary = self.root / 'domicile'
        self.binary.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['CALLS']).write_text(json.dumps({'argv':sys.argv[1:],'socket':os.environ['DOMICILE_SOCK']}))
sys.exit(int(os.environ.get('RETURN_CODE','0')))
''')
        self.binary.chmod(0o755)
        self.config = self.root / 'client.json'
        self.config.write_text(json.dumps({'desktopId':'zenbook','runtimeDirectory':str(self.runtime),
                                           'domicileBinary':str(self.binary)}))
        self.config.chmod(0o600)
        self.env = dict(os.environ, CALLS=str(self.log))

    def peer(self, name='one'):
        peer = socket.socket(socket.AF_UNIX)
        peer.bind(str(self.runtime / f'domicile-ipc.{name}.sock'))
        peer.listen(16)
        (self.runtime / f'domicile-ipc.{name}.sock').chmod(0o600)
        self.addCleanup(peer.close)
        return peer

    def launch(self, desktop='zenbook', cwd='/home/tom/project'):
        return subprocess.run([str(HELPER), desktop, '--cwd', cwd, '--config', str(self.config)],
                              env=self.env, capture_output=True, text=True)

    def test_native_request_preserves_project_data_and_uses_selected_desktop(self):
        self.peer()
        cwd = "/home/tom/a ' ; $(touch BAD) `touch BAD2`"
        result = self.launch(cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {'ok':True,'desktop':'zenbook','status':'launch-queued',
                                                    'dshOwnedPty':False,'observedWindow':None})
        call = json.loads(self.log.read_text())
        self.assertEqual(call['argv'], ['send-shell','exec','domicile-apps','terminal','--cwd',cwd])
        self.assertEqual(call['socket'], str(self.runtime/'domicile-ipc.one.sock'))

    def test_absent_ambiguous_and_wrong_desktop_never_launch(self):
        self.assertEqual(self.launch().returncode, 2)
        self.peer()
        self.assertEqual(self.launch(desktop='other').returncode, 2)
        self.peer('two')
        self.assertEqual(self.launch().returncode, 2)
        self.assertFalse(self.log.exists())

    def test_stale_socket_is_skipped(self):
        self.peer('stale').close()
        self.peer('live')
        self.assertEqual(self.launch().returncode, 0)
        self.assertEqual(json.loads(self.log.read_text())['socket'], str(self.runtime/'domicile-ipc.live.sock'))

    def test_untrusted_config_and_invalid_cwd_are_rejected(self):
        self.peer()
        self.config.chmod(0o644)
        self.assertEqual(self.launch().returncode, 2)
        self.config.chmod(0o600)
        for cwd in ('relative', '/home/tom/control\x1b', '/home/tom/line\nbreak'):
            self.assertEqual(self.launch(cwd=cwd).returncode, 2)
        self.assertFalse(self.log.exists())

    def test_refusal_is_not_reported_as_launch_success(self):
        self.peer()
        self.env['RETURN_CODE']='1'
        result = self.launch()
        self.assertEqual(result.returncode, 2)
        self.assertFalse(json.loads(result.stdout)['retryAutomatically'])

    def test_nas_launch_uses_one_fixed_helper_and_no_fallback(self):
        module = load(NATIVE)
        registry = {'desktops':{'zenbook':{'tailnetIp':'100.121.160.100','sshAlias':'client','hostKeyAlias':'client',
                                        'terminalLauncher':'/home/tom/.local/bin/domicile-terminal-open'}}}
        cwd = "/home/tom/a ' ; $(touch BAD)"
        argv = module.command(registry,'zenbook',cwd)
        self.assertEqual(shlex.split(argv[-1]), ['/home/tom/.local/bin/domicile-terminal-open','zenbook','--cwd',cwd])
        for item in ('-oStrictHostKeyChecking=yes','-oHostName=100.121.160.100','-oHostKeyAlias=client',
                     '-oForwardAgent=no','-oClearAllForwardings=yes','-oControlPath=none'):
            self.assertIn(item, argv)
        for key,value in (('tailnetIp','192.168.1.1'),('terminalLauncher','relative'),('sshAlias','-oProxyCommand=bad')):
            bad = json.loads(json.dumps(registry)); bad['desktops']['zenbook'][key]=value
            with self.assertRaises(ValueError):module.command(bad,'zenbook',cwd)
        with self.assertRaises(KeyError):module.command(registry,'other',cwd)


if __name__ == '__main__':
    unittest.main()
