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
$sw = @'
const CACHE = 'c75-__HASH__';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
});
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(r => r || fetch(e.request)));
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

# zip the kit for easy upload. As of v10.1 the app lives at the REPO ROOT
# (he deleted site/ on 2026-08-03 and always uploads to the front page anyway):
# bare files — extract, select all six, drag onto the repo's main page.
# App URL: https://berniemail00.github.io/congruence75/
if (Test-Path "$root\dist\congruence75-site.zip") { Remove-Item "$root\dist\congruence75-site.zip" -Force }
Compress-Archive -Path "$site\*" -DestinationPath "$root\dist\congruence75-site.zip"

# 4. copy the standalone build into the scratchpad so the local test server sees it
Copy-Item "$root\dist\congruence-75.html" "$scratch\app.html" -Force
New-Item -ItemType Directory -Force "$scratch\site" | Out-Null
Copy-Item "$site\*" "$scratch\site\" -Force -Recurse

Write-Output ("standalone: " + (Get-Item "$root\dist\congruence-75.html").Length + " bytes")
Write-Output ("artifact:   " + (Get-Item "$root\dist\c75-artifact.html").Length + " bytes")
Write-Output ("site kit:   " + ((Get-ChildItem $site | Measure-Object Length -Sum).Sum) + " bytes, sw cache c75-" + $hash)
