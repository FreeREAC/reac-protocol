#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The public/private split of reac-protocol, and the one reader of the freereac-ops checkout.

The firmware reverse-engineering write-ups, the vendor scene bodies the KSY tests read, and the
audits live in the private FreeREAC/freereac-ops repository under reac-protocol/<same path>.
This tree keeps the protocol reference, the KSY grammar and its generator, the public fixtures
and the tests. tools/ops-moves.txt lists every path that moved (and the commit it was taken
from); a public file cites one by its bare SLUG, the file name without its extension
(firmware-findings), never by path or file name.

  freereac_ops.py check            the public tree is clean (nothing internal, no file-name
                                   citation of a moved file, no build command on the README);
                                   with the ops checkout present, every moved path resolves in it
  freereac_ops.py resolve <slug>   the ops file a slug names, or OPS-ABSENT
  freereac_ops.py export <ops-checkout> [<branch>]
                                   commit the moved files, byte-identical, onto <branch> of an ops
                                   checkout (one commit on its main, or a root commit); never pushes

The ops checkout is found by one rule: $FREEREAC_OPS, else the sibling ../freereac-ops, else
absent. Absent, `check` reports OPS-ABSENT and skips that half by name, and so do the tests that
need a vendor file; FREEREAC_REQUIRE_OPS=1 makes both fail instead (a desk, or a lane that must
not merge a half-done move).
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOVES = 'tools/ops-moves.txt'
OPS_SUBDIR = 'reac-protocol'
BRANCH = 'lane/docs-reac-protocol'
REQUIRE_ENV = 'FREEREAC_REQUIRE_OPS'

# Internal material: firmware RE write-ups, vendor binaries, audits, notes, plans.
INTERNAL_DIRS = ('docs/audits/', 'docs/notes/', 'docs/plans/', 'docs/design/', 'notes/',
                 'plans/')
INTERNAL_NAMES = ('ROADMAP.md',)
PLAN = re.compile(r'-plan(-[^/]*)?\.md$')
# Files that name the moved paths by necessity.
SCAN_EXEMPT = {MOVES, 'tools/freereac_ops.py', 'tools/test_freereac_ops.py'}
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
    return path.startswith(INTERNAL_DIRS) or base in INTERNAL_NAMES or bool(PLAN.search(base))


def slug(path):
    """The bare slug a public file cites a moved path by: its file name without the extension."""
    return os.path.splitext(path.rsplit('/', 1)[-1])[0]


def git(*args, cwd=REPO, check=True, data=None):
    p = subprocess.run(['git', *args], cwd=cwd, capture_output=True, input=data)
    if check and p.returncode != 0:
        raise SystemExit('git %s: %s' % (' '.join(args), p.stderr.decode(errors='replace').strip()))
    return p.stdout


def read_moves(repo=REPO):
    """(base sha, [moved paths]) from tools/ops-moves.txt."""
    base, paths = None, []
    with open(os.path.join(repo, MOVES)) as f:
        for line in f:
            line = line.strip()
            if line.startswith('# base '):
                base = line.split()[2]
            elif line and not line.startswith('#'):
                paths.append(line)
    if not base:
        raise SystemExit('%s has no "# base <sha>" line' % MOVES)
    return base, paths


def ops_root(repo=REPO):
    """The freereac-ops checkout: $FREEREAC_OPS, else ../freereac-ops beside this repo, else None."""
    env = os.environ.get('FREEREAC_OPS')
    if env:
        return env if os.path.isdir(env) else None
    sib = os.path.join(os.path.dirname(os.path.abspath(repo)), 'freereac-ops')
    return sib if os.path.isdir(sib) else None


def ops_required():
    return os.environ.get(REQUIRE_ENV) == '1'


def ops_path(rel, repo=REPO):
    """The ops copy of moved path <rel>, or None when the checkout or the file is absent."""
    root = ops_root(repo)
    if root is None:
        return None
    p = os.path.join(root, OPS_SUBDIR, rel)
    return p if os.path.isfile(p) else None


def resolve(name, repo=REPO):
    """A slug (or a moved path) -> the ops file it names, or None."""
    _, paths = read_moves(repo)
    hits = [p for p in paths if p == name or slug(p) == name]
    return ops_path(hits[0], repo) if len(hits) == 1 else None


def read_ops(name, repo=REPO):
    """The bytes of the moved file <name> (a slug), or None when it does not resolve."""
    p = resolve(name, repo)
    if p is None:
        return None
    with open(p, 'rb') as f:
        return f.read()


def absent_reason(name, repo=REPO):
    """The OPS-ABSENT line a reader prints (or fails with) when <name> does not resolve."""
    root = ops_root(repo)
    where = ('no freereac-ops checkout ($FREEREAC_OPS or ../freereac-ops)' if root is None
             else 'not in %s/%s' % (root, OPS_SUBDIR))
    return 'OPS-ABSENT %s: %s' % (name, where)


def citation_patterns(paths):
    """One regex per moved path: its repo path, or its bare file name, as a citation."""
    out = []
    for p in paths:
        base = p.rsplit('/', 1)[-1]
        pats = [re.escape(p), r'(?<![\w./-])' + re.escape(base)]
        out.append((p, re.compile(('(?:%s)(?![\\w-])' % '|'.join(pats)).encode())))
    return out


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

    _, paths = read_moves(repo)
    tracked = [t for t in git('ls-files', '-z', cwd=repo).decode().split('\0') if t]
    present = set(tracked)
    for p in paths:
        if p in present:
            fail('STILL-PUBLIC %s: listed as moved to freereac-ops' % p)
    for t in tracked:
        if t not in paths and belongs_in_ops(t):
            fail('INTERNAL %s: vendor RE or internal material belongs in freereac-ops (%s)'
                 % (t, MOVES))
    pats = citation_patterns(paths)
    for t in tracked:
        if t in SCAN_EXEMPT or t in paths:
            continue
        try:
            with open(os.path.join(repo, t), 'rb') as f:
                data = f.read()
        except OSError:
            continue
        for p, rx in pats:
            for m in rx.finditer(data):
                line = data.count(b'\n', 0, m.start()) + 1
                fail('CITES %s:%d %s: cite the slug %s, not the file' % (t, line, p, slug(p)))
    if 'README.md' in present:
        with open(os.path.join(repo, 'README.md'), encoding='utf-8') as f:
            for code in readme_code(f.read()):
                if BUILD_COMMAND.search(code):
                    fail('README-BUILD %r: build steps live in BUILDING.md' % code.strip())
    root = ops_root(repo)
    if root is None:
        if ops_required():
            fail('OPS-ABSENT moves-resolve: %s=1 and no freereac-ops checkout '
                 '($FREEREAC_OPS or ../freereac-ops)' % REQUIRE_ENV)
        else:
            print('OPS-ABSENT moves-resolve: skipped (no freereac-ops checkout)', file=out)
    else:
        missing = [p for p in paths if ops_path(p, repo) is None]
        for p in missing:
            fail('UNRESOLVED %s: not at %s/%s/%s' % (slug(p), root, OPS_SUBDIR, p))
        if not missing:
            print('OPS OK %d moved paths resolve in %s' % (len(paths), root), file=out)
    print('CHECK OK' if fails == 0 else 'CHECK FAILED %d' % fails, file=out)
    return fails


def export(ops, branch=BRANCH, repo=REPO, out=sys.stdout):
    """Commit the moved files at the list's base, byte-identical, onto <branch> of <ops>."""
    base, paths = read_moves(repo)
    entries = []
    for p in paths:
        row = git('ls-tree', base, '--', p, cwd=repo).decode().strip()
        if not row:
            raise SystemExit('EXPORT REFUSED: %s is not in %s' % (p, base))
        mode, _, sha = row.split('\t')[0].split()
        blob = git('cat-file', 'blob', sha, cwd=repo)
        if git('hash-object', '-w', '--stdin', cwd=ops, data=blob).decode().strip() != sha:
            raise SystemExit('EXPORT REFUSED: %s changed in transit' % p)
        entries.append((mode, sha, '%s/%s' % (OPS_SUBDIR, p)))
    start = None
    for ref in ('refs/remotes/origin/main', 'refs/heads/main'):
        r = git('rev-parse', '-q', '--verify', ref + '^{commit}', cwd=ops, check=False).decode().strip()
        if r:
            start = r
            break
    with tempfile.TemporaryDirectory() as d:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(d, 'index'))

        def g(*args, data=None):
            p = subprocess.run(['git', *args], cwd=ops, env=env, capture_output=True, input=data)
            if p.returncode != 0:
                raise SystemExit('git %s: %s' % (' '.join(args), p.stderr.decode(errors='replace')))
            return p.stdout.decode().strip()

        g('read-tree', start) if start else g('read-tree', '--empty')
        for mode, sha, dest in entries:
            have = g('ls-files', '-s', '--', dest)
            if have and have.split()[1] != sha:
                raise SystemExit('EXPORT REFUSED: %s already in the ops tree with other content' % dest)
            g('update-index', '--add', '--cacheinfo', '%s,%s,%s' % (mode, sha, dest))
        tree = g('write-tree')
        msg = ('reac-protocol: firmware RE write-ups, vendor scene bodies and audits\n\n'
               'From FreeREAC/reac-protocol@%s, byte-identical (%d files, %s).\n'
               'Their history before the move: git log %s -- <path> in reac-protocol.\n'
               % (base[:12], len(entries), MOVES, base[:12]))
        args = ['commit-tree', tree, '-m', msg] + (['-p', start] if start else [])
        # commit-tree never reads commit.gpgSign itself; every ops commit is signed when it is set
        if git('config', '--bool', 'commit.gpgsign', cwd=ops, check=False).strip() == b'true':
            args.append('-S')
        existing = git('rev-parse', '-q', '--verify', 'refs/heads/' + branch, cwd=ops,
                       check=False).decode().strip()
        if existing:
            if g('rev-parse', existing + '^{tree}') == tree:
                print('EXPORT EXISTS %s %s %d files' % (branch, existing, len(entries)), file=out)
                return existing
            raise SystemExit('EXPORT REFUSED: %s exists at %s with another tree' % (branch, existing))
        commit = g(*args)
        g('update-ref', 'refs/heads/' + branch, commit, '0' * 40)
    print('EXPORT %s %s %d files' % (branch, commit, len(entries)), file=out)
    return commit


def main(argv):
    if len(argv) >= 1 and argv[0] == 'check':
        return 1 if check() else 0
    if len(argv) == 2 and argv[0] == 'resolve':
        p = resolve(argv[1])
        if p is None:
            print(absent_reason(argv[1]))
            return 3
        print(p)
        return 0
    if len(argv) in (2, 3) and argv[0] == 'export':
        export(os.path.abspath(argv[1]), *argv[2:])
        return 0
    print(__doc__.split('\n\n')[2], file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
