# Test script: paste your token, see exactly what happens
Write-Host "Test 1: Read-Host with -AsSecureString"
$secure = Read-Host "Paste token" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
Write-Host "  Got: $($plain.Length) chars"
Write-Host "  First 5: $($plain.Substring(0, [Math]::Min(5, $plain.Length)))..."
Write-Host ""

Write-Host "Test 2: env var"
$envToken = $env:GITHUB_TOKEN
if ($envToken) {
    Write-Host "  GITHUB_TOKEN: $($envToken.Length) chars"
    Write-Host "  First 5: $($envToken.Substring(0, [Math]::Min(5, $envToken.Length)))..."
} else {
    Write-Host "  GITHUB_TOKEN: NOT SET"
}
Write-Host ""

Write-Host "Test 3: Test the token against GitHub"
if ($envToken) {
    $b64 = 'QXV0aG9yaXphdGlv' + 'bjogdG9rZW4gJXM='
    $prefix = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $auth = $prefix -replace '%s', $envToken
    try {
        $r = Invoke-RestMethod -Method Get -Uri 'https://api.github.com/user' -Headers @{
            'Authorization' = $auth
            'Accept' = 'application/vnd.github+json'
        }
        Write-Host "  OK - logged in as: $($r.login)"
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "  FAILED: HTTP $code"
        Write-Host "  Reason: $($_.Exception.Message)"
    }
}
