import copy
import json
import tempfile
import shutil
import subprocess
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch
import events

class EventTests(unittest.TestCase):
    def preview(self, completed=0, last=None, now='2026-10-20T19:00', frog=True, host=True):
        when=datetime.fromisoformat(now)
        night=(when-timedelta(days=1 if when.hour<6 else 0)).strftime('%Y-%m-%d')
        earned=30 if last and night>last else 0
        return events.preview(dict(config=events.load(),completed=completed,
            lastNight=last,lastKotohogi=0 if completed else None,
            earnedKotohogi=earned,now=now,
            owned=([events.HOST] if host else [])+([events.FROG] if frog else [])))
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
        self.assertTrue(self.preview(now='2026-10-21T05:59')['active'])
        self.assertFalse(self.preview(now='2026-10-21T06:00')['active'])
    def test_config_generated_data_is_current(self):
        self.assertEqual(events.DART.read_text(encoding='utf-8'),events.generated(events.load()))
    def test_resignation_read_checkpoint_precedes_job(self):
        doc = events.load()
        resignation = doc['stages']['joined']['resignationConversation']
        self.assertEqual(resignation['id'],'oyasumi_joined_resignation_001')
        self.assertEqual(resignation['unlockAfterKotohogi'],30)
        self.assertEqual(len(resignation['turns']),8)
        base = dict(config=doc,completed=3,lastNight='2026-10-20',
                    lastKotohogi=160,earnedKotohogi=180,
                    now='2026-10-25T19:00',owned=[events.HOST,events.FROG])
        self.assertIsNone(events.preview(base)['resignationDialogue'])
        unlocked = {**base,'earnedKotohogi':190}
        self.assertEqual(events.preview(unlocked)['resignationDialogue'],
                         resignation)
        self.assertIsNone(events.preview(unlocked)['parkCleanerDialogue'])
        backlog = {**base,'earnedKotohogi':300}
        self.assertEqual(events.preview(backlog)['resignationDialogue'],
                         resignation)
        self.assertIsNone(events.preview(backlog)['parkCleanerDialogue'])
        read = {**backlog,'resignationAtKotohogi':300}
        self.assertIsNone(events.preview(read)['resignationDialogue'])
        self.assertIsNone(events.preview(read)['parkCleanerDialogue'])
        self.assertIsNone(events.preview(read)['rumorDialogue'])
        self.assertEqual(events.preview({**read,'earnedKotohogi':330})
            ['parkCleanerDialogue'],
            doc['stages']['joined']['parkCleanerConversation'])
        self.assertIsNone(events.preview({
            **unlocked,'now':'2026-10-25T12:00'})['resignationDialogue'])
        with self.assertRaisesRegex(ValueError,'退職会話を読了'):
            events.preview({**unlocked,'resignationAtKotohogi':200})

    def test_park_cleaner_job_is_first_at_joining_plus_sixty(self):
        doc = events.load()
        job = doc['stages']['joined']['parkCleanerConversation']
        self.assertEqual(job['id'], 'frog_park_cleaner_started')
        self.assertEqual(job['unlockAfterKotohogi'], 60)
        self.assertEqual([part['speaker'] for part in job['turns']],
                         [events.FROG, events.HOST, events.FROG,
                          events.HOST, events.FROG])
        base = dict(config=doc, completed=3, lastNight='2026-10-20',
                    lastKotohogi=160, earnedKotohogi=210,
                    now='2026-10-25T19:00',
                    owned=[events.HOST, events.FROG])
        self.assertIsNone(events.preview(base)['parkCleanerDialogue'])
        job_ready = {**base, 'earnedKotohogi': 220,
                     'resignationAtKotohogi': 190}
        self.assertEqual(events.preview(job_ready)['parkCleanerDialogue'], job)
        self.assertIsNone(events.preview(job_ready)['rumorDialogue'])
        backlog = {**base, 'earnedKotohogi': 280,
                   'resignationAtKotohogi': 190}
        self.assertEqual(events.preview(backlog)['parkCleanerDialogue'], job)
        self.assertIsNone(events.preview(backlog)['rumorDialogue'])
        self.assertIsNone(events.preview(backlog)['wishDialogue'])
        read = {**backlog, 'parkCleanerStarted': True}
        self.assertIsNone(events.preview(read)['parkCleanerDialogue'])
        self.assertIsNotNone(events.preview(read)['rumorDialogue'])
        self.assertIsNone(events.preview({**job_ready,
            'now': '2026-10-25T12:00'})['parkCleanerDialogue'])
        self.assertIsNone(events.preview({**job_ready,
            'completed': 2})['parkCleanerDialogue'])
        self.assertIsNone(events.preview({**job_ready,
            'owned': [events.FROG]})['parkCleanerDialogue'])

    def test_kotohoguma_rumor_unlocks_before_wish(self):
        doc = events.load()
        rumor = doc['stages']['joined']['rumorConversation']
        self.assertEqual(rumor['id'], 'oyasumi_joined_kotohoguma_rumor_001')
        self.assertEqual(rumor['unlockAfterKotohogi'], 90)
        self.assertEqual([t['speaker'] for t in rumor['turns']],
                         [events.FROG, events.HOST] * 2)
        self.assertEqual(rumor['turns'][-1]['text'], 'もふ？')
        base = dict(config=doc, completed=3, lastNight='2026-10-20',
                    lastKotohogi=160, earnedKotohogi=240,
                    now='2026-10-25T19:00',
                    owned=[events.HOST, events.FROG],
                    parkCleanerStarted=True)
        self.assertIsNone(events.preview(base)['rumorDialogue'])
        seen_90 = {**base, 'earnedKotohogi': 250}
        self.assertEqual(events.preview(seen_90)['rumorDialogue'], rumor)
        self.assertIsNone(events.preview(seen_90)['wishDialogue'])
        seen_both = {**base, 'earnedKotohogi': 280}
        self.assertEqual(events.preview(seen_both)['rumorDialogue'], rumor)
        self.assertIsNone(events.preview(seen_both)['wishDialogue'])
        read_rumor = {**seen_both, 'rumorSeen': True}
        self.assertIsNone(events.preview(read_rumor)['rumorDialogue'])
        self.assertIsNotNone(events.preview(read_rumor)['wishDialogue'])
        self.assertIsNone(events.preview({**seen_90, 'now': '2026-10-25T12:00'})['rumorDialogue'])
        with self.assertRaisesRegex(ValueError, '噂の既読状態'):
            events.preview({**seen_90, 'rumorSeen': 'yes'})

    def test_wish_conversation_uses_earned_kotohogi_and_read_state(self):
        doc = events.load()
        special = doc['stages']['joined']['specialConversation']
        self.assertEqual(special['unlockAfterKotohogi'], 120)
        self.assertEqual(special['id'], 'oyasumi_joined_wish_001')
        self.assertEqual([t['speaker'] for t in special['turns']],
                         [events.FROG, events.HOST, events.FROG,
                          events.HOST, events.FROG])
        self.assertEqual(special['turns'][1]['text'],
                         'もふ～。毎日ひなたぼっこしたいもふ。\n'
                         'あと…あしたも、かえるくんがくるといいもふ')
        self.assertEqual(special['turns'][-1]['text'],
                         '（……おかねもちになりたいなんて、いえない）')
        base = dict(config=doc, completed=3, lastNight='2026-10-20',
                    lastKotohogi=160, earnedKotohogi=270,
                    now='2026-10-25T19:00',
                    owned=[events.HOST, events.FROG],
                    parkCleanerStarted=True, rumorSeen=True)
        self.assertIsNone(events.preview(base)['wishDialogue'])
        at_threshold = {**base, 'earnedKotohogi': 280}
        self.assertEqual(events.preview(at_threshold)['wishDialogue'], special)
        self.assertIsNone(events.preview({**at_threshold, 'wishSeen': True})['wishDialogue'])
        self.assertIsNone(events.preview({**at_threshold, 'now': '2026-10-25T12:00'})['wishDialogue'])
        self.assertIsNone(events.preview({**at_threshold, 'completed': 2})['wishDialogue'])
        self.assertIsNone(events.preview({**at_threshold, 'owned': [events.HOST]})['wishDialogue'])
        old = {**at_threshold, 'lastKotohogi': None,
               'earnedKotohogi': 120}
        self.assertEqual(events.preview(old)['wishDialogue'], special)
        with self.assertRaisesRegex(ValueError, '既読状態'):
            events.preview({**at_threshold, 'wishSeen': 'false'})

    def test_invalid_wish_configuration_fails_before_save(self):
        valid = events.load()
        alterations = [
            lambda d: d['stages']['joined']['specialConversation'].update(
                unlockAfterKotohogi=115),
            lambda d: d['stages']['joined']['specialConversation'].update(
                unlockAfterKotohogi=True),
            lambda d: d['stages']['joined']['specialConversation'].update(
                turns=d['stages']['joined']['specialConversation']['turns'][:1]),
            lambda d: d['stages']['joined']['specialConversation']['turns'][0].update(
                speaker=events.HOST),
            lambda d: d['stages']['joined']['specialConversation']['turns'][1].update(
                speaker='not_a_resident'),
            lambda d: d['stages']['joined']['specialConversation'].update(
                turns=d['stages']['joined']['specialConversation']['turns']*2),
            lambda d: d['stages']['joined']['specialConversation'].update(
                id='changed'),
            lambda d: d['stages']['joined']['rumorConversation'].update(
                unlockAfterKotohogi=120),
            lambda d: d['stages']['joined']['rumorConversation'].update(
                unlockAfterKotohogi='90'),
            lambda d: d['stages']['joined']['rumorConversation'].update(
                turns=d['stages']['joined']['rumorConversation']['turns'][:1]),
            lambda d: d['stages']['joined']['rumorConversation'].update(
                turns=d['stages']['joined']['rumorConversation']['turns']*2),
            lambda d: d['stages']['joined']['rumorConversation']['turns'][0].update(
                speaker=events.HOST),
            lambda d: d['stages']['joined']['parkCleanerConversation'].update(
                unlockAfterKotohogi=95),
            lambda d: d['stages']['joined']['parkCleanerConversation'].update(
                id='incorrect'),
            lambda d: d['stages']['joined']['parkCleanerConversation'].update(
                turns=d['stages']['joined']['parkCleanerConversation']['turns'][:1]),
            lambda d: d['stages']['joined']['parkCleanerConversation']['turns'][0].update(
                speaker=events.HOST),
            lambda d: d['stages']['joined']['resignationConversation'].update(
                unlockAfterKotohogi=65),
            lambda d: d['stages']['joined']['resignationConversation'].update(
                id='wrong'),
            lambda d: d['stages']['joined']['resignationConversation'].update(
                turns=[]),
            lambda d: d['stages']['joined']['resignationConversation']['turns'][0].update(
                speaker=events.HOST),
        ]
        for alter in alterations:
            with self.subTest(alter=alter):
                doc = copy.deepcopy(valid)
                alter(doc)
                with self.assertRaises(ValueError):
                    events.validate(doc)

    def test_special_dialogues_allow_different_lengths_and_repeated_speakers(self):
        original = events.load()
        for rumor_length, wish_length in ((2, 3), (3, 6), (6, 2)):
            with self.subTest(rumor_length=rumor_length, wish_length=wish_length):
                doc = copy.deepcopy(original)
                joined = doc['stages']['joined']
                rumor = joined['rumorConversation']['turns']
                wish = joined['specialConversation']['turns']
                joined['rumorConversation']['turns'] = [
                    rumor[0], *([rumor[1]] * (rumor_length - 1))]
                joined['specialConversation']['turns'] = [
                    wish[0], *([wish[1]] * (wish_length - 1))]
                events.validate(doc)
                rendered = events.generated(doc)
                self.assertIn('oyasumi_joined_wish_001', rendered)
                preview = events.preview(dict(
                    config=doc, completed=3, lastNight='2026-10-20',
                    lastKotohogi=160, earnedKotohogi=280,
                    now='2026-10-25T19:00',
                    owned=[events.HOST, events.FROG],
                    parkCleanerStarted=True, rumorSeen=True))
                self.assertEqual(
                    len(preview['wishDialogue']['turns']), wish_length)

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
        self.assertEqual(len(joined),4)
        park=joined[1]['turns']
        today=joined[2]['turns']
        self.assertEqual([t['speaker'] for t in park], [frog,host])
        self.assertEqual([t['speaker'] for t in today], [frog,host,frog,host,frog])
        self.assertEqual(park[0]['text'],'おやすみくん、今日は公園を二周したんだ！')
        self.assertFalse(any('今日は何してた？' in turn['text'] for turn in park))
        self.assertEqual(today[0]['text'],'おやすみくん、今日は何してた？')
        self.assertIn('かえるくんをまってた',today[1]['text'])
        self.assertIn('待ってないじゃん',today[-1]['text'])
        reunion=joined[-1]['turns']
        self.assertEqual([turn['speaker'] for turn in reunion],
                         [frog, frog, frog, host])
        self.assertIn('会いに来たんだけど', reunion[1]['text'])
        self.assertIn('起こさないでおこうね', reunion[2]['text'])
        self.assertIn('……すぅ……もふ……', reunion[-1]['text'])
        self.assertEqual(
            self.preview(3,'2026-10-19')['dialogues'][frog][-1]['turns'],
            reunion)
        resignation=doc['stages']['joined']['resignationConversation']['turns']
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
        self.assertNotIn(
            resignation, self.preview(3,'2026-10-19')['dialogues'][frog])
        self.assertFalse(self.preview(3,'2026-10-19',
                                      now='2026-10-20T12:00')['active'])
        self.assertNotIn('辞め',doc['stages']['joining']['intro']['text'])
        self.assertIn('会社を辞め',doc['restingDialogue'][0])
        self.assertTrue(any(not isinstance(x,str) for x in doc['restingDialogue']))
        # The existing stage progression contract must remain unchanged.
        self.assertEqual(self.preview(2,'2026-10-19')['stage'],'joining')
        self.assertEqual(self.preview(3,'2026-10-19')['stage'],'joined')

    def test_park_cleaner_replaces_all_post_club_daytime_lines(self):
        doc=events.load()
        self.assertEqual(len(doc['restingDialogue']),7)
        self.assertEqual(len(doc['cleanerDialogue']),6)
        self.assertIn('筋肉痛',doc['restingDialogue'][5])
        cleaner=doc['cleanerDialogue'][4]
        self.assertEqual(cleaner['turns'][-1]['text'],'ぼくはこうえんじゃないもふ！！')
        base={'config':doc,'completed':3,'lastNight':'2026-10-19',
              'now':'2026-10-20T12:00','owned':[events.HOST,events.FROG],
              'peers':[events.HOST]}
        waiting=events.preview(base)['restingOptions']
        employed=events.preview({**base,'parkCleanerStarted':True})['restingOptions']
        self.assertIn(doc['restingDialogue'][0],waiting)
        self.assertNotIn(doc['restingDialogue'][0],employed)
        self.assertIn(doc['cleanerDialogue'][0],employed)
        self.assertNotIn(doc['cleanerDialogue'][0],waiting)
        self.assertNotIn(cleaner,waiting)
        self.assertIn(cleaner,employed)
        self.assertNotIn(cleaner,events.preview({**base,'parkCleanerStarted':True,'peers':[]})['restingOptions'])
        relaxed=doc['restingDialogue'][-1]
        self.assertIn('気が楽',relaxed['turns'][0]['text'])
        self.assertIn(relaxed,waiting)
        self.assertNotIn(relaxed,events.preview({**base,'peers':[]})['restingOptions'])
        # Every occupation has some solo dialogue when a friend is away.
        self.assertTrue(events.preview({**base,'parkCleanerStarted':True,'peers':[]})['restingOptions'])
        with self.assertRaises(ValueError):
            events.preview({**base,'parkCleanerStarted':'yes'})
        invalid=copy.deepcopy(doc)
        invalid['cleanerDialogue'][4]['requires']='parkCleaner'
        with self.assertRaises(ValueError):events.validate(invalid)
        invalid=copy.deepcopy(doc)
        invalid['stages']['joined']['chatter'][events.FROG][0]['requires']='parkCleaner'
        with self.assertRaises(ValueError):events.validate(invalid)
        invalid=copy.deepcopy(doc)
        invalid['restingDialogue']=['one','two','three']*3
        with self.assertRaises(ValueError):events.validate(invalid)
        invalid=copy.deepcopy(doc)
        invalid['cleanerDialogue']=[{'turns':[
            {'speaker':events.FROG,'text':'話しかけるだけ'},
            {'speaker':events.HOST,'text':'もふ'}]}]*3
        with self.assertRaisesRegex(ValueError,'一人で話せる'):events.validate(invalid)

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
        extra=tea['extraDialogue']
        self.assertEqual(extra['id'],'oyasumi_tea_visit_food_friends')
        self.assertEqual(extra['label'],'たべられなかま')
        self.assertEqual([turn['speaker'] for turn in extra['turns']],
                         [events.FROG,events.HOST,events.TONKO])
        self.assertEqual(extra['turns'][-1]['text'],
                         'わかるわぁ……つらいわよね……')
        base=dict(config=doc,completed=3,lastNight='2026-10-20',
                  lastKotohogi=100,earnedKotohogi=130,
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
            {'earnedKotohogi':100},
            {'earnedKotohogi':120},
            {'earnedKotohogi':160},
            {'now':'2026-10-21T12:00'},
            {'marcheOpen':False},
            {'owned':[events.HOST,events.FROG]},
            {'owned':[events.HOST,events.TONKO]},
            {'completed':2},
        ]:
            params={**base,**change}
            self.assertIsNone(events.preview(params)['teaVisit'],params)
        self.assertEqual(events.preview({**base,'now':'2026-10-24T19:00'})['passersby'],[events.TONKO])
        self.assertEqual(events.preview({**base,'earnedKotohogi':220})['passersby'],[events.TONKO])
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
            lambda d:d['teaVisit']['extraDialogue'].update(id='incorrect'),
            lambda d:d['teaVisit']['extraDialogue'].update(turns=[]),
            lambda d:d['teaVisit']['extraDialogue']['turns'][0].update(speaker=events.TONKO),
            lambda d:d['teaVisit']['extraDialogue']['turns'][1].update(speaker='unknown'),
        ]:
            invalid=copy.deepcopy(doc);change(invalid)
            with self.assertRaises(ValueError):events.validate(invalid)
        with self.assertRaises(ValueError):
            events.preview({**base,'marcheOpen':'yes'})

    def test_preview_never_saves(self):
        with patch.object(events,'commit_files',side_effect=AssertionError('preview wrote data')):
            self.preview();self.preview(3,'2026-10-19')

if __name__=='__main__':unittest.main()
