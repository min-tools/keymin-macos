#!/usr/bin/env python3
"""Export the source without repository metadata or generated app bundles."""
from pathlib import Path
import argparse
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


# export_source(output): Copy the tracked and untracked-but-not-ignored files into a new directory
# and return its path.
def export_source(output):
    output = Path(output).absolute()
    # Never overwrite: an existing directory, or a link to one, may belong to something else.
    if output.exists() or output.is_symlink():
        raise ValueError('Choose a new output directory; existing directories are never replaced.')
    # An export inside the checkout would be picked up by the next export.
    if output == ROOT or ROOT in output.parents:
        raise ValueError('Export outside the source checkout.')
    # Ask git for the file list so ignored files, such as local signing inputs, stay out.
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT
    ).decode().split('\0')
    files = []
    for name in sorted(set(filter(None, names))):
        path = Path(name)
        # Git should never report such a path, but one must not escape the output directory.
        if path.is_absolute() or '..' in path.parts:
            raise ValueError(f'Unsafe source path: {name}')
        # Skip build output and editor state even when git has not been told to ignore them.
        if any(part in ('.git', '.build', 'build', '__pycache__', 'xcuserdata')
               or part.endswith('.app') for part in path.parts):
            continue
        source = ROOT / path
        # A link could pull in files from outside the checkout or dangle in the export.
        if source.is_symlink() or any(parent.is_symlink() for parent in source.parents if parent != ROOT):
            raise ValueError(f'Symbolic links are not exported: {name}')
        # Files deleted from the working tree still appear in the index; copy only what exists.
        if source.is_file():
            files.append((source, path))
    # Refuse to create an empty export.
    if not files:
        raise ValueError('No source files found.')
    # Copy each file with its timestamps so the export matches the checkout.
    output.mkdir(parents=True)
    for source, path in files:
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    print(f'Exported {len(files)} files to {output}.')
    return output


# Export to the requested directory when run as a command.
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    export_source(parser.parse_args().output)
