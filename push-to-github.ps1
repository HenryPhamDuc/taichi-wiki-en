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
    Write-Error ('Run from taichi-wiki or taichi-wiki-en folder (got: ' + $repoName + ')')
    exit 1
}

Write-Host ''
Write-Host '================================================================'
Write-Host ('  Pushing ' + $repoName + ' -> github.com/HenryPhamDuc/' + $ghRepo)
Write-Host ('  Will deploy to: ' + $pagesUrl)
Write-Host '================================================================'
Write-Host ''

# Get token: prefer file (avoids clipboard/SecureString issues)
$token = ''
if ($env:TOKEN_FILE -and (Test-Path $env:TOKEN_FILE)) {
    $token = (Get-Content $env:TOKEN_FILE -Raw).Trim()
    Write-Host ('Loaded token from: ' + $env:TOKEN_FILE)
} elseif (Test-Path (Join-Path (Get-Location) 'github-token.txt')) {
    $token = (Get-Content (Join-Path (Get-Location) 'github-token.txt') -Raw).Trim()
    Write-Host 'Loaded token from github-token.txt'
} else {
    $secure = Read-Host 'Paste your GitHub token (ghp_...)' -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $tokenPtr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    $token = $tokenPtr.TrimEnd([char]0)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
}

if ($token.Length -lt 30) {
    Write-Error ('Token too short (' + $token.Length + ' chars). Expected 40+.')
    exit 1
}
Write-Host ('Got token (' + $token.Length + ' chars)')
Write-Host ''

# Helper: extract HTTP status from curl output (using STATUS= format)
function Get-CurlStatus {
    param([string]$Output)
    $m = $Output | Select-String -Pattern 'STATUS=(\d+)'
    if ($m) { return $m.Matches.Groups[1].Value } else { return 'unknown' }
}

# Build auth in pieces - use -u "user:token" form (works reliably)
# Note: -H "Authorization: token *** caused 400 "Problems parsing JSON"
$authUser = 'HenryPhamDuc'
$authToken = $token
$authFlag = '-u'
$authArg = ($authUser + ':' + $authToken)

# Test the token with curl
Write-Host 'Testing token with curl...'
$formatFile = New-TemporaryFile
Set-Content -Path $formatFile -Value 'STATUS=%{http_code}' -NoNewline
$testOut = & curl.exe -sS -w ('@' + $formatFile.FullName) $authFlag $authArg https://api.github.com/user 2>&1
Remove-Item $formatFile -Force -ErrorAction SilentlyContinue
$testStatus = Get-CurlStatus $testOut
Write-Host ('  HTTP ' + $testStatus)
if ($testStatus -ne '200') {
    Write-Host ''
    Write-Host 'Token is invalid. Common causes:'
    Write-Host '  1. Token copied with extra whitespace'
    Write-Host '  2. Token generated without selecting scopes'
    Write-Host '  3. Token revoked or expired'
    Write-Host ''
    Write-Host 'Fix: regenerate at https://github.com/settings/tokens/new'
    Write-Host '  - Note: anything'
    Write-Host '  - Expiration: 90 days or No expiration'
    Write-Host '  - Scopes: check ONLY repo and workflow'
    exit 1
}
Write-Host '  Token works'
Write-Host ''

# Create repo
Write-Host 'Creating GitHub repo (if not exists)...'
$repoObj = @{ name = $ghRepo; description = $desc; private = $false; auto_init = $false }
$createBody = $repoObj | ConvertTo-Json -Compress
$createUrl = 'https://api.github.com/repos/HenryPhamDuc/' + $ghRepo

$bodyFile = New-TemporaryFile
Set-Content -Path $bodyFile -Value $createBody -NoNewline -Encoding UTF8

$formatFile = New-TemporaryFile
Set-Content -Path $formatFile -Value 'STATUS=%{http_code}' -NoNewline
Write-Host ('  bodyFile: ' + $bodyFile.FullName + ' size=' + (Get-Item $bodyFile).Length)
Write-Host ('  bodyFile content: ' + (Get-Content $bodyFile -Raw))
Write-Host ('  createBody length: ' + $createBody.Length)
Write-Host ('  authArg: ' + $authUser + ':<token-len=' + $token.Length + '>')
$createOut = & curl.exe -sS -w ('@' + $formatFile.FullName) -X POST $authFlag $authArg -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile.FullName) $createUrl 2>&1
Remove-Item $formatFile -Force -ErrorAction SilentlyContinue
Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
$createStatus = Get-CurlStatus $createOut
if ($createStatus -eq '201') {
    Write-Host '  Created'
} elseif ($createStatus -eq '422') {
    Write-Host '  Already exists'
} else {
    Write-Host ('  HTTP ' + $createStatus + ': ' + ($createOut -replace 'STATUS=\d+\s*$', '').Trim())
    exit 1
}

# Enable Pages
Write-Host 'Enabling GitHub Pages...'
$pagesObj = @{ build_type = 'workflow'; source = @{ branch = 'main'; path = '/' } }
$pagesBody = $pagesObj | ConvertTo-Json -Compress
$pagesApiUrl = 'https://api.github.com/repos/HenryPhamDuc/' + $ghRepo + '/pages'

$bodyFile = New-TemporaryFile
Set-Content -Path $bodyFile -Value $pagesBody -NoNewline -Encoding UTF8
$formatFile = New-TemporaryFile
Set-Content -Path $formatFile -Value 'STATUS=%{http_code}' -NoNewline
$pagesOut = & curl.exe -sS -w ('@' + $formatFile.FullName) -X POST $authFlag $authArg -H 'Accept: application/vnd.github+json' -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile.FullName) $pagesApiUrl 2>&1
Remove-Item $formatFile -Force -ErrorAction SilentlyContinue
Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
$pagesStatus = Get-CurlStatus $pagesOut
if ($pagesStatus -eq '201') {
    Write-Host '  Pages enabled'
} elseif ($pagesStatus -eq '409' -or $pagesStatus -eq '422') {
    Write-Host '  Pages already enabled'
} else {
    Write-Host ('  HTTP ' + $pagesStatus + ' (will retry after first push)')
}

# Set remote + push
Write-Host ('Setting remote to https://github.com/HenryPhamDuc/' + $ghRepo + '.git')
git remote remove origin 2>$null
git remote add origin ('https://github.com/HenryPhamDuc/' + $ghRepo + '.git')

Write-Host 'Pushing to main...'
$tmpFile = New-TemporaryFile
try {
    $proto = 'https://'
    $user = 'x-access-token'
    $at = '@'
    $ghHost = 'github.com/'
    $owner = 'HenryPhamDuc/'
    $repoGit = $ghRepo + '.git'
    $authUrl = $proto + $user + ':' + $token + $at + $ghHost + $owner + $repoGit
    Set-Content -Path $tmpFile -Value $authUrl -NoNewline
    $urlForGit = Get-Content $tmpFile -Raw
    git push --set-upstream $urlForGit main
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}

# Wait + poll
Write-Host ''
Write-Host 'Waiting 30s for first deploy...'
Start-Sleep 30

for ($i = 1; $i -le 10; $i++) {
    $runsUrl = 'https://api.github.com/repos/HenryPhamDuc/' + $ghRepo + '/actions/runs?per_page=1'
    $runsOut = & curl.exe -sS $authFlag $authArg -H 'Accept: application/vnd.github+json' $runsUrl 2>&1
    $statusMatch = $runsOut | Select-String -Pattern '"status":"(\w+)"'
    $conclMatch  = $runsOut | Select-String -Pattern '"conclusion":"(\w+)"'
    $runStatus = if ($statusMatch) { $statusMatch.Matches.Groups[1].Value } else { 'none' }
    $runConcl  = if ($conclMatch)  { $conclMatch.Matches.Groups[1].Value  } else { 'none' }
    Write-Host ('  [' + $i + '/10] status=' + $runStatus + ' conclusion=' + $runConcl)
    if ($runStatus -eq 'completed') {
        if ($runConcl -eq 'success') {
            Write-Host ''
            Write-Host '================================================================'
            Write-Host ('  Deployed! Site: ' + $pagesUrl)
            Write-Host '================================================================'
            exit 0
        } else {
            Write-Host ('  Build failed: ' + $runConcl)
            Write-Host ('  Check: https://github.com/HenryPhamDuc/' + $ghRepo + '/actions')
            exit 1
        }
    }
    Start-Sleep 10
}

Write-Host ('  Still running. Check https://github.com/HenryPhamDuc/' + $ghRepo + '/actions')
Write-Host ('  Site will be live at ' + $pagesUrl + ' once workflow completes.')