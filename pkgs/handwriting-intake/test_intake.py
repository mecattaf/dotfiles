from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from intake import Intake, MODEL, SETTINGS, SYSTEM, RECIPE_ID, encoded, hash_bytes, hash_file, read_json, write_json, render

ANSWER={'transcription':'A written line\nQwen sample','uncertainties':[{'text':'Qwen','alternatives':['Qwen'], 'difficulty':'uncertain','reason':'Joined letters'}],'cut_edges':'none'}


def response(answer=ANSWER,finish='stop'):
    return encoded({'choices':[{'finish_reason':finish,'message':{'content':json.dumps(answer)}}], 'usage':{'prompt_tokens':1200,'completion_tokens':50,'completion_tokens_details':{'reasoning_tokens':0}},'timings':{'cache_n':0}})


class FakeTransport:
    def __init__(self,raw=None,error=None):self.raw=response() if raw is None else raw;self.error=error;self.calls=[];self.health_calls=0
    def health(self):self.health_calls+=1;return {'model':MODEL,'vision':{'enabled':True},'in_flight':False}
    def complete(self,request):
        self.calls.append(request)
        if self.error:raise self.error
        return self.raw


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.state=self.root/'state';self.store=Intake(self.state)
        self.page={'page':0,'max_x':100.0,'max_y':200.0,'max_press':8191.0,'strokes':[[{'x':10,'y':20,'press':1200,'pen_down':True},{'x':30,'y':40,'press':3000,'pen_down':True}]]}
        self.source=self.root/'batch'/'page1-14-09.json';write_json(self.source,self.page)
        self.source.with_suffix('.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="900" height="1190"></svg>')
    def tearDown(self):self.temp.cleanup()
    def receive(self):return self.store.receive(self.source,settle_seconds=0)
    def process(self,**options):
        receipt=self.receive();transport=options.pop('transport',FakeTransport());result=self.store.run(receipt['capture_id'],allow_unknown=True,transport=transport,**options)
        return receipt,result,transport
    def annotate(self,receipt,result,actor='writer',action='resolved',literal='The writer reading'):
        review=self.root/'review-state';review.mkdir(exist_ok=True)
        packet=read_json(result['review_packet']);page=packet['items'][0]
        task={**page,'id':'page-task','full_image':'image','image':'image','page_key':'review/page1'}
        write_json(review/'tasks.json',{'tasks':[task],'assets':{'image':{'sha256':page['image_sha256']}}})
        event={'task_id':'page-task','actor':actor,'action':action,'literal':literal,'source_sha256':page['source_sha256'],'image_sha256':page['image_sha256'],'page_key':task['page_key'],'at':'2026-09-14T12:00:00Z'}
        with closing(sqlite3.connect(review/'resolutions.sqlite3')) as db, db:
            db.execute('CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY,task_id TEXT,body TEXT)')
            seq=db.execute('INSERT INTO events(task_id,body) VALUES(?,?)',('page-task',json.dumps(event))).lastrowid
        return review,seq
    def test_receive_idempotence_unknown_completeness_and_changed_version(self):
        first=self.receive();again=self.receive()
        self.assertEqual(first['capture_completeness'],'unknown');self.assertTrue(again['duplicate'])
        self.assertEqual(first['capture_id'],again['capture_id']);self.assertEqual(len(self.store.status()['captures']),1)
        self.page['strokes'][0][-1]['x']=31;write_json(self.source,self.page)
        changed=self.receive();self.assertNotEqual(changed['capture_id'],first['capture_id']);self.assertEqual(len(self.store.status()['captures']),2)
        preserved=self.state/first['sources']['json']['path'];self.assertEqual(read_json(preserved)['strokes'][0][-1]['x'],30)
    def test_incomplete_and_changing_files_do_not_become_captures(self):
        self.source.write_text('{incomplete');self.assertEqual(self.receive()['status'],'waiting_for_files')
        write_json(self.source,self.page);self.source.with_suffix('.svg').unlink();self.assertEqual(self.receive()['status'],'waiting_for_files')
        self.source.with_suffix('.svg').write_text('<svg/>')
        result=self.store.receive(self.source,between_reads=lambda:self.source.write_text('{changed'))
        self.assertEqual(result['status'],'waiting_for_files');self.assertEqual(self.store.status()['captures'],[])
    def test_recover_receipt_written_before_database_commit(self):
        first=self.receive();receipt_path=self.state/'receipts'/(first['capture_id']+'.json');original=receipt_path.read_bytes()
        with self.store.connect() as db:db.execute('DELETE FROM captures')
        recovered=self.receive();self.assertEqual(recovered['received_at'],first['received_at']);self.assertEqual(receipt_path.read_bytes(),original)
        self.assertEqual(len(self.store.status()['captures']),1)
    def test_unknown_requires_explicit_processing_and_source_tampering_is_detected(self):
        receipt=self.receive();transport=FakeTransport()
        with self.assertRaises(ValueError):self.store.run(receipt['capture_id'],transport=transport)
        self.assertEqual(transport.health_calls,0)
        receipt_path=self.state/'receipts'/(receipt['capture_id']+'.json');data=read_json(receipt_path);data['capture_completeness']='complete';write_json(receipt_path,data)
        with self.assertRaises(ValueError):self.store.run(receipt['capture_id'],allow_unknown=True,transport=transport)
        self.assertEqual(transport.health_calls,0)
    def test_one_page_off_request_and_separate_whole_page_review_gate(self):
        receipt,result,transport=self.process();self.assertEqual(result['status'],'review_required');self.assertEqual(len(transport.calls),1)
        request=transport.calls[0]
        for key,value in SETTINGS.items():self.assertEqual(request[key],value)
        self.assertEqual(request['messages'][0],{'role':'system','content':SYSTEM})
        self.assertEqual(len([p for p in request['messages'][1]['content'] if p['type']=='image_url']),1)
        packet=read_json(result['review_packet']);self.assertEqual([i['origin'] for i in packet['items']],['page_review','qwen_uncertainty'])
        self.assertEqual(packet['items'][0]['coverage_flags'],['capture_completeness_unknown']);self.assertEqual(packet['items'][0]['flags'],[])
        self.assertEqual(packet['items'][1]['parent_page_task_id'],packet['items'][0]['id'])
        self.assertEqual(packet['items'][1]['context']['previous'],'A written line')
        self.assertTrue(Path(packet['items'][0]['source']).is_relative_to(Path(packet['collection'])))
        duplicate=self.store.run(receipt['capture_id'],allow_unknown=True,transport=transport);self.assertTrue(duplicate['duplicate']);self.assertEqual(len(transport.calls),1)
        (self.state/receipt['sources']['json']['path']).write_text('tampered')
        with self.assertRaises(ValueError):self.store.run(receipt['capture_id'],allow_unknown=True,transport=transport)
    def test_failed_length_and_invalid_schema_keep_raw_and_need_explicit_retry(self):
        receipt,result,_=self.process(transport=FakeTransport(raw=response(finish='length')));self.assertEqual(result['status'],'failed')
        folder=self.state/'attempts'/result['attempt_id'];self.assertTrue((folder/'response.raw.json').exists());self.assertTrue((folder/'answer.txt').exists())
        self.assertFalse(read_json(folder/'metadata.json')['complete'])
        with self.assertRaises(ValueError):self.store.run(receipt['capture_id'],True,transport=FakeTransport())
        retried=self.store.run(receipt['capture_id'],True,retry=True,transport=FakeTransport(raw=response({'transcription':'missing fields'})))
        self.assertEqual(retried['status'],'failed');self.assertNotEqual(retried['attempt_id'],result['attempt_id']);self.assertEqual((folder/'response.raw.json').read_bytes(),response(finish='length'))
    def test_transport_failure_and_interruption_preserve_attempts(self):
        receipt,result,_=self.process(transport=FakeTransport(error=TimeoutError('test timeout')));self.assertEqual(result['status'],'failed')
        with self.store.connect() as db:db.execute("UPDATE attempts SET status='processing' WHERE id=?",(result['attempt_id'],))
        with self.assertRaises(ValueError):self.store.run(receipt['capture_id'],True,transport=FakeTransport())
        self.assertEqual(self.store.status()['attempts'][0]['status'],'interrupted')
        retried=self.store.run(receipt['capture_id'],True,retry=True,transport=FakeTransport());self.assertEqual(retried['status'],'review_required')
        self.assertEqual(len(self.store.status()['attempts']),2)
    def test_review_packet_failure_does_not_leave_complete_attempt(self):
        with patch.object(self.store,'review_packet',side_effect=ValueError('test import preparation error')):
            _,result,_=self.process()
        self.assertEqual(result['status'],'failed');self.assertFalse(read_json(self.state/'attempts'/result['attempt_id']/'metadata.json')['complete'])
    def test_export_requires_writer_and_keeps_revisions_and_history(self):
        receipt,result,_=self.process();review,_=self.annotate(receipt,result,actor='model_review')
        with self.assertRaises(ValueError):self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        review,revision=self.annotate(receipt,result);exported=self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        path=Path(exported['path']);self.assertEqual((path/'literal.md').read_text(),'The writer reading\n')
        self.assertEqual(read_json(path/'provenance.json')['capture_completeness'],'unknown')
        self.assertEqual(len((path/'correction-history.jsonl').read_text().splitlines()),2)
        self.assertTrue(self.store.export(receipt['capture_id'],review,self.root/'transcribed')['duplicate'])
        self.annotate(receipt,result,action='reopened')
        with self.assertRaises(ValueError):self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        self.annotate(receipt,result,literal='A revised writer reading');new=self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        self.assertNotEqual(new['path'],exported['path']);self.assertEqual((path/'literal.md').read_text(),'The writer reading\n')
    def test_export_recovers_complete_files_after_database_failure_and_refuses_edits(self):
        receipt,result,_=self.process();review,_=self.annotate(receipt,result)
        with patch.object(self.store,'register_export',side_effect=RuntimeError('simulated DB commit interruption')):
            with self.assertRaises(RuntimeError):self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        recovered=self.store.export(receipt['capture_id'],review,self.root/'transcribed');self.assertTrue(recovered['recovered'])
        (Path(recovered['path'])/'literal.md').write_text('manual edit')
        with self.assertRaises(ValueError):self.store.export(receipt['capture_id'],review,self.root/'transcribed')
    def test_backup_is_consistent_and_immutable(self):
        receipt,result,_=self.process();review,_=self.annotate(receipt,result);self.store.export(receipt['capture_id'],review,self.root/'transcribed')
        output=self.root/'backup';manifest=self.store.backup(output);self.assertEqual(manifest['status'],'complete')
        for path,sha in manifest['files_sha256'].items():self.assertEqual(hash_file(output/path),sha)
        with closing(sqlite3.connect(output/'intake.sqlite3')) as db:self.assertEqual(db.execute('SELECT count(*) FROM exports').fetchone()[0],1)
        self.assertTrue((output/'export-files'/'0'/'correction-history.jsonl').exists())
        with self.assertRaises(FileExistsError):self.store.backup(output)
    def test_renderer_has_no_photo_rotation_and_opaque_stride_aligned_output(self):
        from PIL import Image
        import io
        svg,png=render(self.page)
        self.assertIn(b'stroke-width="1.2"',svg);self.assertIn(b'round',svg)
        im=Image.open(io.BytesIO(png));self.assertEqual(im.size,(896,1184));self.assertEqual(im.mode,'RGB')


if __name__=='__main__':unittest.main()
