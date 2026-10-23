"use strict";
const $ = id => document.getElementById(id);
const areas = [
  ["plaza", "中央ひろば"], ["park", "ふれあい公園"],
  ["shopping", "ことほぎ商店街"], ["village", "のんびり里"],
  ["hospital", "びょういん"],
];
let config, characters, selected = 0, dirty = false;
const names = new Map();
const modeNames = {replace:"出演者だけ",add:"通常住民と一緒",exclude:"指定住民を隠す"};
function el(tag, parent, value) {
  const node = document.createElement(tag);
  if (value !== undefined) node.textContent = value;
  parent.append(node);
  return node;
}
function option(parent, value, label) {
  const node = el("option", parent, label); node.value = value; return node;
}
function markDirty() {
  dirty = true;
  $("status").textContent = "未保存の変更があります";
}
async function request(url, options) {
  const res = await fetch(url, options);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || ("HTTP " + res.status));
  return data;
}
function current() { return config?.events[selected] ?? null; }
function choose(id, defaultValue, parent = $("participants")) {
  const select = el("select", parent);
  for (const item of characters) option(select, item.id, item.label + " (" + item.id + ")");
  select.value = id ?? defaultValue;
  if (select.selectedIndex < 0) throw new Error("未知の住民ID: " + id);
  return select;
}
function renderList() {
  const list = $("eventList"); list.replaceChildren();
  config.events.forEach((entry, i) => option(list, i.toString(), entry.label + "｜" + entry.schedule.start + "〜" + entry.schedule.end));
  if (config.events.length) {
    selected = Math.max(0, Math.min(selected, config.events.length - 1));
    list.value = String(selected);
  }
  $("editor").hidden = !config.events.length;
}
function renderParticipants(event) {
  const root = $("participants"); root.replaceChildren();
  event.residents.forEach((person, i) => {
    const row = el("div", root); row.className = "person";
    const selector = choose(person.residentId, characters[0].id, row);
    selector.onchange = () => {
      const oldId = person.residentId;
      person.residentId = selector.value;
      if (event.hostResidentId === oldId) event.hostResidentId = selector.value;
      renderHost(event); markDirty();
    };
    for (const axis of ["x", "y"]) {
      const label = el("label", row, axis.toUpperCase() + " ");
      const inp = el("input", label); inp.type = "number"; inp.min = 0; inp.max = .82; inp.step = .01; inp.value = person[axis];
      inp.oninput = () => { person[axis] = inp.value === "" ? NaN : Number(inp.value); markDirty(); };
    }
    const stayLabel = el("label", row, "その場にいる ");
    const stay = el("input", stayLabel); stay.type = "checkbox"; stay.checked = person.stay;
    const stepLabel = el("label", row, "足踏み ");
    const step = el("input", stepLabel); step.type = "checkbox";
    step.checked = person.stepInPlace ?? false; step.disabled = !person.stay;
    stay.onchange = () => {
      person.stay = stay.checked;
      if (!stay.checked) { person.stepInPlace = false; step.checked = false; }
      step.disabled = !stay.checked; markDirty();
    };
    step.onchange = () => { person.stepInPlace = step.checked; markDirty(); };
    const remove = el("button", row, "削除"); remove.type = "button"; remove.className = "secondary";
    remove.onclick = () => {
      if (event.hostResidentId === person.residentId) delete event.hostResidentId;
      event.residents.splice(i, 1); renderParticipants(event); renderHost(event); markDirty();
    };
  });
}
function renderHost(event) {
  const input = $("hostResidentId"); input.replaceChildren();
  option(input, "", "なし（各出演者を個別に表示）");
  event.residents.forEach(person =>
      option(input, person.residentId,
          names.get(person.residentId) + " (" + person.residentId + ")"));
  input.value = event.hostResidentId ?? "";
  if (input.selectedIndex < 0) {
    throw new Error("中心となる住民は出演者から選択してください");
  }
  input.onchange = () => {
    if (input.value) event.hostResidentId = input.value;
    else delete event.hostResidentId;
    markDirty();
  };
}
function renderEditor() {
  renderList();
  const event = current();
  if (!event) return;
  for (const key of ["id","label","areaId","mode","requiresOwned"]) {
    const input = $(key === "areaId" ? "area" : key);
    if (key === "requiresOwned") input.checked = event[key]; else input.value = event[key];
    input.onchange = () => { event[key] = key === "requiresOwned" ? input.checked : input.value; markDirty(); if (key === "label") renderList(); };
  }
  for (const key of ["start","end"]) {
    $(key).value = event.schedule[key];
    $(key).onchange = () => { event.schedule[key] = $(key).value; markDirty(); renderList(); };
  }
  const root = $("days"); root.replaceChildren();
  ["月","火","水","木","金","土","日"].forEach((day, i) => {
    const label = el("label", root, day); label.className = "day";
    const checkbox = el("input", label); checkbox.type = "checkbox";
    checkbox.checked = event.schedule.weekdays.includes(i + 1);
    checkbox.onchange = () => {
      event.schedule.weekdays = [...root.querySelectorAll("input")]
        .flatMap((input, idx) => input.checked ? [idx + 1] : []);
      markDirty();
    };
  });
  renderParticipants(event);
  renderHost(event);
}
async function load() {
  [config, {characters: characters}] = await Promise.all([
    request("/api/timed-events"), request("/api/characters"),
  ]);
  characters = characters.filter(c => !c.archived);
  names.clear(); characters.forEach(c => names.set(c.id, c.label));
  if (characters.length === 0) throw new Error("住民の登録がありません");
  selected = 0; dirty = false; renderEditor(); $("status").textContent = "読み込みました";
}
function postPreview() {
  const selectedPeople = [...$("previewPeople").querySelectorAll("input:checked")].map(x => x.value);
  // Preview must not silently grant ownership of an event's performers.
  const owned = [...selectedPeople];
  return {config, now: $("previewTime").value, areaId: $("previewArea").value,
    owned, ordinary: selectedPeople};
}
async function preview() {
  try {
    const result = await request("/api/timed-events-preview", {
      method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(postPreview()),
    });
    $("previewResult").textContent =
      (result.activeLabel ? "開催中: " + result.activeLabel + "（" + modeNames[result.mode] + "）" : "通常のまち") +
      "\n表示住民: " + (result.visible.map(id => names.get(id) || id).join("・") || "なし");
  } catch (error) { $("previewResult").textContent = "エラー: " + error.message; }
}
function initialize() {
  for (const target of ["area","previewArea"]) {
    areas.forEach(([id, label]) => option($(target), id, label));
  }
  $("previewArea").value = "park";
  $("eventList").onchange = () => {selected = Number($("eventList").value);renderEditor();};
  $("add").onclick = () => {
    if (config.events.length >= 30) { $("status").textContent = "最大30件です"; return; }
    const id = "event_" + (config.events.length + 1);
    const unique = Array.from({length:31},(_,i)=>"event_"+(i+1)).find(candidate => !config.events.some(e=>e.id===candidate));
    if (!unique) throw new Error("空きイベントIDがありません");
    config.events.push({
      id:unique, label:"新しいイベント",areaId:"park",
      schedule:{start:"06:00",end:"09:00",weekdays:[]},
      mode:"replace",requiresOwned:false,
      residents:[{residentId:characters[0].id,x:.48,y:.66,stay:true}],
    });
    selected = config.events.length - 1; markDirty(); renderEditor();
  };
  $("remove").onclick = () => {
    if (!current()) return;
    if (!confirm("選択したイベントを削除しますか？")) return;
    config.events.splice(selected,1); markDirty();renderEditor();
  };
  $("addPerson").onclick = () => {
    const event = current(); if (!event) return;
    if (event.residents.length >= 8) { $("status").textContent = "最大8人です"; return; }
    const unused = characters.find(c => !event.residents.some(p => p.residentId === c.id));
    if (!unused) throw new Error("追加可能な住民がいません");
    event.residents.push({residentId:unused.id,x:.48,y:.66,stay:true});
    markDirty();renderParticipants(event);renderHost(event);
  };
  $("reload").onclick = () => { if (dirty && !confirm("未保存の変更を破棄しますか？")) return; load().catch(showError); };
  $("save").onclick = async () => {
    try {
      await request("/api/timed-events", {method:"PUT",
        headers:{"Content-Type":"application/json"},body:JSON.stringify(config)});
      dirty = false; $("status").textContent = "保存しました。アプリは再ビルドすると反映されます。";
    } catch(error) { showError(error); }
  };
  $("preview").onclick = preview;
  for (const c of characters) {
    const label = el("label", $("previewPeople"), c.label+" ");
    label.className = "day";
    const check = el("input", label); check.type = "checkbox";check.value=c.id;
  }
  preview();
}
function showError(error) { $("status").textContent = "エラー: " + error.message; }
window.addEventListener("beforeunload",event=>{
  if (dirty) {event.preventDefault();event.returnValue="";}
});
load().then(initialize).catch(showError);
