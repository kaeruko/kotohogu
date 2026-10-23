"""Editable club specification and deterministic, save-free CMS preview."""
import json
from datetime import datetime, timedelta
from pathlib import Path
from characters import commit_files, load_catalog

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'assets/events/oyasumi_club.json'
DART = ROOT / 'lib/oyasumi_config.g.dart'
STAGES = ('solo', 'watching', 'joining', 'joined')
HOST, FROG, MOSA = '027_daydreamer', '029_office_worker', '036_mosa'


def load():
    return validate(json.loads(DATA.read_text(encoding='utf-8')))


def validate(doc):
    if not isinstance(doc, dict) or set(doc) != {'version','id','label','night','background','stages','restingDialogue','nightPatrol'}:
        raise ValueError('イベントの項目が不正です')
    if doc['version'] != 1 or doc['id'] != 'oyasumi_club' or doc['background'] != 'assets/kotohogu/town_background_night.jpg':
        raise ValueError('イベントID・背景は固定です')
    def text(value):
        if not isinstance(value, str) or not 1 <= len(value.strip()) <= 500:
            raise ValueError('文章は1〜500文字で入力してください')
    text(doc['label'])
    night = doc['night']
    if not isinstance(night,dict) or set(night) != {'startHour','endHour'} or any(type(v) is not int for v in night.values()) or not 12 <= night['startHour'] <= 23 or not 1 <= night['endHour'] <= 11:
        raise ValueError('開始は12〜23時、終了は翌1〜11時で指定してください')
    if not isinstance(doc['stages'],dict) or set(doc['stages']) != set(STAGES):
        raise ValueError('物語の4段階は固定です')
    outdoor = {
        row['id'] for row in load_catalog()['characters']
        if row['walkInTown'] and row['homeAreaId'] != 'salon'
    }
    def lines(items, speaker, allowed, *, max_patterns=4, job_gate=False):
        if not isinstance(items,list) or not 3 <= len(items) <= max_patterns:
            raise ValueError(f'繰り返し会話は3〜{max_patterns}本で設定してください')
        has_solo = False
        for item in items:
            if isinstance(item,str):
                text(item)
                has_solo = True
                continue
            if not isinstance(item,dict) or set(item) not in ({'turns'}, {'turns', 'requires'}) or not isinstance(item['turns'],list) or not 1 <= len(item['turns']) <= 8:
                raise ValueError('掛け合いは1〜8発言の順番で登録してください')
            if 'requires' in item and (not job_gate or item['requires'] != 'parkCleaner'):
                raise ValueError('この掛け合いの表示条件は指定できません')
            turns = item['turns']
            for index,turn in enumerate(turns):
                if not isinstance(turn,dict) or set(turn) != {'speaker','text'} or not isinstance(turn['speaker'],str) or turn['speaker'] not in allowed or (index==0 and turn['speaker']!=speaker):
                    raise ValueError('掛け合いの話者が不正です')
                text(turn['text'])
            if len(turns)==1 and turns[0]['speaker']==speaker and not item.get('requires'):
                has_solo=True
        return has_solo
    for key in STAGES:
        stage = doc['stages'][key]
        if not isinstance(stage,dict) or set(stage) != {'label','positions','intro','chatter'}:
            raise ValueError('段階の項目が不正です')
        text(stage['label'])
        cast = {HOST} if key == 'solo' else {HOST,FROG}
        if set(stage['positions']) != cast or set(stage['chatter']) != cast:
            raise ValueError('出演者はこの段階では変更できません')
        for position in stage['positions'].values():
            if not isinstance(position,list) or len(position)!=2 or any(type(v) not in (int,float) or not .1 <= v <= .85 for v in position):
                raise ValueError('配置は画面内の0.1〜0.85で指定してください')
        if key == 'joined':
            if stage['intro'] is not None: raise ValueError('参加後に導入会話はありません')
        else:
            intro=stage['intro']
            if not isinstance(intro,dict) or set(intro) != {'speaker','text'} or intro['speaker'] != (HOST if key=='solo' else FROG):
                raise ValueError('導入会話の話者が不正です')
            text(intro['text'])
        for speaker,items in stage['chatter'].items():
            # The post-joining frog has one additional resignation story.
            lines(items, speaker, cast,
                  max_patterns=5 if key == 'joined' and speaker == FROG else 4)
    if not lines(doc['restingDialogue'], FROG, outdoor, max_patterns=8, job_gate=True):
        raise ValueError('昼のかえるの会話には、一人で話せる候補を1本以上残してください')
    patrol=doc['nightPatrol']
    if not isinstance(patrol,dict) or set(patrol) != {'residentId','route','dialogues'} or patrol['residentId'] != MOSA:
        raise ValueError('夜回りの住民はモサエド固定です')
    route=patrol['route']
    if not isinstance(route,dict) or set(route) != {'x','y','width','height'} or any(type(v) not in (int,float) or not 0<=v<=.82 for v in route.values()) or route['x']+route['width']>.86 or route['y']+route['height']>.82:
        raise ValueError('夜回りの経路は歩行可能範囲に設定してください')
    if not isinstance(patrol['dialogues'],list) or not 1<=len(patrol['dialogues'])<=4:
        raise ValueError('夜回りの独り言は1〜4本で設定してください')
    for line in patrol['dialogues']: text(line)
    return doc


def generated(doc):
    # JSON string nested in a Dart string: no interpolation or delimiter injection.
    encoded=json.dumps(json.dumps(doc,ensure_ascii=False),ensure_ascii=False).replace('$',r'\$')
    return "// Generated by the event CMS. Edit assets/events/oyasumi_club.json.\nimport 'dart:convert';\nfinal Map<String, dynamic> oyasumiConfig = jsonDecode("+encoded+") as Map<String, dynamic>;\n"


def save(doc):
    validate(doc)
    commit_files({DATA:json.dumps(doc,ensure_ascii=False,indent=2)+'\n',DART:generated(doc)})


def preview(payload):
    doc=validate(payload['config'])
    now=datetime.fromisoformat(payload['now'])
    completed=payload['completed']
    last=payload.get('lastNight') or None
    if type(completed) is not int or not 0<=completed<=3:
        raise ValueError('進行値が不正です')
    if (completed==0)!=(last is None): raise ValueError('完了段階と最終開催日をセットで指定してください')
    if last: datetime.strptime(last,'%Y-%m-%d')
    owned=payload['owned']
    if not isinstance(owned,list) or any(i not in (HOST,FROG,MOSA) for i in owned): raise ValueError('所持設定が不正です')
    peers=payload.get('peers',[])
    park_cleaner_started=payload.get('parkCleanerStarted', False)
    if type(park_cleaner_started) is not bool:
        raise ValueError('公園清掃の開始状態が不正です')
    outdoor={c['id'] for c in load_catalog()['characters'] if c['walkInTown'] and c['homeAreaId']!='salon'}
    if not isinstance(peers,list) or any(type(i) is not str or i not in outdoor for i in peers):
        raise ValueError('同席者の設定が不正です')
    night=now.hour>=doc['night']['startHour'] or now.hour<doc['night']['endHour']
    night_key=(now-timedelta(days=1 if now.hour<doc['night']['endHour'] else 0)).strftime('%Y-%m-%d')
    later=last is None or night_key>last
    step=1 if FROG not in owned else 4 if completed==3 else (3 if later else 2) if completed==2 else (2 if later else 1) if completed==1 else 1
    active=night and HOST in owned
    key=STAGES[step-1]
    stage=doc['stages'][key]
    cast=([HOST]+([FROG] if step>1 and FROG in owned else [])) if active else []
    passersby=[MOSA] if active and MOSA in owned else []
    positions=({**stage['positions'], **({MOSA:[doc['nightPatrol']['route']['x'],doc['nightPatrol']['route']['y']]} if passersby else {})}) if active else {}
    intro=active and step<=3 and completed<step
    reason=('昼のためクラブはお休みです' if not night else 'おやすみくん未所持のため開催しません' if HOST not in owned else 'かえる未所持：一人のクラブを続けます' if FROG not in owned else '今夜の導入会話を読み終えると進行します' if intro else '次の開催夜を待っています' if step<4 else '参加後のクラブを続けます')
    def turn_speakers(item):
        return [FROG] if isinstance(item,str) else [turn['speaker'] for turn in item['turns']]
    rest = [
        item for item in doc['restingDialogue']
        if (not isinstance(item, dict) or item.get('requires') != 'parkCleaner' or park_cleaner_started)
        and set(turn_speakers(item)).issubset(set(peers)|{FROG})
    ] if completed==3 and FROG in owned and not active else []
    return dict(active=active,stage=key,label=stage['label'],nightKey=night_key,cast=cast,passersby=passersby,positions=positions,intro=stage['intro'] if intro else None,canComplete=intro and later,completed=completed,lastNight=last,reason=reason,frogResting=completed==3 and FROG in owned,background='night' if active else 'day',dialogues=stage['chatter'] if active else {},patrolDialogues=doc['nightPatrol']['dialogues'] if passersby else [],restingOptions=rest,nextCompleted=step if intro and later else completed)
