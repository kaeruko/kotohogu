import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html=fs.readFileSync(new URL('./index.html',import.meta.url),'utf8');
const functionsStart=html.indexOf('function isArchived(');
const functionsEnd=html.indexOf('function renderCharacterList(',functionsStart);
const handlerStart=html.indexOf('byId("deleteCharacter").onclick=');
const handlerEnd=html.indexOf('byId("cancelNewCharacter").onclick=',handlerStart);
assert(functionsStart>=0&&functionsEnd>functionsStart);
assert(handlerStart>=0&&handlerEnd>handlerStart);

function editor({blocked={},conditions=[],confirmResult=true}={}){
  const rabbit={id:'002_usagi',label:'うさぎ',inGacha:true};
  const target={id:'038_lion_lady',label:'リオコ',inGacha:true};
  const buttons={deleteCharacter:{}};
  const messages=[];
  let confirmations=0;
  const context=vm.createContext({
    registry:{characters:[rabbit,target]},
    data:{dialogues:[{id:'rabbit_line',residentId:rabbit.id,conditions}]},
    characterSelected:target.id,savedCount:2,selected:'rabbit_line',dirty:false,
    archiveBlockers:blocked,
    byId:id=>{assert(id in buttons);return buttons[id]},
    confirm:()=>{confirmations++;return confirmResult},
    setCharacterStatus:(...args)=>messages.push(args),
  });
  vm.runInContext(html.slice(functionsStart,functionsEnd),context);
  for(const name of ['rebuildResidentOptions','renderCharacterList',
    'renderCharacterEditor','refresh','runPreview','renderAreaPreview']){
    context[name]=()=>{};
  }
  vm.runInContext(html.slice(handlerStart,handlerEnd),context);
  return{context,rabbit,target,messages,click:buttons.deleteCharacter.onclick,
    confirmations:()=>confirmations};
}

test('protected rabbit stays selected and unchanged before confirmation',()=>{
  const ui=editor({blocked:{'002_usagi':'Core resident cannot be archived: 002_usagi'}});
  ui.context.characterSelected=ui.rabbit.id;
  ui.click();
  assert.equal(ui.rabbit.archived,undefined);
  assert.equal(ui.context.characterSelected,ui.rabbit.id);
  assert.equal(ui.context.dirty,false);
  assert.equal(ui.confirmations(),0);
  assert.match(ui.messages[0][0],/削除できません/);
});

test('a server code restriction blocks deletion before local state changes',()=>{
  const ui=editor({blocked:{'038_lion_lady':'Used by app code'}});
  ui.click();
  assert.equal(ui.target.archived,undefined);
  assert.equal(ui.context.dirty,false);
  assert.equal(ui.confirmations(),0);
});

test('missing restrictions stop deletion instead of assuming permission',()=>{
  const ui=editor({blocked:null});
  assert.throws(()=>ui.click(),/削除可否/);
  assert.equal(ui.target.archived,undefined);
  assert.equal(ui.context.dirty,false);
});

test('unsaved dialogue dependencies block deletion without changing ownership',()=>{
  const ui=editor({conditions:[{type:'townTogether',otherResidentId:'038_lion_lady'}]});
  ui.click();
  assert.equal(ui.target.archived,undefined);
  assert.equal(ui.confirmations(),0);
  assert.match(ui.messages[0][0],/rabbit_line/);
});

test('an allowed resident is archived only after explicit confirmation',()=>{
  const ui=editor();
  ui.click();
  assert.equal(ui.target.archived,true);
  assert.equal(ui.rabbit.archived,undefined);
  assert.equal(ui.context.dirty,true);
  assert.equal(ui.confirmations(),1);
});

test('cancelling confirmation preserves the original resident and dirty state',()=>{
  const ui=editor({confirmResult:false});
  ui.click();
  assert.equal(ui.target.archived,undefined);
  assert.equal(ui.context.dirty,false);
  assert.equal(ui.confirmations(),1);
});
