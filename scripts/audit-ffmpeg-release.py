#!/usr/bin/env python3
"""Verify source evidence, collect source notices, and build a release handoff kit.
Never equates checksums with complete copyright/license compliance.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'build/FFmpegSources'
RUNTIME = ROOT / 'build/FFmpegFull'
REPORT = ROOT / 'ThirdParty/FFmpeg/redistribution-audit.json'


def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def checked_sources():
    entries, problems = [], []
    for name in ['source-status.json', 'additional-source-status.json']:
        path = SOURCES / name
        if not path.exists():
            problems.append('Missing ' + name); continue
        for entry in json.loads(path.read_text())['sources']:
            path = SOURCES / entry.get('file', 'missing')
            if (not path.is_file() or path.parent != SOURCES or entry['status'] != 'verified'
                    or digest(path) != entry.get('sha256')):
                problems.append('Unverified source: ' + entry['package'])
            else: entries.append(entry)
    by_name = {e['package']: e for e in entries}
    required = json.loads((RUNTIME/'provenance/sources-required.json').read_text())
    for item in required:
        found = by_name.get(item['installed'])
        source = item['source']
        sha = next((c['checksumValue'] for c in source.get('checksums', []) if c['algorithm'] == 'SHA256'), None)
        if not found or found.get('url') != source['downloadLocation'] or (sha and found.get('sha256') != sha):
            problems.append('Runtime source inventory mismatch: ' + item['installed'])
        if found and source['downloadLocation'].endswith('.git'):
            recipe = next((RUNTIME/'provenance'/item['installed']/'.brew').glob('*.rb')).read_text()
            if not found.get('revision') or found['revision'] not in recipe:
                problems.append('Pinned Git revision mismatch: ' + item['installed'])
    for item in json.loads((ROOT/'ThirdParty/FFmpeg/additional-sources-required.json').read_text()):
        found = by_name.get(item['package'])
        if not found or any(found.get(key) != item.get(key) for key in ['url', 'revision']):
            problems.append('Additional source inventory mismatch: ' + item['package'])
        if item.get('sha256') and (not found or found.get('sha256') != item['sha256']):
            problems.append('Additional source checksum mismatch: ' + item['package'])
        if item.get('formula') and digest(RUNTIME/'provenance'/item['formula']) != item.get('formula_sha256'):
            problems.append('Formula changed since source inventory: ' + item['package'])
    return entries, problems


def collect_notices(entries):
    output = SOURCES / 'source-notices'
    output.mkdir(exist_ok=True)
    index = []
    for entry in entries:
        path = SOURCES / entry['file']
        package = re.sub(r'[^A-Za-z0-9_.-]', '_', entry['package'])
        notices = []
        try:
            with tarfile.open(path, 'r|*') as archive:
                for member in archive:
                    parts = PurePosixPath(member.name).parts
                    if not member.isfile() or '..' in parts or member.name.startswith('/'): continue
                    base = PurePosixPath(member.name).name
                    if not (re.match(r'^(?:.*[-_.])?(copying|licen[cs]e|copyright|notice|patents|authors)([._-].*)?$', base, re.I)
                            or base.lower() in {'ftl.txt', 'gplv2.txt', 'readme.ijg'}
                            or 'licenses' in [p.lower() for p in parts]): continue
                    # Do not extract symlinks, execute code, or follow archive paths.
                    dest = output / package / member.name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as src, dest.open('wb') as target: shutil.copyfileobj(src, target)
                    notices.append({'path': str(dest.relative_to(output)), 'sha256': digest(dest)})
        except tarfile.ReadError:
            # Patches, trained model files and test images are not source tarballs.
            pass
        index.append({'package': entry['package'], 'kind': entry.get('kind', 'main-source'), 'notices': notices})
    (output / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    return index


def audit(entries, problems):
    manifest = json.loads((RUNTIME/'provenance/binary-sha256.json').read_text())
    for relative, expected in manifest.items():
        path = RUNTIME / relative
        if not path.is_file() or digest(path) != expected: problems.append('Runtime hash mismatch: ' + relative)
    version = (RUNTIME/'provenance/version.txt').read_text()
    if '--enable-nonfree' in version: problems.append('Nonredistributable FFmpeg configuration')
    if '--enable-gpl' not in version or '--enable-version3' not in version: problems.append('Unexpected FFmpeg license configuration')
    # Notice reconciliation is tied to these exact binaries, not just package names.
    reconciliation = ROOT/'ThirdParty/FFmpeg/license-reconciliation.json'
    if not reconciliation.exists():
        problems.append('Missing source-to-binary license reconciliation')
    else:
        evidence = json.loads(reconciliation.read_text())
        if evidence['binary_manifest_sha256'] != digest(RUNTIME/'provenance/binary-sha256.json'):
            problems.append('License reconciliation describes a different runtime')
        for directory in ['source-notices', 'license-supplements']:
            base = RUNTIME/'licenses'/directory
            if not (base/'index.json').exists():
                problems.append('Missing bundled notice index: ' + directory)
                continue
            for entry in json.loads((base/'index.json').read_text()):
                for item in entry['notices']:
                    path = base/item['path']
                    if (not path.resolve().is_relative_to(base.resolve()) or not path.is_file()
                            or digest(path) != item['sha256']):
                        problems.append('Bundled notice missing or changed: ' + item['path'])
    # These are concrete unresolved provenance/review findings, not missing downloads.
    review = json.loads((ROOT/'ThirdParty/FFmpeg/release-review.json').read_text())
    problems += [item['reason'] for item in review['items'] if item['status'] != 'resolved']
    main = [e for e in entries if not e.get('kind')]
    report = {'redistribution_ready': not problems,
              'main_sources_verified': len(main), 'additional_inputs_verified': len(entries)-len(main),
              'runtime_binaries_verified': len(manifest),
              'source_manifest_sha256': digest(SOURCES/'source-status.json'),
              'additional_manifest_sha256': digest(SOURCES/'additional-source-status.json'),
              'binary_manifest_sha256': digest(RUNTIME/'provenance/binary-sha256.json'),
              'blockers': problems}
    REPORT.write_text(json.dumps(report, indent=2)+'\n')
    return report


def package_kit(entries, report):
    # New directory each run; never overwrite an existing release/source archive.
    import datetime
    output = ROOT/'build/Redistribution'
    output.mkdir(exist_ok=True)
    folder = output/('DeadlineMaster-source-review-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    folder.mkdir()
    for directory in ['provenance', 'licenses', 'capabilities']:
        shutil.copytree(RUNTIME/directory, folder/directory)
    for directory in ['extra-provenance', 'source-notices', 'license-supplements']:
        if (SOURCES/directory).exists(): shutil.copytree(SOURCES/directory, folder/directory)
    (folder/'sources').mkdir()
    for entry in entries:
        shutil.copy2(SOURCES/entry['file'], folder/'sources'/entry['file'])
    for name in ['source-status.json', 'additional-source-status.json', 'input-inventory-notes.json']:
        shutil.copy2(SOURCES/name, folder/name)
    # Explicit allowlist: no credentials, .git, caches, user library or audio.
    snapshot = folder/'DeadlineMaster-source'; snapshot.mkdir()
    for name in ['Sources', 'Tests', 'Resources', 'scripts', 'docs', 'ThirdParty']:
        shutil.copytree(ROOT/name, snapshot/name, ignore=shutil.ignore_patterns('__pycache__', '.DS_Store'))
    for name in ['Package.swift', 'Package.resolved', 'LICENSE', 'README.md', '.gitignore']:
        if (ROOT/name).exists(): shutil.copy2(ROOT/name, snapshot/name)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    (folder/'snapshot.json').write_text(json.dumps({'base_commit': commit, 'includes_uncommitted_working_tree': True, 'audit': report}, indent=2)+'\n')
    shutil.copy2(ROOT/'docs/FFMPEG-REDISTRIBUTION.md', folder/'READ-ME-FIRST.md')
    checksums = {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob('*')) if p.is_file()}
    (folder/'SHA256SUMS.json').write_text(json.dumps(checksums, indent=2)+'\n')
    archive = folder.with_suffix('.tar.gz')
    with tarfile.open(archive, 'w:gz', compresslevel=1) as tar: tar.add(folder, arcname=folder.name)
    archive.with_suffix(archive.suffix+'.sha256').write_text(digest(archive)+'  '+archive.name+'\n')
    print('Created source REVIEW kit (not release clearance):', archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notices', action='store_true')
    parser.add_argument('--package-review-kit', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    entries, problems = checked_sources()
    if args.notices: collect_notices(entries)
    report = audit(entries, problems)
    print(json.dumps(report, indent=2))
    if args.package_review_kit: package_kit(entries, report)
    return 1 if args.check and report['blockers'] else 0


if __name__ == '__main__': raise SystemExit(main())
