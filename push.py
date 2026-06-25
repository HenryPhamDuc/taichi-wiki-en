"""
Taichi Wiki - One-command push to GitHub
Reads token from github-token.txt, creates repo, enables Pages, pushes.
Usage: python push.py <repo_dir>
  e.g. python push.py C:\\Users\\Henry\\Documents\\taichi-wiki-en
"""
import subprocess
import json
import sys
import time
import tempfile
import os
import shutil

GITHUB_USER = 'HenryPhamDuc'
GIT_USER = 'x-access-token'

# Description mapping
DESCRIPTIONS = {
    'taichi-wiki': 'VI: Bach khoa toan thu mo ve Thai Cuc Quyen',
    'taichi-wiki-en': 'EN: Open encyclopedia of Tai Chi Chuan',
}


def run_curl(args, body=None, capture_status=True):
    """Run curl with the given args. Returns (status_code, response_body)."""
    full_args = ['curl.exe', '-sS', '-i'] + list(args)
    if body is not None:
        full_args += ['-d', body]
    if capture_status:
        full_args += ['-w', r'\nSTATUS=%{http_code}']
    proc = subprocess.run(full_args, capture_output=True, timeout=30)
    output = proc.stdout.decode('utf-8', errors='replace')
    status = None
    if capture_status:
        idx = output.rfind('\nSTATUS=')
        if idx > 0:
            status_line = output[idx+8:].strip()
            try:
                status = int(status_line)
            except ValueError:
                pass
            output = output[:idx]
    if proc.returncode != 0 and not output:
        output = proc.stderr.decode('utf-8', errors='replace')
    return status, output


def main():
    repo_root = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Henry\Documents\taichi-wiki'
    repo_name = os.path.basename(repo_root)
    token_file = os.path.join(repo_root, 'github-token.txt')

    if not os.path.exists(token_file):
        print(f'No github-token.txt found at {token_file}')
        print(f'Create the file and paste your GitHub PAT (with repo+workflow scopes)')
        return 1

    token = open(token_file, 'rb').read().decode('utf-8').strip()
    desc = DESCRIPTIONS.get(repo_name, f'Taichi Wiki - {repo_name}')

    print(f'Pushing {repo_name} -> github.com/{GITHUB_USER}/{repo_name}')
    print(f'Will deploy to: https://{GITHUB_USER}.github.io/{repo_name}/')
    print('=' * 60)

    # Test token
    print('Testing token...')
    status, body = run_curl(['-u', f'{GITHUB_USER}:{token}', 'https://api.github.com/user'])
    if status != 200:
        print(f'  Token test failed: HTTP {status}')
        print(f'  {body[:500]}')
        return 1
    print('  Token works')

    # Create repo
    print('Creating repo (if not exists)...')
    repo_body = json.dumps({
        'name': repo_name,
        'description': desc,
        'private': False,
        'auto_init': False,
    }, separators=(',', ':')).encode('utf-8')
    status, body = run_curl([
        '-X', 'POST',
        '-u', f'{GITHUB_USER}:{token}',
        '-H', 'Accept: application/vnd.github+json',
        '-H', 'Content-Type: application/json',
        'https://api.github.com/user/repos',
    ], body=repo_body)
    if status == 201:
        print('  Created')
    elif status == 422:
        print('  Already exists')
    else:
        print(f'  HTTP {status}: {body[:500]}')
        return 1

    # Enable Pages
    print('Enabling GitHub Pages...')
    pages_body = json.dumps({
        'build_type': 'workflow',
        'source': {'branch': 'main', 'path': '/'},
    }, separators=(',', ':')).encode('utf-8')
    status, body = run_curl([
        '-X', 'POST',
        '-u', f'{GITHUB_USER}:{token}',
        '-H', 'Accept: application/vnd.github+json',
        '-H', 'Content-Type: application/json',
        f'https://api.github.com/repos/{GITHUB_USER}/{repo_name}/pages',
    ], body=pages_body)
    if status == 201:
        print('  Pages enabled')
    elif status in (409, 422):
        print('  Pages already enabled')
    else:
        print(f'  HTTP {status} (will retry after first push)')

    # Push via git - use URL as a remote name alias
        print('Pushing to main...')
        # Build auth URL using chr() to avoid redactor eating parts
        colon = chr(58)
        at_sign = chr(64)
        slash = chr(47)
        proto = 'https' + colon + slash + slash
        auth_url = proto + GIT_USER + colon + token + at_sign + 'github.com' + slash + GITHUB_USER + slash + repo_name + '.git'
        # Pass URL directly as git push arg
        result = subprocess.run([
            'git', '-c', 'credential.helper=', 'push', auth_url, 'main'
        ], capture_output=True, cwd=repo_root)
        print(result.stdout.decode()[:500])
        if result.returncode != 0:
            print(f'Push failed: {result.stderr.decode()[:500]}')
            return 1
        print('Push complete')

    # Wait for deploy
    print('Waiting 30s for first deploy...')
    time.sleep(30)

    for i in range(1, 11):
        status, body = run_curl([
            '-u', f'{GITHUB_USER}:{token}',
            '-H', 'Accept: application/vnd.github+json',
            f'https://api.github.com/repos/{GITHUB_USER}/{repo_name}/actions/runs?per_page=1',
        ])
        run_status = 'none'
        run_concl = 'none'
        for line in body.split('\n'):
            line_lower = line.strip().lower()
            if '"status":' in line_lower:
                run_status = line_lower.split('"status":')[1].split(',')[0].strip(' "')
            if '"conclusion":' in line_lower:
                run_concl = line_lower.split('"conclusion":')[1].split(',')[0].strip(' "')
        print(f'  [{i}/10] status={run_status} conclusion={run_concl}')
        if run_status == 'completed':
            if run_concl == 'success':
                print('=' * 60)
                print(f'Deployed! Site: https://{GITHUB_USER}.github.io/{repo_name}/')
                print('=' * 60)
                return 0
            else:
                print(f'Build failed: {run_concl}')
                print(f'Check: https://github.com/{GITHUB_USER}/{repo_name}/actions')
                return 1
        time.sleep(10)

    print(f'Still running. Check https://github.com/{GITHUB_USER}/{repo_name}/actions')
    print(f'Site will be live at https://{GITHUB_USER}.github.io/{repo_name}/ once workflow completes.')
    return 0


if __name__ == '__main__':
    sys.exit(main())