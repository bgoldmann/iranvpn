/**
 * IranVPN config mirror — serves server-list.json from R2 (if bound) or GitHub upstream.
 * Control-plane only: clients still race Psiphon first; this is a resilient config CDN.
 */

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "public, max-age=60, stale-while-revalidate=300",
  "access-control-allow-origin": "*",
  "x-iranvpn-mirror": "cloudflare-worker",
};

function notFound() {
  return new Response(JSON.stringify({ error: "not_found" }), {
    status: 404,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
    },
  });
}

function isServerList(text) {
  try {
    const data = JSON.parse(text);
    // Raw server list, or a signed envelope whose payload is one.
    const list = data && Array.isArray(data.paths) ? data : data && data.payload;
    if (!list || !Array.isArray(list.paths) || list.paths.length === 0) return false;
    return list.paths.every((p) => p && typeof p.type === "string" && p.type.length > 0);
  } catch {
    return false;
  }
}

function jsonResponse(body, source) {
  return new Response(body, {
    status: 200,
    headers: { ...JSON_HEADERS, "x-iranvpn-source": source },
  });
}

function badGateway(error) {
  return new Response(JSON.stringify({ error }), {
    status: 502,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
    },
  });
}

async function fromR2(env) {
  if (!env.CONFIG_BUCKET) return null;
  const obj = await env.CONFIG_BUCKET.get("server-list.json");
  if (!obj) return null;
  const text = await obj.text();
  if (!isServerList(text)) return null;
  return jsonResponse(text, "r2");
}

async function fromUpstream(env) {
  const upstream =
    env.UPSTREAM_URL ||
    "https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json";
  // Do not cache the subrequest. A bad GitHub body would otherwise stick for
  // cacheTtl and turn into 60s of 502s. The response we return sets max-age itself.
  const resp = await fetch(upstream, {
    headers: { "user-agent": "IranVPN-ConfigMirror/1.0" },
    cf: { cacheTtl: 0 },
  });
  if (!resp.ok) return null;
  const body = await resp.text();
  if (!isServerList(body)) return null;
  return jsonResponse(body, "upstream");
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "GET, HEAD, OPTIONS",
          "access-control-max-age": "86400",
        },
      });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed", {
        status: 405,
        headers: { "cache-control": "no-store" },
      });
    }

    const { pathname } = new URL(request.url);
    if (pathname !== "/" && pathname !== "/server-list.json" && pathname !== "/health") {
      return notFound();
    }

    if (pathname === "/health") {
      return new Response(JSON.stringify({ ok: true, service: "iranvpn-config" }), {
        headers: { "content-type": "application/json", "access-control-allow-origin": "*" },
      });
    }

    let r2 = null;
    try {
      r2 = await fromR2(env);
    } catch {
      r2 = null;
    }
    if (r2) return r2;

    try {
      const upstream = await fromUpstream(env);
      if (upstream) return upstream;
    } catch {
      // fall through to 502
    }
    return badGateway("upstream_failed");
  },
};
