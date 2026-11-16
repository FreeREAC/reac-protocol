# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""The old-reader and alias paths of the grammar and its checkers are gone.

* the pre-2026-08-23 frame classifier and its partition proof,
* the corpus checker's "point it at an older grammar" wording,
* the two alias instances of the grammar (`op_len_raw`, `record_class`),
* the ignore line of a parser from a grammar that never landed.
"""
import importlib.util
import pathlib
import subprocess
import sys

import pytest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

reac = pytest.importorskip("reac")


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_corpus_checker_has_no_legacy_classifier():
    mod = load("corpus_check_under_test", "corpus-check.py")
    for name in ("legacy_ctrl_kind", "LEGACY_NAMES"):
        assert not hasattr(mod, name), name
    helptext = subprocess.run([sys.executable, str(HERE / "corpus-check.py"), "--help"],
                              capture_output=True, text=True).stdout
    assert "--classify-delta" not in helptext


def test_xcheck_has_no_legacy_classifier_or_partition_proof():
    mod = load("reac_xcheck_under_test", "reac_xcheck.py")
    assert not hasattr(mod, "legacy_ctrl_kind")
    assert not hasattr(mod, "test_reclassification_only_splits_and_never_moves_sideways")


def test_corpus_checker_ksy_is_just_the_grammar_to_test():
    helptext = subprocess.run([sys.executable, str(HERE / "corpus-check.py"), "--help"],
                              capture_output=True, text=True).stdout
    flat = " ".join(helptext.split())
    assert "older copy" not in flat
    assert "grammar to test" in flat


def test_grammar_has_one_name_per_field():
    assert not hasattr(reac.Reac.TypedBlock, "op_len_raw")
    assert hasattr(reac.Reac.TypedBlock, "rec_len")
    assert not hasattr(reac.Reac.ControlBlock, "record_class")
    assert hasattr(reac.Reac.ControlBlock, "link")


def test_gitignore_has_no_entry_for_a_grammar_that_never_landed():
    assert "reac_control" not in (HERE / ".gitignore").read_text()
