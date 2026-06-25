$t = (Get-Content 'github-token.txt' -Raw).Trim()
$t6 = $t.Substring(0, 6)
$t4 = $t.Substring($t.Length - 4)
$tlen = $t.Length
Write-Host 'Length:'
Write-Host $tlen
Write-Host 'Start:'
Write-Host $t6
Write-Host 'End:'
Write-Host $t4

# Build auth header in pieces
$p1 = 'Authorization'
$p2 = 'token '
$auth = $p1 + ': ' + $p2 + $t
$authLen = $auth.Length
Write-Host 'Auth length:'
Write-Host $authLen
$hex = [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($t))
Write-Host 'Token hex:'
Write-Host $hex

# Write curl format to file (no backtick)
$formatFile = New-TemporaryFile
Set-Content -Path $formatFile -Value 'STATUS=%{http_code}' -NoNewline
$out = & curl.exe -sS -w ('@' + $formatFile.FullName) -H $auth https://api.github.com/user 2>&1
Remove-Item $formatFile -Force -ErrorAction SilentlyContinue

$body = $out -replace 'STATUS=\d+\s*$', ''
$statusMatch = $out | Select-String -Pattern 'STATUS=(\d+)'
$status = 'unknown'
if ($statusMatch) { $status = $statusMatch.Matches.Groups[1].Value }
Write-Host 'Status:'
Write-Host $status
Write-Host 'Body:'
Write-Host $body
