import unittest
from correction_tasks import select

LEX=[{'term':'workerd.nix','captures':[6]}, {'term':'worker','captures':[8]}, {'term':'herdr-kitten','captures':[2]}]

def answer(text,span,difficulty='uncertain'):
    return {'transcription':text,'uncertainties':[{'text':span,'difficulty':difficulty,'alternatives':[]}]}

class SelectionTests(unittest.TestCase):
    def test_split_identifier_replaces_both_ocr_words(self):
        task=select(answer('rawa: workord mix + cfs','workord'),LEX)[0]
        self.assertEqual(task['text'],'workord mix')
        self.assertEqual(task['span_expansion']['candidate'],'workerd.nix')

    def test_expansion_cannot_cross_line(self):
        task=select(answer('workord\nmix','workord'),LEX)[0]
        self.assertEqual(task['text'],'workord')

    def test_cancelled_text_does_not_consume_budget(self):
        self.assertEqual(select(answer('~~mystery~~ actual text','mystery','hard'),LEX),[])

    def test_known_ordinary_doubt_skipped_but_hard_not_skipped(self):
        self.assertEqual(select(answer('worker node','worker'),LEX),[])
        self.assertEqual(select(answer('worker node','worker','hard'),LEX)[0]['text'],'worker')

    def test_unrelated_next_word_not_consumed(self):
        self.assertEqual(select(answer('workord and later','workord'),LEX)[0]['text'],'workord')

if __name__=='__main__':unittest.main()
