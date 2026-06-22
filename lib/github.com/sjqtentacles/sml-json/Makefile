# sml-json build
#
#   make            build the test binary with MLton (default)
#   make test       build + run tests under MLton
#   make test-poly  build + run tests under Poly/ML (via tools/polybuild)
#   make all-tests  run the suite under both compilers
#   make fmt        build the jsonfmt CLI with MLton
#   make clean      remove build artifacts

MLTON      ?= mlton
BIN        := bin
LIBDIR     := lib/github.com/sjqtentacles/sml-parsec
TEST_MLB   := test/sources.mlb
SRCS       := $(wildcard $(LIBDIR)/*.sml $(LIBDIR)/*.sig $(LIBDIR)/*.mlb) \
              $(wildcard src/*.sml src/*.sig src/*.mlb) \
              $(wildcard test/*.sml) $(TEST_MLB)

.PHONY: all test poly test-poly all-tests fmt clean

all: $(BIN)/test-mlton

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

poly: $(BIN)/test-poly

# Poly/ML has no native .mlb support; tools/polybuild expands the .mlb in
# dependency order, `use`s each source, and exports `main`.
$(BIN)/test-poly: $(SRCS) tools/polybuild | $(BIN)
	sh tools/polybuild -o $@ $(TEST_MLB)

test-poly: $(BIN)/test-poly
	$(BIN)/test-poly

all-tests: test test-poly

# The CLI is MLton-only (uses CommandLine/TextIO and an exported main).
fmt: $(BIN)/jsonfmt

$(BIN)/jsonfmt: $(SRCS) bin/jsonfmt.mlb bin/jsonfmt.sml | $(BIN)
	$(MLTON) -output $@ bin/jsonfmt.mlb

$(BIN):
	mkdir -p $(BIN)

# bin/ also holds the CLI sources (jsonfmt.sml/.mlb), so clean removes only the
# build outputs, not the directory.
clean:
	rm -f $(BIN)/test-mlton $(BIN)/test-poly $(BIN)/jsonfmt
