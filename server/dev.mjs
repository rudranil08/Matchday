// Runs the Worker on this Mac for development: http://localhost:8787
// The iOS Simulator reaches it at the same address. No packages needed (Node 18+).
// Sample data by default; put SPORTMONKS_TOKEN=... in server/.dev.vars to use the real feed.
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { handle } from "./src/index.js";

const env = { ...process.env };
const vars = new URL("./.dev.vars", import.meta.url);
if (existsSync(vars)) {
  for (const line of readFileSync(vars, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*"?([^"]*)"?\s*$/);
    if (m) env[m[1]] = m[2];
  }
}

const port = Number(process.env.PORT ?? 8787);
createServer(async (req, res) => {
  const started = Date.now();
  const response = await handle(new Request(`http://localhost:${port}${req.url}`, { method: req.method }), env);
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
  console.log(`${req.method} ${req.url} → ${response.status} (${Date.now() - started} ms)`);
}).listen(port, () => {
  console.log(`Matchday API on http://localhost:${port} · ${env.SPORTMONKS_TOKEN ? "live Sportmonks data" : "sample data (no key yet)"}`);
});
