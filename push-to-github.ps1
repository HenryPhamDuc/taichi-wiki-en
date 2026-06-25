# Taichi Wiki - One-command push to GitHub Pages (PowerShell)
# Usage: cd to taichi-wiki or taichi-wiki-en folder, then run this script.
# It will prompt for a GitHub Personal Access Token (scopes: repo, workflow).
# Generate one at: https://github.com/settings/tokens/new

$ErrorActionPreference = 'Stop'

$repoName = Split-Path (Get-Location).Path -Leaf
$ghRepo = ''
$pagesUrl = ''
$desc = ''

if ($repoName -eq 'taichi-wiki') {
    $ghRepo = 'taichi-wiki'
    $pagesUrl = 'https://henryPhamDuc.github.io/taichi-wiki/'
    $desc = 'VI: Bach khoa toan thu mo ve Thai Cuc Quyen'
} elseif ($repoName -eq 'taichi-wiki-en') {
    $ghRepo = 'taichi-wiki-en'
    $pagesUrl = 'https://henryPhamDuc.github.io/taichi-wiki-en/'
    $desc = 'EN: Open encyclopedia of Tai Chi Chuan'
} else {
    Write-Error ("Run from taichi-wiki or taichi-wiki-en folder (got: " + $repoName + ")")
    exit 1
}

Write-Host ''
Write-Host '================================================================'
Write-Host ('  Pushing ' + $repoName + ' -> github.com/HenryPhamDuc/' + $ghRepo)
Write-Host ('  Will deploy to: ' + $pagesUrl)
Write-Host '================================================================'
Write-Host ''

# Get token via Read-Host -AsSecureString (handles long opaque strings safely)
$secure = Read-Host "Paste your GitHub token (ghp_...)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$tokenPtr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
$token = $tokenPtr.TrimEnd([char]0)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null

if ($token.Length -lt 30) {
    Write-Error ("Token too short (" + $token.Length + " chars). Expected 40+.")
    exit 1
}
Write-Host ('[+] Got token (' + $token.Length + ' chars)')
Write-Host ''

# Test the token with curl (most reliable method on Windows)
Write-Host '[+] Testing token with curl...'
$curlOut = & curl.exe -sS -w ("`nHTTP_STATUS=%{http_code}") -H ("Authorization: token " + $token) https://api.github.com/user 2>&1
$statusMatch = $curlOut | Select-String -Pattern 'HTTP_STATUS=(\d+)'
if ($statusMatch) {
    $curlStatus = $statusMatch.Matches.Groups[1].Value
} else {
    $curlStatus = 'unknown'
}
Write-Host ('    HTTP ' + $curlStatus)

if ($curlStatus -ne '200') {
    Write-Host ''
    Write-Host 'Token is invalid. Common causes:' -ForegroundColor Yellow
    Write-Host '  1. Token was copied with extra whitespace or a missing character'
    Write-Host '  2. Token was generated but the scopes were not selected'
    Write-Host '  3. Token was revoked or expired'
    Write-Host ''
    Write-Host 'Fix: Go to https://github.com/settings/tokens/new'
    Write-Host '  - Note: anything'
    Write-Host '  - Expiration: 90 days or No expiration'
    Write-Host '  - Scopes: check ONLY repo and workflow'
    Write-Host '  - Click Generate token and COPY THE WHOLE ghp_xxxxx string'
    exit 1
}
Write-Host '    [OK] Token works' -ForegroundColor Green
Write-Host ''

# Build repo
Write-Host '[+] Creating GitHub repo (if not exists)...'
$createBody = ('{"name":"' + $ghRepo + '","description":"' + $desc + '","private":false,"auto_init":false}')
$createOut = & curl.exe -sS -w ("`nHTTP_STATUS=%{http_code}") -X POST -H ("Authorization: token " + $token) -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" -d $createBody ("https://api.github.com/repos/HenryPhamDuc/" + $ghRepo) 2>&1
$createStatus = ($createOut | Select-String -Pattern 'HTTP_STATUS=(\d+)').Matches.Groups[1].Value
if ($createStatus -eq '201') {
    Write-Host '    [OK] Created' -ForegroundColor Green
} elseif ($createStatus -eq '422') {
    Write-Host '    [OK] Already exists' -ForegroundColor Yellow
} else {
    Write-Host ('    [ERR] HTTP ' + $createStatus) -ForegroundColor Red
    exit 1
}

# Enable Pages
Write-Host '[+] Enabling GitHub Pages...'
$pagesBody = '{"build_type":"workflow","source":{"branch":"main","path":"/"}}'
$pagesOut = & curl.exe -sS -w ("`nHTTP_STATUS=%{http_code}") -X POST -H ("Authorization: token " + $token) -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" -d $pagesBody ("https://api.github.com/repos/HenryPhamDuc/" + $ghRepo + "/pages") 2>&1
$pagesStatus = ($pagesOut | Select-String -Pattern 'HTTP_STATUS=(\d+)').Matches.Groups[1].Value
if ($pagesStatus -eq '201') {
    Write-Host '    [OK] Pages enabled' -ForegroundColor Green
} elseif ($pagesStatus -eq '409' -or $pagesStatus -eq '422') {
    Write-Host '    [OK] Pages already enabled' -ForegroundColor Yellow
} else {
    Write-Host ('    [WARN] HTTP ' + $pagesStatus + ' (will retry after push)')
}

# Set remote + push
Write-Host ('[+] Setting remote to https://github.com/HenryPhamDuc/' + $ghRepo + '.git')
git remote remove origin 2>$null
git remote add origin ("https://github.com/HenryPhamDuc/" + $ghRepo + ".git")

Write-Host '[+] Pushing to main...'
$tmpFile = New-TemporaryFile
try {
    $authUrl = "https://x-access-token:" + $token + "@github.com/HenryPhamDuc/" + $ghRepo + ".git"
    Set-Content -Path $tmpFile -Value $authUrl -NoNewline
    $urlForGit = Get-Content $tmpFile -Raw
    git push --set-upstream $urlForGit main
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}

# Wait + poll
Write-Host ''
Write-Host '[+] Waiting 30s for first deploy...'
Start-Sleep 30

for ($i = 1; $i -le 10; $i++) {
    $runsOut = & curl.exe -sS -H ("Authorization: token " + $token) -H "Accept: application/vnd.github+json" ("https://api.github.com/repos/HenryPhamDuc/" + $ghRepo + "/actions/runs?per_page=1") 2>&1
    $statusMatch = $runsOut | Select-String -Pattern '"status":"(\w+)"'
    $conclMatch = $runsOut | Select-String -Pattern '"conclusion":"(\w+)"'
    $runStatus = if ($statusMatch) { $statusMatch.Matches.Groups[1].Value } else { 'none' }
    $runConcl  = if ($conclMatch) { $conclMatch.Matches.Groups[1].Value } else { 'none' }
    Write-Host ('    [' + $i + '/10] status=' + $runStatus + ' conclusion=' + $runConcl)
    if ($runStatus -eq 'completed') {
        if ($runConcl -eq 'success') {
            Write-Host ''
            Write-Host '================================================================'
            Write-Host ('  Deployed! Site: ' + $pagesUrl)
            Write-Host '================================================================'
            exit 0
        } else {
            Write-Host ('    Build failed: ' + $runConcl) -ForegroundColor Red
            Write-Host ('    Check: https://github.com/HenryPhamDuc/' + $ghRepo + '/actions') -ForegroundColor Red
            exit 1
        }
    }
    Start-Sleep 10
}

Write-Host ('    Still running. Check https://github.com/HenryPhamDuc/' + $ghRepo + '/actions')
Write-Host ('    Site will be live at ' + $pagesUrl + ' once workflow completes.')
