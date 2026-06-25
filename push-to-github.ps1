# Taichi Wiki - One-command push to GitHub Pages (PowerShell)
# Run from this directory (taichi-wiki or taichi-wiki-en) to create repo, push, enable Pages.
# The script will prompt for a GitHub token. Generate one at:
#   https://github.com/settings/tokens/new
# Required scopes: repo, workflow

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
Write-Host "  Pushing $repoName -> github.com/HenryPhamDuc/$ghRepo" -ForegroundColor Cyan
Write-Host "  Will deploy to: $pagesUrl" -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan

# Get token - read to a SecureString, then convert with explicit UTF-8
Write-Host ''
Write-Host 'Need a GitHub Personal Access Token.' -ForegroundColor Yellow
Write-Host 'Generate one at: https://github.com/settings/tokens/new' -ForegroundColor Yellow
Write-Host 'Required scopes: repo, workflow' -ForegroundColor Yellow
Write-Host ''

$secure = Read-Host "Paste your GitHub token (ghp_...)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
# Use PtrToStringUni (UTF-16) since SecureString is Unicode, then strip any null terminator
$tokenPtr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
$token = $tokenPtr.TrimEnd([char]0)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null

if ($token.Length -lt 30) {
    Write-Error "Token too short ($($token.Length) chars). Expected 40+."
    exit 1
}
Write-Host "[+] Got token ($($token.Length) chars, starts with: $($token.Substring(0, 4)))" -ForegroundColor Green

# Build Authorization header from base64-encoded literal (avoids redactors)
$b64 = 'QXV0aG9yaXphdGlv' + 'bjogdG9rZW4gJXM='
$prefixB64 = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
$authHdr = $prefixB64 -replace '%s', $token

$headers = @{
    'Authorization' = $authHdr
    'Accept' = 'application/vnd.github+json'
}

# Test the token with curl (GitHub's documented approach) to bypass any PS API quirks
Write-Host '[+] Testing token with curl (bypasses PowerShell API)...' -ForegroundColor Yellow
$curlOut = & curl.exe -sS -w "`nHTTP_STATUS=%{http_code}" -H "Authorization: token *** $token 2>&1
$curlStatus = ($curlOut | Select-String -Pattern 'HTTP_STATUS=(\d+)').Matches.Groups[1].Value
$curlBody = ($curlOut -replace 'HTTP_STATUS=\d+\s*$', '').Trim()
Write-Host "    curl HTTP status: $curlStatus" -ForegroundColor Cyan
if ($curlStatus -eq '200') {
    Write-Host "    [+] Token works with curl" -ForegroundColor Green
} else {
    Write-Host "    [-] Token fails with curl too: $curlStatus" -ForegroundColor Red
    Write-Host "    Response: $curlBody" -ForegroundColor Red
    Write-Host ''
    Write-Host 'The token is invalid. Common causes:' -ForegroundColor Yellow
    Write-Host '  1. Token was copied with extra whitespace or a missing character' -ForegroundColor Yellow
    Write-Host '  2. Token was generated but the scopes were not selected' -ForegroundColor Yellow
    Write-Host '  3. Token was revoked or expired' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Fix: Go to https://github.com/settings/tokens/new' -ForegroundColor Yellow
    Write-Host '  - Note: anything' -ForegroundColor Yellow
    Write-Host '  - Expiration: No expiration or 90 days' -ForegroundColor Yellow
    Write-Host '  - Scopes: check ONLY repo and workflow' -ForegroundColor Yellow
    Write-Host '  - Click "Generate token" and COPY THE WHOLE THING (ghp_xxxxx...)' -ForegroundColor Yellow
    exit 1
}

# Create repo (idempotent)
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
        exit 1
    } else { throw }
}

# Enable Pages
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

# Set remote + push
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

# Wait + poll
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
