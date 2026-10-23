'use strict';
const $=id=>document.getElementById(id);
const names={'027_daydreamer':'おやすみくん','029_office_worker':'かえる'};
const folders={'027_daydreamer':'027_daydreamer','029_office_worker':'029_office_worker'};
let outdoorResidents=[];
let config,result,revision=0;
const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
async function request(url,options){const response=await fetch(url,options);const data=await response.json();if(!response.ok)throw Error(data.error||'読み込みに失敗しました');return data;}
function change(){ $('saveStatus').textContent='未保存の変更があります';preview(); }
function textField(parent,label,value,onChange){const field=el('label',label),input=el('textarea');input.value=value;input.maxLength=500;input.oninput=()=>{onChange(input.value);change();};field.append(input);parent.append(field);}
// Legacy single-speaker strings remain editable. Adding a turn upgrades only
// that one conversation to {turns:[{speaker,text}, ...]}, not other lines.
const turnsFor=(item,primary)=>typeof item==='string'
  ? [{speaker:primary,text:item}] : item.turns;
function editLines(parent,lines,primary,allowed,{isResting=false,maxNightPatterns=4}={}){
  const limit=isResting?8:maxNightPatterns;
  const permitted=allowed.map(id=>[id,names[id]||id]);
  lines.forEach((item,i)=>{
    const block=el('div');block.className='conversation';
    block.append(el('h4',`会話 ${i+1}（発言の順番）`));
    if(isResting){
      const gateLabel=el('label','');
      const gate=el('input');
      gate.type='checkbox';
      gate.checked=typeof item!=='string'&&item.requires==='parkCleaner';
      gate.onchange=()=>{
        if(gate.checked){
          if(typeof lines[i]==='string'){
            lines[i]={turns:[{speaker:primary,text:lines[i]}]};
          }
          lines[i].requires='parkCleaner';
        }else if(typeof lines[i]!=='string'){
          delete lines[i].requires;
        }
        change();
      };
      gateLabel.append(gate,document.createTextNode(' 公園のおそうじやさんになった後だけ'));
      block.append(gateLabel);
    }
    const turns=turnsFor(item,primary);
    turns.forEach((turn,j)=>{
      const row=el('div');row.className='talk-turn';
      const speakerLabel=el('label',`発言 ${j+1}・話す住民 `);
      if(j===0){
        speakerLabel.append(el('strong',names[primary]||primary));
      } else {
        const selector=el('select');
        for(const [id,name] of permitted){
          const option=el('option',name);option.value=id;selector.append(option);
        }
        selector.value=turn.speaker;
        selector.onchange=()=>{lines[i].turns[j].speaker=selector.value;change();};
        speakerLabel.append(selector);
      }
      row.append(speakerLabel);
      textField(row,`セリフ ${j+1}`,turn.text,v=>{
        if(typeof lines[i]==='string')lines[i]=v;
        else lines[i].turns[j].text=v;
      });
      block.append(row);
    });
    if(turns.length<8){
      const addTurn=el('button','＋ 次の発言を追加');
      addTurn.type='button';addTurn.className='secondary';
      addTurn.onclick=()=>{
        if(typeof lines[i]==='string')lines[i]={turns:[{speaker:primary,text:lines[i]}]};
        const other=allowed.find(id=>id!==primary)||primary;
        lines[i].turns.push({speaker:other,text:'新しいセリフ'});
        renderEditor();change();
      };
      block.append(addTurn);
    }
    if(turns.length>1){
      const removeTurn=el('button','最後の発言を削除');
      removeTurn.type='button';removeTurn.className='secondary';
      removeTurn.onclick=()=>{
        lines[i].turns.pop();
        renderEditor();change();
      };
      block.append(removeTurn);
    }
    parent.append(block);
  });
  const add=el('button',`＋ 会話パターンを追加（最大${limit}本）`);
  add.disabled=lines.length>=limit;
  add.onclick=()=>{lines.push('新しい会話');renderEditor();change();};
  parent.append(add);
  if(lines.length>3){
    const remove=el('button','最後の会話パターンを削除');
    remove.className='secondary';
    remove.onclick=()=>{lines.pop();renderEditor();change();};
    parent.append(remove);
  }
}
function renderEditor(){
  $('stages').replaceChildren();
  Object.entries(config.stages).forEach(([key,stage],i)=>{
    const detail=el('details');detail.open=i===0;
    detail.append(el('summary',`${i+1}. ${stage.label}`));
    if(stage.intro)textField(detail,`${names[stage.intro.speaker]}の導入（進行に必要）`,stage.intro.text,v=>stage.intro.text=v);
    const allowed=Object.keys(stage.chatter);
    Object.entries(stage.chatter).forEach(([id,lines])=>{
      detail.append(el('h3',names[id]||id));
      const row=el('div');row.className='row';
      ['X','Y'].forEach((axis,n)=>{
        const label=el('label',axis+' '),input=el('input');input.type='number';
        input.min='.1';input.max='.85';input.step='.01';
        input.value=stage.positions[id][n];
        input.oninput=()=>{stage.positions[id][n]=Number(input.value);change();};
        label.append(input);row.append(label);
      });
      detail.append(row);
      editLines(detail,lines,id,allowed,{
        maxNightPatterns:(key==='solo'&&id==='027_daydreamer')||(key==='joined'&&id==='029_office_worker')?5:4,
      });
    });
    $('stages').append(detail);
  });
  const patrol=config.nightPatrol;
  const watch=el('details');
  watch.append(el('summary','夜回りのモサエド（通行人・ひとり会話）'));
  const desc=el('p','モサエド所持中は夜の広場を歩きます。おやすみクラブの進行には参加しません。');
  desc.className='hint';watch.append(desc);
  const walk=el('div');walk.className='row';
  for(const axis of ['x','y','width','height']){
    const field=el('label',axis+' '),input=el('input');
    input.type='number';input.min='0';input.max='.82';input.step='.01';
    input.value=patrol.route[axis];
    input.oninput=()=>{patrol.route[axis]=Number(input.value);change();};
    field.append(input);walk.append(field);
  }
  watch.append(walk);
  patrol.dialogues.forEach((line,i)=>textField(watch,`ひとり会話 ${i+1}`,line,value=>{
    patrol.dialogues[i]=value;
  }));
  const addPatrol=el('button','＋ ひとり会話を追加（最大4本）');
  addPatrol.type='button';addPatrol.disabled=patrol.dialogues.length>=4;
  addPatrol.onclick=()=>{patrol.dialogues.push('よまわりでござる！');renderEditor();change();};
  watch.append(addPatrol);
  if(patrol.dialogues.length>1){
    const removePatrol=el('button','最後の会話を削除');
    removePatrol.type='button';removePatrol.className='secondary';
    removePatrol.onclick=()=>{patrol.dialogues.pop();renderEditor();change();};
    watch.append(removePatrol);
  }
  $('stages').append(watch);
  const rest=el('details');
  rest.append(el('summary','参加後のかえる：昼間・通常会話'));
  rest.append(el('p','最初の発言はかえる。次の発言から、やすぞうさん・おやすみくんなどを選べます。同じ場所にいない場合は、その掛け合いを出さず、一人用の会話を使います。'));
  rest.lastChild.className='hint';
  editLines(rest,config.restingDialogue,'029_office_worker',outdoorResidents,{isResting:true});
  $('stages').append(rest);
}
function renderConversation(parent,item,primary,index){
  const block=el('div');block.className='preview-talk';
  block.append(el('strong',`会話 ${index+1}${typeof item!=='string'&&item.requires==='parkCleaner'?'（おそうじやさん就職後）':''}`));
  turnsFor(item,primary).forEach(turn=>
    block.append(el('p',`${names[turn.speaker]||turn.speaker}「${turn.text}」`)));
  parent.append(block);
}
function payload(){return {config,now:$('now').value,completed:Number($('completed').value),lastNight:$('last').value||null,owned:[...($('host').checked?['027_daydreamer']:[]),...($('frog').checked?['029_office_worker']:[]),...($('mosa').checked?['036_mosa']:[])],peers:$('previewPeer').value?[$('previewPeer').value]:[],parkCleanerStarted:$('cleanerStarted').checked};}
async function preview(){
  if(!config)return;
  const version=++revision;$('read').disabled=true;
  try{
    const data=await request('/api/event-preview',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify(payload()),
    });
    if(version!==revision)return;
    result=data;
    $('reason').textContent=data.reason;$('reason').className='';
    $('stageName').textContent=(data.active?data.label:'開催していません')+' ｜ 開催日 '+data.nightKey;
    $('read').disabled=!data.canComplete;
    $('scene').replaceChildren();
    $('scene').style.aspectRatio=data.active?'941/1672':'768/1376';
    const bg=el('img');
    bg.alt=data.active?'夜のひろば':'昼のひろば';
    bg.src=data.active?'/api/event-background':'/api/area-background?id=plaza';
    $('scene').append(bg);
    [...data.cast,...data.passersby].forEach(id=>{
      const image=el('img');image.className='person';image.alt=names[id]||id;
      image.src='/api/runtime/sprites/'+folders[id]+'/idle_front_01.png';
      const [x,y]=data.positions[id],scale=y<.55?1.2:y<.72?1.4:1.5;
      image.style.width=76*scale/941*100+'%';
      image.style.left=(x+(76-76*scale)/2/941)*100+'%';
      image.style.top=(y+(76-76*scale)/1672)*100+'%';
      $('scene').append(image);
    });
    $('dayChange').textContent=data.frogResting
      ? 'かえる：参加後。昼間も休養生活の会話を使います。'
      : 'かえる：通常の会社員の会話です。';
    $('lines').replaceChildren();
    if(data.intro){
      $('lines').append(el('strong',(names[data.intro.speaker]||data.intro.speaker)+'の導入（最初に表示）'),el('p',data.intro.text));
    }
    if(data.patrolDialogues.length){
      const patrol=el('details');patrol.open=true;
      patrol.append(el('summary','モサエドの夜回り（通行人・ひとり会話）'));
      data.patrolDialogues.forEach((item,i)=>renderConversation(patrol,item,'036_mosa',i));
      $('lines').append(patrol);
    }
    Object.entries(data.dialogues).forEach(([id,items])=>{
      const detail=el('details');detail.open=true;
      detail.append(el('summary',(names[id]||id)+'の繰り返し会話'));
      items.forEach((item,index)=>renderConversation(detail,item,id,index));
      $('lines').append(detail);
    });
    if(!data.active && !data.frogResting){
      $('lines').append(el('p','今は会話候補がありません。開催日時と所持状況を確認してください。'));
    }
    if(data.frogResting&&!data.active){
      $('lines').append(el('h3','かえる・昼間の会話候補'));
      (data.restingOptions||[]).forEach((item,i)=>
        renderConversation($('lines'),item,'029_office_worker',i));
      $('lines').append(el('p','ここでは選択した同席者との掛け合いだけを表示。ゲーム内では実際に同じエリアにいる場合だけ候補になります。'));
      $('lines').lastChild.className='hint';
    }
  }catch(error){
    if(version!==revision)return;
    result=null;
    $('reason').textContent='プレビューに失敗しました：'+error.message;
    $('reason').className='error';
    $('stageName').textContent='プレビュー失敗';
    $('scene').replaceChildren();
    $('dayChange').textContent='';
    $('lines').replaceChildren(el('p','会話候補を表示できません。上のエラーを確認してください。'));
  }
}
async function load(){
  try{
    const [event,catalog]=await Promise.all([request('/api/events'),request('/api/characters')]);
    config=event;
    outdoorResidents=catalog.characters.filter(row=>row.walkInTown&&row.homeAreaId!=='salon').map(row=>row.id);
    for(const row of catalog.characters){names[row.id]=row.label;folders[row.id]=row.artFolder;}
    const peer=$('previewPeer'),previous=peer.value;
    peer.replaceChildren();
    const none=el('option','なし（かえる一人）');none.value='';peer.append(none);
    outdoorResidents.filter(id=>id!=='029_office_worker').forEach(id=>{
      const option=el('option',names[id]);option.value=id;peer.append(option);
    });
    if([...peer.options].some(option=>option.value===previous))peer.value=previous;
    $('start').value=config.night.startHour;$('end').value=config.night.endHour;
    renderEditor();$('saveStatus').textContent='保存済みの設定を読み込みました';
    await preview();
  }catch(error){
    $('saveStatus').textContent='読み込みに失敗しました：'+error.message;
    $('saveStatus').className='status error';
    $('reason').textContent='イベント設定を読み込めないため、会話プレビューを表示できません。';
    $('reason').className='error';
    $('lines').replaceChildren(el('p','上の読み込みエラーを確認してください。'));
  }
}
$('start').oninput=()=>{config.night.startHour=Number($('start').value);change();};$('end').oninput=()=>{config.night.endHour=Number($('end').value);change();};
['host','frog','mosa','now','last','previewPeer','cleanerStarted'].forEach(id=>$(id).onchange=preview);
$('completed').onchange=()=>{$('last').disabled=$('completed').value==='0';$('last').value=$('last').disabled?'':$('now').value.slice(0,10);preview();};
$('preview').onclick=preview;
$('read').onclick=async()=>{if(!result?.canComplete)return;$('completed').value=result.nextCompleted;$('last').disabled=false;$('last').value=result.nightKey;await preview();};
$('next').onclick=()=>{const date=new Date((result?.nightKey||$('now').value.slice(0,10))+'T12:00:00');date.setDate(date.getDate()+1);const pad=n=>String(n).padStart(2,'0');$('now').value=`${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(config.night.startHour)}:00`;preview();};
$('reset').onclick=()=>{$('completed').value='0';$('last').value='';$('last').disabled=true;preview();};
$('save').onclick=async()=>{try{await request('/api/events',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(config)});$('saveStatus').textContent='保存しました。アプリは再ビルドすると反映されます。';}catch(error){$('saveStatus').textContent=error.message;}};
$('reload').onclick=load;
load();
