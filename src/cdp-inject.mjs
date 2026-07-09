// Codex RTL — CDP injector (no bundle patch, update-proof).
// Reads the RTL patch JS and injects it into every Codex page target via CDP,
// re-applying every few seconds (the patch is idempotent via its version guard).
import fs from "node:fs";
const PORT = process.env.CDP_PORT || 9333;
const PATCH_PATH = new URL("./codex-rtl-patch.js", import.meta.url);
const PATCH = fs.readFileSync(PATCH_PATH, "utf8");
let idc = 0;

async function listPages() {
  const r = await fetch(`http://127.0.0.1:${PORT}/json`);
  const t = await r.json();
  return t.filter((x) => x.type === "page" && x.webSocketDebuggerUrl);
}

function withTarget(wsUrl, fn) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const pend = new Map();
    const send = (method, params = {}) =>
      new Promise((res) => { const id = ++idc; pend.set(id, res); ws.send(JSON.stringify({ id, method, params })); });
    ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); } };
    ws.onopen = async () => { try { await fn(send); resolve(); } catch (err) { reject(err); } finally { try { ws.close(); } catch {} } };
    ws.onerror = () => reject(new Error("ws error"));
    setTimeout(() => { try { ws.close(); } catch {}; resolve(); }, 8000);
  });
}

const registered = new Set();
async function tick() {
  let pages = [];
  try { pages = await listPages(); } catch { return; }
  for (const p of pages) {
    await withTarget(p.webSocketDebuggerUrl, async (send) => {
      await send("Page.enable");
      await send("Runtime.enable");
      if (!registered.has(p.id)) {
        await send("Page.addScriptToEvaluateOnNewDocument", { source: PATCH });
        registered.add(p.id);
      }
      await send("Runtime.evaluate", { expression: PATCH, allowUnsafeEvalBlockedByCSP: true });
    }).catch(() => {});
  }
}

console.log("[codex-rtl] injector started on port " + PORT);
while (true) { await tick(); await new Promise((r) => setTimeout(r, 3000)); }
