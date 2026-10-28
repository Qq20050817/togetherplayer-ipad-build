"""True offline Korean-Chinese sentence matching smoke tests. No media files."""
import unittest
import os
from pathlib import Path
from semantic_matcher import MultilingualSemanticMatcher

MODEL=os.environ.get("CAPTURE_SEMANTIC_MODEL_DIR","")
PAIRS=[
("안녕하세요. 물 한 잔 주세요.","你好，请给我一杯水。"),
("오늘 날씨가 참 좋네요.","今天天气真的很好。"),
("기차가 곧 출발합니다.","火车马上要出发了。"),
("어머니가 병원에 계세요.","妈妈现在在医院里。"),
("빨리 경찰에 전화하세요.","快点给警察打电话。"),
("내일 아침 일찍 출발할 거예요.","明天一大早我们就出发。"),
("학교 앞에서 다시 만나요.","我们在学校门口再见面吧。"),
("그 책을 책상 위에 놓으세요.","请把那本书放到桌子上。"),
("문을 닫고 불을 꺼 주세요.","请把门关上然后关灯。"),
]


class MatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(MODEL,"model_quantized.onnx").is_file():raise unittest.SkipTest("semantic model not configured")
        cls.matcher=MultilingualSemanticMatcher(MODEL)

    def inputs(self,shift=21):
        cues=[{"start":200+i*720,"end":202+i*720,"text":zh}
              for i,(_ko,zh) in enumerate(PAIRS)]
        texts={i+1:{"segments":[{"text":ko,"start_seconds":200+i*720+shift}]}
               for i,(ko,_zh) in enumerate(PAIRS)}
        return cues,texts

    def test_real_korean_to_chinese_offset(self):
        cues,texts=self.inputs()
        result=self.matcher.match(texts,cues,7200)
        print("MODEL_SMOKE:",result)
        self.assertEqual(result["status"],"offset_detected")
        self.assertGreaterEqual(result["matched_anchors"],7)
        self.assertAlmostEqual(result["offset_at_start_seconds"],21,delta=0.5)

    def test_weak_mismatched_dialogue_never_auto_edits(self):
        cues,_=self.inputs()
        texts={i:{"segments":[{"text":"今天正在下雨","start_seconds":200+(i-1)*720}]}
               for i in range(1,10)}
        result=self.matcher.match(texts,cues,7200)
        self.assertFalse(result["auto_correct"])
        self.assertNotEqual(result["status"],"offset_detected")

if __name__=="__main__":
    unittest.main()
