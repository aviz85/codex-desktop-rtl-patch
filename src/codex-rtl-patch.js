// Codex Desktop RTL patch.
// Adds smart direction handling for Hebrew/Arabic text while keeping code LTR.
;(function () {
  "use strict";

  if (typeof document === "undefined") return;
  if (window.__codexRtlPatchVersion) return;
  window.__codexRtlPatchVersion = "0.3.0";

  var RTL_SPLIT_FLAG = "data-codex-rtl-plaintext";
  var MANAGED_FLAG = "data-codex-rtl-managed";
  var STYLE_ID = "codex-rtl-patch-styles";
  var INPUT_SEL = ".ProseMirror";
  var CODE_SEL =
    "pre, code, kbd, samp, .cm-editor, .monaco-editor, .xterm, [class*=\"language-\"]";
  var TEXT_SEL =
    "p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, summary, dt, dd";
  var LEAF_SEL = "div, span";

  function isRTLChar(ch) {
    var code = ch.charCodeAt(0);
    return (
      (code >= 0x0590 && code <= 0x05ff) ||
      (code >= 0x0600 && code <= 0x06ff) ||
      (code >= 0x0750 && code <= 0x077f) ||
      (code >= 0x08a0 && code <= 0x08ff) ||
      (code >= 0xfb1d && code <= 0xfdff) ||
      (code >= 0xfe70 && code <= 0xfeff)
    );
  }

  function firstStrong(text) {
    if (!text) return null;
    for (var i = 0; i < text.length; i += 1) {
      if (isRTLChar(text[i])) return "rtl";
      if (/[A-Za-z]/.test(text[i])) return "ltr";
    }
    return null;
  }

  function detectTextDir(text) {
    if (!text || !text.trim()) return null;
    for (var i = 0; i < text.length; i += 1) {
      if (isRTLChar(text[i])) return "rtl";
    }
    return firstStrong(text);
  }

  function textWithoutCode(el) {
    var out = "";
    var nodes = el.childNodes || [];
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      if (node.nodeType === 3) {
        out += node.textContent || "";
      } else if (
        node.nodeType === 1 &&
        !node.matches(CODE_SEL) &&
        !node.closest(CODE_SEL)
      ) {
        out += textWithoutCode(node);
      }
    }
    return out;
  }

  function detectElementDir(el) {
    return detectTextDir(textWithoutCode(el));
  }

  function qsa(root, selector) {
    var base = root && root.querySelectorAll ? root : document;
    var result = Array.prototype.slice.call(base.querySelectorAll(selector));
    if (root && root.matches && root.matches(selector)) result.unshift(root);
    return result;
  }

  function isEditable(el) {
    return !!(el && el.closest && el.closest(INPUT_SEL));
  }

  function hasBlockChild(el) {
    return !!el.querySelector(
      "p, div, ul, ol, li, h1, h2, h3, h4, h5, h6, pre, table, blockquote"
    );
  }

  function clearDir(el) {
    if (
      !el.hasAttribute(MANAGED_FLAG) &&
      !el.hasAttribute(RTL_SPLIT_FLAG)
    ) {
      return;
    }

    el.removeAttribute(MANAGED_FLAG);
    el.removeAttribute(RTL_SPLIT_FLAG);
    el.removeAttribute("dir");
    el.style.direction = "";
    el.style.textAlign = "";
    el.style.unicodeBidi = "";
    el.style.listStylePosition = "";
  }

  function applyDir(el, dir, align) {
    clearDir(el);
    if (!dir) return;

    el.setAttribute(MANAGED_FLAG, "1");
    el.setAttribute("dir", dir);
    el.style.direction = dir;
    el.style.textAlign = align || "start";
    if (dir === "rtl") {
      el.setAttribute(RTL_SPLIT_FLAG, "1");
      el.style.unicodeBidi = "isolate";
    }
  }

  function forceCodeLTR(root) {
    qsa(root, CODE_SEL).forEach(function (el) {
      el.setAttribute("dir", "ltr");
      el.style.direction = "ltr";
      el.style.textAlign = "left";
      el.style.unicodeBidi = el.tagName === "CODE" ? "isolate" : "embed";
    });
  }

  function processText(root) {
    qsa(root, TEXT_SEL).forEach(function (el) {
      if (isEditable(el) || el.closest(CODE_SEL)) return;
      var dir = detectElementDir(el);
      if (dir === "rtl") applyDir(el, "rtl");
      else clearDir(el);
    });
  }

  function processLeafContainers(root) {
    qsa(root, LEAF_SEL).forEach(function (el) {
      if (isEditable(el) || el.closest(CODE_SEL)) return;
      var managedAncestor = el.parentElement &&
        el.parentElement.closest("[" + MANAGED_FLAG + "]");
      if (managedAncestor) return;
      if (hasBlockChild(el)) return;
      var dir = detectElementDir(el);
      if (dir === "rtl") applyDir(el, "rtl");
      else clearDir(el);
    });
  }

  function processInputs(root) {
    qsa(root, INPUT_SEL).forEach(function (el) {
      if (el.closest(CODE_SEL)) return;
      var text = el.value || el.textContent || el.innerText || "";
      var dir = detectTextDir(text);
      if (dir === "rtl") {
        applyDir(el, "rtl", "right");
      } else if (dir === "ltr") {
        applyDir(el, "ltr", "left");
      } else {
        clearDir(el);
      }
    });
  }

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = [
      "#root{direction:ltr}",
      "#root :where(pre,code,kbd,samp,.cm-editor,.monaco-editor,.xterm,[class*=\"language-\"]){direction:ltr!important;text-align:left!important}",
      "#root code{unicode-bidi:isolate!important}",
      "#root pre{unicode-bidi:embed!important}",
      "#root .ProseMirror[data-codex-rtl-managed=\"1\"]{unicode-bidi:isolate!important}",
      "#root [data-codex-rtl-plaintext=\"1\"]{unicode-bidi:isolate!important;text-align:start!important}"
    ].join("");
    document.head.appendChild(style);
  }

  function processAll(root) {
    var target = root || document.body || document;
    processText(target);
    processLeafContainers(target);
    processInputs(target);
    forceCodeLTR(target);
  }

  function init() {
    injectStyles();
    processAll(document.body || document);

    document.addEventListener(
      "input",
      function (event) {
        var target = event.target;
        if (target && target.closest && target.closest(INPUT_SEL)) {
          processInputs(target.closest(INPUT_SEL));
        }
      },
      true
    );

    var pending = false;
    var observer = new MutationObserver(function (mutations) {
      var shouldProcess = false;
      for (var i = 0; i < mutations.length; i += 1) {
        if (mutations[i].addedNodes.length || mutations[i].type === "characterData") {
          shouldProcess = true;
          break;
        }
      }
      if (!shouldProcess || pending) return;
      pending = true;
      window.setTimeout(function () {
        pending = false;
        processAll(document.body || document);
      }, 60);
    });

    if (document.body) {
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
