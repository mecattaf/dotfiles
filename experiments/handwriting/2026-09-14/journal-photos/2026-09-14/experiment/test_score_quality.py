import unittest
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
from unittest.mock import patch
from score_quality import normalized, align, score, main, load_completed_output

class QualityTests(unittest.TestCase):
    def test_formatting_and_source_notes(self):
        ref={'transcription':"I'm HERE: 144 000 tokens. ~~old~~ [Margin addition: New text] [crossed out: illegible]"}
        out={'transcription':"I’m here, 144,000 tokens! ~~older~~ New\ntext",'uncertainties':[]}
        result=score(ref,out)
        self.assertEqual(result['metrics']['full_disagreement_operations'],0)
        self.assertEqual(result['reference_tokens'],['im','here','144000','tokens','new','text'])

    def test_substitution_deletion_and_insertion(self):
        result=score({'transcription':'the red door opens slowly at dawn'}, {'transcription':'the blue door slowly at dawn today', 'uncertainties':[{'text':'blue','difficulty':'hard'}]})
        self.assertEqual(result['metrics']['full_disagreement_operations'],3)
        self.assertEqual(result['metrics']['known_operations'],{'match':5,'substitute':1,'delete':1,'insert':1})
        self.assertEqual(result['metrics']['known_differences_directly_flagged'],1)
        deletion=next(x for x in result['operations'] if x['operation']=='delete')
        self.assertIsNone(deletion['output_index'])
        self.assertFalse(deletion['directly_flagged'])

    def test_unclear_exclusion_and_known_error(self):
        result=score({'transcription':'call [unclear: Alice | Alise] tomorrow please'}, {'transcription':'call Alicia today please','uncertainties':[]})
        self.assertEqual(result['metrics']['full_disagreement_operations'],2)
        self.assertEqual(result['metrics']['known_disagreement_operations'],1)
        self.assertEqual(result['metrics']['known_reference_words'],3)
        self.assertTrue(result['differences'][0]['excluded_from_known_word_measure'])

    def test_shifted_date_is_separate(self):
        result=score({'transcription':'06/09/26\nKeep notes','visible_date':'06/09/26'}, {'transcription':'Keep 06.09.26 notes','uncertainties':[]})
        self.assertEqual(result['metrics']['full_disagreement_operations'],0)
        self.assertTrue(result['metrics']['dates_match'])
        wrong=score({'transcription':'06/09/26\nKeep notes'}, {'transcription':'Keep notes 09/06/26','uncertainties':[]})
        self.assertFalse(wrong['metrics']['dates_match'])
        self.assertEqual(wrong['metrics']['full_disagreement_operations'],0)

    def test_repeated_uncertainty_does_not_flag_every_occurrence(self):
        result=score({'transcription':'red then blue'}, {'transcription':'blue then blue','uncertainties':[{'text':'blue','difficulty':'uncertain'}]})
        self.assertEqual(result['metrics']['known_differences_directly_flagged'],0)
        self.assertEqual(result['metrics']['uncertainty_location_counts'],{'ambiguous_repetition':1})

    def test_deletion_neighbor_is_separate(self):
        result=score({'transcription':'the red door'}, {'transcription':'the door','uncertainties':[{'text':'door','difficulty':'hard'}]})
        self.assertEqual(result['metrics']['known_differences_directly_flagged'],0)
        self.assertEqual(result['metrics']['known_deletions_with_flagged_neighbor'],1)

    def test_nested_brackets_and_cropped_editorial_placeholder(self):
        result=normalized('[P.21 Thomas [unclear: Bench | Benh]] [Bottom line cropped: omitted text]')
        self.assertEqual(result['tokens'],['p','21','thomas','bench'])
        self.assertEqual(result['uncertain'],[False,False,False,True])

    def test_custom_modes_and_capture_subset_expected_cells(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'codex-reviewed').mkdir()
            for capture in (1,9):
                (root/'codex-reviewed'/f'capture-{capture:02}.json').write_text(json.dumps({'transcription':'clear text'}))
            for mode,capture in [('crop-low',1),('crop-low',9),('lookup_v2',1)]:
                folder=root/'runs'/'baseline'/mode
                folder.mkdir(parents=True,exist_ok=True)
                (folder/f'capture-{capture:02}-parsed.json').write_text(json.dumps({'transcription':'clear text','uncertainties':[]}))
            with patch('sys.argv',['score_quality.py','--root',tmp,'--modes','crop-low,lookup_v2','--captures','1,9']), redirect_stdout(io.StringIO()):
                main()
            out=root/'runs'/'baseline'/'quality'
            report=json.loads((out/'quality-summary.json').read_text())
            self.assertEqual(report['expected_cells'],4)
            self.assertEqual(report['scored_cells'],3)
            self.assertFalse(report['complete'])
            self.assertEqual(report['selected_modes'],['crop-low','lookup_v2'])
            self.assertEqual(report['selected_captures'],[1,9])
            self.assertEqual(report['summaries']['crop-low']['heldout']['captures'],1)
            self.assertEqual(report['missing_cells'],[{'mode':'lookup_v2','capture':9,'reason':'missing_parsed_output'}])
            self.assertIn('3/4', (out/'QUALITY.md').read_text())

    def test_present_failed_or_malformed_metadata_rejects_stale_parsed_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'capture-01-parsed.json'
            path.write_text(json.dumps({'transcription':'stale old success','uncertainties':[]}))
            meta=Path(tmp)/'capture-01-metadata.json'
            obj,provenance,error=load_completed_output(path)
            self.assertIsNone(error);self.assertEqual(provenance,'unverified_metadata_absent')
            for bad in [{'complete':False,'parsed':True,'finish_reason':'stop'}, {'complete':True,'parsed':False,'finish_reason':'stop'}, {'complete':True,'parsed':True,'finish_reason':'length'}]:
                meta.write_text(json.dumps(bad))
                self.assertEqual(load_completed_output(path)[2],'incomplete_or_unsuccessful_metadata')
                self.assertIsNone(load_completed_output(path)[0])
            meta.write_text('{bad json')
            self.assertEqual(load_completed_output(path)[2],'malformed_completion_metadata')
            meta.write_text(json.dumps({'complete':True,'parsed':True,'finish_reason':'stop'}))
            self.assertEqual(load_completed_output(path)[1],'verified_success_metadata')

    def test_numbered_cross_markers_not_multiplication_or_prose_x(self):
        ref={'transcription':'15. Small-model coding\n16. Other work\n17. Final item'}
        out={'transcription':'15 x Small-model coding\n16 X Other work\n17 * Final item','uncertainties':[]}
        self.assertEqual(score(ref,out)['metrics']['full_disagreement_operations'],0)
        ordinary='15 x5\n16 x 5\n7x Appliances\n7xAppliances\nThe value x remains.\n40 x Ambiguous isolated form'
        tokens=normalized(ordinary)['tokens']
        self.assertIn('x5',tokens);self.assertIn('7x',tokens);self.assertIn('7xappliances',tokens)
        self.assertEqual(tokens.count('x'),3)

    def test_existing_fr_separator_equivalence_preserves_wrong_numbers(self):
        ref={'transcription':'FR·03 task FR·08 next; FR·10 [corrected from 08] final'}
        same={'transcription':'FR.03 task FR-08 next; FR.~~08~~10 final','uncertainties':[]}
        self.assertEqual(score(ref,same)['metrics']['full_disagreement_operations'],0)
        wrong={'transcription':'FR.04 task FR-08 next; FR.~~08~~10 final','uncertainties':[]}
        self.assertEqual(score(ref,wrong)['metrics']['full_disagreement_operations'],1)

if __name__=='__main__':unittest.main()
