"""Check source claims/assets and the exact deployable ZIP. No dependencies/network."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import zipfile

root = Path(__file__).resolve().parents[1]


class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.references = []
        self.label_ids = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id'):
            self.ids.append(attrs['id'])
        if attrs.get('aria-labelledby'):
            self.label_ids.extend(attrs['aria-labelledby'].split())
        if tag in ['a', 'link', 'script', 'img']:
            value = attrs.get('href') or attrs.get('src')
            if value:
                self.references.append(value)
        if tag == 'img':
            assert 'alt' in attrs, 'Image needs alt text'


for name in ['index.html', 'evidence.html']:
    document = Document()
    document.feed((root / name).read_text(encoding='utf-8'))
    assert len(set(document.ids)) == len(document.ids), f'Duplicate IDs in {name}'
    assert all(identifier in document.ids for identifier in document.label_ids), 'Missing accessible label'
    for reference in document.references:
        parsed = urlsplit(reference)
        if parsed.scheme:
            assert parsed.scheme == 'https' and parsed.hostname == 'github.com', reference
            continue
        assert not parsed.path.startswith('/'), f'Absolute path breaks GitHub Pages project subpath: {reference}'
        target = (root / unquote(parsed.path or name)).resolve()
        assert target.is_relative_to(root) and target.is_file(), f'Missing/unsafe local reference: {reference}'
        if parsed.fragment and target.suffix == '.html':
            target_document = Document()
            target_document.feed(target.read_text(encoding='utf-8'))
            assert parsed.fragment in target_document.ids, f'Missing anchor: {reference}'
print('PASS: static references, project-relative paths, anchors and accessible labels')

css = (root / 'styles.css').read_text(encoding='utf-8')
for name in re.findall(r"url\(['\"]?([^)'\"]+)", css):
    assert (root / name).is_file(), f'Missing CSS asset: {name}'
assert '@media(prefers-reduced-motion:reduce)' in css
print('PASS: local font assets and reduced-motion fallback')

manifest = json.loads((root / 'evidence/sources.json').read_text(encoding='utf-8'))
for source in manifest['sources']:
    content = (root / 'evidence' / source['local']).read_bytes().replace(b'\r\n', b'\n')
    assert hashlib.sha256(content).hexdigest() == source['sha256'], f'Evidence changed: {source["local"]}'
assert b'60 Flutter tests passed' in (root / 'evidence/android-current.md').read_bytes()
assert 'CF1550C7FE8E8F204C91F96906294F2651BE154AEEC3B621D38DFB89B55D7B34' in (root / 'evidence/android-download.md').read_text(encoding='utf-8')
assert '8bf78e29b9ff740c3336067dd610b4c4e25e9fca' in manifest['presented_android_source']
assert b'flutter build apk --debug' in (root / 'evidence/build-review.md').read_bytes()
print('PASS: pinned evidence copies match their SHA-256 manifest; reported test/build results exist')

release = (root / 'release-config.js').read_text(encoding='utf-8')
assert 'releases/download/onya-android-security-v0.0.1-test.1/Onya-Android-Security-Test-0.0.1.apk' in release
page = (root / 'index.html').read_text(encoding='utf-8')
assert 'Download the Onya Android security test APK.' in page
assert 'id=\"android-download\" href=\"https://github.com/Laxmi-Srinivas/Offline-relay/releases/download/onya-android-security-v0.0.1-test.1/Onya-Android-Security-Test-0.0.1.apk\"' in page
for public_file in ['evidence.html', 'app.js', 'release-config.js']:
    assert not re.search(r'iOS|iPhone|iPad|ios|iphone', (root / public_file).read_text(encoding='utf-8'), re.I), public_file
assert 'Planned, not delivered before submission:' in page
assert 'The merge failed' in page and 'not completed or verified' in page
assert not re.search(r'iOS public download|iPhone / iOS|Watch iPhone|id=\"ios-access\"', page, re.I)
print('PASS: Android delivery plus clearly unfinished integration note and pinned APK configuration')

with tempfile.TemporaryDirectory(prefix='onya-package-check-') as directory:
    archive_path = Path(directory) / 'onya.zip'
    subprocess.run([sys.executable, str(root / 'package_site.py'), '--output', str(archive_path)], check=True)
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        allowed = {'index.html', 'evidence.html', 'styles.css', 'app.js', 'release-config.js'}
        assert 'index.html' in names
        assert all(name in allowed or name.startswith(('assets/', 'evidence/')) for name in names)
        assert not any('ios' in name.lower() or 'iphone' in name.lower() for name in names), names
        assert not any('..' in Path(name).parts or name.startswith('/') for name in names)
        assert not any(name.startswith(('apps/', '.git/', 'tests/', 'presentation/')) for name in names)
        assert not any(name.endswith(('.py', '.apk', '.ipa', '.jks', '.keystore')) for name in names)
        assert archive.testzip() is None
print('PASS: deployment ZIP includes only public website output, never mobile files/tooling/signing data')


def luminance(hex_color):
    components = [int(hex_color[index:index + 2], 16) / 255 for index in [1, 3, 5]]
    values = [value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4 for value in components]
    return .2126 * values[0] + .7152 * values[1] + .0722 * values[2]


for foreground, background in [('#172B28', '#F7F5EF'), ('#53625B', '#F7F5EF'),
                               ('#FFFFFF', '#246B57'), ('#D6E2D7', '#246B57'),
                               ('#246B57', '#F7F5EF'), ('#53625B', '#E7F0EA'),
                               ('#194D3F', '#DFE9DC'), ('#684530', '#F1DBCA')]:
    bright, dark = sorted([luminance(foreground), luminance(background)], reverse=True)
    ratio = (bright + .05) / (dark + .05)
    assert ratio >= 4.5, f'Text contrast below 4.5:1: {foreground}/{background} = {ratio:.2f}'
print('PASS: primary text/control/status palette pairs meet 4.5:1 contrast')
