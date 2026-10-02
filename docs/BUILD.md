# Build & Export Workflow

How to build, visually verify, export, and deploy the Geography Game. Adapted for
**Godot 4.7.2-stable** running headless in Docker on a Cloud Desktop (the host glibc is
too old to run the Godot binary directly, so every Godot invocation goes through Docker).

## One-time setup

### 1. Docker image (xvfb + Mesa software GL)

```bash
docker build -t godot-test -f - . <<'EOF'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq \
  xvfb libgl1-mesa-dri libgl1-mesa-glx libegl-mesa0 \
  libglib2.0-0 libx11-6 libxcursor1 libxinerama1 \
  libxrandr2 libxi6 libxext6 libxfixes3 > /dev/null 2>&1
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV MESA_GL_VERSION_OVERRIDE=3.3
EOF
```

### 2. Godot 4.7.2 binary + web export templates

```bash
wget -q "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip" -O godot.zip
unzip -o -q godot.zip

wget -q "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz" -O templates.tpz
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable
unzip -o -q templates.tpz "templates/web*" -d /tmp/godot_templates_472
cp /tmp/godot_templates_472/templates/web* ~/.local/share/godot/export_templates/4.7.2.stable/
```

The binary and `*.zip`/`*.tpz` are gitignored — re-download on a fresh checkout.

## Data pipeline

Regenerate the projected map/capital GeoJSON from the raw Census data. Requires `npx`
(mapshaper is fetched on demand, no global install):

```bash
bash tools/build_states.sh     # -> data/us_states.geojson
bash tools/build_capitals.sh   # -> data/capitals.geojson
```

Both use mapshaper's `albersusa` composite projection (Albers lower-48 + Alaska inset +
Hawaii reposition). The states and capitals go through the **same** projection so capital
pins align with the map.

## Visual iteration (headless screenshot)

The core feedback loop: render a scene in a virtual framebuffer and save a PNG. Use the
dedicated `scenes/test_map.tscn` harness (builds the map, waits for layout, captures
`test_screenshot.png`, quits).

```bash
rm -f test_screenshot.png
docker run --rm -v "$(pwd)":/project -w /project \
  -e LIBGL_ALWAYS_SOFTWARE=1 -e MESA_GL_VERSION_OVERRIDE=3.3 \
  godot-test bash -c "timeout 30 xvfb-run -a -s '-screen 0 1280x720x24' \
    ./Godot_v4.7.2-stable_linux.x86_64 --display-driver x11 \
    --rendering-driver opengl3 scenes/test_map.tscn 2>&1" \
  | grep -iE "built|screenshot|SCRIPT ERROR"
sudo chown "$(whoami)" test_screenshot.png
```

Key points:
- Use `--display-driver x11` + xvfb, **not** `--headless` — headless mode has no viewport
  texture to capture.
- Screenshots are written as root (Docker); `chown` after.
- `class_name` globals do **not** resolve when running a scene directly without a populated
  `.godot` cache. In headless harness scripts, `preload("res://scripts/foo.gd")` instead of
  relying on the global class name.

## WASM export

Keep this current so the latest build is always viewable.

```bash
rm -rf export && mkdir -p export
docker run --rm -v "$(pwd)":/project \
  -v "$HOME/.local/share/godot/export_templates":/root/.local/share/godot/export_templates \
  -w /project \
  godot-test bash -c "./Godot_v4.7.2-stable_linux.x86_64 --headless --export-release 'Web' export/index.html"
sudo chown -R "$(whoami)" export
cp assets/favicon.png export/favicon.png
```

Export uses `--headless` (unlike the screenshot step). Output in `export/`:
`index.html`, `index.js` (loader), `index.wasm` (runtime, ~38 MB), `index.pck` (game data),
audio worklets, icons.

The Web preset sets `thread_support=false` so the build runs on hosts that cannot send
COOP/COEP headers (GitHub Pages). Do not enable threads unless the host can set
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.

### Verify the export locally

```bash
cd export && python3 -m http.server 8099
# then, from another shell:
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" http://localhost:8099/index.wasm
```

Expect HTTP 200 and `application/wasm`. Open `http://localhost:8099/` in a browser to play.

### Browser verification (headless Chromium)

A local HTTP 200 only proves the files are served — **not** that the WASM boots and the
canvas paints. A desktop-renderer screenshot (the step above) also cannot catch web-only or
export-only failures: for example, data files silently omitted from the `.pck` render blank
in the browser while the desktop build looks fine. To actually verify the exported build,
load it in headless Chromium via `tools/verify_web.js` (serves `export/`, loads the page,
waits for the runtime to boot, screenshots the canvas, reports console errors):

```bash
docker run --rm -v "$(pwd)":/project -w /project \
  -e PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
  mcr.microsoft.com/playwright:v1.48.0-jammy \
  bash -c "cd /tmp && npm init -y >/dev/null 2>&1 && \
    npm install playwright-core@1.48.0 >/dev/null 2>&1 && \
    cd /project && NODE_PATH=/tmp/node_modules node tools/verify_web.js 2>&1; \
    chown \$(id -u):\$(id -g) /project/browser_screenshot.png 2>/dev/null"
```

Then inspect `browser_screenshot.png`. A clean run prints `RESULT {"stats":{"canvas":true,...},"errors":[]}` and no `SCRIPT ERROR` / `could not read` lines in the console output.
Pull the image once with `docker pull mcr.microsoft.com/playwright:v1.48.0-jammy`.

**Any change to the export packaging (new data files, filters, assets) must be verified this
way, not just by the desktop screenshot.** Non-resource data files (`.geojson`, `.csv`) are
only packed when listed in the Web preset's `include_filter`.

## Formatting

gdtoolkit's console script is not on PATH in this environment; invoke the module directly:

```bash
pip install -q gdtoolkit
python3 -m gdtoolkit.formatter scripts/*.gd scenes/*.gd   # format
```

Config in `gdformatrc` (4 spaces, line length 100).

## Deploy to GitHub Pages

Only when explicitly asked. Copies the export into the sibling Pages repo, commits, pushes.

```bash
mkdir -p ~/GitHub/drautb/drautb.github.io/random/geography-game
cp -r export/* ~/GitHub/drautb/drautb.github.io/random/geography-game/
cd ~/GitHub/drautb/drautb.github.io
git add random/geography-game/
git commit -m "Update geography game"
git push
```
