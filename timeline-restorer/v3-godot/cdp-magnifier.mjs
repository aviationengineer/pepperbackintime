// Focused magnifier pickup test with generous waits for slow headless rendering.
import { writeFileSync } from "node:fs";

const port = process.argv[2] || "9224";
const CDP = `http://127.0.0.1:${port}`;
const URL = "file:///home/hatch/workspace/timeline-restorer/v3-godot/web-export/index.html";

const list = await (await fetch(`${CDP}/json/list`)).json();
const target = list.find((t) => t.type === "page");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => { ws.onopen = r; });
let id = 0; const pending = new Map();
ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
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
await send("Page.navigate", { url: URL }); // force a clean reload
console.log("waiting for engine boot...");
await sleep(24000);
await click(300, 640);
console.log("waiting for the (slow, headless) walk to the magnifier...");
await sleep(25000);
await shot("shot-magnifier-popup.png");
await click(300, 540); // "Pick up" button
await sleep(2000);
await shot("shot-inventory.png");
process.exit(0);
