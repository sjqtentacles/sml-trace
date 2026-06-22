# sml-trace build
MLTON      ?= mlton
BIN        := bin
LIBDIR     := lib/github.com/sjqtentacles/sml-trace
VENDOR_PRNG := lib/github.com/sjqtentacles/sml-prng
VENDOR_JSON := lib/github.com/sjqtentacles/sml-json
TEST_MLB   := test/sources.mlb
SRCS       := $(wildcard $(LIBDIR)/*.sml $(LIBDIR)/*.sig) \
              $(wildcard $(VENDOR_PRNG)/*.sml $(VENDOR_PRNG)/*.sig) \
              $(wildcard $(VENDOR_JSON)/src/*.sml $(VENDOR_JSON)/src/*.sig) \
              $(wildcard $(VENDOR_JSON)/lib/github.com/sjqtentacles/sml-parsec/*.sml \
                         $(VENDOR_JSON)/lib/github.com/sjqtentacles/sml-parsec/*.sig) \
              $(wildcard test/*.sml) $(TEST_MLB) $(LIBDIR)/sources.mlb \
              $(VENDOR_PRNG)/prng.mlb $(VENDOR_JSON)/src/json.mlb \
              $(VENDOR_JSON)/lib/github.com/sjqtentacles/sml-parsec/parsec.mlb

.PHONY: all test poly test-poly all-tests clean

all: $(BIN)/test-mlton

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

poly: $(BIN)/test-poly

$(BIN)/test-poly: $(SRCS) tools/polybuild | $(BIN)
	sh tools/polybuild -o $@ $(TEST_MLB)

test-poly: $(BIN)/test-poly
	$(BIN)/test-poly

all-tests: test test-poly

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -rf $(BIN)
