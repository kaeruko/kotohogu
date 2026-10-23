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

    def test_oyasumi_kun_dinner_dialogue_is_available_at_night(self):
        doc = events.load()
        for stage in events.STAGES:
            lines = doc['stages'][stage]['chatter'][events.HOST]
            dinner = [item for item in lines
                      if isinstance(item, dict)
                      and any('おにぎりと、あったかいおみそ汁' in turn['text']
                              for turn in item['turns'])]
            self.assertEqual(len(dinner), 1 if stage == 'solo' else 0, stage)
            if stage == 'solo':
                self.assertEqual([turn['speaker'] for turn in dinner[0]['turns']],
                                 [events.HOST] * 5)
                self.assertIn('いっしょに起きてるよ', dinner[0]['turns'][-1]['text'])
        self.assertEqual(len(doc['stages']['solo']['chatter'][events.HOST]), 4)
        self.assertEqual(len(doc['stages']['joined']['chatter'][events.HOST]), 3)
        for stage in ('watching', 'joining', 'joined'):
            self.assertEqual(len(self.preview(1 if stage == 'watching' else 2 if stage == 'joining' else 3,
                                               '2026-10-19')['dialogues'][events.HOST]),
                             4 if stage == 'watching' else 3)
        events.validate(doc)
        over_limit = copy.deepcopy(doc)
        over_limit['stages']['solo']['chatter'][events.HOST].append('5本目')
        with self.assertRaisesRegex(ValueError, '3〜4本'):
            events.validate(over_limit)

    def test_faraway_frog_sees_the_club_of_one(self):
        doc = events.load()
        solo = doc['stages']['solo']['chatter'][events.HOST]
        watching = doc['stages']['watching']['chatter'][events.HOST]
        self.assertEqual(len(solo), 4)
        self.assertEqual(len(watching), 4)
        expected = [
            'もふ〜。きょうも、おやすみくらぶをはじめるもふ〜',
            '……さんかしゃ、ぼくひとりもふ',
            '……ぜんいんしゅっせきもふ〜！',
        ]
        self.assertEqual(watching[3]['turns'], [
            {'speaker': events.HOST, 'text': text} for text in expected
        ])
        self.assertEqual(self.preview(1, '2026-10-19')['dialogues'][events.HOST][3]['turns'],
                         watching[3]['turns'])
        self.assertTrue(all(item != watching[3] for item in solo))

    def test_night_conversation_pattern_limits_and_preview(self):
        doc=events.load()
        for key,stage in doc['stages'].items():
            for speaker,patterns in stage['chatter'].items():
                self.assertGreaterEqual(len(patterns),3)
                limit=5 if key=='joined' and speaker==events.FROG else 4
                self.assertLessEqual(len(patterns),limit)
        merged=doc['stages']['solo']['chatter'][events.HOST][0]
        self.assertEqual(len(merged['turns']),2)
        self.assertIn('おほしさま',merged['turns'][1]['text'])
        self.assertEqual(len(self.preview()['dialogues'][events.HOST]),4)
        page=(events.ROOT/'tools/dialogue_cms/events.html').read_text(encoding='utf-8')
        self.assertLess(page.index('id="lines"'),page.index('id="scene"'))

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
        self.assertEqual([t['speaker'] for t in joined[0]['turns']], [frog,host])
        self.assertEqual(len(joined),5)
        park=joined[1]['turns']
        today=joined[2]['turns']
        self.assertEqual([t['speaker'] for t in park], [frog,host])
        self.assertEqual([t['speaker'] for t in today], [frog,host,frog,host,frog])
        self.assertEqual(park[0]['text'],'おやすみくん、今日は公園を二周したんだ！')
        self.assertFalse(any('今日は何してた？' in turn['text'] for turn in park))
        self.assertEqual(today[0]['text'],'おやすみくん、今日は何してた？')
        self.assertIn('かえるくんをまってた',today[1]['text'])
        self.assertIn('待ってないじゃん',today[-1]['text'])
        reunion=joined[-2]['turns']
        self.assertEqual([turn['speaker'] for turn in reunion],
                         [frog, frog, frog, host])
        self.assertIn('会いに来たんだけど', reunion[1]['text'])
        self.assertIn('起こさないでおこうね', reunion[2]['text'])
        self.assertIn('……すぅ……もふ……', reunion[-1]['text'])
        self.assertEqual(
            self.preview(3,'2026-10-19')['dialogues'][frog][-2]['turns'],
            reunion)
        resignation=joined[-1]['turns']
        self.assertEqual(len(resignation),8)
        self.assertEqual([t['speaker'] for t in resignation],
                         [frog,host,frog,host,frog,host,frog,frog])
        self.assertIn('会社を辞めた', resignation[0]['text'])
        self.assertIn('あしたもあそべる', resignation[1]['text'])
        self.assertIn('しばらくゆっくり', resignation[2]['text'])
        self.assertIn('また明日ね', resignation[-2]['text'])
        # Frog voices his doubts only after leaving Oyasumi-kun.
        self.assertIn('ひとりで', resignation[-1]['text'])
        self.assertIn('決めたのは、ぼくだ', resignation[-1]['text'])
        self.assertNotIn('仲良くならなかったら',
                         ''.join(turn['text'] for turn in resignation[:-1]))
        self.assertEqual(
            self.preview(3,'2026-10-19')['dialogues'][frog][-1]['turns'],
            resignation)
        self.assertFalse(self.preview(3,'2026-10-19',
                                      now='2026-10-20T12:00')['active'])
        self.assertNotIn('辞め',doc['stages']['joining']['intro']['text'])
        self.assertIn('会社を辞め',doc['restingDialogue'][0])
        self.assertTrue(any(not isinstance(x,str) for x in doc['restingDialogue']))
        # The existing stage progression contract must remain unchanged.
        self.assertEqual(self.preview(2,'2026-10-19')['stage'],'joining')
        self.assertEqual(self.preview(3,'2026-10-19')['stage'],'joined')

    def test_park_cleaner_gated_and_post_club_lines(self):
        doc=events.load()
        self.assertEqual(len(doc['restingDialogue']),8)
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
        relaxed=doc['restingDialogue'][-1]
        self.assertIn('気が楽',relaxed['turns'][0]['text'])
        self.assertIn(relaxed,events.preview(base)['restingOptions'])
        self.assertNotIn(relaxed,events.preview({**base,'peers':[]})['restingOptions'])
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

    def test_tonko_tea_delivery_is_gated_and_editable(self):
        doc=events.load()
        tea=doc['teaVisit']
        self.assertEqual(tea['residentId'],events.TONKO)
        self.assertEqual(tea['intervalNights'],3)
        self.assertEqual([row['speaker'] for row in tea['turns']],
                         [events.TONKO,events.FROG,events.HOST,events.TONKO])
        base=dict(config=doc,completed=3,lastNight='2026-10-20',
                  now='2026-10-21T19:00',
                  owned=[events.HOST,events.FROG,events.TONKO],
                  marcheOpen=True)
        active=events.preview(base)
        self.assertEqual(active['stage'],'joined')
        self.assertEqual(active['cast'],[events.HOST,events.FROG])
        self.assertEqual(active['passersby'],[events.TONKO])
        self.assertEqual(active['positions'][events.TONKO],tea['position'])
        self.assertEqual(active['teaVisit'],tea)
        for change in [
            {'now':'2026-10-22T19:00'},
            {'now':'2026-10-23T19:00'},
            {'now':'2026-10-21T12:00'},
            {'marcheOpen':False},
            {'owned':[events.HOST,events.FROG]},
            {'owned':[events.HOST,events.TONKO]},
            {'completed':2},
        ]:
            params={**base,**change}
            self.assertIsNone(events.preview(params)['teaVisit'],params)
        self.assertEqual(events.preview({**base,'now':'2026-10-24T19:00'})['passersby'],[events.TONKO])
        midnight=events.preview({**base,'now':'2026-10-22T02:00'})
        self.assertEqual(midnight['nightKey'],'2026-10-21')
        self.assertEqual(midnight['passersby'],[events.TONKO])
        for change in [
            lambda d:d['teaVisit'].update(residentId=events.FROG),
            lambda d:d['teaVisit'].update(intervalNights=0),
            lambda d:d['teaVisit'].update(position=[.95,.4]),
            lambda d:d['teaVisit'].update(turns=[]),
            lambda d:d['teaVisit']['turns'][0].update(speaker=events.FROG),
            lambda d:d['teaVisit']['turns'][2].update(speaker=events.TONKO),
        ]:
            invalid=copy.deepcopy(doc);change(invalid)
            with self.assertRaises(ValueError):events.validate(invalid)
        with self.assertRaises(ValueError):
            events.preview({**base,'marcheOpen':'yes'})

    def test_preview_never_saves(self):
        with patch.object(events,'commit_files',side_effect=AssertionError('preview wrote data')):
            self.preview();self.preview(3,'2026-10-19')

if __name__=='__main__':unittest.main()
