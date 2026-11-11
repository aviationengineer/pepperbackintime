// Interactive CDP driver: load the game, click hotspots, screenshot each step.
// Usage: node cdp-interact.mjs <port>
import { writeFileSync } from "node:fs";

const port = process.argv[2] || "9224";
const CDP = `http://127.0.0.1:${port}`;
const URL = "file:///home/hatch/workspace/timeline-restorer/v3-godot/web-export/index.html";

const list = await (await fetch(`${CDP}/json/list`)).json();
const target = list.find((t) => t.type === "page");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => { ws.onopen = r; });
let id = 0; const pending = new Map();
const consoleLines = [];
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  if (m.method === "Runtime.exceptionThrown") {
    consoleLines.push(`[EXCEPTION] ${m.params.exceptionDetails.text} ${m.params.exceptionDetails.exception?.description ?? ""}`);
  }
};
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function shot(name) {
  const s = await send("Page.captureScreenshot", { format: "png" });
  if (s.result?.data) { writeFileSync(name, Buffer.from(s.result.data, "base64")); console.log("wrote", name); }
}
async function click(x, y) {
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
  console.log(`clicked (${x}, ${y})`);
}

await send("Page.enable");
await send("Runtime.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
if (target.url !== URL) await send("Page.navigate", { url: URL });
console.log("waiting for engine boot (WASM compile is slow under SwiftShader)...");
await sleep(24000);
// 1. Click the magnifier hotspot at (300, 640) -> Cadet walks, popup opens.
await click(300, 640);
await sleep(5000);
await shot("shot-magnifier-popup.png");
// 2. Click "Pick up" (second button in the popup, panel at ~(190,450)).
await click(300, 540);
await sleep(1500);
await shot("shot-inventory.png");
// 3. Click the humming device at (880, 560) -> Cadet walks, popup opens.
await click(880, 560);
await sleep(5000);
await shot("shot-device-popup.png");
// 4. Click "Truth Check" (second button, panel at ~(770,370); its centre is ~y 488).
await click(880, 488);
await sleep(1500);
await shot("shot-truth.png");
console.log("exceptions:", consoleLines.filter((l) => !l.includes("ServiceWorker")).join(" | ") || "none (besides file:// ServiceWorker)");
process.exit(0);
