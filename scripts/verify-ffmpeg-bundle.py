#!/usr/bin/env python3
"""Check an assembled bundle without compiling FFmpeg or touching user audio."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(args, env=None, timeout=40):
    result = subprocess.run([str(a) for a in args], env=env, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(str(args[0]) + ': ' + result.stderr[-3000:])
    return result.stdout + result.stderr


def check_binary(item):
    path, expected, runtime = item
    if digest(path) != expected:
        raise ValueError('Hash mismatch: ' + str(path))
    if 'arm64' not in run(['/usr/bin/lipo', '-archs', path]).split():
        raise ValueError('Missing arm64 architecture: ' + str(path))
    run(['/usr/bin/codesign', '--verify', '--strict', path])
    links = run(['/usr/bin/otool', '-L', path]).splitlines()[1:]
    for link in links:
        name = link.strip().split(' (compatibility')[0]
        if name.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if not name.startswith('@loader_path/'):
            raise ValueError('Nonlocal dependency: ' + name)
        target = (path.parent/name.removeprefix('@loader_path/')).resolve()
        if not target.is_relative_to(runtime) or not target.is_file():
            raise ValueError('Missing or external dependency: ' + name)
    return str(path.relative_to(runtime))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, default=ROOT/'build/Deadline Master.app/Contents/Resources/FFmpegFull')
    parser.add_argument('--baseline', type=Path, default=ROOT/'build/FFmpegAudit/before')
    parser.add_argument('--report', type=Path, default=ROOT/'build/FFmpegAudit/bundle-verification.json')
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    manifest = json.loads((runtime/'provenance/binary-sha256.json').read_text())
    old = json.loads((args.baseline/'binary-sha256.json').read_text())
    changed = [p for p, sha in old.items() if manifest.get(p) != sha]
    if changed:
        raise ValueError('Previously audited binaries changed: ' + ', '.join(changed))
    with ThreadPoolExecutor(max_workers=6) as pool:
        checked = list(pool.map(check_binary, [(runtime/p, sha, runtime) for p, sha in manifest.items()]))
    if (runtime/'lib/libSDL3.dylib').resolve() != runtime/'lib/libSDL3.0.dylib':
        raise ValueError('Missing local SDL3 runtime alias')
    env = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'FREI0R_PATH': str(runtime/'plugins')}
    ffmpeg, ffprobe = runtime/'bin/ffmpeg', runtime/'bin/ffprobe'
    capabilities = []
    for path in sorted((args.baseline/'capabilities').glob('*.txt')):
        actual = run([ffmpeg, '-hide_banner', '-'+path.stem], env)
        if actual != path.read_text():
            raise ValueError('FFmpeg capability listing changed: ' + path.stem)
        capabilities.append(path.stem)
    formats = [('wav', 'pcm_f32le'), ('flac', 'flac'), ('mp3', 'libmp3lame'),
               ('ogg', 'libvorbis'), ('opus', 'libopus'), ('m4a', 'aac')]
    with tempfile.TemporaryDirectory(prefix='deadline-audio-audit-') as tmp:
        for ext, codec in formats:
            output = Path(tmp)/('test audio.'+ext)
            run([ffmpeg, '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
                 'sine=frequency=997:sample_rate=48000:duration=0.2', '-c:a', codec, output], env)
            probe = json.loads(run([ffprobe, '-v', 'error', '-show_streams', '-of', 'json', output], env))
            if not probe['streams'] or probe['streams'][0]['codec_type'] != 'audio':
                raise ValueError('No encoded audio: ' + codec)
            run([ffmpeg, '-v', 'error', '-nostdin', '-i', output, '-f', 'null', '-'], env)
        # ffplay exercises SDL2's runtime dlopen of SDL3; dummy drivers open no UI.
        play_env = {**env, 'SDL_AUDIODRIVER': 'dummy', 'SDL_VIDEODRIVER': 'dummy', 'DYLD_PRINT_LIBRARIES': '1'}
        play_log = run([runtime/'bin/ffplay', '-v', 'error', '-nodisp', '-autoexit',
                        '-f', 'lavfi', 'sine=frequency=440:duration=0.1'], play_env)
        if str(runtime/'lib/libSDL3') not in play_log or '/opt/homebrew/' in play_log:
            raise ValueError('SDL3 did not load exclusively from the app runtime')
        run([ffmpeg, '-v', 'error', '-nostdin', '-f', 'lavfi', '-i', 'color=s=16x16:d=0.1',
             '-vf', 'frei0r=filter_name=invert0r', '-frames:v', '1', '-f', 'null', '-'], env)
    notices = 0
    for directory in ['source-notices', 'license-supplements']:
        folder = runtime/'licenses'/directory
        for entry in json.loads((folder/'index.json').read_text()):
            for item in entry['notices']:
                if digest(folder/item['path']) != item['sha256']:
                    raise ValueError('Notice checksum mismatch: '+item['path'])
                notices += 1
    report = {'passed': True, 'ffmpeg_components_rebuilt': False,
        'runtime': str(runtime), 'binary_manifest_sha256': digest(runtime/'provenance/binary-sha256.json'),
        'binaries_hash_architecture_signature_linkage_verified': len(checked),
        'original_binaries_unchanged': len(old), 'added_binaries': sorted(set(manifest)-set(old)),
        'capability_listings_unchanged': capabilities, 'audio_encode_decode_smoke_tests': [c for _, c in formats],
        'ffplay_loaded_bundled_sdl3': True, 'frei0r_plugin_smoke_test': True,
        'preserved_notice_hashes_verified': notices,
        'limits': ['Same-Mac tests; not a clean second-Mac test.', 'Capability inventory retention does not exercise every codec, device, plugin or network protocol.', 'No upstream component rebuild or distribution clearance.']}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
