import copy
import json
import tempfile
import shutil
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch
import events

class EventTests(unittest.TestCase):
    def preview(self, completed=0, last=None, now='2026-10-20T19:00', frog=True, host=True):
        return events.preview(dict(config=events.load(),completed=completed,lastNight=last,now=now,owned=([events.HOST] if host else [])+([events.FROG] if frog else [])))
    def test_shared_runtime_contract(self):
        cases=json.loads((events.ROOT/'test/fixtures/oyasumi_preview.json').read_text(encoding='utf-8'))
        for case in cases:
            result=events.preview(dict(case['input'],config=events.load()))
            self.assertEqual({k:result[k] for k in case['expected']},case['expected'])

    def test_full_story_and_no_frog(self):
        self.assertEqual(self.preview()['cast'],[events.HOST])
        self.assertEqual(self.preview(1,'2026-10-20',now='2026-10-21T01:00')['stage'],'solo')
        self.assertEqual(self.preview(1,'2026-10-20',now='2026-11-20T19:00',frog=False)['stage'],'solo')
        self.assertEqual(self.preview(1,'2026-10-19')['stage'],'watching')
        self.assertEqual(self.preview(2,'2026-10-19')['stage'],'joining')
        self.assertEqual(self.preview(2,'2026-10-20')['stage'],'watching')
        self.assertFalse(self.preview(2,'2026-10-20')['canComplete'])
        self.assertTrue(self.preview(3,'2026-10-19',now='2026-10-20T12:00')['frogResting'])
        self.assertFalse(self.preview(host=False)['active'])
        self.assertFalse(self.preview(now='2026-10-21T05:00')['active'])
    def test_config_generated_data_is_current(self):
        self.assertEqual(events.DART.read_text(encoding='utf-8'),events.generated(events.load()))
    def test_save_edits_both_files_and_escapes_dart(self):
        doc=copy.deepcopy(events.load())
        doc['stages']['solo']['intro']['text']="引用 ''' と $value と改行\nを保持"
        with tempfile.TemporaryDirectory() as d:
            data,dart=Path(d)/'event.json',Path(d)/'event.dart'
            data.write_text('{}');dart.write_text('old')
            with patch.object(events,'DATA',data),patch.object(events,'DART',dart): events.save(doc)
            self.assertEqual(json.loads(data.read_text(encoding='utf-8')),doc)
            self.assertIn(r'\$value',dart.read_text(encoding='utf-8'))
    def test_invalid_settings_rejected_before_write(self):
        for mutate in [lambda d:d['night'].update(startHour=5),lambda d:d.update(background='../private'),lambda d:d['stages']['solo']['positions'].update({events.FROG:[.5,.5]}),lambda d:d['stages']['solo']['chatter'].update({events.HOST:['only one']}),lambda d:d['stages']['watching']['positions'].update({events.FROG:[float('nan'),.5]})]:
            doc=copy.deepcopy(events.load());mutate(doc)
            with self.assertRaises(ValueError):events.validate(doc)
    def test_multi_character_replies_and_daytime_peer_filtering(self):
        doc=copy.deepcopy(events.load())
        # Use a controlled fixture, independent of the live dialogue mix.
        doc['restingDialogue']=[
            'ひとりで公園を歩いたよ。',
            '今日は何しようかな。',
            'お昼ごはんがおいしかったよ。',
            {'turns':[
                {'speaker':events.FROG,'text':'やすぞうさん、畑を手伝ってもいいですか？'},
                {'speaker':'026_farmer','text':'ほっほ、やってみるかね'},
                {'speaker':events.FROG,'text':'はい、少しだけ！'},
            ]},
        ]
        doc['stages']['watching']['chatter'][events.FROG][0]={'turns':[
            {'speaker':events.FROG,'text':'あそこに座ってもいいかな'},
            {'speaker':events.HOST,'text':'いつでもどうぞ〜'},
        ]}
        events.validate(doc)
        base={'config':doc,'completed':3,'lastNight':'2026-10-19','now':'2026-10-20T12:00','owned':[events.HOST,events.FROG]}
        alone=events.preview({**base,'peers':[]})
        self.assertEqual(len(alone['restingOptions']),3)
        self.assertNotIn(doc['restingDialogue'][3],alone['restingOptions'])
        with_yasuzo=events.preview({**base,'peers':['026_farmer']})
        self.assertEqual(len(with_yasuzo['restingOptions']),4)
        self.assertEqual(with_yasuzo['restingOptions'][3]['turns'][1]['speaker'],'026_farmer')
        with self.assertRaises(ValueError):
            events.preview({**base,'peers':['035_beaty']})
        self.assertEqual(events.preview({**base,'now':'2026-10-20T19:00'})['restingOptions'],[])

    def test_invalid_multi_character_dialogue_rejected(self):
        for item in [
            {'turns':[]},
            {'turns':[{'speaker':'026_farmer','text':'おやすみ'}]},
            {'turns':[{'speaker':events.FROG,'text':'やあ'},{'speaker':'035_beaty','text':'こんにちは'}]},
            {'turns':[{'speaker':events.FROG,'text':'やあ'},{'speaker':'nobody','text':'こんにちは'}]},
            {'turns':[{'speaker':events.FROG,'text':'やあ','extra':'invalid'}]},
            {'turns':[{'speaker':events.FROG,'text':'ひとこと'}]*9},
        ]:
            with self.subTest(item=item):
                doc=copy.deepcopy(events.load())
                doc['restingDialogue'][1]=item
                with self.assertRaises(ValueError):events.validate(doc)
        doc=copy.deepcopy(events.load())
        doc['stages']['solo']['chatter'][events.HOST][0]={
            'turns':[{'speaker':events.HOST,'text':'やあ'},{'speaker':events.FROG,'text':'どうも'}]}
        with self.assertRaises(ValueError):events.validate(doc)
        doc=copy.deepcopy(events.load())
        doc['restingDialogue']=[
            {'turns':[{'speaker':events.FROG,'text':'一緒に'},{'speaker':events.HOST,'text':'もふ'}]}
            for _ in range(3)
        ]
        with self.assertRaisesRegex(ValueError,'一人で話せる'):events.validate(doc)

    @unittest.skipUnless(shutil.which('node'), 'Node.js is optional')
    def test_event_editor_javascript_syntax(self):
        process=subprocess.run(['node','--check',str(events.ROOT/'tools/dialogue_cms/events.js')],
                               text=True,capture_output=True,check=False,timeout=15)
        self.assertEqual(process.returncode,0,process.stderr)

    def test_playful_frog_dialogue_and_readable_replies(self):
        doc=events.load()
        frog=events.FROG
        host=events.HOST
        watching=doc['stages']['watching']['chatter'][frog]
        joined=doc['stages']['joined']['chatter'][frog]
        self.assertTrue(all(isinstance(item,str) for item in watching))
        self.assertIn('におう',joined[0]['turns'][0]['text'])
        self.assertEqual([t['speaker'] for t in joined[0]['turns']], [frog,host,frog,host,frog])
        self.assertEqual(len(joined),4)
        self.assertNotIn('辞め',doc['stages']['joining']['intro']['text'])
        self.assertIn('会社を辞め',doc['restingDialogue'][0])
        self.assertTrue(any(not isinstance(x,str) for x in doc['restingDialogue']))
        # The existing stage progression contract must remain unchanged.
        self.assertEqual(self.preview(2,'2026-10-19')['stage'],'joining')
        self.assertEqual(self.preview(3,'2026-10-19')['stage'],'joined')

    def test_park_cleaner_gated_and_post_club_lines(self):
        doc=events.load()
        self.assertEqual(len(doc['restingDialogue']),7)
        self.assertIn('筋肉痛',doc['restingDialogue'][5])
        cleaner=doc['restingDialogue'][6]
        self.assertEqual(cleaner['requires'],'parkCleaner')
        self.assertEqual(cleaner['turns'][-1]['text'],'ぼくはこうえんじゃないもふ！！')
        base={'config':doc,'completed':3,'lastNight':'2026-10-19',
              'now':'2026-10-20T12:00','owned':[events.HOST,events.FROG],
              'peers':[events.HOST]}
        self.assertNotIn(cleaner,events.preview(base)['restingOptions'])
        self.assertIn(cleaner,events.preview({**base,'parkCleanerStarted':True})['restingOptions'])
        self.assertNotIn(cleaner,events.preview({**base,'parkCleanerStarted':True,'peers':[]})['restingOptions'])
        with self.assertRaises(ValueError):
            events.preview({**base,'parkCleanerStarted':'yes'})
        invalid=copy.deepcopy(doc)
        invalid['restingDialogue'][6]['requires']='unknown'
        with self.assertRaises(ValueError):events.validate(invalid)
        invalid=copy.deepcopy(doc)
        invalid['stages']['joined']['chatter'][events.FROG][0]['requires']='parkCleaner'
        with self.assertRaises(ValueError):events.validate(invalid)
        invalid=copy.deepcopy(doc)
        invalid['restingDialogue']=['one','two','three']*3
        with self.assertRaises(ValueError):events.validate(invalid)

    def test_mosaedo_night_patrol_is_solo_and_requires_ownership(self):
        cfg=events.load()
        patrol=cfg['nightPatrol']
        self.assertEqual(patrol['residentId'],events.MOSA)
        self.assertIn('今宵も町は平和でござる！ あおんあおん！',patrol['dialogues'])
        base=dict(config=cfg,completed=0,lastNight=None,
                  now='2026-10-20T19:00',owned=[events.HOST,events.MOSA])
        night=events.preview(base)
        self.assertEqual(night['cast'],[events.HOST])
        self.assertEqual(night['passersby'],[events.MOSA])
        self.assertEqual(night['positions'][events.MOSA],
                         [patrol['route']['x'],patrol['route']['y']])
        self.assertEqual(night['patrolDialogues'],patrol['dialogues'])
        self.assertEqual(events.preview({**base,'owned':[events.HOST]})['passersby'],[])
        self.assertEqual(events.preview({**base,'owned':[events.MOSA]})['passersby'],[])
        self.assertEqual(events.preview({**base,'now':'2026-10-20T12:00'})['passersby'],[])
        self.assertEqual(events.preview({**base,'owned':[events.HOST,events.FROG,events.MOSA]})['stage'],'solo')
        for mutation in [
            lambda d:d['nightPatrol'].update(residentId=events.FROG),
            lambda d:d['nightPatrol']['route'].update(x=.82,width=.15),
            lambda d:d['nightPatrol']['route'].update(height=float('nan')),
            lambda d:d['nightPatrol'].update(dialogues=[]),
            lambda d:d['nightPatrol'].update(dialogues=['こんにちは',{'turns':[]}]),
        ]:
            modified=copy.deepcopy(cfg)
            mutation(modified)
            with self.assertRaises(ValueError):
                events.validate(modified)

    def test_preview_never_saves(self):
        with patch.object(events,'commit_files',side_effect=AssertionError('preview wrote data')):
            self.preview();self.preview(3,'2026-10-19')

if __name__=='__main__':unittest.main()
