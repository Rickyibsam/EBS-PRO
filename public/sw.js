const CACHE_NAME = "ebs-pro-shell-v4";
const APP_SHELL = ["/manifest.webmanifest", "/icon.svg"];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    const shell = await fetch("/");
    if (!shell.ok) throw new Error("EBS PRO app shell could not be cached.");
    await cache.put("/", shell.clone());
    const html = await shell.text();
    const assets = [...html.matchAll(/(?:src|href)=["']([^"']+\.(?:js|css))["']/gi)]
      .map(match => new URL(match[1], self.location.origin).href)
      .filter(url => new URL(url).origin === self.location.origin);
    await Promise.all(assets.map(async asset => {
      try {
        const response = await fetch(asset);
        if (response.ok && response.type !== "opaque") await cache.put(asset, response.clone());
      } catch { /* Keep the rest of the app shell installable if one optional asset fails. */ }
    }));
  })());
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  event.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(key => key.startsWith("ebs-pro-shell-") && key !== CACHE_NAME).map(key => caches.delete(key)))
  ));
  self.clients.claim();
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;

  const url = new URL(request.url);
  // Never cache API, authentication, RPC, or application data responses.
  if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/auth/") ||
      url.pathname.startsWith("/rest/") || url.pathname.startsWith("/functions/")) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok && url.pathname === "/") {
          const cache = await caches.open(CACHE_NAME);
          await cache.put("/", response.clone());
        }
        return response;
      } catch {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match("/")) ||
          new Response("EBS PRO is offline. Reconnect to synchronize business data.", {
            status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" }
          });
      }
    })());
    return;
  }

  // Cache only static build assets and the public app shell; never cache HTML/data fetches.
  const isStaticAsset = /\.(?:js|css|svg|png|jpg|jpeg|webp|woff2?)$/i.test(url.pathname);
  if (!isStaticAsset) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response.ok && response.type !== "opaque") await cache.put(request, response.clone());
      return response;
    } catch {
      return new Response("EBS PRO asset unavailable offline.", {
        status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" }
      });
    }
  })());
});
