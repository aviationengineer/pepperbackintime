// Minimal CDP screenshot driver (Node 24 built-in WebSocket, no deps).
// Usage: node cdp-shot.mjs <url> <out.png> <waitMs> [logFile]
import { writeFileSync } from "node:fs";

const [url, outPng, waitMsStr, logFile, portStr] = process.argv.slice(2);
const waitMs = Number(waitMsStr || "8000");

const CDP = `http://127.0.0.1:${portStr || "9222"}`;

// Attach to the existing about:blank page target and navigate via CDP —
// navigating from /json/new counts as initiated by a public page, which
// trips Chrome's Local Network Access check for localhost.
let target;
const listRes = await fetch(`${CDP}/json/list`);
const targets = await listRes.json();
target = targets.find((t) => t.type === "page");
if (!target) throw new Error("no page target found");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const pending = new Map();
const consoleLines = [];
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  if (msg.method === "Runtime.consoleAPICalled") {
    const args = (msg.params.args || []).map((a) => a.value ?? a.description ?? "").join(" ");
    consoleLines.push(`[console.${msg.params.type}] ${args}`);
  }
  if (msg.method === "Runtime.exceptionThrown") {
    const d = msg.params.exceptionDetails;
    consoleLines.push(`[EXCEPTION] ${d.text} ${d.exception?.description ?? ""}`);
  }
  if (msg.method === "Log.entryAdded") {
    const e = msg.params.entry;
    consoleLines.push(`[log.${e.level}] ${e.text} ${e.url ?? ""}`);
  }
};
function send(method, params = {}) {
  return new Promise((resolve) => {
    const mid = ++id;
    pending.set(mid, resolve);
    ws.send(JSON.stringify({ id: mid, method, params }));
  });
}

await send("Page.enable");
await send("Runtime.enable");
await send("Log.enable");
// Force a true 1280x720 viewport (headless window size includes browser UI).
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
if (target.url !== url) {
  await send("Page.navigate", { url });
}
await new Promise((r) => setTimeout(r, waitMs));
const shot = await send("Page.captureScreenshot", { format: "png" });
if (shot.result?.data) {
  writeFileSync(outPng, Buffer.from(shot.result.data, "base64"));
  console.log("wrote", outPng);
} else {
  console.log("screenshot failed:", JSON.stringify(shot).slice(0, 300));
}
console.log("--- console/log lines ---");
for (const line of consoleLines.slice(0, 40)) console.log(line);
if (logFile) writeFileSync(logFile, consoleLines.join("\n"));
ws.close();
process.exit(0);
