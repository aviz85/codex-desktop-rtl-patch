const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const patchPath = path.join(__dirname, "..", "src", "codex-rtl-patch.js");
const source = fs.readFileSync(patchPath, "utf8");
const endMarker = "  function forceCodeLTR";
const endIndex = source.indexOf(endMarker);

assert.notEqual(endIndex, -1, "Could not locate direction helpers in patch");

const helperSource =
  source
    .slice(0, endIndex)
    .replace('  if (typeof document === "undefined") return;', "") +
  "\n  globalThis.__rtlTestApi = {" +
  " firstStrong, detectTextDir, detectElementDir, clearDir, applyDir" +
  " };\n})();";

const context = { window: {} };
vm.runInNewContext(helperSource, context, { filename: patchPath });

const { firstStrong, detectTextDir, detectElementDir, clearDir, applyDir } =
  context.__rtlTestApi;

const cases = [
  ["Hebrew first", "שלום hello", "rtl"],
  ["Arabic first", "مرحبا hello", "rtl"],
  ["Latin first with Hebrew", "Hello שלום", "rtl"],
  ["Latin path first with Hebrew", "C:\\Workspace\\file.js שלום", "rtl"],
  ["Latin URL first with Hebrew", "https://example.com שלום", "rtl"],
  ["Hebrew after numbers", "123 שלום", "rtl"],
  ["Latin after numbers", "123 hello", "ltr"],
  ["English only", "English only", "ltr"],
  ["Hebrew only", "עברית בלבד", "rtl"],
  ["Punctuation only", "123 !?", null],
  ["Empty text", "", null],
  ["Whitespace", "   ", null]
];

for (const [name, text, expected] of cases) {
  assert.equal(detectTextDir(text), expected, `${name}: detectTextDir`);
}

assert.equal(firstStrong("Hello שלום"), "ltr", "firstStrong remains literal");
assert.equal(firstStrong("שלום hello"), "rtl", "firstStrong detects RTL first");

assert.match(source, /var INPUT_SEL = "\.ProseMirror";/);
assert.match(source, /var LEAF_SEL = "div, span";/);
assert.doesNotMatch(source, /qsa\(root, "ul, ol"\)/);
assert.match(source, /processLeafContainers\(target\)/);
assert.match(
  source,
  /el\.parentElement\.closest\("\[" \+ MANAGED_FLAG \+ "\]"\)/
);
assert.doesNotMatch(
  source,
  /p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, summary, label/
);

function createElement() {
  const attributes = new Map();
  return {
    style: {
      direction: "",
      textAlign: "",
      unicodeBidi: "",
      listStylePosition: ""
    },
    hasAttribute(name) {
      return attributes.has(name);
    },
    setAttribute(name, value) {
      attributes.set(name, value);
    },
    removeAttribute(name) {
      attributes.delete(name);
    },
    getAttribute(name) {
      return attributes.get(name);
    }
  };
}

const managed = createElement();
applyDir(managed, "rtl", "right");
assert.equal(managed.getAttribute("dir"), "rtl");
assert.equal(managed.getAttribute("data-codex-rtl-managed"), "1");
assert.equal(managed.getAttribute("data-codex-rtl-plaintext"), "1");
assert.equal(managed.style.unicodeBidi, "isolate");

applyDir(managed, "ltr", "left");
assert.equal(managed.getAttribute("dir"), "ltr");
assert.equal(managed.getAttribute("data-codex-rtl-managed"), "1");
assert.equal(managed.hasAttribute("data-codex-rtl-plaintext"), false);
assert.equal(managed.style.unicodeBidi, "");

clearDir(managed);
assert.equal(managed.hasAttribute("dir"), false);
assert.equal(managed.hasAttribute("data-codex-rtl-managed"), false);
assert.equal(managed.style.direction, "");
assert.equal(managed.style.textAlign, "");
assert.equal(managed.style.unicodeBidi, "");

const appOwned = createElement();
appOwned.setAttribute("dir", "rtl");
appOwned.style.direction = "rtl";
clearDir(appOwned);
assert.equal(appOwned.getAttribute("dir"), "rtl");
assert.equal(appOwned.style.direction, "rtl");

function textNode(text) {
  return { nodeType: 3, textContent: text };
}

function codeNode(text) {
  return {
    nodeType: 1,
    textContent: text,
    matches() {
      return true;
    },
    closest() {
      return this;
    }
  };
}

function elementNode(children) {
  return {
    nodeType: 1,
    childNodes: children,
    matches() {
      return false;
    },
    closest() {
      return null;
    }
  };
}

assert.equal(
  detectElementDir(elementNode([textNode("Hello שלום")])),
  "rtl"
);
assert.equal(
  detectElementDir(elementNode([textNode("שלום hello")])),
  "rtl"
);
assert.equal(
  detectElementDir(
    elementNode([codeNode("const value = 1;"), textNode(" שלום")])
  ),
  "rtl"
);
assert.equal(
  detectElementDir(
    elementNode([
      textNode("function "),
      codeNode("regular"),
      textNode(" לעומת "),
      codeNode("arrow function")
    ])
  ),
  "rtl"
);

assert.match(
  source,
  /#root \[data-codex-rtl-plaintext=\\"1\\"\]\{unicode-bidi:isolate!important/
);
assert.doesNotMatch(source, /unicode-bidi:plaintext/);

console.log(`RTL direction tests passed (${cases.length} cases).`);

