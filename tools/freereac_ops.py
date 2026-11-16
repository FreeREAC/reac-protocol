#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The public/private split of reac-protocol, and the one reader of the freereac-ops checkout.

The firmware reverse-engineering write-ups, the vendor scene bodies the KSY tests read, and the
audits are private material and live in the FreeREAC/freereac-ops repository. This tree keeps the
protocol reference, the KSY grammar and its generator, the public fixtures and the tests.

  freereac_ops.py check   the public tree is clean: no notebook Markdown, no vendor binary, no
                          build command on the README

One plain rule, no list of moved paths. The only other thing here is the reader of the two vendor
scene bodies the tests need, found by one rule: $FREEREAC_OPS, else the sibling ../freereac-ops,
else absent. Absent, the tests that need a body skip by name (OPS-ABSENT <slug>);
FREEREAC_REQUIRE_OPS=1 makes them fail instead.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OPS_SUBDIR = 'reac-protocol'
VENDOR_DIR = 'spec/fixtures'
REQUIRE_ENV = 'FREEREAC_REQUIRE_OPS'

# Internal material: firmware RE write-ups, vendor binaries, audits, notes, plans.
INTERNAL_DIRS = ('docs/audits/', 'docs/notes/', 'docs/plans/', 'docs/design/', 'notes/',
                 'plans/')
INTERNAL_NAMES = ('ROADMAP.md',)
PLAN = re.compile(r'-plan(-[^/]*)?\.md$')
LEDGER = re.compile(r'(^|-)(audit|census)(-[^/]*)?\.md$')  # dated audits and censuses
# A README sells; BUILDING.md builds (docs-to-ops plan §5).
BUILD_COMMAND = re.compile(r'\b(make|meson|cmake|ninja|rpmbuild|kaitai-struct-compiler)\b'
                           r'|\bpnpm build\b|\bpip3? install\b')


def belongs_in_ops(path):
    """True when <path> is vendor RE or internal material: it lives in freereac-ops."""
    base = path.rsplit('/', 1)[-1]
    if '/' not in path and base.startswith('firmware-') and base.endswith('.md'):
        return True
    if base.endswith('.bin'):
        return True  # a vendor binary; public tests build their bodies in code
    return (path.startswith(INTERNAL_DIRS) or base in INTERNAL_NAMES or bool(PLAN.search(base))
            or bool(LEDGER.search(base)))


def git(*args, cwd=REPO, check=True, data=None):
    p = subprocess.run(['git', *args], cwd=cwd, capture_output=True, input=data)
    if check and p.returncode != 0:
        raise SystemExit('git %s: %s' % (' '.join(args), p.stderr.decode(errors='replace').strip()))
    return p.stdout


def ops_root(repo=REPO):
    """The freereac-ops checkout: $FREEREAC_OPS, else ../freereac-ops beside this repo, else None."""
    env = os.environ.get('FREEREAC_OPS')
    if env:
        return env if os.path.isdir(env) else None
    sib = os.path.join(os.path.dirname(os.path.abspath(repo)), 'freereac-ops')
    return sib if os.path.isdir(sib) else None


def ops_required():
    return os.environ.get(REQUIRE_ENV) == '1'


def read_ops(name, repo=REPO):
    """The bytes of the vendor scene body <name> (a slug), or None when the ops checkout or the
    file is absent."""
    root = ops_root(repo)
    p = os.path.join(root, OPS_SUBDIR, VENDOR_DIR, name + '.bin') if root else None
    if p is None or not os.path.isfile(p):
        return None
    with open(p, 'rb') as f:
        return f.read()


def absent_reason(name, repo=REPO):
    """The OPS-ABSENT line a reader prints (or fails with) when <name> is not found."""
    root = ops_root(repo)
    where = ('no freereac-ops checkout ($FREEREAC_OPS or ../freereac-ops)' if root is None
             else 'not in %s/%s' % (root, OPS_SUBDIR))
    return 'OPS-ABSENT %s: %s' % (name, where)


def readme_code(text):
    """The code on a README: fenced blocks, indented blocks and inline `spans`."""
    code, fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith('```'):
            fence = not fence
            continue
        if fence or line.startswith(('    ', '\t')):
            code.append(line)
        else:
            code.extend(re.findall(r'`([^`]+)`', line))
    return code


def check(repo=REPO, out=sys.stdout):
    """Every failure on its own line; returns the count."""
    fails = 0

    def fail(msg):
        nonlocal fails
        fails += 1
        print(msg, file=out)

    tracked = [t for t in git('ls-files', '-z', cwd=repo).decode().split('\0') if t]
    for t in tracked:
        if belongs_in_ops(t):
            fail('INTERNAL %s: vendor RE or internal material belongs in freereac-ops' % t)
    if 'README.md' in tracked:
        with open(os.path.join(repo, 'README.md'), encoding='utf-8') as f:
            for code in readme_code(f.read()):
                if BUILD_COMMAND.search(code):
                    fail('README-BUILD %r: build steps live in BUILDING.md' % code.strip())
    print('CHECK OK' if fails == 0 else 'CHECK FAILED %d' % fails, file=out)
    return fails


def main(argv):
    if len(argv) >= 1 and argv[0] == 'check':
        return 1 if check() else 0
    print(__doc__.split('\n\n')[2], file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
