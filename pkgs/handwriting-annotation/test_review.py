import json
import tempfile
import unittest
import shutil
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image
from review import Store, digest, write, merge_queue, request_allowed, trusted_origins, snapshot, import_items

class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.image=self.root/'sample.png';Image.new('RGB',(100,80),'white').save(self.image)
        write(self.root/'tasks.json',{'assets':{'a':{'path':str(self.image),'sha256':digest(self.image),'size':[100,80],'kind':'full_photo'}},
            'tasks':[{'id':'one','raw':'rn','image':'a','full_image':'a','source_sha256':'source','page_key':'sample/page1'}]})
        self.store=Store(self.root)
    def tearDown(self):self.tmp.cleanup()
    def payload(self,**changes):
        return {'task_id':'one','op_id':'operation-1','revision':0,'action':'resolved','literal':'m','intended':'','note':'Joined strokes','tags':'rn, m',
                'reuse':True,'image':'a','box':[10,10,40,50],'example_text':'m',**changes}
    def test_persist_idempotence_and_conflicting_edit(self):
        saved=self.store.save(self.payload());self.assertEqual(saved['revision'],1)
        self.assertEqual(self.store.save(self.payload())['revision'],1)
        self.assertEqual(Store(self.root).latest()['one']['literal'],'m')
        with self.assertRaises(ValueError):self.store.save(self.payload(op_id='operation-2'))
        with self.assertRaises(ValueError):self.store.save(self.payload(literal='different'))
        self.assertEqual(len(self.store.export().splitlines()),1)
    def test_reopen_preserves_log_and_removes_example(self):
        self.store.save(self.payload())
        self.assertEqual(len(self.store.compile('rn','other/page')['examples']),1)
        self.store.save(self.payload(op_id='operation-2',revision=1,action='reopened',reuse=False))
        self.assertEqual(len(self.store.export().splitlines()),2)
        self.assertEqual(self.store.compile('rn','other/page')['examples'],[])
    def test_confirmed_only_and_no_same_page_leakage(self):
        self.assertEqual(self.store.compile('rn','other/page')['examples'],[])
        self.store.save(self.payload())
        self.assertEqual(self.store.compile('rn','sample/page1')['examples'],[])
        packet=self.store.compile('rn','other/page')
        self.assertEqual(packet['examples'][0]['literal'],'m')
        self.assertTrue(packet['examples'][0]['image_url'].startswith('data:image/png;base64,'))
    def test_crop_and_label_required_for_visual_reuse(self):
        for changes in ({'box':None},{'box':[-1,0,20,20]},{'box':[1,1,101,20]},{'example_text':''},{'image':'other'},{'literal':''}):
            with self.assertRaises((ValueError,KeyError)):self.store.save(self.payload(**changes))
        self.assertEqual(self.store.events(),[])
    def test_correction_without_example_and_intended_separate(self):
        self.store.save(self.payload(literal='Huyon',intended='Huion',reuse=False,box=None,example_text=''))
        self.assertEqual(self.store.latest()['one']['literal'],'Huyon')
        self.assertEqual(self.store.compile('Huion','other/page')['examples'],[])
    def test_changed_source_refused(self):
        self.image.write_bytes(b'changed')
        with self.assertRaises(ValueError):self.store.asset('a')
    def test_source_transcription_hash_checked_before_confirmation(self):
        source=self.root/'transcription.json';source.write_text('{"transcription":"rn"}')
        data=json.loads((self.root/'tasks.json').read_text());data['tasks'][0].update(source=str(source),source_sha256=digest(source))
        write(self.root/'tasks.json',data);source.write_text('changed')
        with self.assertRaises(ValueError):self.store.save(self.payload())
        self.assertEqual(self.store.events(),[])
    def test_append_and_metadata_enrichment_keep_events_and_refresh_live_store(self):
        self.store.save(self.payload())
        current=json.loads((self.root/'tasks.json').read_text());first=current['tasks'][0]
        second={**first,'id':'two','raw':'new','page_key':'sample/page2'}
        data={'collection':'sample','assets':current['assets'],'tasks':[{**first,'context':{'previous':'before','current':'rn','next':'after'}},second]}
        merge_queue(self.root,data);merge_queue(self.root,data)
        queue=self.store.queue()['tasks']
        self.assertEqual(len(queue),2);self.assertEqual(queue[0]['review']['literal'],'m')
        self.assertEqual(queue[0]['context']['previous'],'before');self.assertEqual(len(self.store.events()),1)
        self.assertTrue(self.store.asset('a').is_file())
        with self.assertRaises(ValueError):merge_queue(self.root,{**data,'tasks':[{**first,'raw':'changed'}]})
        self.assertEqual(len(self.store.queue()['tasks']),2)
    def test_concurrent_stale_edits_have_exactly_one_winner(self):
        def attempt(n):
            try:return self.store.save(self.payload(op_id=f'concurrent-{n}'))
            except ValueError:return None
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(attempt,[1,2]))
        self.assertEqual(sum(r is not None for r in results),1);self.assertEqual(len(self.store.events()),1)
    def test_import_metadata_cannot_confirm_a_model_label(self):
        current=json.loads((self.root/'tasks.json').read_text());task=current['tasks'][0]
        merge_queue(self.root,{'assets':current['assets'],'tasks':[{**task,'review':{'action':'resolved'},'actor':'writer','literal':'invented','reuse':True}]})
        self.assertIsNone(self.store.queue()['tasks'][0]['review']);self.assertEqual(self.store.compile('rn','other/page')['examples'],[])
    def test_same_page_and_origin_guards(self):
        with self.assertRaises(ValueError):self.store.compile('rn','')
        origins=['https://handwriting.internal']
        self.assertTrue(request_allowed('handwriting.internal','https://handwriting.internal',8766,origins))
        self.assertTrue(request_allowed('127.0.0.1:8766','http://127.0.0.1:8766',8766,origins))
        self.assertFalse(request_allowed('evil.example',None,8766,origins))
        self.assertFalse(request_allowed('handwriting.internal','https://evil.example',8766,origins))
        self.assertFalse(request_allowed('handwriting.internal','null',8766,origins))
        with self.assertRaises(ValueError):trusted_origins(['https://handwriting.internal/path'])
    def test_snapshot_survives_original_change_and_state_move(self):
        relative,sha=snapshot(self.root,self.image)
        self.image.write_bytes(b'changed original')
        self.assertEqual(digest(self.root/relative),sha)
    def test_absence_is_distinct_from_unreadable_and_never_an_example(self):
        saved=self.store.save(self.payload(action='absent',literal='',reuse=False,box=None,example_text=''))
        self.assertEqual(saved['action'],'absent');self.assertEqual(saved['literal'],'')
        self.assertEqual(self.store.compile('rn','other/page')['examples'],[])
        with self.assertRaises(ValueError):self.store.save(self.payload(op_id='absence-bad',revision=saved['revision'],action='absent',literal='word',reuse=False))
        with self.assertRaises(ValueError):self.store.save(self.payload(op_id='absence-bad2',revision=saved['revision'],action='absent',literal='',reuse=True))
    def test_huion_page_and_doubt_import_keep_capture_provenance(self):
        collection=self.root/'huion-capture';collection.mkdir()
        source=collection/'parsed.json';write(source,{'transcription':'first line\nsecond line'})
        write(collection/'input-manifest.json',{'captures':[{'capture_order':1,'page':1}]})
        common={'capture':1,'source':str(source),'source_sha256':digest(source),'image_path':str(self.image),
                'image_sha256':digest(self.image),'capture_id':'capture-a','attempt_id':'attempt-a','family_id':'family-a',
                'capture_completeness':'unknown','transcription':'first line\nsecond line'}
        items=collection/'items.json';document={'collection':str(collection),'items':[
            {**common,'id':'page-a','origin':'page_review','raw':'first line\nsecond line'},
            {**common,'id':'doubt-a','origin':'qwen_uncertainty','raw':'second','parent_page_task_id':'page-a',
             'flags':[{'text':'second','difficulty':'uncertain','reason':'joined letters','alternatives':['seconds']}]}]}
        write(items,document);import_items(self.root,items);import_items(self.root,items)
        queue=self.store.queue()['tasks'];page=next(t for t in queue if t.get('origin')=='page_review')
        doubt=next(t for t in queue if t.get('origin')=='qwen_uncertainty')
        self.assertEqual(len(queue),3);self.assertIsNone(page['review'])
        self.assertEqual(page['capture_completeness'],'unknown');self.assertEqual(page['attempt_id'],'attempt-a')
        self.assertEqual(doubt['parent_page_task_id'],page['id']);self.assertEqual(doubt['flags'][0]['reason'],'joined letters')
        document['items'][0]['capture_completeness']='complete';write(items,document)
        with self.assertRaises(ValueError):import_items(self.root,items)
        self.assertEqual(next(t for t in self.store.queue()['tasks'] if t['id']==page['id'])['capture_completeness'],'unknown')
    def test_whole_page_literal_supports_multiline_but_word_limits_remain(self):
        literal=('A full handwritten line.\n'*220).strip()
        with self.assertRaises(ValueError):self.store.save(self.payload(literal=literal,reuse=False))
        data=json.loads((self.root/'tasks.json').read_text());data['tasks'][0]['origin']='page_review'
        write(self.root/'tasks.json',data)
        saved=self.store.save(self.payload(literal=literal,reuse=False))
        self.assertEqual(saved['literal'],literal)
        with self.assertRaises(ValueError):self.store.save(self.payload(op_id='too-long-page',revision=1,literal='a'*65537,reuse=False))
    def model_decisions(self, revision=0):
        reference=self.root/'codex-reading.json';write(reference,{'transcription':'m'})
        item={'task_id':'one','revision':revision,'source_sha256':'source','image_sha256':digest(self.image),
              'action':'resolved','literal':'m','method':'Codex/Claude visual reconciliation',
              'evidence':[{'path':str(reference),'sha256':digest(reference),'reader':'codex-reviewed','location':'line1'}]}
        decisions=self.root/'model-decisions.json';write(decisions,{'items':[item]});return decisions
    def test_model_resolution_keeps_provenance_and_is_not_a_writer_example(self):
        decisions=self.model_decisions();result=self.store.import_model_review(decisions)
        self.assertEqual((result['saved'],result['rejected']),(1,0))
        self.assertEqual(self.store.import_model_review(decisions)['saved'],1)
        self.assertEqual(len(self.store.events()),1)
        review=self.store.latest()['one'];self.assertEqual(review['actor'],'model_review')
        self.assertEqual(self.store.compile('rn','other/page')['examples'],[])
        with tempfile.TemporaryDirectory() as d:
            output=Path(d)/'backup';self.store.backup(output)
            for evidence in review['resolution_evidence']:
                self.assertEqual(digest(output/evidence['snapshot']),evidence['sha256'])
        self.store.save(self.payload(op_id='writer-overrides',revision=1,literal='rn',reuse=False))
        self.assertEqual(self.store.latest()['one']['actor'],'writer')
        self.assertEqual(len(self.store.events()),2)
    def test_model_resolution_cannot_overwrite_writer_or_changed_reference(self):
        self.store.save(self.payload())
        result=self.store.import_model_review(self.model_decisions(revision=1))
        self.assertEqual(result['rejected'],1);self.assertEqual(len(self.store.events()),1)
        decisions=self.model_decisions();(self.root/'codex-reading.json').write_text('changed')
        self.assertEqual(self.store.import_model_review(decisions)['rejected'],1)
        self.assertEqual(self.store.latest()['one']['actor'],'writer')
    def test_versioned_snapshot_is_consistent_restorable_and_never_overwrites(self):
        self.store.save(self.payload())
        with tempfile.TemporaryDirectory() as d:
            output=Path(d)/'backup';manifest=self.store.backup(output)
            self.assertEqual(manifest['status'],'complete');self.assertEqual(manifest['events'],1)
            self.assertEqual(manifest['last_revision'],1)
            for file,sha in manifest['files_sha256'].items():self.assertEqual(digest(output/file),sha)
            with sqlite3.connect(output/'resolutions.sqlite3') as db:
                rows=db.execute('SELECT seq,body FROM events ORDER BY seq').fetchall()
            exported=[json.loads(line) for line in (output/'events.jsonl').read_text().splitlines()]
            self.assertEqual(exported,[{**json.loads(body),'revision':seq} for seq,body in rows])
            self.store.save(self.payload(op_id='after-backup',revision=1,action='reopened',reuse=False))
            restored=Path(d)/'restored';shutil.copytree(output,restored);store=Store(restored)
            self.image.unlink()
            self.assertEqual(store.latest()['one']['action'],'resolved')
            self.assertEqual(len(store.compile('rn','other/page')['examples']),1)
            with self.assertRaises(FileExistsError):self.store.backup(output)
            self.assertEqual(json.loads((output/'manifest.json').read_text())['events'],1)

if __name__=='__main__':unittest.main()
