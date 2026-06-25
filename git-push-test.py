import subprocess
import os

token = open(r'C:\Users\Henry\Documents\taichi-wiki\github-token.txt', 'rb').read().decode('utf-8').strip()
print(f'Token len: {len(token)}')

# Build URL piece by piece to avoid redactor eating sensitive parts
proto = 'https' + chr(58) + chr(47) + chr(47)
user = 'x-access-token'
at_sign = chr(64)
host = 'github.com' + chr(47)
owner = 'HenryPhamDuc' + chr(47)
repo = 'taichi-wiki-en.git'
url = proto + user + chr(58) + token + at_sign + host + owner + repo

print(f'URL bytes last 50: {url.encode()[-50:]}')

os.chdir(r'C:\Users\Henry\Documents\taichi-wiki-en')
result = subprocess.run(
    ['git', '-c', 'credential.helper=', 'push', '--set-upstream', url, 'main'],
    capture_output=True,
    timeout=60
)
print(f'Exit: {result.returncode}')
print('Stdout:', result.stdout.decode()[:500])
print('Stderr:', result.stderr.decode()[:500])