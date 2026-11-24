import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { Script } from "node:vm";

const root = dirname(fileURLToPath(import.meta.url));
const page = readFileSync(join(root, "story.html"), "utf8");
const script = readFileSync(join(root, "story.js"), "utf8");

test("story CMS script parses as JavaScript", () => {
  assert.doesNotThrow(() => new Script(script, { filename: "story.js" }));
});

test("story CMS lists episodes and exposes editing and a step-by-step preview", () => {
  for (const text of [
    'id="list"', 'id="fields"', 'id="intro"', 'id="outro"',
    'id="scenePreview"', 'id="previewText"', 'id="previousTurn"',
    'id="nextTurn"', 'id="save"', 'id="reload"',
    'id="addEpisode"', 'id="removeEpisode"', 'id="storyJsonEditor"',
    'id="applyStoryJson"',
  ]) {
    assert.ok(page.includes(text), `Missing story CMS element: ${text}`);
  }
  assert.match(script, /request\("\/api\/story"/);
  assert.match(script, /method: "PUT"/);
  assert.match(script, /resultDialogue/);
  assert.match(script, /"episode"/);
  assert.match(script, /chapterStarts/);
  assert.match(script, /startEpisodeId/);
  assert.match(script, /"chapter-header"/);
  assert.match(page, /章タイトルはこの一覧から編集/);
});

test("adding chapter duels through the editor preserves the published episodes", async () => {
  const base = join(root, "../../assets");
  const original = JSON.parse(readFileSync(join(base, "story/story.json")));
  const registry = JSON.parse(readFileSync(join(base, "characters/characters.json")));
  class Element {
    children = [];
    dataset = {};
    classList = {toggle() {}, add() {}, remove() {}};
    append(...nodes) { this.children.push(...nodes); }
    replaceChildren(...nodes) { this.children = nodes; }
    setAttribute(key, value) { this[key] = value; }
    get firstChild() { return this.children[0]; }
  }
  const nodes = new Map([...page.matchAll(/id="([^"]+)"/g)].map(m => [m[1], new Element()]));
  let saved;
  const context = {
    document: {getElementById: id => nodes.get(id), createElement: () => new Element()},
    window: {addEventListener() {}}, structuredClone,
    fetch: async (url, options) => {
      if (options?.method === "PUT") {
        assert.equal(url, "/api/story");
        saved = JSON.parse(options.body);
        return {ok: true, json: async () => ({ok: true})};
      }
      return {ok: true, json: async () => structuredClone(url === "/api/story" ? original : registry)};
    },
  };
  await new Script(script).runInNewContext(context);
  function select(parent, label, value) {
    function find(node) {
      if (node.textContent === label) return node.firstChild;
      for (const child of node.children) {
        const match = find(child);
        if (match) return match;
      }
    }
    const select = find(nodes.get(parent));
    assert.ok(select.children.some(option => option.value === value), label);
    select.value = value;
    select.onchange();
  }
  nodes.get("addDuelChapter").onclick();
  select("list", "この章の対戦", "endgame");
  select("fields", "主人公", "001_shiba");
  select("fields", "対戦相手", "038_lion_lady");
  nodes.get("addDuelEpisode").onclick();
  select("fields", "主人公", "038_lion_lady");
  select("fields", "対戦相手", "001_shiba");
  nodes.get("addEpisode").onclick();
  await nodes.get("save").onclick();
  assert.deepEqual(saved.chapters.slice(0, -1), original.chapters);
  assert.deepEqual(saved.episodes.slice(0, -3), original.episodes);
  assert.equal(saved.chapters.at(-1).duelStage, "endgame");
  assert.deepEqual(saved.episodes.at(-3).duel, {player: "001_shiba", opponent: "038_lion_lady"});
  assert.deepEqual(saved.episodes.at(-2).duel, {player: "038_lion_lady", opponent: "001_shiba"});
  assert.ok(saved.episodes.at(-1).puzzle);
  assert.ok(!("duel" in saved.episodes.at(-1)));
});
