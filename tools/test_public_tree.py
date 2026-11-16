# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/freereac_ops.py after the move: one plain rule, no move list.

The public tree refuses notebook material (firmware write-ups, plans, audits, vendor
binaries) and build commands on the README. There is no list of moved paths, no
resolver, no export and no history walk. The one other thing the tool does is find the
private checkout that holds the two vendor scene bodies the tests read.
Run: python3 -m unittest discover -s tools -p 'test_*.py'"""
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


def sh(cwd, *args):
    subprocess.run(['git', '-c', 'commit.gpgsign=false', *args], cwd=cwd, check=True,
                   capture_output=True)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as f:
        f.write(text)


class Rule(unittest.TestCase):
    def test_classifier(self):
        for p in ('firmware-findings.md', 'x.bin', 'docs/notes/n.md', 'docs/plans/p.md',
                  'ROADMAP.md', 'docs/scene-plan.md', 'unknowns-census.md',
                  'docs/audit-2026-09-13-unknown-facts.md'):
            self.assertTrue(fo.belongs_in_ops(p), p)
        for p in ('README.md', 'BUILDING.md', 'wire-format.md', 'docs/mixer-protocol.md',
                  'spec/reac.ksy', 'spec/fixtures/control.json', 'docs/planning.md'):
            self.assertFalse(fo.belongs_in_ops(p), p)

    def test_the_move_machinery_is_gone(self):
        for name in ('MOVES', 'read_moves', 'moved_paths', 'resolve', 'export', 'history',
                     'history_check', 'history_internal', 'slug', 'citation_patterns'):
            self.assertFalse(hasattr(fo, name), name)
        self.assertFalse(os.path.exists(os.path.join(fo.REPO, 'tools', 'ops-moves.txt')))

    def test_readme_build_command(self):
        code = fo.readme_code('Run `make -C spec check`.\n\n    pip install x\n\nWe make sense.\n')
        self.assertEqual([c for c in code if fo.BUILD_COMMAND.search(c)],
                         ['make -C spec check', '    pip install x'])


class Check(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pub = os.path.join(self.tmp, 'pub')
        os.makedirs(self.pub)
        sh(self.pub, 'init', '-q', '-b', 'main')
        write(self.pub, 'README.md', 'protocol\n')
        write(self.pub, 'wire-format.md', 'frames\n')
        sh(self.pub, 'add', '-A')

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_check(self):
        buf = io.StringIO()
        n = fo.check(self.pub, out=buf)
        return n, buf.getvalue()

    def add(self, rel, text):
        write(self.pub, rel, text)
        sh(self.pub, 'add', rel)

    def test_clean_tree_passes_with_no_move_list(self):
        n, out = self.run_check()
        self.assertEqual(n, 0, out)
        self.assertIn('CHECK OK', out)

    def test_notebook_markdown_fails(self):
        for rel in ('firmware-x.md', 'docs/plans/p.md', 'docs/audits/a-audit.md'):
            self.add(rel, 'notes\n')
        n, out = self.run_check()
        self.assertEqual(n, 3, out)
        self.assertIn('INTERNAL firmware-x.md', out)

    def test_vendor_binary_fails(self):
        self.add('spec/fixtures/scene-y.bin', 'vendor bytes\n')
        n, out = self.run_check()
        self.assertIn('INTERNAL spec/fixtures/scene-y.bin', out)
        self.assertEqual(n, 1, out)

    def test_build_command_on_the_readme_fails(self):
        self.add('README.md', 'Build:\n\n    make -C spec check\n')
        n, out = self.run_check()
        self.assertIn("README-BUILD 'make -C spec check'", out)
        self.assertEqual(n, 1, out)

    def test_the_real_tree_is_clean(self):
        buf = io.StringIO()
        self.assertEqual(fo.check(out=buf), 0, buf.getvalue())


class Vendor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        env = {k: v for k, v in os.environ.items() if not k.startswith('FREEREAC_')}
        self.env = mock.patch.dict(os.environ, env, clear=True)
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.tmp)

    def test_scene_body_is_read_from_the_ops_checkout(self):
        write(self.tmp, 'reac-protocol/spec/fixtures/scene-x.bin', 'body')
        os.environ['FREEREAC_OPS'] = self.tmp
        self.assertEqual(fo.read_ops('scene-x'), b'body')
        self.assertIsNone(fo.read_ops('scene-missing'))
        self.assertIn('not in %s/reac-protocol' % self.tmp, fo.absent_reason('scene-missing'))

    def test_absent_checkout(self):
        os.environ['FREEREAC_OPS'] = os.path.join(self.tmp, 'nope')
        self.assertIsNone(fo.read_ops('scene-x'))
        self.assertEqual(fo.absent_reason('scene-x'),
                         'OPS-ABSENT scene-x: no freereac-ops checkout ($FREEREAC_OPS or ../freereac-ops)')


if __name__ == '__main__':
    unittest.main()
