// Codex Desktop RTL patch.
// Adds smart direction handling for Hebrew/Arabic text while keeping code LTR.
;(function () {
  "use strict";

  if (typeof document === "undefined") return;
  if (window.__codexRtlPatchVersion) return;
  window.__codexRtlPatchVersion = "0.1.0";

  var RTL_SPLIT_FLAG = "data-codex-rtl-plaintext";
  var STYLE_ID = "codex-rtl-patch-styles";
  var INPUT_SEL =
    ".ProseMirror, [contenteditable=\"true\"], textarea, input[type=\"text\"], input:not([type])";
  var CODE_SEL =
    "pre, code, kbd, samp, .cm-editor, .monaco-editor, .xterm, [class*=\"language-\"]";
  var TEXT_SEL =
    "p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, summary, label, dt, dd";
  var LEAF_SEL =
    "div, span, button, a, label";

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

  function hasRTL(text) {
    if (!text) return false;
    for (var i = 0; i < text.length; i += 1) {
      if (isRTLChar(text[i])) return true;
    }
    return false;
  }

  function firstStrong(text) {
    if (!text) return null;
    for (var i = 0; i < text.length; i += 1) {
      if (isRTLChar(text[i])) return "rtl";
      if (/[A-Za-z]/.test(text[i])) return "ltr";
    }
    return null;
  }

  function stripLeadingLTRNoise(text) {
    return (text || "")
      .replace(/^[\s]*(?:[\w.-]+\.[\w]{1,8})\s*/g, "")
      .replace(/https?:\/\/\S+/g, "")
      .replace(/[\w.-]+[\/\\][\w.\/\\-]+/g, "")
      .replace(/`[^`]+`/g, "")
      .replace(/\$[A-Za-z_][\w-]*/g, "");
  }

  function detectTextDir(text) {
    if (!text || !text.trim()) return null;
    var direct = firstStrong(text);
    if (direct === "rtl") return "rtl";
    if (!hasRTL(text)) return "ltr";
    var stripped = firstStrong(stripLeadingLTRNoise(text));
    return stripped === "rtl" ? "rtl" : "rtl";
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
    var full = el.textContent || "";
    if (!hasRTL(full)) return null;
    var noCode = textWithoutCode(el);
    var direct = firstStrong(noCode);
    if (direct === "rtl") return "rtl";
    var stripped = firstStrong(stripLeadingLTRNoise(noCode));
    return stripped === "rtl" ? "rtl" : "rtl";
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

  function applyDir(el, dir) {
    if (!dir) {
      if (el.hasAttribute("dir")) el.removeAttribute("dir");
      el.style.direction = "";
      el.style.textAlign = "";
      return;
    }
    el.setAttribute("dir", dir);
    el.style.direction = dir;
    el.style.textAlign = "start";
    if (dir === "rtl") {
      el.setAttribute(RTL_SPLIT_FLAG, "1");
      el.style.unicodeBidi = "plaintext";
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
      if (dir) {
        applyDir(el, dir);
        if (el.tagName === "LI" && dir === "rtl") {
          el.style.listStylePosition = "inside";
          var list = el.closest("ul, ol");
          if (list && !list.hasAttribute("dir")) applyDir(list, "rtl");
        }
      } else {
        applyDir(el, null);
        if (el.tagName === "LI") el.style.listStylePosition = "";
      }
    });

    qsa(root, "ul, ol").forEach(function (el) {
      if (isEditable(el) || el.closest(CODE_SEL)) return;
      var dir = detectElementDir(el);
      if (dir === "rtl") applyDir(el, "rtl");
      else applyDir(el, null);
    });
  }

  function processLeafContainers(root) {
    qsa(root, LEAF_SEL).forEach(function (el) {
      if (isEditable(el) || el.closest(CODE_SEL)) return;
      if (el.hasAttribute(RTL_SPLIT_FLAG)) return;
      if (hasBlockChild(el)) return;
      if (/^(P|LI|H[1-6]|BLOCKQUOTE|TD|TH|UL|OL|PRE|CODE)$/.test(el.tagName)) {
        return;
      }
      var text = (el.textContent || "").trim();
      if (text.length < 2) return;
      if (hasRTL(text)) applyDir(el, detectTextDir(text) || "rtl");
      else if (el.hasAttribute("dir")) applyDir(el, null);
    });
  }

  function processInputs(root) {
    qsa(root, INPUT_SEL).forEach(function (el) {
      if (el.closest(CODE_SEL)) return;
      var text = el.value || el.textContent || el.innerText || "";
      var dir = detectTextDir(text);
      if (dir === "rtl") {
        el.setAttribute("dir", "rtl");
        el.style.direction = "rtl";
        el.style.textAlign = "right";
      } else {
        el.setAttribute("dir", "ltr");
        el.style.direction = "ltr";
        el.style.textAlign = "left";
      }
      el.style.unicodeBidi = "plaintext";
    });
  }

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;
    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = [
      "#root :where(p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th,summary,label,dt,dd):not([dir]){unicode-bidi:plaintext!important;text-align:start!important}",
      "#root :where(pre,code,kbd,samp,.cm-editor,.monaco-editor,.xterm,[class*=\"language-\"]){direction:ltr!important;text-align:left!important}",
      "#root code{unicode-bidi:isolate!important}",
      "#root pre{unicode-bidi:embed!important}",
      "#root .ProseMirror{unicode-bidi:plaintext!important;text-align:start!important}",
      "#root .ProseMirror[dir=\"rtl\"]{direction:rtl!important;text-align:right!important}",
      "#root [dir=\"rtl\"]{direction:rtl!important}",
      "#root [dir=\"ltr\"]{direction:ltr!important}",
      "#root [data-codex-rtl-plaintext=\"1\"]{unicode-bidi:plaintext!important;text-align:start!important}"
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
