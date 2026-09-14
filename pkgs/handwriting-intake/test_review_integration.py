"""Real intake/review/export interfaces, with synthetic ink and no network calls."""
import json
from pathlib import Path
import tempfile
import unittest
from intake import Intake, write_json, hash_file
from test_intake import FakeTransport
from review import Store, import_items

class ReviewIntegrationTests(unittest.TestCase):
    def test_model_review_cannot_publish_but_writer_revision_can(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'capture.json'
            write_json(source,{'page':0,'max_x':100,'max_y':200,'max_press':8191,
                'strokes':[[{'x':10,'y':20,'press':1200,'pen_down':True},{'x':30,'y':40,'press':3000,'pen_down':True}]]})
            source.with_suffix('.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
            intake=Intake(root/'intake');receipt=intake.receive(source,settle_seconds=0)
            result=intake.run(receipt['capture_id'],allow_unknown=True,transport=FakeTransport())
            review_path=root/'review';import_items(review_path,result['review_packet']);import_items(review_path,result['review_packet'])
            review=Store(review_path);tasks=review.queue()['tasks'];self.assertEqual(len(tasks),2)
            page=next(t for t in tasks if t['origin']=='page_review');flag=next(t for t in tasks if t['origin']=='qwen_uncertainty')
            self.assertEqual(flag['parent_page_task_id'],page['id']);self.assertEqual(page['capture_completeness'],'unknown')
            decisions=root/'decisions.json';write_json(decisions,{'items':[{
                'task_id':page['id'],'revision':0,'action':'resolved','literal':'A model reading',
                'method':'Synthetic interface fixture','source_sha256':page['source_sha256'],
                'image_sha256':review.data['assets'][page['image']]['sha256'],
                'evidence':[{'path':page['source'],'sha256':hash_file(page['source']),'reader':'test-fixture'}]}]})
            self.assertEqual(review.import_model_review(decisions)['saved'],1)
            with self.assertRaisesRegex(ValueError,'writer-resolved'):
                intake.export(receipt['capture_id'],review_path,root/'exports')
            literal='A writer-corrected line\nQwen sample'
            review.save({'task_id':page['id'],'revision':1,'op_id':'writer-fixture-1','action':'resolved',
                         'literal':literal,'reuse':False,'image':page['image'],'box':None})
            exported=intake.export(receipt['capture_id'],review_path,root/'exports');target=Path(exported['path'])
            self.assertEqual((target/'literal.md').read_text(),literal+'\n')
            history=[json.loads(line) for line in (target/'correction-history.jsonl').read_text().splitlines()]
            self.assertEqual([event['actor'] for event in history],['model_review','writer'])
            self.assertIsNone(next(t for t in review.queue()['tasks'] if t['id']==flag['id'])['review'])
            self.assertTrue(intake.export(receipt['capture_id'],review_path,root/'exports')['duplicate'])
            self.assertEqual(intake.backup(root/'intake-backup')['status'],'complete')
            self.assertEqual(review.backup(root/'review-backup')['events'],2)

if __name__=='__main__':unittest.main()
