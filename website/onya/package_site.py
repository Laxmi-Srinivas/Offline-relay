"""Create a deployment/offline ZIP with only public static presentation files."""
import argparse
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, help='Output ZIP outside the source directory')
args = parser.parse_args()
root = Path(__file__).resolve().parent
target = Path(args.output).resolve()
if target == root or root in target.parents:
    parser.error('Choose an output outside website/onya so artifacts do not enter source Git.')
files = [root / name for name in ['index.html', 'evidence.html', 'styles.css', 'app.js', 'release-config.js']]
files += sorted((root / 'assets').glob('*'))
files += [root / 'evidence' / name for name in ['android-current.md', 'android-download.md', 'sources.json']]
assert all(path.is_file() for path in files), 'Missing static asset'
assert not any(path.is_symlink() for path in files), 'Symlinks are not packaged'
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, path.relative_to(root).as_posix())
print(f'Packaged {len(files)} public static files: {target}')
print('No mobile files, Git metadata, local tooling, tests or private signing data included.')
