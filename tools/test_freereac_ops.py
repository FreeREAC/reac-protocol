# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/freereac_ops.py on throwaway git repos: the public-tree guard, the resolver rungs and the
ops export. Run: python3 -m unittest discover -s tools -p 'test_*.py'"""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import freereac_ops as fo  # noqa: E402

MOVED = ['firmware-x.md', 'docs/audits/a-audit.md', 'spec/fixtures/scene-x.bin']


def sh(cwd, *args):
    subprocess.run(['git', '-c', 'commit.gpgsign=false', *args], cwd=cwd, check=True,
                   capture_output=True)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as f:
        f.write(text)


class Fixture(unittest.TestCase):
    """<tmp>/pub: a repo whose base commit holds MOVED, whose tip moved them out."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pub = os.path.join(self.tmp, 'pub')
        os.makedirs(self.pub)
        sh(self.pub, 'init', '-q', '-b', 'main')
        sh(self.pub, 'config', 'user.email', 't@example.com')
        sh(self.pub, 'config', 'user.name', 'T')
        write(self.pub, 'README.md', 'protocol\n')
        write(self.pub, 'wire-format.md', 'frames\n')
        for p in MOVED:
            write(self.pub, p, 'internal %s\n' % p)
        sh(self.pub, 'add', '-A')
        sh(self.pub, 'commit', '-qm', 'base')
        self.base = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=self.pub, capture_output=True,
                                   text=True).stdout.strip()
        sh(self.pub, 'rm', '-q', *MOVED)
        write(self.pub, fo.MOVES, '# base %s\n%s\n' % (self.base, '\n'.join(MOVED)))
        sh(self.pub, 'add', '-A')
        sh(self.pub, 'commit', '-qm', 'move')
        env = {k: v for k, v in os.environ.items() if not k.startswith('FREEREAC_')}
        self.env = mock.patch.dict(os.environ, env, clear=True)
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.tmp)

    def run_check(self):
        buf = io.StringIO()
        n = fo.check(self.pub, out=buf)
        return n, buf.getvalue()

    def add(self, rel, text):
        write(self.pub, rel, text)
        sh(self.pub, 'add', rel)

    def make_ops(self, root, paths=MOVED):
        for p in paths:
            write(root, os.path.join(fo.OPS_SUBDIR, p), 'internal %s\n' % p)


class Classifier(unittest.TestCase):
    def test_rule(self):
        for p in ('firmware-findings.md', 'firmware-protocol.md', 'spec/fixtures/scene-a-8904.bin',
                  'x.bin', 'docs/audits/2026-09-25-contract-copies/libreac.tsv',
                  'docs/notes/n.md', 'docs/plans/p.md', 'ROADMAP.md', 'docs/scene-plan.md',
                  'docs/f-plan-2026.md', '.claude/skills/s.md', 'CLAUDE.md',
                  'docs/audit-2026-09-13-unknown-facts.md', 'unknowns-census.md',
                  'defect-census-2026-08-23.md'):
            self.assertTrue(fo.belongs_in_ops(p), p)
        for p in ('README.md', 'BUILDING.md', 'LICENSE', 'NOTICE', 'wire-format.md',
                  'capturing.md', 'docs/mixer-protocol.md', 'docs/firmware-x.md', 'spec/reac.ksy',
                  'spec/fixtures/control.json', 'spec/fixtures/upstream.json',
                  'spec/generated/reac_facts.h', 'spec/synthetic_scene.py', 'tools/ops-moves.txt',
                  '.github/workflows/check.yml', 'docs/planning.md', 'docs/auditing.md'):
            self.assertFalse(fo.belongs_in_ops(p), p)

    def test_slug_is_bare(self):
        self.assertEqual(fo.slug('firmware-findings.md'), 'firmware-findings')
        self.assertEqual(fo.slug('docs/audits/2026-09-25-contract-copies.md'),
                         '2026-09-25-contract-copies')
        self.assertEqual(fo.slug('spec/fixtures/scene-m200i-8904.bin'), 'scene-m200i-8904')

    def test_readme_build_command(self):
        code = fo.readme_code('Run `make -C spec check`.\n\n    pip install x\n\nWe make sense.\n')
        self.assertEqual([c for c in code if fo.BUILD_COMMAND.search(c)],
                         ['make -C spec check', '    pip install x'])


class Check(Fixture):
    def test_clean_tree_passes_and_names_the_skip(self):
        n, out = self.run_check()
        self.assertEqual(n, 0, out)
        self.assertIn('OPS-ABSENT moves-resolve: skipped', out)
        self.assertIn('CHECK OK', out)

    def test_moved_path_still_public_fails(self):
        self.add('firmware-x.md', 'back\n')
        n, out = self.run_check()
        self.assertIn('STILL-PUBLIC firmware-x.md', out)
        self.assertGreater(n, 0)

    def test_new_internal_file_fails(self):
        self.add('spec/fixtures/scene-y.bin', 'vendor bytes\n')
        n, out = self.run_check()
        self.assertIn('INTERNAL spec/fixtures/scene-y.bin', out)
        self.assertEqual(n, 1, out)

    def test_citation_by_file_fails_and_slug_passes(self):
        self.add('wire-format.md', 'see [x](firmware-x.md) and docs/audits/a-audit.md\n')
        n, out = self.run_check()
        self.assertIn('CITES wire-format.md:1 firmware-x.md', out)
        self.assertIn('CITES wire-format.md:1 docs/audits/a-audit.md', out)
        self.assertEqual(n, 2, out)  # one finding per citation, by path or by bare name
        self.add('wire-format.md', 'see `firmware-x` and `a-audit`\n')
        self.assertEqual(self.run_check()[0], 0)

    def test_build_command_on_the_readme_fails(self):
        self.add('README.md', 'Build:\n\n    make -C spec check\n')
        n, out = self.run_check()
        self.assertIn("README-BUILD 'make -C spec check'", out)
        self.assertEqual(n, 1, out)
        self.add('README.md', 'Build: see [BUILDING.md](BUILDING.md).\n')
        self.assertEqual(self.run_check()[0], 0)

    def test_require_ops_fails_when_absent(self):
        os.environ['FREEREAC_REQUIRE_OPS'] = '1'
        n, out = self.run_check()
        self.assertIn('OPS-ABSENT moves-resolve: FREEREAC_REQUIRE_OPS=1', out)
        self.assertEqual(n, 1)

    def test_env_rung_resolves_every_move(self):
        ops = os.path.join(self.tmp, 'elsewhere')
        self.make_ops(ops)
        os.environ['FREEREAC_OPS'] = ops
        n, out = self.run_check()
        self.assertEqual(n, 0, out)
        self.assertIn('OPS OK 3 moved paths', out)
        self.assertEqual(fo.resolve('scene-x', self.pub),
                         os.path.join(ops, 'reac-protocol', 'spec', 'fixtures', 'scene-x.bin'))
        self.assertEqual(fo.read_ops('firmware-x', self.pub), b'internal firmware-x.md\n')

    def test_sibling_rung_and_half_moved_fails(self):
        sib = os.path.join(self.tmp, 'freereac-ops')
        self.make_ops(sib, MOVED[:2])
        self.assertEqual(fo.ops_root(self.pub), sib)
        n, out = self.run_check()
        self.assertIn('UNRESOLVED scene-x', out)
        self.assertEqual(n, 1, out)
        self.assertIn('not in %s/reac-protocol' % sib, fo.absent_reason('scene-x', self.pub))
        os.environ['FREEREAC_OPS'] = os.path.join(self.tmp, 'nope')
        self.assertIsNone(fo.ops_root(self.pub), 'a set but missing $FREEREAC_OPS never falls through')

    def test_resolve_absent(self):
        self.assertIsNone(fo.resolve('scene-x', self.pub))
        self.assertIsNone(fo.read_ops('scene-x', self.pub))
        self.assertEqual(fo.absent_reason('scene-x', self.pub),
                         'OPS-ABSENT scene-x: no freereac-ops checkout ($FREEREAC_OPS or ../freereac-ops)')


class Export(Fixture):
    def ops_repo(self, seeded):
        ops = os.path.join(self.tmp, 'freereac-ops')
        os.makedirs(ops)
        sh(ops, 'init', '-q', '-b', 'main')
        sh(ops, 'config', 'user.email', 't@example.com')
        sh(ops, 'config', 'user.name', 'T')
        sh(ops, 'config', 'commit.gpgsign', 'false')
        if seeded:
            write(ops, 'README.md', 'ops\n')
            sh(ops, 'add', '-A')
            sh(ops, 'commit', '-qm', 'seed')
        return ops

    def ls(self, ops, ref):
        return subprocess.run(['git', 'ls-tree', '-r', ref], cwd=ops, capture_output=True,
                              text=True).stdout

    def test_export_onto_main_is_byte_identical_and_idempotent(self):
        ops = self.ops_repo(seeded=True)
        buf = io.StringIO()
        c = fo.export(ops, repo=self.pub, out=buf)
        self.assertIn('EXPORT lane/docs-reac-protocol', buf.getvalue())
        tree = self.ls(ops, fo.BRANCH)
        self.assertIn('\tREADME.md\n', tree)
        for p in MOVED:
            src = subprocess.run(['git', 'rev-parse', '%s:%s' % (self.base, p)], cwd=self.pub,
                                 capture_output=True, text=True).stdout.strip()
            self.assertIn('%s\treac-protocol/%s\n' % (src, p), tree)
        parent = subprocess.run(['git', 'rev-parse', fo.BRANCH + '^'], cwd=ops,
                                capture_output=True, text=True).stdout.strip()
        main = subprocess.run(['git', 'rev-parse', 'main'], cwd=ops, capture_output=True,
                              text=True).stdout.strip()
        self.assertEqual(parent, main)
        buf = io.StringIO()
        self.assertEqual(fo.export(ops, repo=self.pub, out=buf), c)
        self.assertIn('EXPORT EXISTS', buf.getvalue())
        # the exported checkout is what `check` then resolves through the sibling rung
        subprocess.run(['git', '-c', 'advice.detachedHead=false', 'checkout', '-q', fo.BRANCH],
                       cwd=ops, check=True)
        n, out = self.run_check()
        self.assertEqual(n, 0, out)
        self.assertIn('OPS OK 3 moved paths', out)

    def test_export_signs_when_commit_gpgsign_is_set(self):
        ops = self.ops_repo(seeded=True)
        sh(ops, 'config', 'commit.gpgsign', 'true')
        sh(ops, 'config', 'gpg.program', os.path.join(self.tmp, 'no-gpg'))
        with self.assertRaises(SystemExit) as e:
            fo.export(ops, repo=self.pub, out=io.StringIO())
        self.assertIn('commit-tree', str(e.exception), 'the export asked gpg to sign, and gpg failed')

    def test_export_into_empty_ops_is_a_root_commit(self):
        ops = self.ops_repo(seeded=False)
        fo.export(ops, repo=self.pub, out=io.StringIO())
        self.assertEqual(len(self.ls(ops, fo.BRANCH).splitlines()), len(MOVED))

    def test_export_takes_each_group_from_its_own_base(self):
        sh(self.pub, 'checkout', '-q', '-b', 'side', self.base)
        self.add('unknowns-census.md', 'only ever in the history\n')
        sh(self.pub, 'commit', '-qm', 'census')
        side = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=self.pub, capture_output=True,
                              text=True).stdout.strip()
        sh(self.pub, 'checkout', '-q', 'main')
        write(self.pub, fo.MOVES, '# base %s\n%s\n# base %s\nunknowns-census.md\n'
              % (self.base, '\n'.join(MOVED), side))
        ops = self.ops_repo(seeded=True)
        fo.export(ops, repo=self.pub, out=io.StringIO())
        tree = self.ls(ops, fo.BRANCH)
        blob = subprocess.run(['git', 'rev-parse', side + ':unknowns-census.md'], cwd=self.pub,
                              capture_output=True, text=True).stdout.strip()
        self.assertIn('%s\treac-protocol/unknowns-census.md\n' % blob, tree)
        self.assertEqual(len(tree.splitlines()), len(MOVED) + 2)  # + the seed README
        msg = subprocess.run(['git', 'log', '-1', '--format=%B', fo.BRANCH], cwd=ops,
                             capture_output=True, text=True).stdout
        self.assertIn('%s,%s' % tuple(sorted([self.base[:12], side[:12]])), msg)

    def test_export_refuses_a_path_missing_at_base(self):
        ops = self.ops_repo(seeded=True)
        write(self.pub, fo.MOVES, '# base %s\nnot/there.md\n' % self.base)
        with self.assertRaises(SystemExit) as e:
            fo.export(ops, repo=self.pub, out=io.StringIO())
        self.assertIn('not/there.md is not in', str(e.exception))


class History(Fixture):
    """The rewrite's drop list and the guard that keeps the rewritten history clean."""

    def commit(self, msg):
        sh(self.pub, 'commit', '-qm', msg)

    def drops(self, *revs):
        out, err = io.StringIO(), io.StringIO()
        n = fo.history(revs or ('--all',), self.pub, out=out, err=err)
        return n, out.getvalue().split(), err.getvalue()

    def guard(self, *revs):
        buf = io.StringIO()
        n = fo.history_check(revs or ('HEAD',), self.pub, out=buf)
        return n, buf.getvalue()

    def test_drop_list_is_every_moved_path_even_deleted_ones(self):
        n, paths, err = self.drops()
        self.assertEqual((n, err), (0, ''))
        self.assertEqual(paths, sorted(MOVED))

    def test_an_internal_path_off_the_list_is_refused_by_name(self):
        sh(self.pub, 'checkout', '-q', '-b', 'side')
        self.add('docs/notes/n.md', 'a note\n')
        self.commit('note')
        sh(self.pub, 'rm', '-q', 'docs/notes/n.md')
        self.commit('drop note')
        sh(self.pub, 'checkout', '-q', 'main')
        self.assertEqual(self.drops('main')[0], 0, 'the side branch is not in main')
        n, paths, err = self.drops()
        self.assertEqual(n, 1)
        self.assertIn('UNLISTED docs/notes/n.md', err)
        self.assertIn('docs/notes/n.md', paths)

    def test_guard_is_red_on_the_old_history_and_names_the_paths(self):
        n, out = self.guard()
        self.assertEqual(n, len(MOVED), out)
        self.assertIn('HISTORY-INTERNAL spec/fixtures/scene-x.bin: added in %s' % self.base[:12], out)
        self.assertIn('HISTORY FAILED 3', out)

    def test_guard_is_green_on_a_clean_history_and_red_on_an_add_and_delete(self):
        sh(self.pub, 'checkout', '-q', '--orphan', 'clean')
        sh(self.pub, 'rm', '-rq', '--cached', '.')
        self.add('README.md', 'protocol\n')
        self.add(fo.MOVES, '# base %s\n%s\n' % (self.base, '\n'.join(MOVED)))
        self.add('a' * 40, 'a 40-hex file name is a file, not a commit\n')
        self.commit('rewritten')
        n, out = self.guard()
        self.assertEqual(n, 0, out)
        self.assertIn('HISTORY OK 1 commits', out)
        self.add('firmware-x.md', 'back\n')
        self.commit('oops')
        sh(self.pub, 'rm', '-q', 'firmware-x.md')
        self.commit('undo')
        n, out = self.guard()
        self.assertIn('HISTORY-INTERNAL firmware-x.md', out)
        self.assertEqual(n, 1, out)

    def test_a_file_a_merge_adds_is_seen(self):
        sh(self.pub, 'checkout', '-q', '-b', 'side')
        self.add('side.md', 'x\n')
        self.commit('side')
        sh(self.pub, 'checkout', '-q', 'main')
        sh(self.pub, 'merge', '-q', '--no-ff', '--no-commit', 'side')
        self.add('docs/plans/p.md', 'only the merge adds this\n')
        self.commit('merge')
        self.assertIn('docs/plans/p.md', fo.history_paths(['HEAD'], self.pub))


def has_commit(sha):
    return subprocess.run(['git', 'cat-file', '-e', sha + '^{commit}'], cwd=fo.REPO,
                          capture_output=True).returncode == 0


class RealTree(unittest.TestCase):
    """This repository, before its history rewrite and after it: the tree is clean, every internal
    path its history carries is on the move list, and the list can be exported."""

    def test_the_public_tree_is_clean(self):
        env = {k: v for k, v in os.environ.items() if k != 'FREEREAC_REQUIRE_OPS'}
        with mock.patch.dict(os.environ, env, clear=True):
            buf = io.StringIO()
            self.assertEqual(fo.check(out=buf), 0, buf.getvalue())

    def test_every_internal_path_in_the_history_is_listed(self):
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(fo.history(('HEAD',), out=out, err=err), 0, err.getvalue())

    def test_every_listed_path_is_at_its_base_or_rewritten_away(self):
        for base, p in fo.read_moves():
            if has_commit(base):
                self.assertTrue(fo.git('ls-tree', base, '--', p).strip(), '%s not at %s' % (p, base))
            else:
                # the base went with the history rewrite (it lives on in the backup tags), so
                # nothing on the list may be reachable here either
                self.assertNotIn(p, fo.history_internal(['HEAD']), p)

    def test_the_rule_at_each_base_is_on_the_list(self):
        paths = set(fo.moved_paths())
        for base in {b for b, _ in fo.read_moves()}:
            if not has_commit(base):
                continue  # rewritten away: test_every_internal_path_in_the_history_is_listed holds
            tree = fo.git('ls-tree', '-r', '--name-only', base).decode().splitlines()
            self.assertLessEqual({p for p in tree if fo.belongs_in_ops(p)}, paths, base)

    def test_slugs_are_unique(self):
        paths = fo.moved_paths()
        self.assertEqual(len({fo.slug(p) for p in paths}), len(paths))


if __name__ == '__main__':
    unittest.main()
