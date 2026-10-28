"""Parser/segmentation regressions with controlled scores; no accuracy claim."""
import unittest
import numpy as np
from semantic_matcher import MultilingualSemanticMatcher

class AlignedRegressions(unittest.TestCase):
 def matcher(self,mapping):
  m=object.__new__(MultilingualSemanticMatcher)
  def embed(texts):
   out=[]
   for text in texts:
    v=np.zeros(10);v[mapping.get(''.join(text.split()),9)]=1;out.append(v)
   return np.array(out)
  m.embed=embed;return m

 def test_short_cjk_dialogue_is_not_discarded(self):
  mapping={};cues=[];transcripts={}
  for i in range(9):
   jp='水'+str(i);zh='茶'+str(i);mapping[jp]=mapping[zh]=i;t=200+i*720
   cues.append({'start':t,'end':t+2,'text':zh})
   transcripts[i+1]={'segments':[{'start_seconds':t,'end_seconds':t+2,'text':jp}]}
  result=self.matcher(mapping).match(transcripts,cues,7200)
  self.assertEqual(result['status'],'verified')
  self.assertEqual(result['matched_anchors'],9)

 def test_one_sentence_can_match_three_adjacent_subtitle_cues(self):
  mapping={};cues=[];transcripts={}
  for i in range(9):
   t=200+i*720;phrase='字幕甲'+str(i)+'字幕乙'+str(i)+'字幕丙'+str(i)
   mapping[phrase]=mapping['日本語文章'+str(i)]=i
   for j,part in enumerate(('字幕甲','字幕乙','字幕丙')):
    cues.append({'start':t+j*2,'end':t+(j+1)*2,'text':part+str(i)})
   transcripts[i+1]={'segments':[{'start_seconds':t,'end_seconds':t+6,'text':'日本語文章'+str(i)}]}
  result=self.matcher(mapping).match(transcripts,cues,7200)
  self.assertEqual(result['status'],'verified')
  self.assertTrue(all(x['subtitle_cue_count']==3 for x in result['sample_matches']))

 def test_repeated_short_dialogue_stays_ambiguous(self):
  mapping={};cues=[];transcripts={}
  for i in range(9):
   t=200+i*720;mapping['水'+str(i)]=mapping['茶'+str(i)]=i
   cues.append({'start':t,'end':t+2,'text':'茶'+str(i)})
   transcripts[i+1]={'segments':[{'start_seconds':t,'end_seconds':t+2,'text':'水'+str(i)}]}
  cues[4]['text']=cues[0]['text']
  result=self.matcher(mapping).match(transcripts,cues,7200)
  self.assertFalse(result['auto_correct'])
  self.assertNotIn(1,result['matched_samples'])
  self.assertIn({'sample_index':1,'reason':'ambiguous_subtitle_match'},result['unmatched_samples'])
