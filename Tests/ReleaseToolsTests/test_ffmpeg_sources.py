import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT/'scripts'/f'{name}.py')
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

collector = module('collect-ffmpeg-sources')
audit = module('audit-ffmpeg-release')
licenses = module('reconcile-ffmpeg-licenses')
bundle = module('verify-ffmpeg-bundle')

class SourceEvidenceTests(unittest.TestCase):
    def test_cached_source_is_rehashed(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp); data = b'exact source'
            sha = collector.hashlib.sha256(data).hexdigest()
            entry = {'package': 'codec', 'url': 'https://example.invalid/source', 'sha256': sha}
            dest = out/f'codec-{sha[:12]}.source'; dest.write_bytes(data)
            with patch.object(collector, 'OUT', out), patch.object(collector.subprocess, 'run') as network:
                self.assertEqual(collector.collect(entry)['status'], 'verified'); network.assert_not_called()
                dest.write_bytes(b'corrupted')
                network.return_value.returncode = 1; network.return_value.stderr = 'offline'
                self.assertEqual(collector.collect(entry)['status'], 'download failed')

    def test_unpinned_and_non_https_inputs_fail_closed(self):
        self.assertEqual(collector.collect({'package':'x','url':'http://example.invalid/x','sha256':'a'*64})['status'], 'missing source locator')
        self.assertEqual(collector.collect({'package':'x','url':'https://example.invalid/x'})['status'], 'missing expected checksum')

    def test_git_revision_parses_spaced_tag(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); p = root/'provenance/aom/.brew'; p.mkdir(parents=True)
            commit = 'a'*40
            (p/'aom.rb').write_text('url "https://example.invalid/aom.git",\n tag:      "v1",\n revision: "'+commit+'"\n')
            (root/'provenance/sources-required.json').write_text(json.dumps([{'installed':'aom','source':{'downloadLocation':'https://example.invalid/aom.git'}}]))
            with patch.object(collector, 'RUNTIME', root): self.assertEqual(collector.main_entries()[0]['revision'], commit)

    def test_notice_extraction_rejects_traversal_and_links(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); source = root/'input.tar.gz'
            with tarfile.open(source, 'w:gz') as archive:
                for name in ['codec/LICENSE', 'codec/codec-license.txt', 'codec/docs/FTL.TXT', 'codec/README.ijg', '../LICENSE', '/LICENSE']:
                    info = tarfile.TarInfo(name); info.size = 4; archive.addfile(info, io.BytesIO(b'text'))
                link = tarfile.TarInfo('codec/NOTICE'); link.type = tarfile.SYMTYPE; link.linkname = '/etc/passwd'; archive.addfile(link)
            with patch.object(audit, 'SOURCES', root):
                result = audit.collect_notices([{'package':'codec','file':source.name}])
            self.assertEqual(len(result[0]['notices']), 4)
            self.assertEqual((root/'source-notices/codec/codec/LICENSE').read_text(), 'text')
            self.assertFalse((root/'source-notices/codec/codec/NOTICE').exists())

    def test_missing_required_source_is_a_blocker(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); sources=root/'sources'; sources.mkdir(); runtime=root/'runtime'; (runtime/'provenance').mkdir(parents=True)
            (root/'ThirdParty/FFmpeg').mkdir(parents=True)
            for name in ['source-status.json','additional-source-status.json']: (sources/name).write_text('{"sources":[]}')
            (root/'ThirdParty/FFmpeg/additional-sources-required.json').write_text('[]')
            (runtime/'provenance/sources-required.json').write_text(json.dumps([{'installed':'missing','source':{'downloadLocation':'https://example.invalid/source'}}]))
            with patch.object(audit, 'ROOT', root), patch.object(audit, 'SOURCES', sources), patch.object(audit, 'RUNTIME', runtime):
                _, problems = audit.checked_sources()
                self.assertIn('Runtime source inventory mismatch: missing', problems)

    def test_notice_reconciliation_rejects_corruption_and_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root/'LICENSE').write_bytes(b'actual terms')
            item = {'path': 'LICENSE', 'sha256': licenses.digest(root/'LICENSE')}
            licenses.verified_notice(root, item)
            (root/'LICENSE').write_bytes(b'changed terms')
            with self.assertRaises(ValueError): licenses.verified_notice(root, item)
            with self.assertRaises(ValueError): licenses.verified_notice(root, {'path': '../LICENSE', 'sha256': 'a'*64})

    def test_bundle_rejects_external_library_dependency(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve(); binary = root/'codec'; binary.write_bytes(b'binary')
            def fake_run(args):
                if 'lipo' in args[0]: return 'arm64'
                if 'otool' in args[0]: return 'codec:\n\t/opt/homebrew/lib/hidden.dylib (compatibility version 1.0.0)\n'
                return ''
            with patch.object(bundle, 'run', side_effect=fake_run):
                with self.assertRaisesRegex(ValueError, 'Nonlocal dependency'):
                    bundle.check_binary((binary, bundle.digest(binary), root))

if __name__ == '__main__': unittest.main()
