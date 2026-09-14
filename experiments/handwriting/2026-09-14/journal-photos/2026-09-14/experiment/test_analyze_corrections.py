import unittest
import tempfile
from pathlib import Path
import json
from unittest.mock import patch
from contextlib import redirect_stdout
import io
from analyze_corrections import propose,consensus,evaluate,cost,main


def result(reading,difficulty='clear',found=True):
    return {'found':found,'reading':reading,'difficulty':difficulty,'alternatives':[],'evidence':'test'}

class CorrectionTests(unittest.TestCase):
    def test_exact_unique_replacement_and_unrelated_flags(self):
        base={'transcription':'call Alise tomorrow','uncertainties':[{'text':'Alise','difficulty':'uncertain'},{'text':'tomorrow','difficulty':'uncertain'}]}
        out,status=propose(base,'Alise',result('Alice'))
        self.assertEqual(status,'proposed');self.assertEqual(out['transcription'],'call Alice tomorrow')
        self.assertEqual(out['uncertainties'],[{'text':'tomorrow','difficulty':'uncertain'}])
        self.assertEqual(base['transcription'],'call Alise tomorrow')
        self.assertEqual(propose({'transcription':'x x'},'x',result('y'))[1],'old_span_not_unique')

    def test_consensus_clear_agreement_and_punctuation_disagreement(self):
        self.assertEqual(consensus(result('Herdr Kitten'),result(' herdr   kitten '))[1],'accepted_agreement')
        self.assertEqual(consensus(result('herdr-kitten'),result('herdr kitten'))[1],'review_disagreement')
        self.assertEqual(consensus(result('Alice'),result('Alice','uncertain'))[1],'review_not_both_clear')
        self.assertEqual(consensus(result('Alice'),None)[1],'pending_or_invalid')

    def test_expanded_filename_retires_contained_uncertainty(self):
        base={'transcription':'use workord mix today','uncertainties':[{'text':'workord','difficulty':'uncertain'},{'text':'today','difficulty':'uncertain'}]}
        out,_=propose(base,'workord mix',result('workerd.nix'))
        self.assertEqual(out['transcription'],'use workerd.nix today')
        self.assertEqual(out['uncertainties'],[{'text':'today','difficulty':'uncertain'}])
        out,_=propose(base,'workord mix',result('workerd.nix','uncertain'))
        self.assertEqual(out['uncertainties'][0]['text'],'workerd.nix')

    def test_known_improvement_and_regression(self):
        ref={'transcription':'call Alice tomorrow'};bad={'transcription':'call Alise tomorrow','uncertainties':[]}
        good,_=propose(bad,'Alise',result('Alice'))
        a=evaluate(ref,bad,good,'Alise');self.assertEqual(a['outcome'],'improved');self.assertEqual(a['known_word_delta'],-1)
        a=evaluate(ref,good,bad,'Alice');self.assertEqual(a['outcome'],'regressed');self.assertEqual(a['known_word_delta'],1)

    def test_unknown_reference_not_counted_as_correct(self):
        ref={'transcription':'call [unclear: Alice | Alise] tomorrow'}
        base={'transcription':'call Alise tomorrow','uncertainties':[]}
        candidate,_=propose(base,'Alise',result('Alice'))
        a=evaluate(ref,base,candidate,'Alise')
        self.assertEqual(a['outcome'],'unknown_reference_unscorable')
        self.assertEqual(a['known_word_delta'],0);self.assertEqual(a['full_word_delta'],-1)

    def test_cost_requires_complete_timing_coverage(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths=[Path(tmp)/f'{n}-parsed.json' for n in range(3)]
            for n,p in enumerate(paths[:2]):
                Path(str(p).replace('-parsed','-metadata')).write_text(json.dumps({'elapsed_seconds':n+1,'usage':{'total_tokens':10}}))
            self.assertIsNone(cost(paths)['elapsed_seconds'])
            self.assertEqual(cost(paths)['available_elapsed_seconds'],3)
            Path(str(paths[2]).replace('-parsed','-metadata')).write_text(json.dumps({'elapsed_seconds':3}))
            self.assertEqual(cost(paths)['elapsed_seconds'],6)

    def test_partial_results_generate_baseline_copies_without_fake_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for n in range(1,18):
                for folder,obj in [('runs/baseline/off',{'transcription':'call Alise tomorrow','uncertainties':[]}),('codex-reviewed',{'transcription':'call Alice tomorrow'})]:
                    d=root/folder;d.mkdir(parents=True,exist_ok=True)
                    name=f'capture-{n:02}'+('-parsed.json' if 'baseline' in folder else '.json')
                    (d/name).write_text(json.dumps(obj))
            (root/'correction').mkdir()
            (root/'correction/tasks-validated.json').write_text(json.dumps({'tasks':[{'capture':n,'text':'Alise','baseline':f'runs/baseline/off/capture-{n:02}-parsed.json'} for n in (1,9)]}))
            d=root/'runs/correction/off-crop';d.mkdir(parents=True)
            (d/'capture-01-parsed.json').write_text(json.dumps(result('Alice')))
            with patch('sys.argv',['analyze_corrections.py','--root',tmp]),redirect_stdout(io.StringIO()):main()
            out=root/'runs/correction';report=json.loads((out/'correction-summary.json').read_text())
            self.assertEqual(report['expected_cells'],8);self.assertEqual(report['available_cells'],1);self.assertFalse(report['complete'])
            self.assertEqual(report['summaries']['off-crop']['all']['all_available_results']['outcomes'],{'improved':1})
            self.assertEqual(report['summaries']['consensus']['all']['all_available_results']['evaluated_cells'],0)
            candidate=json.loads((out/'candidates/consensus/capture-09-parsed.json').read_text())
            self.assertEqual(candidate['transcription'],'call Alise tomorrow')
            meta=json.loads((out/'candidates/consensus/capture-09-metadata.json').read_text())
            self.assertFalse(meta['complete'])
            self.assertTrue((out/'candidates/off-crop-clear-only/capture-17-parsed.json').exists())

if __name__=='__main__':unittest.main()
