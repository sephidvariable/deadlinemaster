#!/usr/bin/env python3
"""Recover missing crate notices at the exact commit recorded in each crate.
Never substitutes a repository's current license for historical license evidence.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'build/FFmpegSources'


def main():
    notices = {e['package']: e for e in json.loads((SOURCES/'source-notices/index.json').read_text())}
    output = SOURCES/'license-supplements'
    output.mkdir(exist_ok=True)
    findings = []
    for entry in json.loads((SOURCES/'additional-source-status.json').read_text())['sources']:
        if entry.get('kind') != 'cargo-crate' or notices.get(entry['package'], {}).get('notices'):
            continue
        source = SOURCES/entry['file']
        with source.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != entry['sha256']:
                raise ValueError('Source checksum mismatch: ' + entry['package'])
        with tarfile.open(source) as tar:
            members = tar.getmembers()
            manifest = next(m for m in members if m.name.count('/') == 1 and m.name.endswith('/Cargo.toml'))
            package = tomllib.loads(tar.extractfile(manifest).read().decode())['package']
            vcs = next((m for m in members if m.name.count('/') == 1 and m.name.endswith('/.cargo_vcs_info.json')), None)
            commit = json.load(tar.extractfile(vcs))['git']['sha1'] if vcs else None
        record = {'package': entry['package'], 'source_sha256': entry['sha256'],
                  'declared_license': package.get('license'), 'repository': package.get('repository'),
                  'commit': commit, 'notices': [], 'status': 'unresolved'}
        repository = package.get('repository', '')
        if commit and len(commit) == 40 and all(c in '0123456789abcdef' for c in commit) and repository.startswith('https://github.com/'):
            repo = repository.removeprefix('https://github.com/').removesuffix('.git').strip('/')
            if len(repo.split('/')) != 2:
                raise ValueError('Unexpected repository URL')
            folder = output/entry['package']; folder.mkdir(exist_ok=True)
            for name in ['LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE', 'LICENSE.md']:
                url = f'https://raw.githubusercontent.com/{repo}/{commit}/{name}'
                target = folder/name
                if not target.exists():
                    response = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '10', '--max-time', '20', url], capture_output=True)
                    if response.returncode != 0:
                        continue
                    target.write_bytes(response.stdout)
                raw = target.read_bytes()
                # Preserve fetched original text, never synthesize copyright holders.
                if b'license' not in raw.lower() and b'permission' not in raw.lower():
                    continue
                record['notices'].append({'path': str(target.relative_to(output)), 'url': url,
                    'sha256': hashlib.sha256(raw).hexdigest()})
            if record['notices']:
                record['status'] = 'historical-notice-recovered'
        findings.append(record)
        print(entry['package'] + ': ' + record['status'], flush=True)
    (output/'index.json').write_text(json.dumps(findings, indent=2)+'\n')


if __name__ == '__main__':
    main()
