"""Time-window town events shared with Flutter through a generated Dart catalog."""
import json
import math
import re
from datetime import datetime, timedelta
from pathlib import Path
from characters import commit_files, load_catalog

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'assets/events/timed_events.json'
DART = ROOT / 'lib/timed_events_config.g.dart'
AREAS = {'plaza', 'park', 'shopping', 'village', 'hospital'}
MODES = {'replace', 'add', 'exclude'}


def clock(value):
    if not isinstance(value, str) or not re.fullmatch(r'(?:[01][0-9]|2[0-3]):[0-5][0-9]', value):
        raise ValueError('時刻はHH:mm（00:00〜23:59）で指定してください')
    return int(value[:2]) * 60 + int(value[3:])


def occurs(schedule, day, minute):
    start, end = clock(schedule['start']), clock(schedule['end'])
    active = start <= minute < end if start < end else minute >= start or minute < end
    if not active:
        return False
    anchor = day - timedelta(days=1 if start > end and minute < end else 0)
    return not schedule['weekdays'] or anchor.isoweekday() in schedule['weekdays']


def validate(doc):
    if not isinstance(doc, dict) or set(doc) != {'version', 'events'} or type(doc['version']) is not int or doc['version'] != 1:
        raise ValueError('時限イベントのデータ形式が不正です')
    rows = doc['events']
    if not isinstance(rows, list) or len(rows) > 30:
        raise ValueError('イベント数は最大30件です')
    active_ids = {row['id'] for row in load_catalog()['characters'] if not row.get('archived')}
    event_ids = set()
    for event in rows:
        base_fields = {'id', 'label', 'areaId', 'schedule', 'mode', 'requiresOwned', 'residents'}
        if not isinstance(event, dict) or set(event) not in (base_fields, base_fields | {'hostResidentId'}):
            raise ValueError('イベントの項目が不正です')
        event_id = event['id']
        if not isinstance(event_id, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', event_id) or event_id in event_ids:
            raise ValueError('イベントIDは英小文字・数字・_のみで重複不可です')
        event_ids.add(event_id)
        if not isinstance(event['label'], str) or not 1 <= len(event['label'].strip()) <= 100:
            raise ValueError('イベント名は1〜100文字にしてください')
        if event['areaId'] not in AREAS or event['mode'] not in MODES or type(event['requiresOwned']) is not bool:
            raise ValueError('開催場所・表示方法・所持条件が不正です')
        schedule = event['schedule']
        if not isinstance(schedule, dict) or set(schedule) != {'start', 'end', 'weekdays'}:
            raise ValueError('開催日時の項目が不正です')
        start, end = clock(schedule['start']), clock(schedule['end'])
        if start == end:
            raise ValueError('開始時刻と終了時刻は異なる値にしてください')
        days = schedule['weekdays']
        if not isinstance(days, list) or any(type(day) is not int or day < 1 or day > 7 for day in days) or len(set(days)) != len(days):
            raise ValueError('曜日は月曜=1〜日曜=7を重複なく指定してください')
        participants = event['residents']
        if not isinstance(participants, list) or not 1 <= len(participants) <= 8:
            raise ValueError('出演者は1〜8人にしてください')
        seen = set()
        for p in participants:
            participant_fields = {'residentId', 'x', 'y', 'stay'}
            if (not isinstance(p, dict) or
                    set(p) not in (participant_fields, participant_fields | {'stepInPlace'}) or
                    p['residentId'] not in active_ids):
                raise ValueError('出演者は有効なキャラクターから選択してください')
            if p['residentId'] in seen:
                raise ValueError('出演者の重複はできません')
            seen.add(p['residentId'])
            if any(type(p[k]) not in (int, float) or not math.isfinite(p[k]) or not 0 <= p[k] <= .82 for k in ('x', 'y')) or type(p['stay']) is not bool:
                raise ValueError('位置は0〜0.82の数値、待機は真偽値にしてください')
            if ('stepInPlace' in p and type(p['stepInPlace']) is not bool) or (p.get('stepInPlace', False) and not p['stay']):
                raise ValueError('足踏みには「その場にいる」を指定してください')
        if 'hostResidentId' in event:
            host = event['hostResidentId']
            if type(host) is not str or host not in seen or event['mode'] == 'exclude':
                raise ValueError('中心となる住民はイベント出演者から選択してください')
    # Reject overlap in the same area; runtime checks also fail fast if edited externally.
    monday = datetime(2026, 10, 19)
    for offset in range(7):
        day = monday + timedelta(days=offset)
        for minute in range(1440):
            occupied = set()
            for event in rows:
                if occurs(event['schedule'], day, minute):
                    area = event['areaId']
                    if area in occupied:
                        raise ValueError('同じ場所・時刻のイベントが重複しています')
                    occupied.add(area)
    return doc


def load():
    return validate(json.loads(DATA.read_text(encoding='utf-8')))


def generated(doc):
    encoded = json.dumps(json.dumps(doc, ensure_ascii=False, separators=(',', ':')), ensure_ascii=False).replace('$', r'\$')
    return ("// Generated by timed_events.py. Edit assets/events/timed_events.json.\n"
            "import 'dart:convert';\n"
            "final Map<String, dynamic> timedEventsConfig = jsonDecode(" + encoded + ") as Map<String, dynamic>;\n")


def save(doc):
    validate(doc)
    commit_files({DATA: json.dumps(doc, ensure_ascii=False, indent=2) + '\n', DART: generated(doc)})


def preview(payload):
    if not isinstance(payload, dict) or set(payload) != {'config', 'now', 'areaId', 'owned', 'ordinary'}:
        raise ValueError('プレビューの入力が不正です')
    doc = validate(payload['config'])
    if not isinstance(payload['now'], str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d', payload['now']):
        raise ValueError('日時はYYYY-MM-DDTHH:mmで指定してください')
    now = datetime.fromisoformat(payload['now'])
    if payload['areaId'] not in AREAS:
        raise ValueError('不明なエリアです')
    active_ids = {row['id'] for row in load_catalog()['characters'] if not row.get('archived')}
    if not isinstance(payload['owned'], list) or not isinstance(payload['ordinary'], list) or any(
            not isinstance(people, str) or people not in active_ids for people in payload['owned'] + payload['ordinary']):
        raise ValueError('プレビューに不明な住民が含まれています')
    if len(set(payload['ordinary'])) != len(payload['ordinary']):
        raise ValueError('通常住民が重複しています')
    minute = now.hour * 60 + now.minute
    current = [
        event for event in doc['events']
        if occurs(event['schedule'], now, minute)
        and (not event['requiresOwned'] or
             set(p['residentId'] for p in event['residents']).issubset(payload['owned']))
    ]
    area = payload['areaId']
    same = [event for event in current if event['areaId'] == area]
    if len(same) > 1:
        raise ValueError('同じ場所・時刻のイベントが重複しています')
    event = same[0] if same else None
    def shown_cast(event):
        if 'hostResidentId' in event and event['hostResidentId'] not in payload['owned']:
            return []
        return [p['residentId'] for p in event['residents'] if p['residentId'] in payload['owned']]

    relocated = {resident for other in current if other['areaId'] != area and other['mode'] != 'exclude' for resident in shown_cast(other)}
    visible = [resident for resident in payload['ordinary'] if resident not in relocated]
    if event:
        cast = shown_cast(event)
        if event['mode'] == 'replace':
            visible = cast
        elif event['mode'] == 'exclude':
            excluded = {p['residentId'] for p in event['residents']}
            visible = [resident for resident in visible if resident not in excluded]
        else:
            visible += [resident for resident in cast if resident not in visible]
    return {'activeId': event['id'] if event else None,
            'activeLabel': event['label'] if event else None,
            'areaId': area, 'visible': visible,
            'mode': event['mode'] if event else None}
