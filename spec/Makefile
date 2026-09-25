# REAC Kaitai spec — regenerate the parser, then run the cross-check.
#
#   make parser   generate reac.py from reac.ksy
#   make check    generate + run the cross-validation harness (includes the
#                 protocol-facts ratchet)
#   make facts    regenerate spec/generated/ from spec/protocol-facts.yaml
#   make facts-fresh
#                 regenerate into a scratch dir and require byte-identity with
#                 the tracked generated/, with positive and sabotage controls
#                 and the perturbation contract (facts_fresh_xcheck.py)
#   make facts-perturb SEED=n OUT=dir
#                 write a PERTURBED fact set to OUT: every free number moved
#                 within its legal range. Build libreac / reac-pw against it
#                 to find hand-written copies (docs/audits/2026-09-25-contract-copies.md)
#   make facts-idempotent
#                 generate twice and diff — a generator that varies between two
#                 runs over one input regresses the file it maintains
#   make cpp      prove the C-family target also generates (CI gate)
#   make check-ctrl-oracle
#                 DEV-ONLY: build a frame with libreac, parse it with the
#                 ksy-generated parser, require them to agree — and the reverse
#                 over the committed corpus. This is the check that catches a
#                 MISUNDERSTANDING rather than a typo.
#                   make check-ctrl-oracle LIBREAC=../../libreac
#   make corpus-check
#                 DEV-ONLY: parse EVERY capture in the corpus with the grammar
#                 and refuse a regression against spec/corpus-baseline.json.
#                 The unit suite runs on the goldens; this runs on the whole
#                 body of evidence, and they are not the same check.
#                   make corpus-check CAPTURES=~/Devel/audio/reac-captures
#   make corpus-selftest
#                 corrupt every frame and require the corpus check to go RED.
#                 A checker that cannot fail reports success over any grammar.
#   make check-oracle
#                 DEV-ONLY: diff the generated parser against the COMPILED
#                 libreac rather than a Python transcription of it. Needs a
#                 libreac checkout and a C compiler, so it is out of `check`
#                 and out of CI, both of which stay hermetic.
#                   make check-oracle LIBREAC=../../libreac
#   make clean    remove generated parsers
#
# The generated parser is NEVER committed: reac.ksy is the source of truth and
# a stale checked-in parser is exactly the drift this spec exists to prevent.

KSC ?= kaitai-struct-compiler
PYTHON ?= python3
KSY := reac.ksy
LIBREAC ?= ../../libreac

.PHONY: all parser check check-oracle check-ctrl-oracle facts \
        facts-idempotent facts-fresh facts-perturb cpp clean ksc-help corpus-check corpus-selftest

all: check

parser: reac.py

reac.py: $(KSY)
	@command -v $(KSC) >/dev/null 2>&1 || { $(MAKE) --no-print-directory ksc-help; exit 1; }
	$(KSC) -t python --outdir . $(KSY)

check: parser facts-idempotent
	$(PYTHON) -m pytest reac_xcheck.py facts_xcheck.py facts_fresh_xcheck.py -q

facts:
	$(PYTHON) gen-facts.py

facts-fresh:
	$(PYTHON) -m pytest facts_fresh_xcheck.py -q

SEED ?= 1
OUT ?= out/facts-perturbed
facts-perturb:
	$(PYTHON) gen-facts.py --perturb $(SEED) --outdir $(OUT)

# Generate into a scratch tree, generate again, diff. Nothing here reads the
# clock or the environment, and this is what keeps it that way.
facts-idempotent:
	@rm -rf out/facts-idem && mkdir -p out/facts-idem
	@cp gen-facts.py protocol-facts.yaml out/facts-idem/
	@cd out/facts-idem && $(PYTHON) gen-facts.py >/dev/null
	@cp -r out/facts-idem/generated out/facts-idem/generated.first
	@cd out/facts-idem && $(PYTHON) gen-facts.py >/dev/null
	@diff -r out/facts-idem/generated.first out/facts-idem/generated
	@$(PYTHON) gen-facts.py --check

CAPTURES ?= $(HOME)/Devel/audio/reac-captures

corpus-check:
	$(PYTHON) corpus-check.py --captures $(CAPTURES)

corpus-selftest:
	$(PYTHON) corpus-check.py --captures $(CAPTURES) --self-test --quiet

check-oracle: parser
	$(PYTHON) xcheck_c_oracle.py --libreac $(LIBREAC)

check-ctrl-oracle: parser facts
	$(PYTHON) xcheck_ctrl_oracle.py --libreac $(LIBREAC)

cpp: $(KSY)
	@command -v $(KSC) >/dev/null 2>&1 || { $(MAKE) --no-print-directory ksc-help; exit 1; }
	$(KSC) -t cpp_stl --outdir cpp $(KSY)
	test -f cpp/reac.cpp && test -f cpp/reac.h

clean:
	rm -rf reac.py cpp/ out/ __pycache__/ .pytest_cache/ c_oracle_dump c_ctrl_dump

ksc-help:
	@echo 'kaitai-struct-compiler (ksc) not found. It is not in the distro repos;'
	@echo 'grab the universal zip — it needs a JRE at BUILD time only, the parser'
	@echo 'it generates is plain Python with no JVM anywhere near it:'
	@echo
	@echo '  curl -fsSLO https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.11/kaitai-struct-compiler-0.11.zip'
	@echo '  unzip -q kaitai-struct-compiler-0.11.zip'
	@echo '  export PATH="$$PWD/kaitai-struct-compiler-0.11/bin:$$PATH"'
	@echo
	@echo 'The harness also needs the Kaitai Python runtime, pytest and PyYAML'
	@echo '(gen-facts.py / facts_xcheck.py read protocol-facts.yaml):'
	@echo
	@echo '  pip install kaitaistruct pytest pyyaml'
