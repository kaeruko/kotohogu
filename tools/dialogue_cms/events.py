"""Editable club specification and deterministic, save-free CMS preview."""
import json
from datetime import datetime, timedelta
from pathlib import Path
from characters import commit_files, load_catalog

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'assets/events/oyasumi_club.json'
DART = ROOT / 'lib/oyasumi_config.g.dart'
STAGES = ('solo', 'watching', 'joining', 'joined')
KOTOHOGI_PER_STORY_DAY = 30
HOST, FROG, MOSA, TONKO = '027_daydreamer', '029_office_worker', '036_mosa', '041_pig_middle'


def load():
    return validate(json.loads(DATA.read_text(encoding='utf-8')))


def validate(doc):
    if not isinstance(doc, dict) or set(doc) != {'version','id','label','night','background','stages','restingDialogue','cleanerDialogue','nightPatrol','teaVisit'}:
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
    def lines(items, speaker, allowed, *, max_patterns=4):
        if not isinstance(items,list) or not 3 <= len(items) <= max_patterns:
            raise ValueError(f'繰り返し会話は3〜{max_patterns}本で設定してください')
        has_solo = False
        for item in items:
            if isinstance(item,str):
                text(item)
                has_solo = True
                continue
            if not isinstance(item,dict) or set(item) != {'turns'} or not isinstance(item['turns'],list) or not 1 <= len(item['turns']) <= 8:
                raise ValueError('掛け合いは1〜8発言の順番で登録してください')
             turns = item['turns']
            for index,turn in enumerate(turns):
                if not isinstance(turn,dict) or set(turn) != {'speaker','text'} or not isinstance(turn['speaker'],str) or turn['speaker'] not in allowed or (index==0 and turn['speaker']!=speaker):
                    raise ValueError('掛け合いの話者が不正です')
                text(turn['text'])
            if len(turns)==1 and turns[0]['speaker']==speaker:
                has_solo=True
        return has_solo
    for key in STAGES:
        stage = doc['stages'][key]
        required = {'label','positions','intro','chatter'}
        if key == 'joined':
            required.update({'specialConversation','rumorConversation','parkCleanerConversation'})
        if not isinstance(stage,dict) or set(stage) != required:
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
            wish = stage['specialConversation']
            if (not isinstance(wish,dict) or
                    set(wish) != {'id','unlockAfterKotohogi','turns'} or
                    wish['id'] != 'oyasumi_joined_wish_001'):
                raise ValueError('願いごと会話の設定が不正です')
            threshold = wish['unlockAfterKotohogi']
            if type(threshold) is not int or not 10 <= threshold <= 3000 or threshold % 10:
                raise ValueError('願いごとの解放条件は10刻みの累積ことほぎにしてください')
            turns = wish['turns']
            if not isinstance(turns,list) or not 2 <= len(turns) <= 6:
                raise ValueError('願いごとの会話は2〜6発言で設定してください')
            for i,turn in enumerate(turns):
                if (not isinstance(turn,dict) or set(turn) != {'speaker','text'} or
                        turn['speaker'] not in (FROG,HOST) or
                        (i==0 and turn['speaker'] != FROG)):
                    raise ValueError('願いごとの話者が不正です')
                text(turn['text'])
            rumor = stage['rumorConversation']
            if (not isinstance(rumor,dict) or
                    set(rumor) != {'id','unlockAfterKotohogi','turns'} or
                    rumor['id'] != 'oyasumi_joined_kotohoguma_rumor_001'):
                raise ValueError('コトホグマの噂の設定が不正です')
            rumor_threshold = rumor['unlockAfterKotohogi']
            if (type(rumor_threshold) is not int or
                    rumor_threshold < 10 or rumor_threshold % 10 or
                    rumor_threshold >= threshold):
                raise ValueError('コトホグマの噂は願いごとより先の累積ことほぎで解放してください')
            rumor_turns = rumor['turns']
            if not isinstance(rumor_turns,list) or not 2 <= len(rumor_turns) <= 6:
                raise ValueError('コトホグマの噂は2〜6発言で設定してください')
            for i,turn in enumerate(rumor_turns):
                if (not isinstance(turn,dict) or set(turn) != {'speaker','text'} or
                        turn['speaker'] not in (FROG,HOST) or
                        (i==0 and turn['speaker'] != FROG)):
                    raise ValueError('コトホグマの噂の話者が不正です')
                text(turn['text'])
            cleaner = stage['parkCleanerConversation']
            if (not isinstance(cleaner,dict) or
                    set(cleaner) != {'id','unlockAfterKotohogi','turns'} or
                    cleaner['id'] != 'frog_park_cleaner_started'):
                raise ValueError('おそうじやさん就職会話の設定が不正です')
            cleaner_threshold = cleaner['unlockAfterKotohogi']
            if (type(cleaner_threshold) is not int or
                    cleaner_threshold < 10 or cleaner_threshold % 10 or
                    cleaner_threshold >= rumor_threshold):
                raise ValueError('就職会話はコトホグマの噂より先の累積ことほぎで解放してください')
            cleaner_turns = cleaner['turns']
            if not isinstance(cleaner_turns,list) or not 2 <= len(cleaner_turns) <= 6:
                raise ValueError('おそうじやさん就職会話は2〜6発言で設定してください')
            for i,turn in enumerate(cleaner_turns):
                if (not isinstance(turn,dict) or set(turn) != {'speaker','text'} or
                        turn['speaker'] not in (FROG,HOST) or
                        (i==0 and turn['speaker'] != FROG)):
                    raise ValueError('就職会話の話者が不正です')
                text(turn['text'])
        else:
            intro=stage['intro']
            if not isinstance(intro,dict) or set(intro) != {'speaker','text'} or intro['speaker'] != (HOST if key=='solo' else FROG):
                raise ValueError('導入会話の話者が不正です')
            text(intro['text'])
        for speaker,items in stage['chatter'].items():
            # The post-joining frog has one additional resignation story.
            lines(items, speaker, cast,
                  max_patterns=5 if key == 'joined' and speaker == FROG else 4)
    if not lines(doc['restingDialogue'], FROG, outdoor, max_patterns=8):
        raise ValueError('休養中のかえるの会話には一人用を1本以上残してください')
    if not lines(doc['cleanerDialogue'], FROG, outdoor, max_patterns=8):
        raise ValueError('就職後のかえるの会話には一人用を1本以上残してください')
    patrol=doc['nightPatrol']
    if not isinstance(patrol,dict) or set(patrol) != {'residentId','route','dialogues'} or patrol['residentId'] != MOSA:
        raise ValueError('夜回りの住民はモサエド固定です')
    route=patrol['route']
    if not isinstance(route,dict) or set(route) != {'x','y','width','height'} or any(type(v) not in (int,float) or not 0<=v<=.82 for v in route.values()) or route['x']+route['width']>.86 or route['y']+route['height']>.82:
        raise ValueError('夜回りの経路は歩行可能範囲に設定してください')
    if not isinstance(patrol['dialogues'],list) or not 1<=len(patrol['dialogues'])<=4:
        raise ValueError('夜回りの独り言は1〜4本で設定してください')
    for line in patrol['dialogues']: text(line)
    tea=doc['teaVisit']
    if not isinstance(tea,dict) or set(tea) != {'label','residentId','intervalNights','position','turns','extraDialogue'} or tea['residentId'] != TONKO:
        raise ValueError('とんこの差し入れイベントが不正です')
    text(tea['label'])
    if type(tea['intervalNights']) is not int or not 1 <= tea['intervalNights'] <= 30:
        raise ValueError('差し入れの間隔は1〜30夜で指定してください')
    pos=tea['position']
    if not isinstance(pos,list) or len(pos)!=2 or any(type(v) not in (int,float) or not .1 <= v <= .85 for v in pos):
        raise ValueError('差し入れの位置が不正です')
    turns=tea['turns']
    if not isinstance(turns,list) or not 3 <= len(turns) <= 8:
        raise ValueError('差し入れの会話は3〜8発言で指定してください')
    speakers=[]
    for i,turn in enumerate(turns):
        if not isinstance(turn,dict) or set(turn) != {'speaker','text'} or turn['speaker'] not in (TONKO,HOST,FROG) or (i==0 and turn['speaker']!=TONKO):
            raise ValueError('差し入れの話者が不正です')
        text(turn['text'])
        speakers.append(turn['speaker'])
    if not {TONKO,HOST,FROG}.issubset(speakers):
        raise ValueError('差し入れの会話は3人の発言が必要です')
    extra=tea['extraDialogue']
    if (not isinstance(extra,dict) or set(extra) != {'id','label','turns'} or
            extra['id'] != 'oyasumi_tea_visit_food_friends'):
        raise ValueError('たべられなかまの設定が不正です')
    text(extra['label'])
    food_turns=extra['turns']
    if not isinstance(food_turns,list) or not 3 <= len(food_turns) <= 6:
        raise ValueError('たべられなかまの会話は3〜6発言で設定してください')
    food_speakers=[]
    for i,turn in enumerate(food_turns):
        if (not isinstance(turn,dict) or set(turn) != {'speaker','text'} or
                turn['speaker'] not in (TONKO,HOST,FROG) or
                (i == 0 and turn['speaker'] != FROG)):
            raise ValueError('たべられなかまの話者が不正です')
        text(turn['text'])
        food_speakers.append(turn['speaker'])
    if not {TONKO,HOST,FROG}.issubset(food_speakers):
        raise ValueError('たべられなかまには3人の発言が必要です')
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
    earned=payload.get('earnedKotohogi',0)
    milestone=payload.get('lastKotohogi')
    if type(earned) is not int or earned<0 or earned%10:
        raise ValueError('累積ことほぎは10刻みの0以上で入力してください')
    if milestone is not None and (type(milestone) is not int or
            milestone<0 or milestone%10 or milestone>earned or completed==0):
        raise ValueError('最後の読了時の累積ことほぎが不正です')
    if type(completed) is not int or not 0<=completed<=3:
        raise ValueError('進行値が不正です')
    if (completed==0)!=(last is None): raise ValueError('完了段階と最終開催日をセットで指定してください')
    if last: datetime.strptime(last,'%Y-%m-%d')
    owned=payload['owned']
    if not isinstance(owned,list) or any(i not in (HOST,FROG,MOSA,TONKO) for i in owned): raise ValueError('所持設定が不正です')
    marche_open=payload.get('marcheOpen', False)
    if type(marche_open) is not bool:
        raise ValueError('茶房の開店状態が不正です')
    peers=payload.get('peers',[])
    park_cleaner_started=payload.get('parkCleanerStarted', False)
    wish_seen=payload.get('wishSeen', False)
    rumor_seen=payload.get('rumorSeen', False)
    if type(rumor_seen) is not bool:
        raise ValueError('コトホグマの噂の既読状態が不正です')
    if type(wish_seen) is not bool:
        raise ValueError('願いごとの既読状態が不正です')
    if type(park_cleaner_started) is not bool:
        raise ValueError('公園清掃の開始状態が不正です')
    outdoor={c['id'] for c in load_catalog()['characters'] if c['walkInTown'] and c['homeAreaId']!='salon'}
    if not isinstance(peers,list) or any(type(i) is not str or i not in outdoor for i in peers):
        raise ValueError('同席者の設定が不正です')
    night=now.hour>=doc['night']['startHour'] or now.hour<doc['night']['endHour']
    night_key=(now-timedelta(days=1 if now.hour<doc['night']['endHour'] else 0)).strftime('%Y-%m-%d')
    story_days=0 if milestone is None else (earned-milestone)//KOTOHOGI_PER_STORY_DAY
    ready=milestone is None or story_days>=1
    step=1 if FROG not in owned else 4 if completed==3 else (3 if ready else 2) if completed==2 else (2 if ready else 1) if completed==1 else 1
    active=night and HOST in owned
    key=STAGES[step-1]
    stage=doc['stages'][key]
    cast=([HOST]+([FROG] if step>1 and FROG in owned else [])) if active else []
    tea=doc['teaVisit']
    tea_days=story_days if milestone is not None else earned//KOTOHOGI_PER_STORY_DAY
    tea_visible=active and completed==3 and FROG in owned and TONKO in owned and marche_open and tea_days>=1 and (tea_days-1)%tea['intervalNights']==0
    passersby=([MOSA] if active and MOSA in owned else [])+([TONKO] if tea_visible else [])
    positions=({**stage['positions'],
                **({MOSA:[doc['nightPatrol']['route']['x'],doc['nightPatrol']['route']['y']]} if MOSA in passersby else {}),
                **({TONKO:tea['position']} if tea_visible else {})}) if active else {}
    intro=active and step<=3 and completed<step
    remaining=max(0,KOTOHOGI_PER_STORY_DAY-(earned-milestone)) if milestone is not None else 0
    reason=('昼のためクラブはお休みです' if not night else 'おやすみくん未所持のため開催しません' if HOST not in owned else 'かえる未所持：一人のクラブを続けます' if FROG not in owned else '導入会話を最後まで読むと進行します' if intro else f'あと{remaining}ことほぎで次の場面に進めます' if step<4 else '参加後のクラブを続けます')
    def turn_speakers(item):
        return [FROG] if isinstance(item,str) else [turn['speaker'] for turn in item['turns']]
    wish=doc['stages']['joined']['specialConversation']
    rumor=doc['stages']['joined']['rumorConversation']
    cleaner=doc['stages']['joined']['parkCleanerConversation']
    special_ready=(active and key=='joined' and completed==3)
    elapsed=earned-(milestone if milestone is not None else 0)
    cleaner_available=(special_ready and
                       elapsed >= cleaner['unlockAfterKotohogi'] and
                       not park_cleaner_started)
    rumor_available=(special_ready and elapsed >= rumor['unlockAfterKotohogi'] and
                     not rumor_seen and not cleaner_available)
    wish_available=(special_ready and elapsed >= wish['unlockAfterKotohogi'] and
                    not wish_seen and not rumor_available and not cleaner_available)
    daily_lines = doc['cleanerDialogue'] if park_cleaner_started else doc['restingDialogue']
    rest = [
        item for item in daily_lines
        if set(turn_speakers(item)).issubset(set(peers)|{FROG})
    ] if completed==3 and FROG in owned and not active else []
    return dict(active=active,stage=key,label=stage['label'],nightKey=night_key,cast=cast,passersby=passersby,positions=positions,intro=stage['intro'] if intro else None,canComplete=intro,completed=completed,lastNight=last,earnedKotohogi=earned,lastKotohogi=milestone,storyDays=story_days,remainingKotohogi=remaining,reason=reason,frogResting=completed==3 and FROG in owned,background='night' if active else 'day',dialogues=stage['chatter'] if active else {},parkCleanerDialogue=cleaner if cleaner_available else None,rumorDialogue=rumor if rumor_available else None,wishDialogue=wish if wish_available else None,patrolDialogues=doc['nightPatrol']['dialogues'] if MOSA in passersby else [],teaVisit=tea if tea_visible else None,restingOptions=rest,nextCompleted=step if intro else completed)
