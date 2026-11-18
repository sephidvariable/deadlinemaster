#!/usr/bin/env python3
"""Bind preserved notices and source evidence to the actually shipped binaries.
This records evidence and specific exceptions; it does not grant legal clearance.
"""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT/'build/FFmpegSources'
RUNTIME = ROOT/'build/FFmpegFull'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verified_notice(root, item):
    path = root/item['path']
    if not path.resolve().is_relative_to(root.resolve()) or digest(path) != item['sha256']:
        raise ValueError('Notice missing, changed or outside evidence directory: ' + str(path))


def main():
    origins = json.loads((RUNTIME/'provenance/binary-origins.json').read_text())
    manifest = json.loads((RUNTIME/'provenance/binary-sha256.json').read_text())
    if origins.keys() != manifest.keys():
        raise ValueError('Binary origin inventory does not match bundled manifest')
    for relative, origin in origins.items():
        if digest(RUNTIME/relative) != manifest[relative] or origin['bundled_sha256'] != manifest[relative]:
            raise ValueError('Binary changed: ' + relative)
    statuses = json.loads((SOURCES/'source-status.json').read_text())['sources']
    notices = json.loads((SOURCES/'source-notices/index.json').read_text())
    by_name = {n['package']: n for n in notices}
    for item in notices:
        for notice in item['notices']:
            verified_notice(SOURCES/'source-notices', notice)
    supplements = json.loads((SOURCES/'license-supplements/index.json').read_text())
    for item in supplements:
        for notice in item['notices']:
            verified_notice(SOURCES/'license-supplements', notice)
    decisions = json.loads((ROOT/'ThirdParty/FFmpeg/license-findings.json').read_text())
    components = []
    for source in statuses:
        if source['status'] != 'verified' or digest(SOURCES/source['file']) != source['sha256']:
            raise ValueError('Unverified source: ' + source['package'])
        package = source['package']
        sbom = json.loads((RUNTIME/'provenance'/package/'sbom.spdx.json').read_text())
        upstream = next(p for p in sbom['packages'] if p['SPDXID'].startswith('SPDXRef-Archive'))
        paths = by_name[package]['notices']
        binaries = sorted(p for p, origin in origins.items() if origin['package'] == package)
        if not binaries or not paths:
            raise ValueError('Missing shipped binary or notices: ' + package)
        components.append({'package': package, 'recorded_license': upstream.get('licenseConcluded'),
            'source_sha256': source['sha256'], 'binaries': binaries, 'source_notices': paths,
            'review': decisions.get(package, {'status': 'top-level-notices-reviewed',
                'note': 'Original source notices retained. This is not a per-file license conclusion or proof of static dependency completeness.'})})
    covered = {p for c in components for p in c['binaries']}
    if covered != manifest.keys():
        raise ValueError('Shipped binary lacks source/notice mapping')
    report = {'redistribution_ready': False,
        'scope': 'Main component notice review and byte-verified source/binary mapping; unresolved static and supplementary attribution remains listed.',
        'binary_manifest_sha256': digest(RUNTIME/'provenance/binary-sha256.json'),
        'components': components, 'supplemental_notices': supplements,
        'unresolved_supplemental_packages': [s['package'] for s in supplements if not s['notices']],
        'unresolved_static_dependency': 'Historical fast_float version used by libplacebo remains unknown.'}
    target = ROOT/'ThirdParty/FFmpeg/license-reconciliation.json'
    target.write_text(json.dumps(report, indent=2)+'\n')
    lines = ['# FFmpeg component notice reconciliation', '',
        'Source notices take precedence over package-manager labels. Original SBOMs remain unchanged as evidence.',
        'This review covers the recorded main components; it is not distribution clearance. See license-reconciliation.json for exact hashes, paths and unresolved supplementary notices.', '',
        '| Shipped component | Recorded license | Source review | Binaries |',
        '| --- | --- | --- | --- |']
    for c in sorted(components, key=lambda c: c['package']):
        review = c['review'].get('note', '').replace('|', '/')
        lines.append(f"| {c['package']} | {c['recorded_license']} | {review} | {len(c['binaries'])} |")
    (ROOT/'ThirdParty/FFmpeg/COMPONENT-NOTICES.md').write_text('\n'.join(lines)+'\n')
    for directory in ['source-notices', 'license-supplements']:
        shutil.copytree(SOURCES/directory, RUNTIME/'licenses'/directory, dirs_exist_ok=True)
    for name in ['COMPONENT-NOTICES.md', 'license-reconciliation.json', 'license-findings.json']:
        shutil.copy2(ROOT/'ThirdParty/FFmpeg'/name, RUNTIME/'licenses'/name)
    shutil.copy2(ROOT/'ThirdParty/FFmpeg/NOTICE.txt', RUNTIME/'NOTICE.txt')
    print(f'Mapped {len(manifest)} shipped binaries to {len(components)} source packages; all preserved notice hashes verified.')
    print('Unresolved supplemental notices:', ', '.join(report['unresolved_supplemental_packages']))


if __name__ == '__main__':
    main()
