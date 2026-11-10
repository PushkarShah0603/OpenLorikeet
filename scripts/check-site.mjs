import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const docs = new URL("../docs/", import.meta.url);
const html = readFileSync(new URL("index.html", docs), "utf8");
const script = readFileSync(new URL("assets/demo.js", docs), "utf8");

const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map(([, id]) => id);
assert.equal(new Set(ids).size, ids.length, "HTML IDs must be unique");
for (const [, attribute, value] of html.matchAll(/\s(href|src)="([^"]+)"/g)) {
  if (value.startsWith("#")) {
    assert(ids.includes(value.slice(1)), `Missing anchor ${value}`);
  } else if (!value.startsWith("https://")) {
    assert(existsSync(new URL(value, docs)), `Missing ${attribute} asset ${value}`);
  }
}
assert(existsSync(new URL(".nojekyll", docs)), "Pages should serve the static assets directly");

function element(dataset = {}) {
  return {
    dataset,
    textContent: "",
    attributes: new Map(),
    events: new Map(),
    setAttribute(name, value) { this.attributes.set(name, value); },
    addEventListener(name, callback) { this.events.set(name, callback); },
    click() { this.events.get("click")(); },
  };
}

function testDemo(reduced) {
  const controls = [...html.matchAll(/<button [^>]*data-format="([^"]+)"([^>]*)>/g)]
    .map(([, format, rest]) => element({ format, action: /data-action="([^"]+)"/.exec(rest)?.[1] }));
  assert.equal(controls.length, 4, "Demo exposes the four documented actions");
  const demo = element();
  const reset = element();
  const status = element();
  const title = element();
  const classes = new Set();
  demo.classList = { add: value => classes.add(value), remove: value => classes.delete(value) };
  demo.querySelectorAll = () => controls;

  const selectors = { "#demo": demo, "#demo-title": title, "#demo-status": status, "#reset-demo": reset };
  const timers = new Map();
  let nextTimer = 0;
  const window = {
    matchMedia: () => ({ matches: reduced }),
    setTimeout(callback, delay) {
      assert.equal(delay, reduced ? 0 : 420);
      timers.set(++nextTimer, callback);
      return nextTimer;
    },
    clearTimeout(id) { timers.delete(id); },
  };

  runInNewContext(script, { document: { querySelector: selector => selectors[selector] }, window });

  controls[0].click();
  controls[1].click();
  assert.equal(timers.size, 1, "A new choice cancels the previous completion");
  assert.equal(controls[0].attributes.get("aria-pressed"), "false");
  assert.equal(controls[1].attributes.get("aria-pressed"), "true");
  assert.equal(title.textContent, "Converting to PDF");
  timers.get(nextTimer)();
  assert.equal(status.textContent, "postcard.pdf");
  assert(classes.has("is-done"));

  controls[3].click();
  timers.get(nextTimer)();
  assert.equal(status.textContent, "postcard (compressed).png");

  controls[0].click();
  reset.click();
  assert.equal(timers.size, 0, "Reset cancels pending completion");
  assert.equal(title.textContent, "Choose an output");
  assert(!classes.has("is-done"));
}

testDemo(false);
testDemo(true);
console.log("PASS: site links, asset paths, picker actions, reset, and reduced-motion timing");
