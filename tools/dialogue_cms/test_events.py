import copy
import json
import tempfile
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
    def test_preview_never_saves(self):
        with patch.object(events,'commit_files',side_effect=AssertionError('preview wrote data')):
            self.preview();self.preview(3,'2026-10-19')

if __name__=='__main__':unittest.main()
