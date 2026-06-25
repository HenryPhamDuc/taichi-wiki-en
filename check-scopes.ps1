$t = (Get-Content 'C:\Users\Henry\Documents\taichi-wiki\github-token.txt' -Raw).Trim()
$auth = 'Authorization: token *** + $t
$h = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers @{Authorization = $auth} -UseBasicParsing
Write-Host 'Status:' $h.StatusCode
Write-Host 'X-OAuth-Scopes:' $h.Headers['X-OAuth-Scopes']
Write-Host 'X-Accepted-OAuth-Scopes:' $h.Headers['X-Accepted-OAuth-Scopes']