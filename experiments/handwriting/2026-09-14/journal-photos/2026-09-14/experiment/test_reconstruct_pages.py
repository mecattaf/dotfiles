import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from reconstruct_pages import JoinRefused, heading_join, numbered_join, reconstruct, reference_pages, suffix_join


class ReconstructionTests(unittest.TestCase):
    def test_numbered_overlap_selects_later_own_text_and_audits_all_chars(self):
        left = '36. Earlier item\n37 * Shared laptop idea\nold cropped tail'
        right = '36. cropped previous fragment\n37 x Shared laptop idea\nnew complete tail\n38. Next item'
        objects = {7: {'transcription':left, 'uncertainties':[{'text':'old cropped tail','difficulty':'hard'}]},
                   8: {'transcription':right, 'uncertainties':[{'text':'new complete tail','difficulty':'hard'}]}}
        result = reconstruct(6, objects)
        self.assertEqual(result['transcription'], '36. Earlier item\n37 x Shared laptop idea\nnew complete tail\n38. Next item')
        self.assertEqual([x['text'] for x in result['uncertainties']], ['new complete tail'])
        self.assertEqual([x['status'] for x in result['uncertainty_selection_audit']], ['discarded','retained'])
        for capture in (7,8):
            self.assertEqual(''.join(x['text'] for x in result['spans'] if x['capture']==capture), objects[capture]['transcription'])

    def test_ambiguous_or_crossed_number_is_refused(self):
        with self.assertRaises(JoinRefused):
            numbered_join('36. prior\n~~37~~ old words', '37. old words\n38. next', 37)
        with self.assertRaises(JoinRefused):
            numbered_join('36. prior\n37. shared old words', '37. shared old words\n37. repeated old words\n38. next', 37)

    def test_bracket_join_does_not_repair_heading_words(self):
        result = reconstruct(4, {4:{'transcription':'earlier body\n[P91 wrong surname]'},
                                 5:{'transcription':'[P21 another wrong surname]\n1 * own item'}})
        self.assertEqual(result['transcription'], 'earlier body\n[P21 another wrong surname]\n1 * own item')
        with self.assertRaises(JoinRefused):
            heading_join('body\n[P21 shared]\nunexplained last words', '[P21 shared]', 'bracket')

    def test_suffix_overlap_tolerates_wraps_and_spelling_not_content_injection(self):
        shared = 'Keyboard charger Imzone receiver Inzone charger USB photo tool seven appliances. With laptop that is reduced to the Thunderbolt dock and requires absolutely no setup crucially.'
        left = 'earlier first paragraph\n'+shared
        right = 'cropped leading sliver\n'+shared.replace('Imzone','Inzone').replace('With laptop', 'With\nlaptop')+'\nnew paragraph emitted by right'
        result = reconstruct(7, {9:{'transcription':left},10:{'transcription':right}})
        self.assertEqual(result['transcription'], left+'\nnew paragraph emitted by right')
        self.assertIn('Imzone',result['transcription'])
        self.assertEqual(result['join']['strategy'],'left_capture_plus_unique_common_suffix')

    def test_ambiguous_common_anchor_is_refused(self):
        shared='one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive'
        with self.assertRaises(JoinRefused):
            suffix_join(shared,shared+'\n'+shared+'\nnew paragraph')

    def test_missing_goals_heading_is_refused(self):
        with self.assertRaises(JoinRefused):
            heading_join('body only','The goals I want to achieve:\nAn own-output goal','goals')
        result = reconstruct(11,{15:{'transcription':'body\nThe goals I want to achieve:'},
                                 16:{'transcription':'The goals I want to achieve:\nAn own-output goal'}})
        self.assertEqual(result['transcription'].count('The goals'),1)

    def test_reference_assembly_uses_frozen_unknowns_not_final_context_names(self):
        path = Path(__file__).resolve().parents[1]/'codex-reviewed'
        refs = reference_pages({n:json.loads((path/f'capture-{n:02}.json').read_text()) for n in range(1,18)})
        self.assertIn('[unclear: nick-icong | nick-iconq]',refs[6]['transcription'])
        self.assertIn('[unclear: Lacie | Laie]',refs[7]['transcription'])
        self.assertIn('[unclear: Emaki | Enaki]',refs[7]['transcription'])
        self.assertEqual(refs[8]['transcription'].count('(13)'),1)

    def test_stale_success_is_removed_when_completion_metadata_fails(self):
        script=Path(__file__).with_name('reconstruct_pages.py')
        actual_refs=script.resolve().parents[1]/'codex-reviewed'
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            shutil.copytree(actual_refs, root/'codex-reviewed')
            arm=root/'runs/baseline/off';arm.mkdir(parents=True)
            (arm/'capture-01-parsed.json').write_text(json.dumps({'transcription':'own emitted text','uncertainties':[]}))
            metadata=arm/'capture-01-metadata.json'
            metadata.write_text(json.dumps({'complete':True,'parsed':True,'finish_reason':'stop'}))
            command=[sys.executable,str(script),'--root',str(root),'--modes','off']
            subprocess.run(command,check=True,capture_output=True)
            output=root/'runs/baseline/reconstructed/off'
            self.assertTrue((output/'page1-alignment.json').exists())
            metadata.write_text(json.dumps({'complete':False,'parsed':True,'finish_reason':'length'}))
            subprocess.run(command,check=True,capture_output=True)
            self.assertFalse((output/'page1-alignment.json').exists())
            self.assertIn('Reconstruction unavailable:',(output/'page1.md').read_text())
            self.assertEqual(json.loads((output/'page1.json').read_text())['status'],'incomplete_inputs')


if __name__=='__main__':
    unittest.main()
