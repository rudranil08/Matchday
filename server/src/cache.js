// Every provider response is cached, so the number of calls to Sportmonks depends on how often
// the data changes, not on how many people use the app. If the provider fails, the last good copy
// (up to a day old) is served and marked stale.
const memory = new Map();
const KEEP_STALE_MS = 24 * 3600 * 1000;

function edgeCache() {
  // Cloudflare Workers: the data centre's cache. Not available under plain Node (tests, local dev).
  return typeof caches !== "undefined" && caches.default ? caches.default : null;
}

const cacheURL = (key) => `https://cache.matchday.internal/${encodeURIComponent(key)}`;

async function read(key) {
  const hit = memory.get(key);
  if (hit) return hit;
  const edge = edgeCache();
  if (!edge) return null;
  const res = await edge.match(cacheURL(key));
  if (!res) return null;
  const entry = await res.json();
  memory.set(key, entry);
  return entry;
}

async function write(key, entry) {
  memory.set(key, entry);
  const edge = edgeCache();
  if (!edge) return;
  await edge.put(cacheURL(key), new Response(JSON.stringify(entry), {
    headers: { "content-type": "application/json", "cache-control": `max-age=${KEEP_STALE_MS / 1000}` },
  }));
}

/** Calls `load` at most once per `ttlSeconds` for this key. Returns { value, at, stale }. */
export async function cached(key, ttlSeconds, load, now = Date.now()) {
  const hit = await read(key);
  if (hit && now - hit.at < ttlSeconds * 1000) return { ...hit, stale: false };
  try {
    const entry = { at: now, value: await load() };
    await write(key, entry);
    return { ...entry, stale: false };
  } catch (error) {
    if (hit && now - hit.at < KEEP_STALE_MS) return { ...hit, stale: true };
    throw error;
  }
}

export function clearMemory() {
  memory.clear();
}
