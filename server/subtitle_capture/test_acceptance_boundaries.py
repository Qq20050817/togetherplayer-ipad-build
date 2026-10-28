import unittest
from pathlib import Path
from subtitle_alignment import SpeechAnchor,verify_real_anchors
from test_semantic_matcher import MODEL,PAIRS
from semantic_matcher import MultilingualSemanticMatcher

class TimingBoundaries(unittest.TestCase):
    def anchors(self):
        return [SpeechAnchor(i,200+(i-1)*720,221+(i-1)*720,0.95) for i in range(1,10)]

    def test_conflicting_evidence_cannot_be_discarded_to_pass(self):
        anchors=self.anchors()
        a=anchors[4]
        anchors[4]=SpeechAnchor(a.sample_index,a.subtitle_seconds,a.matched_speech_seconds+20,a.semantic_confidence)
        result=verify_real_anchors(anchors)
        self.assertEqual(result['status'],'version_might_differ')
        self.assertFalse(result['auto_correct'])
        self.assertEqual(result['rejected_samples'],[5])

    def test_consistent_offset_still_passes(self):
        result=verify_real_anchors(self.anchors())
        self.assertEqual(result['status'],'offset_detected')
        self.assertTrue(result['auto_correct'])
        self.assertAlmostEqual(result['offset_at_start_seconds'],21)

    def test_impossible_confidence_cannot_verify(self):
        anchors=[SpeechAnchor(a.sample_index,a.subtitle_seconds,a.matched_speech_seconds,1.2) for a in self.anchors()]
        self.assertEqual(verify_real_anchors(anchors)['status'],'unavailable')

    def test_linear_drift_is_reported(self):
        anchors=[SpeechAnchor(a.sample_index,a.subtitle_seconds,a.subtitle_seconds+2+a.subtitle_seconds*0.001,0.95) for a in self.anchors()]
        result=verify_real_anchors(anchors)
        self.assertEqual(result['status'],'drift_detected')
        self.assertAlmostEqual(result['linear_drift_seconds_per_hour'],3.6)

class SemanticBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(MODEL,"model_quantized.onnx").is_file():raise unittest.SkipTest("semantic model not configured")
        cls.matcher=MultilingualSemanticMatcher(MODEL)

    def inputs(self):
        cues=[{'start':200+i*720,'end':202+i*720,'text':zh} for i,(_ko,zh) in enumerate(PAIRS)]
        texts={i+1:{'segments':[{'text':ko,'start_seconds':221+i*720}]} for i,(ko,_zh) in enumerate(PAIRS)}
        return cues,texts

    def test_opening_only_evidence_cannot_verify_long_film(self):
        cues,texts=self.inputs()
        result=self.matcher.match(texts,cues,20000)
        self.assertEqual(result['status'],'unavailable')
        self.assertEqual(result['reason'],'anchors_do_not_cover_film')
        self.assertFalse(result['auto_correct'])

    def test_missing_speech_lists_problem_samples(self):
        cues,texts=self.inputs()
        del texts[4]
        texts[5]={'segments':[]}
        result=self.matcher.match(texts,cues,7200)
        issues={x['sample_index']:x['reason'] for x in result['unmatched_samples']}
        self.assertEqual(issues[4],'no_transcript')
        self.assertEqual(issues[5],'no_reliable_dialogue')
        self.assertFalse(result['auto_correct'])

    def test_duplicate_clip_cannot_reuse_subtitle_evidence(self):
        cues,texts=self.inputs()
        texts={i:texts[1] for i in range(1,10)}
        result=self.matcher.match(texts,cues,7200)
        self.assertEqual(result['status'],'unavailable')
        self.assertEqual(len(result['sample_matches']),1)
        self.assertEqual(len(result['unmatched_samples']),8)
        self.assertTrue(all(x['reason']=='subtitle_cue_reused' for x in result['unmatched_samples']))
