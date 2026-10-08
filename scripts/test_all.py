#!/usr/bin/env python3
"""Run offline Keymin fixtures without launching or replacing an app bundle."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


# run_suites(root, logs, [jobs=2], [scripts=None], [environment=None]): Run every test script in
# parallel and summarize the results. Returns 0 when all suites pass, otherwise 1.
def run_suites(root, logs, jobs=2, *, scripts=None, environment=None):
    root, logs = Path(root), Path(logs)
    logs.mkdir(parents=True, exist_ok=True)
    # Suites inherit this environment plus any overrides and a default Xcode toolchain.
    env = os.environ.copy()
    env.update(environment or {})
    env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    # Every test_*.py script is a suite, except this runner itself.
    scripts = scripts if scripts is not None else sorted((root / 'scripts').glob('test_*.py'))
    tasks = [(path.stem, [sys.executable, str(path)]) for path in scripts if path.name != 'test_all.py']

    # run(task): Run one suite with its output captured to a log file; return (name, exit code).
    def run(task):
        name, command = task
        with (logs / (name + '.log')).open('w') as output:
            try:
                result = subprocess.run(command, cwd=root, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, timeout=300)
                return name, result.returncode
            # A hung suite gets its own exit code so it is not mistaken for a failed check.
            except subprocess.TimeoutExpired:
                output.write('\nSuite exceeded its five-minute limit.\n')
                return name, 124

    # Report each suite as it finishes so a slow one does not hide the others' results.
    results = {}
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        for future in as_completed([executor.submit(run, task) for task in tasks]):
            name, code = future.result()
            results[name] = code
            print(f'{"PASS" if code == 0 else "FAIL"} {name}', flush=True)
    # Keep a machine-readable summary next to the logs.
    (logs / 'results.json').write_text(json.dumps(results, indent=2, sort_keys=True) + '\n')
    passed = sum(code == 0 for code in results.values())
    print(f'{passed}/{len(results)} suites passed. Logs: {logs}', flush=True)
    return 0 if passed == len(results) else 1


# Run every suite as a command, logging to --logs or to a fresh directory under /private/tmp.
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs', type=Path)
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    logs = args.logs or Path(tempfile.mkdtemp(prefix='keymin-checks-', dir='/private/tmp'))
    sys.exit(run_suites(ROOT, logs, args.jobs))
