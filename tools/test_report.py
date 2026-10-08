import json, pathlib, subprocess, tempfile, unittest
SCRIPT=pathlib.Path(__file__).with_name('report.py')
class ReportTest(unittest.TestCase):
    def run_report(self,rows):
        with tempfile.NamedTemporaryFile(mode='w') as f:
            for r in rows:f.write(json.dumps(r)+'\n')
            f.flush()
            return json.loads(subprocess.check_output(['python3',str(SCRIPT),f.name,'--room','r']))
    def test_no_data_does_not_invent_results(self):
        r=self.run_report([])
        self.assertIsNone(r['meanCanonicalErrorMs']);self.assertIsNone(r['meanInterpolatedPairErrorMs'])
        self.assertFalse(r['hasThirtyMinuteTelemetry'])
    def test_interpolation_uses_timeline_and_rejects_buffered_samples(self):
        rows=[]
        for user,offset,time_offset in [('a',0,0),('b',100,500)]:
            for t in range(0,4000,1000):
                ts=t+time_offset
                rows.append({'roomId':'r','userId':user,'data':{'serverTimeMs':ts,'positionMs':ts+offset,'errorMs':-offset,'rttMs':40,'version':1,'ready':True,'buffering':False,'playing':True}})
        r=self.run_report(rows)
        self.assertEqual(r['pairSamples'],3);self.assertEqual(r['meanInterpolatedPairErrorMs'],100)
        for row in rows:row['data']['buffering']=True
        self.assertIsNone(self.run_report(rows)['meanInterpolatedPairErrorMs'])
    def test_scheduled_seek_does_not_interpolate_across_jump(self):
        rows=[{'roomId':'r','kind':'control','type':'SEEK','room':{'version':2,'executeAt':1500}}]
        for uid,offset in [('a',0),('b',500)]:
            for t in range(0,5000,1000):
                ts=t+offset
                pos=ts if ts<1500 else ts+100000
                rows.append({'roomId':'r','userId':uid,'data':{'serverTimeMs':ts,'positionMs':pos,'errorMs':0,'rttMs':40,'version':2,'ready':True,'buffering':False,'playing':True}})
        r=self.run_report(rows)
        self.assertEqual(r['maxInterpolatedPairErrorMs'],0)
        self.assertEqual(r['pairSamples'],3)
    def test_missing_clock_breaks_interpolation_and_playing_coverage(self):
        def row(uid,t,pos):
            return {'roomId':'r','userId':uid,'data':{'serverTimeMs':t,'positionMs':pos,'errorMs':0,'rttMs':40,'version':1,'ready':True,'buffering':False,'playing':True}}
        rows=[row('a',1000,1000),row('b',500,500),row('b',None,900),row('b',1500,1500)]
        r=self.run_report(rows)
        self.assertEqual(r['pairSamples'],0)
        self.assertEqual(r['estimatedReadyPlayingSecondsByUser']['b'],0)
    def test_transition_diagnostics_do_not_count_as_progress_samples(self):
        rows=[{'roomId':'r','userId':'a','data':{'diagnostic':True,'event':'isPlayingChanged','serverTimeMs':1000,'ready':True,'playing':True,'errorMs':9999}}]
        r=self.run_report(rows)
        self.assertEqual(r['users'],[])
        self.assertIsNone(r['maxCanonicalErrorMs'])
    def test_different_media_offsets_are_normalized(self):
        rows=[]
        for uid,shift,time_shift in [('a',0,0),('b',8000,500)]:
            for t in range(0,4000,1000):
                now=t+time_shift
                rows.append({'roomId':'r','userId':uid,'data':{'serverTimeMs':now,'positionMs':now+shift,'timelineOffsetMs':shift,'errorMs':0,'version':1,'ready':True,'buffering':False,'playing':True}})
        result=self.run_report(rows)
        self.assertEqual(result['meanInterpolatedPairErrorMs'],0)
if __name__=='__main__':unittest.main()
