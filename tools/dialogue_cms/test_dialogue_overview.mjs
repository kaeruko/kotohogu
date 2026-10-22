import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const directory=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(directory,'../..');
const html=fs.readFileSync(path.join(directory,'index.html'),'utf8');
const dialogue=JSON.parse(fs.readFileSync(path.join(root,'assets/dialogues/dialogues.json'),'utf8'));
const registry=JSON.parse(fs.readFileSync(path.join(root,'assets/characters/characters.json'),'utf8'));
const missions={all:'全ミッション',movement:'身体を動かした'};
const residents=Object.fromEntries(registry.characters.map(r=>[r.id,r.label]));
const start='// BEGIN CMS DIALOGUE OVERVIEW HELPERS';
const end='// END CMS DIALOGUE OVERVIEW HELPERS';
const i=html.indexOf(start), j=html.indexOf(end);
assert.ok(i>=0&&j>i,'Overview helpers are discoverable');
const functions=new Function('residents','missions',html.slice(i+start.length,j)+
  ';return {dialogueCategoryMatches,conditionDescription,dialogueRuleText}');
const {dialogueCategoryMatches,conditionDescription,dialogueRuleText}=functions(residents,missions);
const rows=dialogue.dialogues;
const byId=new Map(rows.map(row=>[row.id,row]));

test('all local dialogue types have a readable rule summary',()=>{
  assert.ok(rows.length>200);
  for(const row of rows){
    assert.equal(dialogueCategoryMatches(row,'all'),true);
    const description=dialogueRuleText(row);
    assert.ok(description.length>0,row.id);
    assert.ok(!description.includes('[object Object]'),row.id);
    assert.ok(!description.includes('undefined'),row.id);
    if(row.firstGreeting)assert.match(description,/初対面/);
    if(row.priority===-1000){
      assert.equal(dialogueCategoryMatches(row,'facility'),true);
      assert.match(description,/通常抽選には出ない/);
    }
  }
});
test('a dialogue with two condition types appears under both filters',()=>{
  const sample=rows.find(row=>row.conditions.some(c=>c.type==='seenDialogue')&&
    row.conditions.some(c=>c.type==='townTogether'));
  assert.ok(sample);
  assert.equal(dialogueCategoryMatches(sample,'seenDialogue'),true);
  assert.equal(dialogueCategoryMatches(sample,'townTogether'),true);
  assert.match(dialogueRuleText(sample),/ かつ | または /);
});
test('normal, first greeting and mission filters do not overlap incorrectly',()=>{
  const first=rows.find(row=>row.firstGreeting);
  assert.ok(first);
  assert.equal(dialogueCategoryMatches(first,'greeting'),true);
  assert.equal(dialogueCategoryMatches(first,'everyday'),false);
  const normal=rows.find(row=>!row.firstGreeting&&!row.conditions.length&&!row.once);
  assert.ok(normal);
  assert.equal(dialogueCategoryMatches(normal,'everyday'),true);
  assert.equal(dialogueCategoryMatches(normal,'mission'),false);
  const completed=rows.find(row=>row.conditions.some(c=>c.type==='mission'));
  assert.equal(dialogueCategoryMatches(completed,'mission'),true);
});
test('story prerequisite references are navigable via stable dialogue IDs',()=>{
  const references=rows.flatMap(row=>row.conditions
    .filter(c=>c.type==='seenDialogue').map(c=>({from:row.id,to:c.dialogueId})));
  assert.ok(references.length>20);
  for(const {from,to} of references){
    assert.ok(byId.has(to),from+' references missing '+to);
  }
  const example=rows.find(row=>row.conditions.some(c=>c.type==='seenDialogue'));
  assert.match(dialogueRuleText(example),/を読んだ/);
});
test('OR summaries and today-only mission rules are explicitly shown',()=>{
  assert.match(dialogueRuleText({conditions:[{type:'kotohogi',min:40},{type:'kotohogi',min:90}],logic:'any',once:false,firstGreeting:false,priority:0}),/ または /);
  assert.match(conditionDescription({type:'mission',missionId:'movement',minCount:5,withinDays:1}),/今日の達成が必要/);
  assert.match(conditionDescription({type:'date',mode:'weekday',days:[1,7]}),/月・日曜日/);
});
