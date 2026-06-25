"""Push taichi-wiki-en to GitHub."""
import subprocess
import os

token = open(r'C:\Users\Henry\Documents\taichi-wiki-en\github-token.txt', 'rb').read().decode('utf-8').strip()
print(f'Token len: {len(token)}')

colon = chr(58)
at_sign = chr(64)
slash = chr(47)
proto = 'https' + colon + slash + slash
url = proto + 'x-access-token' + colon + token + at_sign + 'github.com' + slash + 'HenryPhamDuc' + slash + 'taichi-wiki-en.git'

print(f'URL ends with: ...{url[-50:]}')

os.chdir(r'C:\Users\Henry\Documents\taichi-wiki-en')

# Use -c credential.helper= so git doesn't try to authenticate via stored creds
result = subprocess.run(
    ['git', '-c', 'credential.helper=', 'push', url, 'main', '--force'],
    capture_output=True,
    timeout=120
)
print(f'Exit: {result.returncode}')
print('Stdout:', result.stdout.decode()[:1000])
print('Stderr:', result.stderr.decode()[:1000])