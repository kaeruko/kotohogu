import copy
import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
import timed_events

class TimedEventTests(unittest.TestCase):
    def test_generated_matches_config(self):
        self.assertEqual(timed_events.DART.read_text(encoding='utf-8'),
                         timed_events.generated(timed_events.load()))

    def test_morning_park_empty_without_gonsuke_and_only_gonsuke_when_owned(self):
        doc = timed_events.load()
        common = {'config': doc, 'areaId': 'park', 'owned': ['001_shiba'],
                  'ordinary': ['001_shiba']}
        morning = timed_events.preview({**common, 'now':'2026-10-23T06:00'})
        self.assertEqual(morning['activeId'], 'morning_exercises')
        self.assertEqual(morning['visible'], [])
        self.assertEqual(morning['mode'], 'replace')
        owned = timed_events.preview({**common,
            'owned': ['001_shiba', '042_senior_dog'],
            'now':'2026-10-23T06:00'})
        self.assertEqual(owned['visible'], ['042_senior_dog'])
        afternoon = timed_events.preview({**common, 'now':'2026-10-23T09:00'})
        self.assertEqual(afternoon['visible'], ['001_shiba'])

    def test_night_crosses_midnight_and_weekday_anchors(self):
        schedule = {'start':'18:00','end':'05:00','weekdays':[5]}
        self.assertTrue(timed_events.occurs(schedule, datetime(2026,10,23), 1080))
        self.assertTrue(timed_events.occurs(schedule, datetime(2026,10,24), 299))
        self.assertFalse(timed_events.occurs(schedule, datetime(2026,10,24), 300))
        self.assertFalse(timed_events.occurs(schedule, datetime(2026,10,24), 1080))

    def test_rejects_invalid_data_and_conflicts(self):
        for mutate in [
            lambda d: d['events'][0]['schedule'].update(end='06:00', start='06:00'),
            lambda d: d['events'][0]['schedule'].update(end='25:00'),
            lambda d: d['events'][0]['schedule'].update(weekdays=[1,1]),
            lambda d: d['events'][0]['residents'][0].update(x=float('nan')),
            lambda d: d['events'][0]['residents'][0].update(residentId='unknown'),
            lambda d: d['events'].append(dict(d['events'][0], id='second')),
        ]:
            data = copy.deepcopy(timed_events.load()); mutate(data)
            with self.assertRaises(ValueError):
                timed_events.validate(data)

    def test_saves_json_and_generated_dart_atomically(self):
        data=copy.deepcopy(timed_events.load())
        data['events'][0]['label']='朝の体操と$おしゃべり'
        with tempfile.TemporaryDirectory() as d:
            doc, dart = Path(d)/'events.json', Path(d)/'events.g.dart'
            doc.write_text('{}', encoding='utf-8')
            dart.write_text('old', encoding='utf-8')
            with patch.object(timed_events, 'DATA', doc), patch.object(timed_events, 'DART', dart):
                timed_events.save(data)
            self.assertEqual(json.loads(doc.read_text(encoding='utf-8')), data)
            self.assertEqual(dart.read_text(encoding='utf-8'), timed_events.generated(data))
            self.assertIn(r'\$おしゃべり', dart.read_text(encoding='utf-8'))
