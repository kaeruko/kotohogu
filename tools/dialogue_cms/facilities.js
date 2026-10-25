'use strict';
const $=id=>document.getElementById(id);
const el=(tag,text)=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=text;return node;};
let config,characters=[],selectedId,dirty=false;
const owned=new Set();
const current=()=>config.facilities.find(r=>r.id===$('room').value);
const person=id=>characters.find(c=>c.id===id);
const selected=()=>current().placements.find(p=>p.residentId===selectedId);
const portrait=id=>'/api/runtime/sprites/'+person(id).artFolder+'/idle_front_01.png';
const publicRoom=room=>room.id==='community_center';
const fixedClinicStaff=room=>room.id==='hospital';
async function request(url,options){const response=await fetch(url,options);const data=await response.json();if(!response.ok)throw Error(data.error||'読み込みに失敗しました');return data;}
function status(text,error=false){$('status').textContent=text;$('status').className='status'+(error?' error':'');}
function changed(){dirty=true;status('未保存の変更があります');}
function fields(){const p=selected(),room=current();$('selectedName').textContent=person(selectedId).label+'の位置';for(const key of ['x','y'])$(key).value=p[key];$('size').value=room.spriteSize;$('x').max=room.width-room.spriteSize;$('y').max=room.height-room.spriteSize;$('remove').disabled=selectedId===room.owner||fixedClinicStaff(room);}
function select(id){selectedId=id;fields();document.querySelectorAll('.sprite').forEach(node=>node.classList.toggle('selected',node.dataset.id===id));document.querySelectorAll('.member').forEach(node=>node.setAttribute('aria-pressed',String(node.dataset.id===id)));}
function place(node,p){const r=current();node.style.left=p.x/r.width*100+'%';node.style.top=p.y/r.height*100+'%';node.style.width=r.spriteSize/r.width*100+'%';node.style.height=r.spriteSize/r.height*100+'%';}
function normalize(p){const r=current();p.x=Math.max(0,Math.min(r.width-r.spriteSize,Math.round(p.x)));p.y=Math.max(0,Math.min(r.height-r.spriteSize,Math.round(p.y)));}
function renderStage(){const room=current(),edit=$('mode').value==='edit',open=publicRoom(room)||owned.has(room.owner);$('previewTitle').textContent=room.label+'の配置プレビュー';$('stage').style.aspectRatio=room.width+'/'+room.height;$('stage').replaceChildren();const bg=el('img');bg.className='bg';bg.alt=room.label+'の背景';bg.src='/api/facility-background?id='+room.id;$('stage').append(bg);const visible=room.placements.filter(p=>edit||publicRoom(room)||(open&&owned.has(p.residentId)));for(const p of visible){const sprite=el('button');sprite.className='sprite'+(p.residentId===selectedId?' selected':'');sprite.dataset.id=p.residentId;sprite.title=person(p.residentId).label;sprite.setAttribute('aria-label',person(p.residentId).label+'を配置');place(sprite,p);const image=el('img');image.src=portrait(p.residentId);image.alt=person(p.residentId).label;image.draggable=false;sprite.append(image);sprite.onclick=()=>select(p.residentId);sprite.onpointerdown=event=>{select(p.residentId);if(!edit)return;event.preventDefault();sprite.focus();sprite.setPointerCapture(event.pointerId);const bounds=$('stage').getBoundingClientRect(),start={clientX:event.clientX,clientY:event.clientY,x:p.x,y:p.y};sprite.onpointermove=move=>{if(!sprite.hasPointerCapture(move.pointerId))return;p.x=start.x+(move.clientX-start.clientX)*room.width/bounds.width;p.y=start.y+(move.clientY-start.clientY)*room.height/bounds.height;normalize(p);place(sprite,p);fields();changed();};sprite.onpointerup=up=>{if(sprite.hasPointerCapture(up.pointerId))sprite.releasePointerCapture(up.pointerId);sprite.onpointermove=null;};sprite.onpointercancel=()=>{sprite.onpointermove=null;};};sprite.onkeydown=event=>{if(!edit||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();const d=event.shiftKey?10:1;p.x+=event.key==='ArrowLeft'?-d:event.key==='ArrowRight'?d:0;p.y+=event.key==='ArrowUp'?-d:event.key==='ArrowDown'?d:0;normalize(p);place(sprite,p);fields();changed();};$('stage').append(sprite);}if(!edit&&!open){const overlay=el('div',person(room.owner).label+'をお迎えすると開放されます');overlay.className='locked';$('stage').append(overlay);}const absent=room.placements.filter(p=>!publicRoom(room)&&!owned.has(p.residentId)).map(p=>person(p.residentId).label);$('previewStatus').textContent=edit?'編集用に配置キャラ全員を表示しています。':!open?'未開放：店主が未所持です。':'入店できます。表示 '+visible.length+'人。'+(absent.length?' 未所持で非表示：'+absent.join('、'):'');}
function render(){const room=current();if(!room.placements.some(p=>p.residentId===selectedId))selectedId=room.placements[0].residentId;$('rule').textContent=publicRoom(room)?'開放条件：累計240ことほぎ。配置キャラは所持状況にかかわらず登場します。':fixedClinicStaff(room)?'開院条件：せんせい（004_neko）を所持。ナースさん（024_nurse）はお迎えすると診療所に登場します。':'開放条件：'+person(room.owner).label+'（'+room.owner+'）を所持。配置キャラも、それぞれ所持しているときだけ登場します。';$('members').replaceChildren();for(const p of room.placements){const button=el('button');button.className='member';button.dataset.id=p.residentId;button.setAttribute('aria-pressed',String(p.residentId===selectedId));const image=el('img');image.src=portrait(p.residentId);image.alt='';const label=el('span',person(p.residentId).label);label.append(el('small',p.residentId+(p.residentId===room.owner?' ｜ '+(publicRoom(room)?'施設の案内役':'店主・開放条件'):'')));button.append(image,label);button.onclick=()=>select(p.residentId);$('members').append(button);}$('addResident').replaceChildren();for(const c of characters.filter(c=>!room.placements.some(p=>p.residentId===c.id))){const option=el('option',c.label+'（'+c.id+'）');option.value=c.id;$('addResident').append(option);}$('addResident').disabled=fixedClinicStaff(room);$('add').disabled=fixedClinicStaff(room)||room.placements.length>=7||!$('addResident').value;$('owned').replaceChildren();for(const p of room.placements){const label=el('label'),check=el('input');check.type='checkbox';check.checked=owned.has(p.residentId);check.onchange=()=>{check.checked?owned.add(p.residentId):owned.delete(p.residentId);renderStage();};label.append(check,document.createTextNode(' '+person(p.residentId).label));$('owned').append(label);}fields();renderStage();}
async function load(){try{const [data,catalog]=await Promise.all([request('/api/facilities'),request('/api/characters')]);config=data;characters=catalog.characters.filter(c=>!c.archived);for(const room of config.facilities)for(const p of room.placements)owned.add(p.residentId);dirty=false;selectedId=null;render();status('保存済みの配置を読み込みました');}catch(error){status(error.message,true);}}
$('room').onchange=()=>{selectedId=null;render();};$('mode').onchange=()=>{$('ownership').open=$('mode').value==='play';renderStage();};
for(const key of ['x','y'])$(key).onchange=()=>{const p=selected(),value=Number($(key).value);if(!Number.isFinite(value)||$(key).value===''){fields();return;}p[key]=value;normalize(p);fields();renderStage();changed();};
$('size').onchange=()=>{
  const room=current(),input=$('size').value,value=Number(input);
  if(input===''||!Number.isInteger(value)||value<80||value>400){$('size').value=room.spriteSize;status('共通サイズは80〜400の整数で指定してください',true);return;}
  if(value===room.spriteSize)return;
  const delta=room.spriteSize-value;
  const positions=room.placements.map(p=>({
    residentId:p.residentId,x:p.x+delta/2,y:p.y+delta,
  }));
  if(positions.some(p=>p.x<0||p.y<0||p.x+value>room.width||p.y+value>room.height)){
    $('size').value=room.spriteSize;
    status('サイズ変更で背景からはみ出すキャラがいます。位置を調整してから保存してください',true);
    return;
  }
  room.spriteSize=value;
  for(const [i,p] of room.placements.entries()){
    p.x=positions[i].x;p.y=positions[i].y;
  }
  fields();renderStage();changed();
};
$('add').onclick=()=>{if(fixedClinicStaff(current()))throw Error('診療所のスタッフは固定です');if(current().placements.length>=7)return;selectedId=$('addResident').value;if(!selectedId)return;const p={residentId:selectedId,x:Math.round(current().width*.35),y:Math.round(current().height*.55)};normalize(p);current().placements.push(p);render();changed();};
$('remove').onclick=()=>{if(fixedClinicStaff(current()))throw Error('診療所のスタッフは固定です');if(selectedId===current().owner)return;current().placements=current().placements.filter(p=>p.residentId!==selectedId);selectedId=null;render();changed();};
$('save').onclick=async()=>{try{await request('/api/facilities',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(config)});dirty=false;status('保存しました。アプリを再ビルドすると配置が反映されます。');}catch(error){status(error.message,true);}};
$('reload').onclick=load;
window.addEventListener('beforeunload',event=>{if(dirty){event.preventDefault();event.returnValue='';}});
load();
