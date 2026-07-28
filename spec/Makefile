# REAC Kaitai spec — regenerate the parser, then run the cross-check.
#
#   make parser   generate reac.py from reac.ksy
#   make check    generate + run the cross-validation harness
#   make cpp      prove the C-family target also generates (CI gate)
#   make clean    remove generated parsers
#
# The generated parser is NEVER committed: reac.ksy is the source of truth and
# a stale checked-in parser is exactly the drift this spec exists to prevent.

KSC ?= kaitai-struct-compiler
PYTHON ?= python3
KSY := reac.ksy

.PHONY: all parser check cpp clean ksc-help

all: check

parser: reac.py

reac.py: $(KSY)
	@command -v $(KSC) >/dev/null 2>&1 || { $(MAKE) --no-print-directory ksc-help; exit 1; }
	$(KSC) -t python --outdir . $(KSY)

check: parser
	$(PYTHON) -m pytest reac_xcheck.py -q

cpp: $(KSY)
	@command -v $(KSC) >/dev/null 2>&1 || { $(MAKE) --no-print-directory ksc-help; exit 1; }
	$(KSC) -t cpp_stl --outdir cpp $(KSY)
	test -f cpp/reac.cpp && test -f cpp/reac.h

clean:
	rm -rf reac.py cpp/ __pycache__/ .pytest_cache/

ksc-help:
	@echo 'kaitai-struct-compiler (ksc) not found. It is not in the distro repos;'
	@echo 'grab the universal zip — it needs a JRE at BUILD time only, the parser'
	@echo 'it generates is plain Python with no JVM anywhere near it:'
	@echo
	@echo '  curl -fsSLO https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.11/kaitai-struct-compiler-0.11.zip'
	@echo '  unzip -q kaitai-struct-compiler-0.11.zip'
	@echo '  export PATH="$$PWD/kaitai-struct-compiler-0.11/bin:$$PATH"'
	@echo
	@echo 'The harness also needs the Kaitai Python runtime and pytest:'
	@echo
	@echo '  pip install kaitaistruct pytest'
