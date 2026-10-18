import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html=fs.readFileSync(new URL('./index.html',import.meta.url),'utf8');
const start=html.indexOf('function previewOutingArea(');
const end=html.indexOf('function renderAreaPreview(',start);
assert(start>=0&&end>start,'Outing preview function must exist');
const context=vm.createContext({});
vm.runInContext(html.slice(start,end),context);
const destination=context.previewOutingArea;
const resident=(id,homeAreaId='village',walkInTown=true)=>({id,homeAreaId,walkInTown});

test('outings use open areas and retain destinations without another draw',()=>{
  const placements=new Map();let calls=0;
  const draw=()=>{calls++;return .99};
  const walker=resident('032_miner','shopping');
  assert.equal(destination(walker,['plaza','park'],placements,false,draw),'park');
  assert.equal(destination(walker,['plaza','park','shopping'],placements,false,draw),'park');
  assert.equal(calls,1);
  assert.equal(destination(resident('027_daydreamer','park'),['plaza','park'],placements,false,draw),'park');
  assert.equal(calls,2);
  assert.equal(placements.size,2);
});

test('salon occupants, hidden residents and shopkeepers keep their fixed roles',()=>{
  const placements=new Map();
  const noDraw=()=>{throw Error('Fixed placement must not draw')};
  assert.equal(destination(resident('038_lion_lady','salon'),['plaza'],placements,false,noDraw),null);
  assert.equal(destination(resident('035_beaty','salon',false),['plaza'],placements,false,noDraw),null);
  assert.equal(destination(resident('hidden','park',false),['plaza'],placements,false,noDraw),null);
  assert.equal(destination(resident('041_pig_middle'),['plaza','park'],placements,true,noDraw),'plaza');
  assert.equal(placements.size,0);
});

test('locked destinations and invalid random values fail without substitution',()=>{
  const placements=new Map([['032_miner','park']]);
  assert.throws(()=>destination(resident('032_miner'),['plaza'],placements,false),/未開放/);
  assert.throws(()=>destination(resident('new'),[],new Map(),false),/開放済み/);
  assert.throws(()=>destination(resident('new'),['plaza'],new Map(),false,()=>1),/範囲外/);
});
