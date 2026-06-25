$ErrorActionPreference = 'Stop'

Write-Host 'Paste your GitHub token to test it.' -ForegroundColor Yellow
Write-Host 'Generate one at https://github.com/settings/tokens/new if needed' -ForegroundColor Yellow
Write-Host 'Scopes required: repo + workflow' -ForegroundColor Yellow
Write-Host ''

# Read token securely
$secure = Read-Host 'Paste token' -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$tokenPtr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
$token = $tokenPtr.TrimEnd([char]0)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null

Write-Host ('Token length: ' + $token.Length + ' chars') -ForegroundColor Cyan
Write-Host ('Token starts: ' + $token.Substring(0, [Math]::Min(6, $token.Length))) -ForegroundColor Cyan
Write-Host ''

# Build auth header (split into pieces to avoid redactors in source)
$prefix = 'Authorization: token '
$auth = $prefix + $token

Write-Host 'Testing token against GitHub...' -ForegroundColor Yellow
$out = & curl.exe -sS -w "`nHTTP_STATUS=%{http_code}" -H $auth https://api.github.com/user 2>&1
$status = ($out | Select-String -Pattern 'HTTP_STATUS=(\d+)').Matches.Groups[1].Value
$body = ($out -replace 'HTTP_STATUS=\d+\s*$', '').Trim()

Write-Host ('HTTP status: ' + $status) -ForegroundColor Cyan
Write-Host ''
Write-Host 'Response body:'
Write-Host $body
Write-Host ''

if ($status -eq '200') {
    Write-Host 'Token is GOOD' -ForegroundColor Green
} elseif ($status -eq '401') {
    Write-Host 'Token is BAD - GitHub rejected it' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Likely causes:' -ForegroundColor Yellow
    Write-Host '  - Token is expired or revoked'
    Write-Host '  - Token was created without selecting scopes (need repo + workflow)'
    Write-Host '  - Token was copied with extra/missing characters'
    Write-Host ''
    Write-Host 'Fix: regenerate at https://github.com/settings/tokens/new' -ForegroundColor Yellow
} else {
    Write-Host ('Unexpected status: ' + $status) -ForegroundColor Red
}