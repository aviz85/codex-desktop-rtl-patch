// Runtime compatibility probe. It must pass before a rebuilt app is activated.
const port = process.argv[2];
if (!port) throw new Error("usage: probe-renderer.mjs <cdp-port>");

const pages = await fetch(`http://127.0.0.1:${port}/json`).then((r) => r.json());

function evaluate(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timeout = setTimeout(() => reject(new Error("CDP timeout")), 8000);
    ws.onerror = () => reject(new Error("CDP websocket error"));
    ws.onopen = () => ws.send(JSON.stringify({
      id: 1,
      method: "Runtime.evaluate",
      params: {
        awaitPromise: true,
        returnByValue: true,
        expression: `(async () => {
          const p = document.createElement('p');
          p.textContent = 'שלום hello';
          document.body.appendChild(p);
          const pre = document.createElement('pre');
          pre.textContent = 'const x = 1;';
          document.body.appendChild(pre);
          await new Promise(r => setTimeout(r, 250));
          const result = {
            patchVersion: window.__codexRtlPatchVersion || null,
            styleLoaded: !!document.getElementById('codex-rtl-patch-styles'),
            hebrewDirection: getComputedStyle(p).direction,
            codeDirection: getComputedStyle(pre).direction
          };
          p.remove(); pre.remove();
          return result;
        })()`
      }
    }));
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== 1) return;
      clearTimeout(timeout);
      ws.close();
      resolve(message.result?.result?.value || null);
    };
  });
}

let passing = null;
for (const page of pages.filter((item) => item.type === "page" && item.webSocketDebuggerUrl)) {
  const result = await evaluate(page.webSocketDebuggerUrl).catch(() => null);
  if (result?.patchVersion && result.styleLoaded) {
    passing = result;
    break;
  }
}

console.log(JSON.stringify(passing, null, 2));
if (!passing || passing.hebrewDirection !== "rtl" || passing.codeDirection !== "ltr") {
  process.exit(1);
}
