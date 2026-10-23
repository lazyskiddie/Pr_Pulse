// Cloudflare Worker: exchanges a GitHub authorization code for a user token.
// The client secret lives ONLY here (wrangler secret), never in the iOS app.
//
//   wrangler secret put GITHUB_CLIENT_ID
//   wrangler secret put GITHUB_CLIENT_SECRET
//   wrangler deploy

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json" } });

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

    let body;
    try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
    const { code, redirect_uri } = body;
    if (!code) return json({ error: "Missing code" }, 400);

    const res = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        code,
        redirect_uri,
      }),
    });
    const data = await res.json();
    if (data.error) return json({ error: data.error_description || data.error }, 400);
    return json({ access_token: data.access_token, expires_in: data.expires_in ?? null });
  },
};
