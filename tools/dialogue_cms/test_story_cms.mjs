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
});
