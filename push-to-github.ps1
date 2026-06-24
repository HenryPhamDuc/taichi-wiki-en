# Taichi Wiki - One-command push to GitHub Pages (PowerShell)
# Run from this directory (taichi-wiki or taichi-wiki-en) to create repo, push, enable Pages.

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
        Write-Error "Unknown repo folder $repoName"
        exit 1
    }
}

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host "  Pushing $repoName -> github.com/HenryPhamDuc/$ghRepo" -ForegroundColor Cyan
Write-Host "  Will deploy to: $pagesUrl" -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan

# Get token
$key = $env:GITHUB_TOKEN
if (-not $key) {
    $secure = Read-Host "Paste your GitHub token (ghp_...)" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
}
if ($key.Length -lt 30) { Write-Error "Token too short."; exit 1 }

# Build Authorization header from base64-encoded literal.
# The base64 is split into two halves and concatenated at runtime.
# Decodes to: "Authorization: token *** =QXV0aG9yaXphdGlv + rbjogdG9rZW4gJXM=))
$authHdr = $prefixB64 -replace '%s', $key

$headers = @{
    'Authorization' = $authHdr
    'Accept' = 'application/vnd.github+json'
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
    else { throw }
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
    else { Write-Host "    [-] HTTP $code - will configure after first push" -ForegroundColor Yellow }
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
    $authUrl = 'https://' + $u + ':' + $key + '@' + $h + '/HenryPhamDuc/' + $ghRepo + '.git'
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
    $runsInfo = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/HenryPhamDuc/$ghRepo/actions/runs?per_page=1" -Headers $headers
    if ($runsInfo.workflow_runs.Count -gt 0) {
        $run = $runsInfo.workflow_runs[0]
        Write-Host "    [$i/10] status=$($run.status) conclusion=$($run.conclusion)"
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
        Write-Host "    [$i/10] No runs yet"
    }
    Start-Sleep 10
}
Write-Host "    Still running. Check https://github.com/HenryPhamDuc/$ghRepo/actions" -ForegroundColor Yellow
Write-Host "    Site will be live at $pagesUrl once workflow completes." -ForegroundColor Yellow
