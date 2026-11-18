#!/usr/bin/env python3
"""Collect exact source inputs. A verified download is not a license approval.

No Homebrew installation is changed. Git sources are pinned to recorded commits;
archives retain .git metadata needed by version-generating build scripts.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'build/FFmpegFull'
OUT = ROOT / 'build/FFmpegSources'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def system_proxy():
    settings = subprocess.check_output(['scutil', '--proxy'], text=True)
    host = re.search(r'HTTPSProxy\s*:\s*(\S+)', settings)
    port = re.search(r'HTTPSPort\s*:\s*(\d+)', settings)
    if not (re.search(r'HTTPSEnable\s*:\s*1', settings) and host and port):
        raise RuntimeError('No system HTTPS proxy configured')
    return 'http://' + host[1] + ':' + port[1]


def main_entries():
    entries = []
    for item in json.loads((RUNTIME / 'provenance/sources-required.json').read_text()):
        source = item['source']
        entry = {'package': item['installed'], 'url': source.get('downloadLocation', ''),
                 'sha256': next((c['checksumValue'] for c in source.get('checksums', []) if c['algorithm'] == 'SHA256'), None)}
        if entry['url'].endswith('.git'):
            formula = next((RUNTIME / 'provenance' / entry['package'] / '.brew').glob('*.rb'))
            match = re.search(r'url "' + re.escape(entry['url']) + r'",\s*(?:tag: \s*"[^"]+",\s*)?revision: "([0-9a-f]{40})"', formula.read_text())
            if match: entry['revision'] = match[1]
        entries.append(entry)
    return entries


def collect(entry, proxy=None, timeout=180, previous=None):
    result = dict(entry)
    name = re.sub(r'[^A-Za-z0-9_.-]', '_', entry['package'])
    url, expected, revision = entry.get('url', ''), entry.get('sha256'), entry.get('revision')
    if not url.startswith('https://'):
        return result | {'status': 'missing source locator'}
    if revision:
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            return result | {'status': 'invalid revision'}
        dest = OUT / (name + '-' + revision[:12] + '.source.tar.gz')
        if previous and previous.get('revision') == revision and previous.get('status') == 'verified' and dest.exists() and previous.get('sha256') == digest(dest):
            return result | {'sha256': previous['sha256'], 'status': 'verified', 'file': dest.name, 'verification': 'Git commit + cached archive SHA256'}
        try:
            with tempfile.TemporaryDirectory(prefix='git-source-', dir=OUT) as temporary:
                repo = Path(temporary) / 'source'
                env = os.environ | {'GIT_TERMINAL_PROMPT': '0', 'GIT_CONFIG_NOSYSTEM': '1'}
                git = ['git', '-c', 'protocol.file.allow=never']
                if proxy: git += ['-c', 'http.proxy=' + proxy]
                def run(*args):
                    return subprocess.check_output(git + list(args), text=True, stderr=subprocess.STDOUT, timeout=timeout, env=env)
                run('init', str(repo))
                run('-C', str(repo), 'fetch', '--depth=1', url, revision)
                actual = run('-C', str(repo), 'rev-parse', 'FETCH_HEAD').strip()
                if actual != revision: raise RuntimeError('Git commit does not match the pinned formula')
                run('-C', str(repo), 'checkout', '--detach', actual)
                run('-C', str(repo), 'fsck', '--no-dangling')
                # Fail closed instead of silently omitting recursively embedded sources.
                if run('-C', str(repo), 'ls-tree', '-r', 'HEAD').find('160000 commit') >= 0:
                    raise RuntimeError('Git submodules require separate pinned source collection')
                for hook in (repo / '.git/hooks').glob('*'): hook.unlink()
                with tarfile.open(dest.with_suffix('.download'), 'w:gz') as archive:
                    archive.add(repo, arcname=name)
                dest.with_suffix('.download').replace(dest)
            return result | {'sha256': digest(dest), 'status': 'verified', 'file': dest.name, 'verification': 'Git commit + SHA256 recorded for archive'}
        except (subprocess.SubprocessError, OSError, RuntimeError) as error:
            dest.with_suffix('.download').unlink(missing_ok=True)
            return result | {'status': 'git retrieval failed', 'reason': str(error)[-400:]}
    if not expected or not re.fullmatch(r'[0-9a-f]{64}', expected):
        return result | {'status': 'missing expected checksum'}
    dest = OUT / (name + '-' + expected[:12] + '.source')
    if dest.exists() and digest(dest) == expected:
        return result | {'status': 'verified', 'file': dest.name}
    temporary = dest.with_suffix('.download')
    args = ['curl'] + (['--proxy', proxy] if proxy else [])
    args += ['--fail', '--location', '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15', '--max-time', str(timeout), '--silent', '--show-error', '--output', str(temporary), url]
    process = subprocess.run(args, capture_output=True, text=True)
    if process.returncode or digest(temporary) != expected:
        temporary.unlink(missing_ok=True)
        return result | {'status': 'download failed' if process.returncode else 'checksum mismatch', 'reason': process.stderr[-300:]}
    temporary.replace(dest)
    return result | {'status': 'verified', 'file': dest.name}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--system-proxy', action='store_true')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--additional-manifest', type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    entries = main_entries()
    report_path = OUT / 'source-status.json'
    if args.additional_manifest:
        entries = json.loads(args.additional_manifest.read_text())
        report_path = OUT / 'additional-source-status.json'
    previous = {x['package']: x for x in json.loads(report_path.read_text()).get('sources', [])} if report_path.exists() else {}
    proxy = system_proxy() if args.system_proxy else None
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda e: collect(e, proxy, args.timeout, previous.get(e['package'])), entries))
    report = {'redistribution_ready': False, 'reason': 'Source collection alone is not complete license/build-input review.', 'sources': results}
    temporary = report_path.with_suffix('.tmp'); temporary.write_text(json.dumps(report, indent=2) + '\n'); temporary.replace(report_path)
    print(f"Verified {sum(r['status'] == 'verified' for r in results)}/{len(results)} inputs. See {report_path}")
    return 0 if all(r['status'] == 'verified' for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
