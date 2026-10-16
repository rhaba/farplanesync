<#
    farplanesync uploader.

    Runs OUTSIDE the game. The farplanesync addon writes your character's progress to
    ..\out\<Name>.json; this script sends each file to the Farplane portal when it changes.
    It talks to one address only: https://farplane.org/api/game/report.

    It needs your personal portal key (Portal > My progress > In-game sync > Create key). It asks
    for it the first time and saves it in tools\.key next to this script. The key only lets the
    holder update characters linked to your Discord account; revoke it in the portal any time.

    Start it with uploader.bat (double-click, or /fps upload in game). Close its window to stop.
#>
param(
    [int]$CheckSeconds = 20,      # how often to look for changed files
    [string]$Portal = 'https://farplane.org',
    [switch]$Once                 # upload anything changed, then exit (testing)
)

$ErrorActionPreference = 'Stop'
$addonDir = Split-Path -Parent $PSScriptRoot      # ...\addons\farplanesync
$outDir   = Join-Path $addonDir 'out'
$keyFile  = Join-Path $PSScriptRoot '.key'
$endpoint = "$Portal/api/game/report"
$sent = @{}                                        # file -> hash of the content last accepted

function Read-Key {
    if (Test-Path $keyFile) {
        $k = (Get-Content -Raw $keyFile).Trim()
        if ($k -like 'fpm_*') { return $k }
    }
    Write-Host 'Paste your personal key from farplane.org/portal (My progress > In-game sync).'
    $k = (Read-Host 'Key').Trim()
    if ($k -notlike 'fpm_*') { throw 'That is not a portal key (they start with fpm_).' }
    Set-Content -Path $keyFile -Value $k -NoNewline
    return $k
}

function Hash-Of([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))
}

# the file minus its write time, so a rewrite with nothing new isn't sent again
function Content-Key([string]$text) { Hash-Of ($text -replace '"written_at":\d+,?', '') }

$key = Read-Key
Write-Host "Watching $outDir"
Write-Host "Sending changes to $endpoint every $CheckSeconds s. Close this window to stop."

while ($true) {
    if (Test-Path $outDir) {
        foreach ($file in Get-ChildItem -Path $outDir -Filter '*.json' -File) {
            try {
                $body = Get-Content -Raw -Encoding UTF8 $file.FullName
                $ck = Content-Key $body
                if ($sent[$file.FullName] -eq $ck) { continue }
                $r = Invoke-RestMethod -Method Post -Uri $endpoint -ContentType 'application/json; charset=utf-8' `
                    -Headers @{ Authorization = "Bearer $key" } -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
                $sent[$file.FullName] = $ck
                $ticked = if ($r.milestones_ticked -and $r.milestones_ticked.Count) { ' New milestones: ' + ($r.milestones_ticked -join ', ') } else { '' }
                Write-Host ("{0:HH:mm:ss} {1} updated.{2}" -f (Get-Date), $file.BaseName, $ticked)
            } catch {
                $msg = $_.Exception.Message
                $answered = [bool]$_.ErrorDetails.Message    # the portal replied (not a network error)
                try { $msg = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch {}
                Write-Host ("{0:HH:mm:ss} {1}: {2}" -f (Get-Date), $file.BaseName, $msg) -ForegroundColor Yellow
                if ($msg -match 'key') {
                    Remove-Item $keyFile -ErrorAction SilentlyContinue
                    $key = Read-Key
                } elseif ($answered) {
                    $sent[$file.FullName] = Content-Key $body   # refused: don't resend it until it changes
                }
            }
        }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $CheckSeconds
}
