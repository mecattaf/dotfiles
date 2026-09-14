"""Offline geometry, reference-free selection and conservative stitching checks."""
import unittest
from PIL import Image
from tile_probe import choose, stitch, target_size, tile_boxes, upright


class TileProbe(unittest.TestCase):
    def test_selection_is_partitioned_word_count_with_stable_tie(self):
        rows=[{'capture':n,'transcription':'base'} for n in range(1,18)]
        rows[5]['transcription']='One, TWO three.'
        rows[6]['transcription']='also three words'
        rows[14]['transcription']='heldout has four words'
        winners=choose(rows)
        self.assertEqual([r['capture'] for r in winners],[6,15])
        with self.assertRaises(ValueError):choose(rows[:-1])

    def test_orientation_and_native_overlap_bounds(self):
        im=Image.new('RGB',(100,200));im.putpixel((0,0),(255,0,0))
        rotated=upright(im,90)
        self.assertEqual(rotated.size,(200,100))
        self.assertEqual(rotated.getpixel((0,99)),(255,0,0))
        self.assertEqual(upright(im,0).size,(100,200))
        for width,height in [(3072,4080),(4080,3072)]:
            boxes=tile_boxes(width,height)
            self.assertEqual(boxes['top'][:2],(0,0))
            self.assertEqual(boxes['bottom'][2:],(width,height))
            self.assertAlmostEqual((boxes['top'][3]-boxes['bottom'][1])/height,.2,delta=2/height)
            for left,top,right,bottom in boxes.values():
                self.assertTrue(0<=left<right<=width and 0<=top<bottom<=height)
                size=target_size(right-left,bottom-top)
                self.assertEqual(size[0]%32,0);self.assertEqual(size[1]%32,0)
                self.assertLessEqual(size[0]*size[1],3686400)
                self.assertLessEqual(size[0],right-left+16);self.assertLessEqual(size[1],bottom-top+16)

    def test_unique_anchor_preserves_text_and_removes_duplicate(self):
        prefix=' '.join('prefix'+str(n) for n in range(12))
        overlap=' '.join('shared'+str(n) for n in range(20))
        suffix=' '.join('suffix'+str(n) for n in range(20))
        result=stitch(prefix+'\n'+overlap.upper()+'.',overlap+'.\n'+suffix)
        self.assertEqual(result['status'],'stitched')
        self.assertEqual(result['transcription'],prefix+'\n'+overlap.upper()+'.\n'+suffix)
        self.assertGreaterEqual(result['anchor']['words'],10)

    def test_ambiguous_and_absent_anchors_do_not_make_proposals(self):
        repeat=' '.join('word'+str(n) for n in range(12))
        top=' '.join([repeat]*4)
        bottom=' '.join([repeat]*2)+' '+' '.join('tail'+str(n) for n in range(30))
        ambiguous=stitch(top,bottom)
        self.assertEqual(ambiguous['status'],'ambiguous_anchor')
        self.assertIsNone(ambiguous['transcription'])
        self.assertEqual(ambiguous['top_text'],top);self.assertEqual(ambiguous['bottom_text'],bottom)
        missing=stitch(' '.join('a'+str(n) for n in range(40)),' '.join('b'+str(n) for n in range(40)))
        self.assertEqual(missing['status'],'no_anchor');self.assertIsNone(missing['transcription'])


if __name__=='__main__':unittest.main()
