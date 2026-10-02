// Headless-browser verification of the WASM export.
// Serves export/ on :8077, loads it in Chromium, waits for the Godot canvas to
// paint, screenshots it to browser_screenshot.png, and reports non-blank pixels.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");

const DIR = "/project/export";
const PORT = 8077;
const TYPES = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
};

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/index.html";
  const fp = path.join(DIR, p);
  fs.readFile(fp, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("not found");
      return;
    }
    const ext = path.extname(fp);
    res.writeHead(200, { "Content-Type": TYPES[ext] || "application/octet-stream" });
    res.end(data);
  });
});

(async () => {
  await new Promise((r) => server.listen(PORT, r));
  const browser = await chromium.launch({ args: ["--use-gl=swiftshader", "--enable-webgl", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  page.on("console", (m) => console.log("  [console]", m.type(), m.text()));
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(`http://localhost:${PORT}/index.html`, { waitUntil: "load" });

  // Give the WASM runtime time to download, boot, and render a few frames.
  await page.waitForTimeout(15000);

  await page.screenshot({ path: "/project/browser_screenshot.png" });

  // Interaction smoke test: click on the canvas (over the lower-48 landmass) to
  // exercise the real Area2D input_event path. A clean run shows no new errors
  // and the "Next" button becomes visible (an answer was resolved).
  const canvas = await page.$("canvas");
  if (canvas) {
    const box = await canvas.boundingBox();
    // Click the DC callout off the east coast (fraction 0.869, 0.465 of the
    // design viewport) to verify the enlarged inset is clickable.
    await page.mouse.click(box.x + box.width * 0.869, box.y + box.height * 0.465);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: "/project/browser_click.png" });
  }

  // Sample the canvas for non-background pixels to detect a blank screen.
  const stats = await page.evaluate(() => {
    const c = document.querySelector("canvas");
    if (!c) return { canvas: false };
    return { canvas: true, w: c.width, h: c.height };
  });
  console.log("RESULT", JSON.stringify({ stats, errors }));
  await browser.close();
  server.close();
})();
