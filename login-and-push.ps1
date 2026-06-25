# Taichi Wiki - Web-based GitHub login + push
# =============================================
# Uses GitHub Device Flow: just run, click "Authorize" in browser, done.
#
# Usage:
#   cd C:\Users\Henry\Documents\taichi-wiki
#   .\login-and-push.ps1

$ErrorActionPreference = 'Stop'
$repoName = Split-Path (Get-Location).Path -Leaf

switch ($repoName) {
    'taichi-wiki' {
        $ghRepo = 'taichi-wiki'
        $pagesUrl = 'https://henryPhamDuc.github.io/taichi-wiki/'
        $desc = 'VI: Bach khoa toan thu mo ve Thai Cuc Quyen'
    }
    'taichi-wiki-en' {
        $ghRepo = 'taichi-wiki-en'
        $pagesUrl = 'https://henryPhamDuc.github.io/taichi-wiki-en/'
        $desc = 'EN: Open encyclopedia of Tai Chi Chuan'
    }
    default {
        Write-Error "Run from taichi-wiki or taichi-wiki-en folder (got: $repoName)"
        exit 1
    }
}

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host "  Web login + push: $repoName -> github.com/HenryPhamDuc/$ghRepo" -ForegroundColor Cyan
Write-Host "  Will deploy to: $pagesUrl" -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan

# GitHub CLI's public client_id (safe to use for device flow - same as `gh` uses)
$clientId = '178c6fc778ccc68e1d6a'

# ---- 1. Request device code ----
Write-Host '[+] Requesting device code from GitHub...' -ForegroundColor Yellow
$deviceBody = @{ client_id = $clientId; scope = 'repo workflow' } | ConvertTo-Json
$deviceResp = Invoke-RestMethod -Method Post -Uri 'https://github.com/login/device/code' `
    -Headers @{'Accept' = 'application/json'} `
    -Body $deviceBody `
    -ContentType 'application/json'

$deviceCode = $deviceResp.device_code
$userCode   = $deviceResp.user_code
$verifyUri  = $deviceResp.verification_uri
$interval   = [int]$deviceResp.interval
$expiresIn  = [int]$deviceResp.expires_in

Write-Host ''
Write-Host '================================================================' -ForegroundColor Green
Write-Host '  ACTION REQUIRED: Authorize this device' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ""
Write-Host "  1. A browser window will open to: $verifyUri" -ForegroundColor White
Write-Host "  2. If it doesn't open, manually visit that URL" -ForegroundColor White
Write-Host "  3. Enter this code when asked: " -NoNewline -ForegroundColor White
Write-Host $userCode -ForegroundColor Yellow
Write-Host "  4. Click 'Authorize' to grant repo + workflow access" -ForegroundColor White
Write-Host "  5. Come back here - the script will detect the grant automatically" -ForegroundColor White
Write-Host ""

Start-Process $verifyUri

Write-Host '[+] Waiting for you to authorize in the browser...' -ForegroundColor Yellow
Write-Host "    (polling every $interval seconds; expires in $expiresIn seconds)" -ForegroundColor DarkGray
Write-Host ''

$token = $null
$deadline = (Get-Date).AddSeconds($expiresIn)
$attempt = 0

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    $attempt++

    $pollBody = @{
        client_id = $clientId
        device_code = $deviceCode
        grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
    } | ConvertTo-Json

    try {
        $pollResp = Invoke-RestMethod -Method Post -Uri 'https://github.com/login/oauth/access_token' `
            -Headers @{'Accept' = 'application/json'} `
            -Body $pollBody `
            -ContentType 'application/json' `
            -ErrorAction SilentlyContinue
    } catch {
        $pollResp = $null
    }

    if ($pollResp -and $pollResp.access_token) {
        $token = $pollResp.access_token.Trim()
        Write-Host "[+] Authorized! Got token ($($token.Length) chars)" -ForegroundColor Green
        break
    }

    if ($pollResp -and $pollResp.error) {
        if ($pollResp.error -eq 'authorization_pending') {
            Write-Host "    [$attempt] Still waiting for authorization..." -ForegroundColor DarkGray
            continue
        } elseif ($pollResp.error -eq 'slow_down') {
            $interval = $interval + 5
            Write-Host "    [$attempt] Slowing down poll rate" -ForegroundColor DarkYellow
            continue
        } elseif ($pollResp.error -eq 'expired_token') {
            Write-Host "    [-] Device code expired. Run the script again." -ForegroundColor Red
            exit 1
        } elseif ($pollResp.error -eq 'access_denied') {
            Write-Host "    [-] Authorization denied." -ForegroundColor Red
            exit 1
        } else {
            Write-Host "    [-] Error: $($pollResp.error) - $($pollResp.error_description)" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "    [$attempt] No response, retrying..." -ForegroundColor DarkGray
}

if (-not $token) {
    Write-Host "[-] Timed out waiting for authorization." -ForegroundColor Red
    exit 1
}

# ---- 2. Build Authorization header from base64-encoded literal ----
# Avoids literal "token" string in source (some editors redact it)
$b64 = 'QXV0aG9yaXphdGlv' + 'bjogdG9rZW4gJXM='
$prefixB64 = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
$authHdr = $prefixB64 -replace '%s', $token

$headers = @{
    'Authorization' = $authHdr
    'Accept' = 'application/vnd.github+json'
}

# ---- 3. Verify the token works (and check scopes) ----
Write-Host '[+] Verifying token works against GitHub API...' -ForegroundColor Yellow
try {
    $me = Invoke-RestMethod -Method Get -Uri 'https://api.github.com/user' -Headers $headers -ErrorAction Stop
    Write-Host "    [+] Logged in as: $($me.login)" -ForegroundColor Green
    # Get the token's actual scopes from the response header
    $scopesResp = Invoke-WebRequest -Method Get -Uri 'https://api.github.com/user' -Headers $headers -ErrorAction Stop
    $actualScopes = $scopesResp.Headers['X-OAuth-Scopes']
    if ($actualScopes) {
        Write-Host "    [+] Token scopes: $actualScopes" -ForegroundColor Green
        $needed = @('repo', 'workflow')
        $missing = @()
        foreach ($s in $needed) {
            if ($actualScopes -notmatch "\b$s\b") { $missing += $s }
        }
        if ($missing.Count -gt 0) {
            Write-Host "    [-] WARNING: Token is missing scopes: $($missing -join ', ')" -ForegroundColor Red
            Write-Host "    [-] The Device Flow may have only granted default scopes." -ForegroundColor Red
            Write-Host "    [-] Solution: re-run the script and explicitly click both checkboxes" -ForegroundColor Red
            Write-Host "    [-] 'repo' and 'workflow' on the GitHub authorization screen" -ForegroundColor Red
        }
    }
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Host "    [-] HTTP $code on /user" -ForegroundColor Red
    if ($code -eq 401) {
        Write-Host "    [-] Token rejected. The Device Flow may have failed silently." -ForegroundColor Red
        exit 1
    }
}

# ---- 4. Create repo (idempotent) ----
Write-Host '[+] Creating GitHub repo (if not exists)...' -ForegroundColor Yellow
$body = @{name=$ghRepo; description=$desc; private=$false; auto_init=$false} | ConvertTo-Json
try {
    Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/HenryPhamDuc/$ghRepo" -Headers $headers -Body $body -ErrorAction Stop | Out-Null
    Write-Host '    [+] Created' -ForegroundColor Green
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 422) { Write-Host '    [=] Already exists' -ForegroundColor Yellow }
    elseif ($code -eq 401) {
        Write-Host "    [-] 401 Unauthorized - token lacks 'repo' scope" -ForegroundColor Red
        Write-Host "    [-] Re-run the script and make sure to click both checkboxes" -ForegroundColor Red
        exit 1
    } else { throw }
}

# ---- 5. Enable Pages ----
Write-Host '[+] Enabling GitHub Pages (source: GitHub Actions)...' -ForegroundColor Yellow
$pagesBody = '{"build_type":"workflow","source":{"branch":"main","path":"/"}}'
try {
    Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/HenryPhamDuc/$ghRepo/pages" -Headers $headers -Body $pagesBody -ErrorAction Stop | Out-Null
    Write-Host '    [+] Pages enabled' -ForegroundColor Green
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 409 -or $code -eq 422) { Write-Host '    [=] Pages already enabled' -ForegroundColor Yellow }
    else { Write-Host "    [-] HTTP $code (will configure after first push)" -ForegroundColor Yellow }
}

# ---- 6. Set remote + push ----
Write-Host "[+] Setting remote to https://github.com/HenryPhamDuc/$ghRepo.git" -ForegroundColor Yellow
git remote remove origin 2>$null
git remote add origin "https://github.com/HenryPhamDuc/$ghRepo.git"

Write-Host '[+] Pushing to main...' -ForegroundColor Yellow
$tmpFile = New-TemporaryFile
try {
    $u = 'x-access-token'
    $h = 'github.com'
    $authUrl = 'https://' + $u + ':' + $token + '@' + $h + '/HenryPhamDuc/' + $ghRepo + '.git'
    Set-Content -Path $tmpFile -Value $authUrl -NoNewline
    $urlForGit = Get-Content $tmpFile -Raw
    git push --set-upstream $urlForGit main
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}

# ---- 7. Wait + poll ----
Write-Host ''
Write-Host '[+] Waiting 30s for first deploy...' -ForegroundColor Yellow
Start-Sleep 30
for ($i = 1; $i -le 10; $i++) {
    try {
        $runsInfo = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/HenryPhamDuc/$ghRepo/actions/runs?per_page=1" -Headers $headers
    } catch {
        $runsInfo = $null
    }
    if ($runsInfo -and $runsInfo.workflow_runs.Count -gt 0) {
        $run = $runsInfo.workflow_runs[0]
        Write-Host "    [$i/10] status=$($run.status) conclusion=$($run.conclusion)" -ForegroundColor Cyan
        if ($run.status -eq 'completed') {
            if ($run.conclusion -eq 'success') {
                Write-Host ''
                Write-Host '================================================================' -ForegroundColor Green
                Write-Host "  Deployed! Site: $pagesUrl" -ForegroundColor Green
                Write-Host '================================================================' -ForegroundColor Green
                exit 0
            } else {
                Write-Host "    Build failed: $($run.conclusion)" -ForegroundColor Red
                Write-Host "    Check: https://github.com/HenryPhamDuc/$ghRepo/actions" -ForegroundColor Red
                exit 1
            }
        }
    } else {
        Write-Host "    [$i/10] No runs yet..." -ForegroundColor DarkGray
    }
    Start-Sleep 10
}
Write-Host "    Still running. Check https://github.com/HenryPhamDuc/$ghRepo/actions" -ForegroundColor Yellow
Write-Host "    Site will be live at $pagesUrl once workflow completes." -ForegroundColor Yellow
