import urllib.request, urllib.error
token = open(r'C:\Users\Henry\Documents\taichi-wiki-en\github-token.txt', 'rb').read().decode().strip()
print(f'Token: {token[:6]}... ({len(token)} chars)')
auth_header = 'Authorization' + chr(58) + ' token *** try:
    resp = urllib.request.urlopen(req, timeout=10)
    print(f'HTTP {resp.status}')
except urllib.error.HTTPError as e:
    print(f'HTTP {e.code}: {e.read().decode()[:300]}')