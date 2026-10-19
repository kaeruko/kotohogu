import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html=fs.readFileSync(new URL('./index.html',import.meta.url),'utf8');
const helpersStart=html.indexOf('function firstGreetingTextError(');
const helpersEnd=html.indexOf('function renderCharacterEditor(',helpersStart);
const saveStart=html.indexOf('async function saveAll(');
const saveEnd=html.indexOf('byId("saveCharacters").onclick=',saveStart);
assert(helpersStart>=0&&helpersEnd>helpersStart);
assert(saveStart>=0&&saveEnd>saveStart);

function editor({text='はじめまして。',confirmResult=true,serverError=null}={}){
  const row={id:'004_neko',label:'せんせい',profile:'',nextDialogueNumber:2};
  const normal={id:'cat_default_1',residentId:row.id,text:'こんにちは。',
    priority:0,once:false,logic:'all',conditions:[]};
  const greeting={id:'004_neko_001',residentId:row.id,text,
    priority:0,once:true,firstGreeting:true,logic:'all',conditions:[]};
  const messages=[];const requests=[];
  let loads=0,confirmations=0;
  const context=vm.createContext({
    registry:{version:5,characters:[row]},
    data:{version:1,dialogues:[normal,greeting]},areaDoc:{version:1,areas:[]},
    selected:greeting.id,characterSelected:row.id,dirty:true,
    previewSeenIds:new Set([normal.id,greeting.id]),
    confirm:()=>{confirmations++;return confirmResult},
    fetch:async(url,options)=>{
      requests.push({url,body:JSON.parse(options.body)});
      return{ok:serverError===null,json:async()=>serverError===null
        ?{characters:1,dialogues:2,areas:4}:{error:serverError}};
    },
    load:async()=>{loads++},
    setStatus:(message,error)=>messages.push({where:'dialogues',message,error}),
    setCharacterStatus:(message,error)=>messages.push({where:'characters',message,error}),
    setAreaStatus:(message,error)=>messages.push({where:'areas',message,error}),
    renderCharacterEditor:()=>{},refresh:()=>{},runPreview:()=>{},
  });
  vm.runInContext(html.slice(helpersStart,helpersEnd),context);
  vm.runInContext(html.slice(saveStart,saveEnd),context);
  return{context,row,normal,greeting,messages,requests,
    loads:()=>loads,confirmations:()=>confirmations};
}

test('blank greeting stops saving before PUT and preserves unsaved edits',async()=>{
  for(const text of ['', ' \n\t\u3000']){
    const ui=editor({text});
    const before=JSON.stringify(ui.context.data);
    await ui.context.saveAll();
    assert.equal(ui.requests.length,0);
    assert.equal(ui.loads(),0);
    assert.equal(JSON.stringify(ui.context.data),before);
    assert.equal(ui.row.label,'せんせい');
    assert.equal(ui.row.profile,'');
    assert.equal(ui.greeting.text,text);
    assert.equal(ui.context.dirty,true);
    assert.equal(ui.context.selected,ui.greeting.id);
    assert.equal(ui.confirmations(),0);
    const message=ui.messages.find(item=>item.where==='characters');
    assert.equal(message.error,true);
    assert.match(message.message,/せんせい.*初対面のあいさつ.*004_neko_001.*空欄/);
    assert.match(message.message,/初対面のあいさつを削除/);
  }
});

test('greeting length uses Unicode characters and rejects invalid text types',()=>{
  const ui=editor();
  const error=value=>ui.context.firstGreetingTextError(ui.row,{...ui.greeting,text:value});
  assert.equal(error('あ'.repeat(500)),'');
  assert.equal(error('🌸'.repeat(500)),'');
  assert.match(error('🌸'.repeat(501)),/500文字以内/);
  assert.match(error(null),/文字列/);
});

test('valid greeting and empty profile save the entered data without substitution',async()=>{
  const ui=editor();
  await ui.context.saveAll();
  assert.equal(ui.requests.length,1);
  assert.equal(ui.requests[0].url,'/api/cms');
  const sent=ui.requests[0].body;
  assert.equal(sent.characters.characters[0].label,'せんせい');
  assert.equal(sent.characters.characters[0].profile,'');
  assert.equal(sent.dialogues.dialogues[1].text,'はじめまして。');
  assert.equal(sent.dialogues.dialogues[1].firstGreeting,true);
  assert.equal(ui.loads(),1);
});

test('server rejection keeps the draft and reports the original diagnostic',async()=>{
  const ui=editor({serverError:'diagnostic from validator'});
  const before=JSON.stringify(ui.context.data);
  await ui.context.saveAll();
  assert.equal(ui.requests.length,1);
  assert.equal(ui.loads(),0);
  assert.equal(JSON.stringify(ui.context.data),before);
  assert.equal(ui.context.dirty,true);
  assert.match(ui.messages[0].message,/diagnostic from validator/);
});

test('explicit removal retains normal lines, profile and the next sequence number',async()=>{
  const ui=editor({text:''});
  ui.context.deleteFirstGreeting(ui.row);
  assert.equal(ui.confirmations(),1);
  assert.deepEqual(ui.context.data.dialogues,[ui.normal]);
  assert.equal(ui.row.profile,'');
  assert.equal(ui.row.nextDialogueNumber,2);
  assert.equal(ui.context.selected,null);
  assert.equal(ui.context.previewSeenIds.has(ui.greeting.id),false);
  assert.equal(ui.context.previewSeenIds.has(ui.normal.id),true);
  await ui.context.saveAll();
  assert.equal(ui.requests.length,1);
  assert.deepEqual(ui.requests[0].body.dialogues.dialogues,[ui.normal]);
});

test('cancelled removal preserves even a blank draft',()=>{
  const ui=editor({text:'',confirmResult:false});
  const before=JSON.stringify(ui.context.data);
  ui.context.deleteFirstGreeting(ui.row);
  assert.equal(ui.confirmations(),1);
  assert.equal(JSON.stringify(ui.context.data),before);
  assert.equal(ui.context.selected,ui.greeting.id);
  assert.equal(ui.context.previewSeenIds.has(ui.greeting.id),true);
});

test('a seen-dialogue dependency blocks removal before confirmation',()=>{
  const ui=editor();
  ui.context.data.dialogues.push({id:'dependent_line',residentId:ui.row.id,
    text:'お話の続き。',priority:10,once:true,logic:'all',
    conditions:[{type:'seenDialogue',dialogueId:ui.greeting.id}]});
  const before=JSON.stringify(ui.context.data);
  ui.context.deleteFirstGreeting(ui.row);
  assert.equal(ui.confirmations(),0);
  assert.equal(JSON.stringify(ui.context.data),before);
  assert.match(ui.messages[0].message,/dependent_line/);
  assert.equal(ui.messages[0].error,true);
});
