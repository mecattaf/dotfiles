import importlib.util, unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('p',Path(__file__).parents[2]/'pkgs/mykonos-wake/playback.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class Tests(unittest.TestCase):
 def test_unknown_fails_closed_and_cue_exempt(self):
  s=p.PlaybackState();self.assertEqual(s.reason(),'playback-monitor-unavailable')
  s.update([{'id':1,'info':{'state':'running','props':{'media.class':'Stream/Output/Audio','node.name':'mykonos-listening-cue'}}}]);self.assertIsNone(s.reason())
 def test_browser_stream_update_inhibits(self):
  s=p.PlaybackState();s.update([{'id':1,'info':{'state':'idle','props':{'media.class':'Stream/Output/Audio','node.name':'Chromium'}}}]);self.assertIsNone(s.reason())
  s.update([{'id':1,'info':{'state':'running'}}]);self.assertEqual(s.reason(),'media-playback')
  s.update([{'id':1,'info':None}]);self.assertEqual(s.reason(),'media-playback')
  s.last_active-=1;self.assertIsNone(s.reason())
if __name__=='__main__':unittest.main()
