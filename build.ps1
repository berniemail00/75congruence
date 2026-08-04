# Builds the two deliverables from the master congruence-75.html:
#   dist\congruence-75.html  - full standalone file (PWA icons injected)
#   dist\c75-artifact.html   - body-only variant for claude.ai Artifact publishing
$ErrorActionPreference = 'Stop'
$root = "C:\Users\capta\Claude\75 Hard App"
$scratch = "C:\Users\capta\AppData\Local\Temp\claude\C--Users-capta-Claude-75-Hard-App\21c37171-6e2e-4885-8a19-a7b81fc14063\scratchpad"

$src = [System.IO.File]::ReadAllText("$root\congruence-75.html")

# 1. inject icons (base64 data URLs captured from canvas rasterization of logo.svg)
$i180 = [System.IO.File]::ReadAllText("$scratch\icon180.txt").Trim()
$i192 = [System.IO.File]::ReadAllText("$scratch\icon192.txt").Trim()
$i512 = [System.IO.File]::ReadAllText("$scratch\icon512webp.txt").Trim()
$bebas = [System.IO.File]::ReadAllText("$scratch\bebas-b64.txt").Trim()
foreach ($pair in @(@('__ICON180__', $i180), @('__ICON192__', $i192), @('__ICON512W__', $i512), @('__BEBAS__', $bebas))) {
  if (-not $src.Contains($pair[0])) { Write-Warning "marker $($pair[0]) not found in master" }
  $src = $src.Replace($pair[0], $pair[1])
}

# The vision photo pack. The manifest is baked into the HTML as a plain
# comma-separated list so the app needs no fetch(): fetch is blocked on file://,
# while a relative <img src> loads fine everywhere.
$photoDir = "$root\photos"
$packList = ""
if (Test-Path $photoDir) {
  $packFiles = @(Get-ChildItem $photoDir -Filter *.jpg -File | Sort-Object Name | ForEach-Object { $_.Name })
  $packList = $packFiles -join ','
  Write-Output ("photo pack: " + $packFiles.Count + " images")
} else {
  Write-Warning "photos folder not found - the vision feed will ship empty"
}
if (-not $src.Contains('__PACK__')) { Write-Warning "marker __PACK__ not found in master" }
$src = $src.Replace('__PACK__', $packList)

New-Item -ItemType Directory -Force "$root\dist" | Out-Null
[System.IO.File]::WriteAllText("$root\dist\congruence-75.html", $src, [System.Text.UTF8Encoding]::new($false))

# 2. artifact variant: strip document shell, keep <style> + body content, prepend <title>
$bodyStart = $src.IndexOf('<body>') + 6
$bodyEnd = $src.LastIndexOf('</body>')   # template literals inside the JS contain '</body>' too
if ($bodyStart -lt 6 -or $bodyEnd -lt 0) { throw "body tags not found" }
$body = $src.Substring($bodyStart, $bodyEnd - $bodyStart)

$styleStart = $src.IndexOf('<style>')
$styleEnd = $src.IndexOf('</style>') + 8
if ($styleStart -lt 0) { throw "style tag not found" }
$style = $src.Substring($styleStart, $styleEnd - $styleStart)

$emdash = [string][char]0x2014
$artifact = "<title>Congruence 75 $emdash The Forge</title>`n" + $style + "`n" + $body
[System.IO.File]::WriteAllText("$root\dist\c75-artifact.html", $artifact, [System.Text.UTF8Encoding]::new($false))

# 3. GitHub Pages site kit: real manifest + service worker + PNG icons
$site = "$root\dist\site"
New-Item -ItemType Directory -Force $site | Out-Null

# index.html = standalone with a real manifest link (injectPWA then skips the data-URI one)
$siteHtml = $src.Replace('<link rel="icon"', '<link rel="manifest" href="manifest.webmanifest">' + "`n" + '<link rel="icon"')
[System.IO.File]::WriteAllText("$site\index.html", $siteHtml, [System.Text.UTF8Encoding]::new($false))

# icons: decode the canvas-captured data URLs to real PNG files
foreach ($pair in @(@('icon192.txt','icon-192.png'), @('icon512.txt','icon-512.png'))) {
  $dataUrl = [System.IO.File]::ReadAllText("$scratch\$($pair[0])").Trim()
  $b64 = $dataUrl.Substring($dataUrl.IndexOf(',') + 1)
  [System.IO.File]::WriteAllBytes("$site\$($pair[1])", [Convert]::FromBase64String($b64))
}

$manifest = @'
{
  "name": "Congruence 75",
  "short_name": "C=75",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "background_color": "#080706",
  "theme_color": "#080706",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" }
  ]
}
'@
[System.IO.File]::WriteAllText("$site\manifest.webmanifest", $manifest, [System.Text.UTF8Encoding]::new($false))

# service worker: cache name keyed to the content hash so every deploy updates cleanly
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = ([BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($siteHtml))) -replace '-','').Substring(0,10).ToLower()
# CacheStorage is partitioned by ORIGIN, not by service-worker scope. The app has
# been served from more than one path on berniemail00.github.io, and with a bare
# 'c75-<hash>' name the first path to deploy a new build would activate, sweep
# every cache that isn't its own, and strip the other path's offline assets.
# Tagging the name with the worker's own scope makes that structurally impossible,
# and the fetch handler reads only from THIS build's cache.
$sw = @'
const TAG = new URL(self.registration.scope).pathname;   // e.g. '/congruence75/'
const CACHE = 'c75' + TAG + '__HASH__';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
});
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== CACHE && (k.startsWith('c75' + TAG) || k.startsWith('c75-')))
      .map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// Photos live in their OWN cache, filled as he actually sees them. Precaching
// 35 MB at install would hammer his data for pictures he may never scroll to;
// this way each photo is downloaded once, ever, and is instant (and offline)
// from then on. The old handler fetched every photo from the network EVERY time
// because nothing wrote the response back into a cache.
const PHOTOS = 'c75photos' + TAG;
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin === self.location.origin && url.pathname.indexOf('/photos/') !== -1) {
    e.respondWith(caches.open(PHOTOS).then(c =>
      c.match(e.request).then(hit => hit || fetch(e.request).then(res => {
        if (res && res.ok) c.put(e.request, res.clone());
        return res;
      }).catch(() => hit))));
    return;
  }
  e.respondWith(caches.open(CACHE)
    .then(c => c.match(e.request, { ignoreSearch: true }))
    .then(r => r || fetch(e.request)));
});
'@
[System.IO.File]::WriteAllText("$site\sw.js", $sw.Replace('__HASH__', $hash), [System.Text.UTF8Encoding]::new($false))

# alarm pack: canonical copy lives beside the master (regenerate it in-app if the
# start date ever moves, then refresh $root\c75-alarms.ics before building)
if (Test-Path "$root\c75-alarms.ics") {
  Copy-Item "$root\c75-alarms.ics" "$site\c75-alarms.ics" -Force
} elseif (-not (Test-Path "$site\c75-alarms.ics")) {
  Write-Warning "c75-alarms.ics missing - the site's Subscribe button will 404"
}

# the photo pack rides along with the site kit so the feed has something to show
if (Test-Path $photoDir) {
  $sitePhotos = "$site\photos"
  if (Test-Path $sitePhotos) { Remove-Item $sitePhotos -Recurse -Force }
  New-Item -ItemType Directory -Force $sitePhotos | Out-Null
  Copy-Item "$photoDir\*.jpg" $sitePhotos -Force
  $pmb = ((Get-ChildItem $sitePhotos -File | Measure-Object Length -Sum).Sum / 1MB)
  Write-Output ("photos copied into site kit: {0:N1} MB" -f $pmb)
}

# zip the kit for easy upload. As of v10.1 the app lives at the REPO ROOT
# (he deleted site/ on 2026-08-03 and always uploads to the front page anyway):
# bare files — extract, select all six, drag onto the repo's main page.
# App URL: https://berniemail00.github.io/congruence75/
if (Test-Path "$root\dist\congruence75-site.zip") { Remove-Item "$root\dist\congruence75-site.zip" -Force }
Compress-Archive -Path "$site\*" -DestinationPath "$root\dist\congruence75-site.zip"

# An unzipped copy of an OLD kit sitting next to the fresh one is how stale
# files get uploaded — dist\site is the only folder that is ever current.
if (Test-Path "$root\dist\congruence75-site") {
  Remove-Item "$root\dist\congruence75-site" -Recurse -Force
  Write-Output "cleaned: removed a stale unzipped kit from dist\"
}

# 4. copy the standalone build into the scratchpad so the local test server sees it
Copy-Item "$root\dist\congruence-75.html" "$scratch\app.html" -Force
New-Item -ItemType Directory -Force "$scratch\site" | Out-Null
Copy-Item "$site\*" "$scratch\site\" -Force -Recurse

Write-Output ("standalone: " + (Get-Item "$root\dist\congruence-75.html").Length + " bytes")
Write-Output ("artifact:   " + (Get-Item "$root\dist\c75-artifact.html").Length + " bytes")
Write-Output ("site kit:   " + ((Get-ChildItem $site | Measure-Object Length -Sum).Sum) + " bytes, sw cache c75-" + $hash)
