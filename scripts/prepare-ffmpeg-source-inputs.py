#!/usr/bin/env python3
"""Inventory pinned formula patches/resources and all rav1e lockfile crates.
This deliberately does not infer missing historical build-dependency versions.
"""
import hashlib, json, re, tarfile, tomllib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
base = ROOT / 'build/FFmpegFull/provenance'
output = ROOT / 'ThirdParty/FFmpeg/additional-sources-required.json'
entries = []
findings = []

def block_at(text, match):
    end = re.search(r'^' + re.escape(match[1]) + r'end\s*$', text[match.end():], re.M)
    if not end: raise ValueError('Unterminated formula block')
    return text[match.start():match.end()+end.end()]

for formula in sorted(base.glob('*/.brew/*.rb')):
    text = formula.read_text()
    # Current bottle is stable; HEAD-only sources must not enter the inventory.
    text = re.sub(r'^  head do\n.*?^  end\s*$', '', text, flags=re.M|re.S)
    test = re.search(r'^  test do\n', text, re.M)
    if test: text = text[:test.start()]
    for i, m in enumerate(re.finditer(r'^([ \t]*)(resource "([^\"]+)"[^\n]* do|patch do)\n', text, re.M)):
        if ':test' in m[2]: continue
        block = block_at(text, m)
        url = re.search(r'\burl "([^\"]+)"', block)
        checksum = re.search(r'\bsha256 "([a-f0-9]{64})"', block)
        revision = re.search(r'\brevision: "([a-f0-9]{40})"', block)
        entry = {'package': formula.parent.parent.name + '--' + (m[3] or 'patch-' + str(i)),
                 'kind': 'resource' if m[3] else 'patch',
                 'formula': str(formula.relative_to(base)), 'formula_sha256': hashlib.sha256(formula.read_bytes()).hexdigest()}
        if url: entry['url'] = url[1]
        if checksum: entry['sha256'] = checksum[1]
        if revision: entry['revision'] = revision[1]
        local = re.search(r'\bfile "([^\"]+)"', block)
        if local:
            # The installed formula lacks its patch file. Keep this visible until exact evidence is supplied.
            entry['local_patch'] = local[1]
        entries.append(entry)
    if '__END__\n' in text or '__END__\n' in formula.read_text():
        findings.append({'package': formula.parent.parent.name, 'inline_patch': str(formula.relative_to(base))})

status = json.loads((ROOT/'build/FFmpegSources/source-status.json').read_text())
rav1e = next(x for x in status['sources'] if x['package'].startswith('rav1e-'))
with tarfile.open(ROOT/'build/FFmpegSources'/rav1e['file']) as archive:
    lock = next(m for m in archive.getmembers() if m.name.count('/') == 1 and m.name.endswith('/Cargo.lock'))
    contents = archive.extractfile(lock).read()
    (ROOT/'ThirdParty/FFmpeg/rav1e-Cargo.lock').write_bytes(contents)
    for crate in tomllib.loads(contents.decode())['package']:
        if not crate.get('source'): continue
        if crate['source'] != 'registry+https://github.com/rust-lang/crates.io-index':
            findings.append({'unhandled_crate': crate}); continue
        name, version = crate['name'], crate['version']
        entries.append({'package': f'rav1e-crate--{name}-{version}', 'kind': 'cargo-crate',
                        'url': f'https://static.crates.io/crates/{name}/{name}-{version}.crate',
                        'sha256': crate['checksum'], 'evidence': 'rav1e-Cargo.lock'})
# Input overrides are explicitly reviewed, not guessed from current package versions.
overrides = ROOT/'ThirdParty/FFmpeg/source-input-overrides.json'
if overrides.exists():
    patches = json.loads(overrides.read_text())
    for entry in entries:
        if entry['package'] in patches: entry.update(patches[entry['package']])
    for name, entry in patches.items():
        if name not in {e['package'] for e in entries}: entries.append({'package': name, **entry})
output.write_text(json.dumps(entries, indent=2)+'\n')
(ROOT/'build/FFmpegSources/input-inventory-notes.json').write_text(json.dumps(findings, indent=2)+'\n')
print(f'Inventoried {len(entries)} additional source inputs; {len(findings)} embedded patch notes.')
