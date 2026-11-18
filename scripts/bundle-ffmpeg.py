#!/usr/bin/env python3
"""Vendor the installed full Homebrew build without trimming codecs or filters.
Developer tooling only. No Homebrew lookup occurs inside the shipped app.
"""
import hashlib, json, os, re, shutil, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = root / 'build/FFmpegFull'
prefix = Path(os.environ.get('FFMPEG_FULL_PREFIX', '/opt/homebrew/opt/ffmpeg-full')).resolve()
def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)
version = run(str(prefix/'bin/ffmpeg'), '-version')
assert '--enable-gpl' in version and '--enable-version3' in version
assert '--enable-nonfree' not in version, 'Nonfree builds cannot be redistributed'
assert 'ffmpeg-full' in str(prefix), 'Use the full formula, not regular ffmpeg'
if out.exists(): shutil.rmtree(out) # generated staging tree only
for name in ['bin','lib','licenses','provenance','capabilities']: (out/name).mkdir(parents=True)
shutil.copytree(prefix/'bin', out/'bin', dirs_exist_ok=True)
shutil.copytree(prefix/'share', out/'share', dirs_exist_ok=True)
queue=[]; locations={}; packages={}
def is_macho(p):
    return 'Mach-O' in run('/usr/bin/file','-b',str(p))
def add(src, dest=None):
    src=src.resolve()
    if src in locations: return locations[src]
    dest=dest or out/'lib'/src.name
    if dest in locations.values(): raise RuntimeError('Duplicate library name: '+str(dest))
    if dest.exists(): dest.chmod(0o755)
    shutil.copy2(src,dest); dest.chmod(0o755)
    locations[src]=dest;queue.append(src)
    if '/Cellar/' in str(src):
        parts=src.parts; i=parts.index('Cellar'); keg=Path(*parts[:i+3]);packages[str(keg)]=keg
    return dest
for p in (prefix/'bin').iterdir():
    if p.is_file() and is_macho(p): add(p,out/'bin'/p.name)
# SDL2-compat dlopens SDL3: it is absent from the Mach-O load-command graph.
# Vendor the installed library, without compiling or downloading anything.
if (prefix/'bin/ffplay').exists():
    sdl3 = Path('/opt/homebrew/opt/sdl3/lib/libSDL3.dylib')
    if not sdl3.is_file(): raise RuntimeError('Installed SDL3 is required by bundled ffplay/SDL2-compat')
    packaged_sdl3 = add(sdl3)
    (out/'lib/libSDL3.dylib').symlink_to(packaged_sdl3.name)
# Runtime-loaded frei0r plugins are part of the full formula, not in otool's graph.
plugins=Path('/opt/homebrew/opt/frei0r/lib/frei0r-1')
if plugins.exists():
    (out/'plugins').mkdir()
    for p in plugins.glob('*.so'): add(p,out/'plugins'/p.name)
def dependencies(src):
    return [l.strip().split(' (compatibility')[0] for l in run('/usr/bin/otool','-L',str(src)).splitlines()[1:]]
def resolve(dep,src):
    if dep.startswith('/'): return Path(dep)
    if dep.startswith('@loader_path/'): return src.parent/dep.removeprefix('@loader_path/')
    if dep.startswith('@rpath/'):
        name=dep.removeprefix('@rpath/')
        candidates=[src.parent/name]
        for r in re.findall(r'path (.*?) \(offset',run('/usr/bin/otool','-l',str(src))):
            candidates.append(Path(r.replace('@loader_path',str(src.parent)))/name)
        candidates.extend(Path('/opt/homebrew/opt').glob('*/lib/'+name))
        for c in candidates:
            if c.exists(): return c
    raise RuntimeError('Unresolved dependency '+dep+' in '+str(src))
while queue:
    src=queue.pop(0); dest=locations[src]
    arch=run('/usr/bin/lipo','-archs',str(src))
    assert 'arm64' in arch, str(src)+' lacks arm64'
    for dep in dependencies(src):
        if dep.startswith(('/System/Library/','/usr/lib/')): continue
        target=resolve(dep,src).resolve()
        if target==src: continue
        packaged=add(target)
        replacement='@loader_path/'+os.path.relpath(packaged,dest.parent)
        subprocess.run(['/usr/bin/install_name_tool','-change',dep,replacement,str(dest)],check=True,capture_output=True)
    if dest.suffix in ['.dylib','.so']:
        subprocess.run(['/usr/bin/install_name_tool','-id','@loader_path/'+dest.name,str(dest)],check=True,capture_output=True)
    for r in re.findall(r'path (.*?) \(offset',run('/usr/bin/otool','-l',str(dest))):
        if r.startswith('/opt/homebrew'):
            subprocess.run(['/usr/bin/install_name_tool','-delete_rpath',r,str(dest)],check=True,capture_output=True)
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(dest)],check=True,capture_output=True)
# Preserve exact installed formulas, build receipts, SBOMs and copyright notices.
sources=[]
for keg in packages.values():
    label=keg.parent.name+'-'+keg.name
    d=out/'provenance'/label;d.mkdir()
    for name in ['INSTALL_RECEIPT.json','sbom.spdx.json','.brew']:
        p=keg/name
        if p.is_dir(): shutil.copytree(p,d/name)
        elif p.exists(): shutil.copy2(p,d/name)
    notices=out/'licenses'/label;notices.mkdir()
    for p in keg.iterdir():
        if p.is_file() and re.search('licen[sc]e|copying|copyright|notice|authors',p.name,re.I): shutil.copy2(p,notices/p.name)
    for sub in ['share/licenses','share/doc']:
        if (keg/sub).exists(): shutil.copytree(keg/sub,notices/Path(sub).name)
    sbom=keg/'sbom.spdx.json'
    if sbom.exists():
        for entry in json.loads(sbom.read_text()).get('packages',[]):
            if entry.get('SPDXID','').startswith('SPDXRef-Archive'):
                sources.append({'installed':label,'source':entry})
(out/'provenance/sources-required.json').write_text(json.dumps(sources,indent=2))
(out/'provenance/version.txt').write_text(version)
for cap in ['buildconf','encoders','decoders','filters','formats','protocols','devices']:
    (out/'capabilities'/f'{cap}.txt').write_text(run(str(out/'bin/ffmpeg'),'-hide_banner','-'+cap))
for dest in locations.values():
    assert all(not d.startswith('/opt/homebrew') for d in dependencies(dest)), str(dest)
manifest={str(d.relative_to(out)):hashlib.sha256(d.read_bytes()).hexdigest() for d in locations.values()}
(out/'provenance/binary-sha256.json').write_text(json.dumps(manifest,indent=2))
origins = {}
for src, dest in locations.items():
    parts = src.parts
    i = parts.index('Cellar')
    origins[str(dest.relative_to(out))] = {
        'package': parts[i+1] + '-' + parts[i+2],
        'installed_relative_path': str(Path(*parts[i+3:])),
        'installed_sha256': hashlib.sha256(src.read_bytes()).hexdigest(),
        'bundled_sha256': manifest[str(dest.relative_to(out))]
    }
(out/'provenance/binary-origins.json').write_text(json.dumps(origins,indent=2)+'\n')
# Source notices supplement notices omitted by some installed bottles.
source_notices=root/'build/FFmpegSources/source-notices'
if (source_notices/'index.json').exists():
    shutil.copytree(source_notices,out/'licenses/source-notices')
shutil.copy2(root/'ThirdParty/FFmpeg/NOTICE.txt',out/'NOTICE.txt')
print(f'Bundled {len(locations)} Mach-O files from {len(packages)} packages at {out}')
