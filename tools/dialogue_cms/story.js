"use strict";

const $ = (id) => {
  const node = document.getElementById(id);
  if (!node) throw new Error("CMS element missing: " + id);
  return node;
};
const el = (tag, text) => {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  return node;
};
let documentData = null;
let residents = null;
let selectedId = null;
let previewAt = 0;
let dirty = false;
let rawPending = false;

async function request(url, options) {
  const response = await fetch(url, options);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || "リクエストに失敗しました");
  return body;
}

function setStatus(text, error = false) {
  $("status").textContent = text;
  $("status").classList.toggle("error", error);
}

function changed() {
  dirty = true;
  setStatus("未保存の変更があります");
}

function selectedEpisode() {
  if (!documentData || !selectedId) throw new Error("お話が選択されていません");
  const entry = documentData.episodes.find(row => row.id === selectedId);
  if (!entry) throw new Error("存在しないお話: " + selectedId);
  return entry;
}

function labelInput(parent, label, value, onChange, opts = {}) {
  const wrap = el("label", label);
  const input = el(opts.multiline ? "textarea" : "input");
  input.value = value;
  if (opts.multiline) {
    input.rows = opts.rows || 3;
    input.maxLength = 2000;
  } else {
    input.type = "text";
    input.maxLength = opts.maxLength || 200;
  }
  input.oninput = () => {
    onChange(input.value);
    changed();
    if (opts.refreshImage) renderImages();
    if (opts.refreshPreview) renderPreview();
    if (opts.refreshList) renderList();
  };
  wrap.append(input);
  parent.append(wrap);
  return input;
}

function readOnly(parent, label, value) {
  const wrap = el("label", label);
  const input = el("input");
  input.type = "text";
  input.readOnly = true;
  input.value = String(value);
  wrap.append(input);
  parent.append(wrap);
}

function renderList() {
  const box = $("list");
  box.replaceChildren();
  $("count").textContent = "(" + documentData.episodes.length + "話)";
  for (const [index, episode] of documentData.episodes.entries()) {
    const button = el("button");
    button.type = "button";
    button.className = "episode";
    button.dataset.episodeId = episode.id;
    button.setAttribute("aria-current", String(selectedId === episode.id));
    button.append(
      el("span", "第" + (index + 1) + "話 / " + documentData.episodes.length),
      el("span", episode.title),
      el("span", episode.unlockAt + " ことほぎ ｜ " + episode.clue),
    );
    button.children[0].className = "small";
    button.children[1].className = "episode-title";
    button.children[2].className = "small";
    button.onclick = () => {
      selectedId = episode.id;
      previewAt = 0;
      renderList();
      renderEditor();
    };
    box.append(button);
  }
}

function renderTurns(targetId, episode, key) {
  const target = $(targetId);
  target.replaceChildren();
  const turns = episode[key];
  for (const [index, turn] of turns.entries()) {
    const card = el("div");
    card.className = "turn";
    card.append(el("div", (index + 1) + " / " + turns.length));
    card.firstChild.className = "num";
    const speakerLabel = el("label", "話す住民");
    const selector = el("select");
    for (const resident of residents) {
      const option = el("option", resident.label + " (" + resident.id + ")");
      option.value = resident.id;
      selector.append(option);
    }
    if (!residents.some(row => row.id === turn.speaker)) {
      throw new Error("お話に登録されていない住民: " + turn.speaker);
    }
    selector.value = turn.speaker;
    selector.onchange = () => {
      turn.speaker = selector.value;
      changed();
      renderPreview();
    };
    speakerLabel.append(selector);
    card.append(speakerLabel);
    labelInput(card, "セリフ", turn.text, value => {
      turn.text = value;
    }, {multiline: true, refreshPreview: true});
    const remove = el("button", "このセリフを削除");
    remove.type = "button";
    remove.className = "secondary";
    remove.onclick = () => {
      turns.splice(index, 1);
      previewAt = 0;
      changed();
      renderTurns(targetId, episode, key);
      renderPreview();
    };
    card.append(remove);
    target.append(card);
  }
  const add = el("button", "＋ セリフを追加");
  add.type = "button";
  add.className = "secondary";
  add.onclick = () => {
    if (turns.length >= 20) {
      setStatus("セリフは最大20個です", true);
      return;
    }
    turns.push({speaker: residents[0].id, text: "新しいセリフ"});
    previewAt = 0;
    changed();
    renderTurns(targetId, episode, key);
    renderPreview();
  };
  target.append(add);
}

function renderImages() {
  const episode = selectedEpisode();
  const target = $("scenePreview");
  target.replaceChildren();
  for (const [label, name] of [
    ["会話の場面絵", episode.image],
    ["クリア後の場面絵", episode.resultImage || episode.image],
  ]) {
    const group = el("div");
    group.append(el("div", label + " — " + name));
    const image = el("img");
    image.className = "picture";
    image.alt = label;
    image.src = "/api/runtime/story-images/" + encodeURIComponent(name);
    const error = el("div");
    error.className = "small error";
    image.onerror = () => {
      error.textContent = "画像を読み込めませんでした: " + name;
    };
    group.append(image, error);
    target.append(group);
  }
}

function previewSteps(episode) {
  return [
    ...episode.dialogue.map(turn => ({phase: "数独の前", speaker: turn.speaker, text: turn.text})),
    {phase: "数独", speaker: null, text: episode.puzzle.length === 16
      ? "4×4 数独に挑戦" : "6×6 数独に挑戦"},
    ...episode.resultDialogue.map(turn => ({
      phase: "数独クリア後", speaker: turn.speaker, text: turn.text,
    })),
    {phase: "見つけた手がかり", speaker: null,
      text: episode.clue + "\n" + episode.result},
  ];
}

function renderPreview() {
  const episode = selectedEpisode();
  const steps = previewSteps(episode);
  if (previewAt < 0 || previewAt >= steps.length) {
    throw new Error("プレビューのセリフ位置が不正です");
  }
  const current = steps[previewAt];
  const speaker = current.speaker
    ? residents.find(row => row.id === current.speaker) : null;
  if (current.speaker && !speaker) {
    throw new Error("不明な登場人物: " + current.speaker);
  }
  $("previewPhase").textContent = current.phase;
  $("previewSpeaker").textContent = speaker ? speaker.label : "";
  $("previewText").textContent = current.text;
  $("previewIndex").textContent = (previewAt + 1) + " / " + steps.length;
  $("previousTurn").disabled = previewAt === 0;
  $("nextTurn").disabled = previewAt === steps.length - 1;
}

function renderEditor() {
  const episode = selectedEpisode();
  $("editor").classList.remove("hidden");
  $("loading").classList.add("hidden");
  const fields = $("fields");
  fields.replaceChildren();
  labelInput(fields, "お話のタイトル", episode.title, value => {
    episode.title = value;
  }, {refreshList: true});
  readOnly(fields, "お話ID（変更不可）", episode.id);
  const immutable = el("div");
  immutable.className = "fields";
  readOnly(immutable, "開放に必要な累積ことほぎ", episode.unlockAt);
  readOnly(immutable, "舞台（エリアID）", episode.area);
  readOnly(immutable, "数独のサイズ", (episode.puzzle.length === 16 ? 4 : 6) + "×" +
           (episode.puzzle.length === 16 ? 4 : 6));
  readOnly(immutable, "数独の問題・答え", "下の欄で編集できます");
  fields.append(immutable);
  labelInput(fields, "数独の問題（0は空きマス）", episode.puzzle, value => {
    episode.puzzle = value;
    renderPreview();
  }, {maxLength: 36});
  labelInput(fields, "数独の正解", episode.solution, value => {
    episode.solution = value;
  }, {maxLength: 36});
  labelInput(fields, "場面絵のPNGファイル名", episode.image, value => {
    episode.image = value;
  }, {refreshImage: true});
  labelInput(fields, "クリア後の画像（空欄なら通常の場面絵）",
    episode.resultImage || "", value => {
      if (value === "") delete episode.resultImage;
      else episode.resultImage = value;
    }, {refreshImage: true});
  labelInput(fields, "数独クリアで現れる手がかり", episode.clue,
    value => {episode.clue = value;}, {refreshList: true, refreshPreview: true});
  labelInput(fields, "手がかりを見た後の説明", episode.result,
    value => {episode.result = value;}, {multiline: true, refreshPreview: true});
  renderTurns("intro", episode, "dialogue");
  renderTurns("outro", episode, "resultDialogue");
  renderImages();
  renderPreview();
  $("puzzleInfo").replaceChildren(
    el("h3", "数独の内容"),
    el("p", "問題と正解は編集欄で変更できます"),
    el("p", "次の目的地: " + (episode.destination || "この章では未指定")),
  );
}

async function load() {
  $("save").disabled = true;
  setStatus("読み込み中...");
  try {
    const [data, people] = await Promise.all([
      request("/api/story", {cache: "no-store"}),
      request("/api/characters", {cache: "no-store"}),
    ]);
    if (!Array.isArray(data.episodes) || !Array.isArray(people.characters)) {
      throw new Error("CMSから受け取ったデータ形式が不正です");
    }
    documentData = data;
    residents = people.characters.filter(row => !row.archived);
    selectedId = data.episodes.some(row => row.id === selectedId)
      ? selectedId : data.episodes[0].id;
    previewAt = 0;
    dirty = false;
    rawPending = false;
    $("advancedEditor").open = false;
    renderList();
    renderEditor();
    $("save").disabled = false;
    setStatus("保存済みのストーリーを読み込みました");
  } catch (error) {
    $("editor").classList.add("hidden");
    $("loading").textContent = "ストーリーを読み込めませんでした。";
    $("loading").classList.remove("hidden");
    setStatus("読み込みエラー: " + error.message, true);
  }
}

async function save() {
  if (rawPending) {
    setStatus("JSONの編集内容を一覧に反映してから保存してください", true);
    return;
  }
  if (!documentData || !dirty) return;
  $("save").disabled = true;
  setStatus("保存中...");
  try {
    const response = await request("/api/story", {
      method: "PUT",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(documentData),
    });
    if (response.ok !== true) throw new Error("ストーリーを保存できませんでした");
    dirty = false;
    setStatus("保存しました。公開にはGitへのコミットが必要です。");
  } catch (error) {
    setStatus("保存エラー: " + error.message, true);
  } finally {
    $("save").disabled = false;
  }
}

$("save").onclick = save;
$("reload").onclick = () => {
  if (!(dirty || rawPending) || confirm("未保存の変更を破棄して読み込み直しますか？")) load();
};
$("addEpisode").onclick = () => {
  if (documentData.episodes.length >= 128) {
    setStatus("お話は最大128話です", true);
    return;
  }
  const previous = documentData.episodes.at(-1);
  const clone = structuredClone(previous);
  let number = documentData.episodes.length;
  while (documentData.episodes.some(entry =>
    entry.id === "episode_" + String(number).padStart(2, "0"))) number++;
  clone.id = "episode_" + String(number).padStart(2, "0");
  clone.title = "新しいお話";
  clone.unlockAt = previous.unlockAt + 30;
  delete clone.destination;
  delete clone.resultImage;
  documentData.episodes.push(clone);
  selectedId = clone.id;
  previewAt = 0;
  changed();
  renderList();
  renderEditor();
};
$("removeEpisode").onclick = () => {
  if (documentData.episodes.length <= 1) {
    setStatus("少なくとも1話は残してください", true);
    return;
  }
  const last = documentData.episodes.at(-1);
  if (!confirm("最後の「" + last.title + "」を削除しますか？")) return;
  documentData.episodes.pop();
  selectedId = documentData.episodes.at(-1).id;
  previewAt = 0;
  changed();
  renderList();
  renderEditor();
};
$("advancedEditor").ontoggle = () => {
  if ($("advancedEditor").open) {
    $("storyJsonEditor").value = JSON.stringify(documentData, null, 2);
    rawPending = false;
  }
};
$("storyJsonEditor").oninput = () => {
  rawPending = true;
  setStatus("JSON編集中。保存前に「編集内容を一覧に反映」を押してください");
};
$("applyStoryJson").onclick = () => {
  try {
    const draft = JSON.parse($("storyJsonEditor").value);
    if (!draft || !Array.isArray(draft.episodes) || draft.episodes.length === 0 ||
        draft.episodes.some(row =>
          !row || typeof row.id !== "string" ||
          !Array.isArray(row.dialogue) || !Array.isArray(row.resultDialogue))) {
      throw new Error("ストーリーのJSON形式が不正です");
    }
    documentData = draft;
    selectedId = draft.episodes[0].id;
    previewAt = 0;
    rawPending = false;
    changed();
    $("advancedEditor").open = false;
    renderList();
    renderEditor();
  } catch (error) {
    setStatus("JSONの適用エラー: " + error.message, true);
  }
};
$("previousTurn").onclick = () => {previewAt--; renderPreview();};
$("nextTurn").onclick = () => {previewAt++; renderPreview();};
window.addEventListener("beforeunload", event => {
  if (!(dirty || rawPending)) return;
  event.preventDefault();
  event.returnValue = "";
});
load();
