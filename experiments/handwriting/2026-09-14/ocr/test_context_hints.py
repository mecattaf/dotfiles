import json
from pathlib import Path
import tempfile
import unittest

from context_hints import build, instant, tokens, vocabulary


class ContextHintsTests(unittest.TestCase):
    def test_only_user_context_before_cutoff_and_confirmed_glossary(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            session = root/'session.jsonl'
            rows = []
            for role, timestamp, text in [
                ('user', '2026-09-10T10:00:00Z', 'Huion café ui db'),
                ('assistant', '2026-09-10T10:01:00Z', 'FabricatedLabel'),
                ('user', '2026-09-12T10:00:00Z', 'FutureCorrection'),
                ('user', '2026-09-10T10:02:00Z', '# AGENTS.md instructions\nInjectedLabel'),
                ('user', '2026-09-10T10:03:00Z', '```\nQuotedMachineGuess\n```'),
            ]:
                rows.append({'type':'response_item','timestamp':timestamp,'payload':{'type':'message','role':role,'content':[{'type':'input_text','text':text}]}})
            session.write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
            reviewed = root/'terms.json'
            reviewed.write_text(json.dumps([
                {'term':'UncheckedWord','status':'provisional'},
                {'term':'Élodie','status':'confirmed','kind':'writer_confirmed_word','source':'note-1','observed_at':'2026-09-10T10:00:00Z'},
            ]))
            index = vocabulary([session], [reviewed], instant('2026-09-11T00:00:00Z'))
            self.assertEqual(set(index), {'huion','café','ui','db','élodie'})

    def test_only_hard_spans_get_candidates_and_budget_is_per_page(self):
        cutoff = instant('2026-09-11T00:00:00Z')
        terms = {'huion':{'message:1':{'term':'Huion','source':'message:1','observed_at':'2026-09-10T00:00:00Z','kind':'user_message'}}}
        spans = [{'id':str(i),'page_id':page,'raw':'Huyon','alternatives':[], 'difficulty':difficulty} for i,(page,difficulty) in enumerate([
            ('p1','uncertain'),('p1','hard'),('p1','hard'),('p1','hard'),('p2','hard')])]
        result = build(spans, terms, cutoff)
        items = {item['span']['id']:item for item in result['items']}
        self.assertEqual(items['0']['action'], 'leave_first_pass')
        self.assertEqual(items['1']['candidates'][0]['term'], 'Huion')
        self.assertEqual(items['3']['action'], 'deferred_hard_span')
        self.assertEqual(items['4']['action'], 'prepare_local_visual_retry')
        self.assertTrue(all(item['span']['raw']=='Huyon' for item in result['items']))

    def test_no_candidate_stays_a_visual_retry(self):
        result = build([{'id':'1','page_id':'p1','raw':'???','difficulty':'unreadable'}], {}, instant('2026-09-11T00:00:00Z'))
        self.assertEqual(result['items'][0]['candidates'], [])
        self.assertEqual(result['items'][0]['action'], 'prepare_local_visual_retry')


if __name__ == '__main__':
    unittest.main()
