import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
loader=importlib.machinery.SourceFileLoader('switcher',str(ROOT/'home/dot_local/bin/sway-workspace-switcher'))
spec=importlib.util.spec_from_loader(loader.name,loader)
s=importlib.util.module_from_spec(spec);loader.exec_module(s)
b=s.bridge()

def ws(n,output='eDP-1',**kw):
    return dict(num=n,name=str(n),output=output,**kw)
def node(cid=20,slot=1,title='strix: top-work',marks=()):
    return dict(id=cid,pid=500+cid,type='con',app_id='herdr-projector',name=title,marks=[f'herdr-slot-{slot}',*marks],nodes=[])
def tree(*pairs):
    return {'type':'root','nodes':[dict(type='workspace',num=num,name='__i3_scratch' if num==-1 else str(num),nodes=nodes) for num,nodes in pairs]}
SNAP={'workspaces':[{'label':'top-work','workspace_id':'wA','agent_status':'working'}],'agents':[]}

class Switcher(unittest.TestCase):
    def test_actual_output_overrides_configured_number_assumptions(self):
        rows=s.make_rows(b,tree(),[ws(10,focused=True),ws(4,'eDP-2')],{},'eDP-1')
        self.assertIn(10,[r['slot'] for r in rows]);self.assertNotIn(4,[r['slot'] for r in rows])
        self.assertIn('● 10',next(r['label'] for r in rows if r['slot']==10))
    def test_herdr_status_resolves_live_projector_title(self):
        rows=s.make_rows(b,tree((1,[node()])),[ws(1)],SNAP,'eDP-1')
        self.assertIn('working',rows[0]['label'])
    def test_status_follows_actual_workspace_10_not_old_slot_mark(self):
        rows=s.make_rows(b,tree((10,[node(slot=1)])),[ws(10)],SNAP,'eDP-1')
        self.assertIn('working',next(r['label'] for r in rows if r['slot']==10))
        self.assertNotIn('working',next(r['label'] for r in rows if r['slot']==1))
    def test_unknown_current_identity_is_not_global_focus(self):
        rows=s.make_rows(b,tree((1,[node(title='unrelated')])),[ws(1)],SNAP,'eDP-1')
        self.assertIn('unknown',rows[0]['label']);self.assertNotIn('working',rows[0]['label'])
    def test_assigned_status_explicit(self):
        rows=s.make_rows(b,tree((1,[node(title='other',marks=['herdr-workspace-wA'])])),[ws(1)],SNAP,'eDP-1')
        self.assertIn('assigned working',rows[0]['label'])
    def test_unavailable_status_explicit(self):
        rows=s.make_rows(b,tree((1,[node()])),[ws(1)],{},'eDP-1',True)
        self.assertIn('unavailable',rows[0]['label'])
    def test_ambiguous_numbers_not_selectable(self):
        rows=s.make_rows(b,tree(),[ws(1),ws(1,'eDP-2')],{},'eDP-1')
        self.assertNotIn(1,[r['slot'] for r in rows])
    def test_output_missing_does_not_fallback(self):
        with self.assertRaisesRegex(RuntimeError,'unavailable'):
            s.require_output('eDP-1',[{'name':'eDP-2','active':True}])
    def test_changed_output_refuses_before_any_mutation(self):
        with patch.object(s,'sway_query',side_effect=[[{'name':'eDP-1','active':True}],[ws(1,'eDP-2')]]),patch.object(b,'ipc') as ipc:
            with self.assertRaisesRegex(RuntimeError,'another output'):
                s.activate(b,{'slot':1,'name':'1','output':'eDP-1'})
            ipc.assert_not_called()
    def test_rename_refuses_before_any_mutation(self):
        with patch.object(s,'sway_query',side_effect=[[{'name':'eDP-1','active':True}],[dict(ws(1),name='1:new')]]),patch.object(b,'ipc') as ipc:
            with self.assertRaisesRegex(RuntimeError,'changed'):
                s.activate(b,{'slot':1,'name':'1','output':'eDP-1'})
            ipc.assert_not_called()
    def test_empty_slot_taken_refuses(self):
        with patch.object(s,'sway_query',side_effect=[[{'name':'eDP-1','active':True}],[ws(2)]]),patch.object(b,'ipc') as ipc:
            with self.assertRaisesRegex(RuntimeError,'changed'):
                s.activate(b,{'slot':2,'name':None,'output':'eDP-1'})
            ipc.assert_not_called()
    def test_existing_top_10_focus_does_not_move_any_workspace(self):
        with patch.object(s,'sway_query',side_effect=[[{'name':'eDP-1','active':True}],[ws(10)]]),patch.object(b,'ipc') as ipc,patch.object(b,'select_workspace') as select:
            s.activate(b,{'slot':10,'name':'10','output':'eDP-1'})
            ipc.assert_called_once_with('focus output "eDP-1"');select.assert_called_once_with(10,'10')
    def test_parked_process_identity_checked(self):
        row={'slot':1,'name':None,'output':'eDP-1','parked':{'id':20,'pid':12,'app_id':'herdr-projector'}}
        with patch.object(s,'sway_query',side_effect=[[{'name':'eDP-1','active':True}],[]]),patch.object(b,'tree',return_value=tree((-1,[node()]))),patch.object(b,'ipc') as ipc:
            with self.assertRaisesRegex(RuntimeError,'identity'):
                s.activate(b,row)
            ipc.assert_not_called()
    def test_own_socket_toggle_and_reopen(self):
        with tempfile.TemporaryDirectory() as td,patch.dict(os.environ,{'XDG_RUNTIME_DIR':td,'SWAYSOCK':'test-compositor'}):
            owner=s.Toggle();second=s.Toggle()
            try:
                self.assertTrue(owner.acquire_or_close());self.assertFalse(second.acquire_or_close())
                self.assertTrue(owner.closed.wait(1));self.assertTrue(owner.path.exists())
            finally:second.close();owner.close()
            self.assertFalse(owner.path.exists())
            third=s.Toggle()
            try:self.assertTrue(third.acquire_or_close())
            finally:third.close()
    def test_distinct_compositors_do_not_toggle_each_other(self):
        with tempfile.TemporaryDirectory() as td,patch.dict(os.environ,{'XDG_RUNTIME_DIR':td,'SWAYSOCK':'one'}):
            one=s.Toggle();self.assertTrue(one.acquire_or_close())
            with patch.dict(os.environ,{'SWAYSOCK':'two'}):two=s.Toggle()
            try:self.assertTrue(two.acquire_or_close());self.assertFalse(one.closed.is_set())
            finally:two.close();one.close()
    def test_palette_and_output_are_arguments_not_shell(self):
        with tempfile.TemporaryDirectory() as td,patch.dict(os.environ,{'XDG_CONFIG_HOME':td}):
            theme=Path(td)/'theme';theme.mkdir()
            theme.joinpath('desktop-shell.json').write_text((ROOT/'design/claude-primer/src/palettes.json').read_text())
            palettes=json.loads(theme.joinpath('desktop-shell.json').read_text())
            theme.joinpath('desktop-shell.json').write_text(json.dumps(palettes['claude-light']))
            cmd=s.fuzzel_command('eDP-1',9)
            self.assertIn('--output=eDP-1',cmd);self.assertIn('--background-color=FFFFFFff',cmd)
            self.assertIn('--only-match',cmd);self.assertIn('--config=/dev/null',cmd)

if __name__=='__main__':unittest.main()
