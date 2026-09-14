"""Offline checks of experiment isolation and retry evidence; no inference calls."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from benchmark import archive_incomplete as archive_baseline, completed_cell, record_failure
from correct import archive_incomplete, parse, validate_tasks
from correction_tasks import select
from summarize_runtime import summarize


class ExperimentGuards(unittest.TestCase):
    def test_baseline_retry_failure_and_resume_identity(self):
        with tempfile.TemporaryDirectory() as d:
            prefix=Path(d)/'capture-01';mp=Path(str(prefix)+'-metadata.json')
            expected={'settings':{'temperature':0},'system':'fixed','user':'fixed',
                      'image_sha256':'image-a','encoding':'image/png'}
            Path(str(prefix)+'-request.json').write_text(json.dumps(expected))
            Path(str(prefix)+'-response.json').write_text('{}')
            Path(str(prefix)+'-parsed.json').write_text('{"old":"parsed"}')
            mp.write_text(json.dumps({'complete':True,'parsed':True}))
            self.assertTrue(completed_cell(prefix,expected))
            with self.assertRaises(ValueError):completed_cell(prefix,{**expected,'image_sha256':'changed'})
            meta={'start_monotonic_ns':100,'complete':False}
            with patch('benchmark.time.monotonic_ns',return_value=200):
                record_failure(mp,meta,TimeoutError('test timeout'),'request')
            failure=json.loads(mp.read_text())
            self.assertEqual(failure['end_monotonic_ns'],200)
            self.assertEqual(failure['failure_stage'],'request')
            self.assertEqual(failure['elapsed_seconds'],1e-7)
            self.assertFalse(completed_cell(prefix,expected))
            archive_baseline(prefix)
            self.assertFalse(Path(str(prefix)+'-parsed.json').exists())
            self.assertEqual(len(list((Path(d)/'attempts').glob('*/*'))),4)

    def test_correction_schema_and_absent_target(self):
        valid={'found':True,'reading':'Huion','difficulty':'clear','alternatives':[], 'evidence':'Visible H-u-i-o-n'}
        self.assertEqual(parse(json.dumps(valid)),valid)
        absent={**valid,'found':False,'reading':None,'difficulty':'unreadable'}
        self.assertEqual(parse(json.dumps(absent)),absent)
        for malformed in [{**valid,'alternatives':[12]}, {**valid,'alternatives':['a']*4},
                          {**valid,'found':False},{**valid,'reading':None},
                          {k:v for k,v in valid.items() if k!='evidence'}]:
            with self.assertRaises(ValueError):parse(json.dumps(malformed))

    def test_frozen_lexicon_and_unique_visually_checked_targets(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'correction').mkdir()
            path=root/'correction/development-vocabulary.json'
            path.write_text(json.dumps({'development_captures':list(range(1,9)), 'terms':[{'term':'Huion','captures':[2]}]}))
            task={'capture':9,'location_check':'visually_verified','partition':'heldout','hints':[{'term':'Huion','captures':[2]}]}
            policy=root/'correction/selection-policy-v4.json';policy.write_text('{"version":4}')
            doc={'vocabulary_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'tasks':[task],
                 'selection_policy':policy.name,'selection_policy_sha256':hashlib.sha256(policy.read_bytes()).hexdigest()}
            self.assertEqual(validate_tasks(doc,root),[task])
            bad=copy.deepcopy(doc);bad['tasks'][0]['hints'][0]['captures']=[9]
            with self.assertRaises(ValueError):validate_tasks(bad,root)
            bad=copy.deepcopy(doc);bad['tasks'][0]['hints'][0]['term']='heldout-secret'
            with self.assertRaises(ValueError):validate_tasks(bad,root)
            bad=copy.deepcopy(doc);bad['tasks']*=2
            with self.assertRaises(ValueError):validate_tasks(bad,root)
            bad=copy.deepcopy(doc);bad['tasks'][0]['location_check']='pending'
            with self.assertRaises(ValueError):validate_tasks(bad,root)
            bad=copy.deepcopy(doc);bad['vocabulary_sha256']='wrong'
            with self.assertRaises(ValueError):validate_tasks(bad,root)
            bad=copy.deepcopy(doc);bad['selection_policy_sha256']='wrong'
            with self.assertRaises(ValueError):validate_tasks(bad,root)

    def test_retry_preserves_all_prior_cell_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            prefix=Path(d)/'capture-01'
            for suffix in ['request.json','response.json','metadata.json','parsed.json','answer.txt']:
                Path(str(prefix)+'-'+suffix).write_text(suffix)
            other=Path(d)/'capture-02-response.json';other.write_text('untouched')
            archive_incomplete(prefix)
            self.assertFalse(list(Path(d).glob('capture-01-*')))
            files=list((Path(d)/'attempts').glob('capture-01-*/*'))
            self.assertEqual(len(files),5)
            self.assertEqual(other.read_text(),'untouched')
            self.assertTrue(all(f.read_text()==f.name.replace('capture-01-','') for f in files))

    def test_cancelled_hard_span_does_not_displace_live_uncertainty(self):
        answer={'transcription':'~~old~~ then Huyon','uncertainties':[
            {'text':'old','difficulty':'hard'}, {'text':'Huyon','difficulty':'uncertain'}]}
        self.assertEqual(select(answer,[{'term':'Huion','captures':[2]}])[0]['text'],'Huyon')

    def test_final_idle_filename_and_memory_window(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'off').mkdir()
            (p/'off/capture-01-metadata.json').write_text(json.dumps({'capture':1,'mode':'off','complete':True,'start_monotonic_ns':30,'end_monotonic_ns':50}))
            (p/'idle-first.json').write_text(json.dumps({'start_ns':10,'end_ns':20}))
            (p/'final-idle-last.json').write_text(json.dumps({'start_ns':60,'end_ns':70}))
            samples=[{'received_monotonic_ns':t,'kfd_memory':{'system_used_bytes':x}} for t,x in [(10,100),(20,100),(40,150),(60,110),(70,110)]]
            (p/'memory-test.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in samples)+'{unfinished')
            s=summarize(p)
            self.assertEqual(s['memory_scan']['final_idle'][0]['source'],'final-idle-last.json')
            self.assertEqual(s['memory_scan']['final_idle'][0]['stats']['metrics']['kfd_system']['mean']['bytes'],110)
            self.assertEqual(s['requests'][0]['idle_to_peak']['kfd_system']['peak_minus_idle_mean']['bytes'],50)
            self.assertEqual(s['memory_scan']['invalid_json_lines'],1)


if __name__=='__main__':unittest.main()
