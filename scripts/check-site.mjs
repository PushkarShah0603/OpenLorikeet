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
  const play = element();
  const status = element();
  const title = element();
  const classes = new Set();
  demo.classList = { add: value => classes.add(value), remove: (...values) => values.forEach(value => classes.delete(value)) };
  demo.querySelectorAll = () => controls;

  const selectors = { "#demo": demo, "#demo-title": title, "#demo-status": status, "#reset-demo": reset, "#play-demo": play };
  const timers = new Map();
  let nextTimer = 0;
  const window = {
    matchMedia: () => ({ matches: reduced }),
    setTimeout(callback, delay) {
      assert.equal(delay, reduced ? 0 : classes.has("is-playing") ? 950 : 420);
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

  play.click();
  assert(play.disabled && classes.has("is-playing"));
  timers.get(nextTimer)();
  assert.equal(title.textContent, "Converting to PDF");
  assert(!play.disabled && !classes.has("is-playing"));
  timers.get(nextTimer)();
  assert.equal(status.textContent, "postcard.pdf");
  play.click();
  reset.click();
  assert.equal(timers.size, 0, "Reset cancels the walkthrough");
  assert(!classes.has("is-playing") && !play.disabled);
}

testDemo(false);
testDemo(true);
console.log("PASS: site links, asset paths, picker actions, walkthrough, reset, and reduced-motion timing");

// Platform switching must update both setup instructions and the destination link.
const platformScript = readFileSync(new URL('assets/platforms.js', docs), 'utf8');
const platformButtons = ['mac', 'windows', 'linux'].map(platform => element({platform}));
const platformElements = Object.fromEntries(['title','copy','command','link'].map(key => ['#platform-'+key, element()]));
runInNewContext(platformScript, {document: {
  querySelectorAll: () => platformButtons,
  querySelector: selector => platformElements[selector]
}});
platformButtons[1].click();
assert.match(platformElements['#platform-title'].textContent, /Windows/);
assert.match(platformElements['#platform-command'].textContent, /py -3.12/);
assert.match(platformElements['#platform-link'].href, /releases$/);
assert.equal(platformButtons[0].attributes.get('aria-pressed'), 'false');
platformButtons[2].click();
assert.match(platformElements['#platform-copy'].textContent, /Wayland/);
platformButtons[0].click();
assert.match(platformElements['#platform-link'].href, /releases$/);
const css = readFileSync(new URL('assets/site.css', docs), 'utf8');
for (const [,asset] of css.matchAll(/url\(['"]?([^)'"\s]+)['"]?\)/g)) {
  assert(existsSync(new URL('assets/'+asset, docs)), 'Missing CSS asset '+asset);
}
console.log('PASS: platform setup, truthful artifact links, and CSS asset paths');

async function checkDownloads(releases, failure = false) {
  const buttons = ['mac', 'windows', 'linux'].map(platform => element({platform}));
  const fields = Object.fromEntries(['title','copy','command','link','availability'].map(key => ['#platform-'+key, element()]));
  const context = {document: {querySelectorAll: () => buttons, querySelector: key => fields[key]},
    AbortSignal: {timeout: () => undefined},
    fetch: async () => { if (failure) throw new Error('offline'); return {ok:true, json:async () => releases}; }};
  runInNewContext(platformScript, context);
  await new Promise(resolve => setImmediate(resolve));
  buttons[1].click();
  return fields;
}
const releaseAssets = ['OpenLorikeet-Windows-x64.zip','OpenLorikeet-Linux-x64.tar.gz','OpenLorikeet-macOS-arm64.zip'].map(name => ({name, state:'uploaded', size:1000, browser_download_url:'https://github.com/PushkarShah0603/OpenLorikeet/releases/download/desktop-test/'+name}));
const live = await checkDownloads([{draft:true,assets:releaseAssets},{draft:false,assets:releaseAssets}]);
assert.match(live['#platform-link'].href, /download\/desktop-test\/OpenLorikeet-Windows-x64.zip$/);
assert.match(live['#platform-link'].textContent, /^Download /);
for (const [data, offline] of [[[], false], [[{assets:releaseAssets.slice(0,1)}], false], [[], true]]) {
  const fallback = await checkDownloads(data, offline);
  assert.match(fallback['#platform-link'].href, /releases$/);
  assert.doesNotMatch(fallback['#platform-link'].textContent, /^Download /);
}
console.log('PASS: real release asset downloads; empty, partial, draft, and offline fallbacks');
