# sml-json

A small, self-contained **JSON parser and serializer** for Standard ML, built
on the [`sml-parsec`](https://github.com/sjqtentacles/sml-parsec) parser
combinator library. `sml-parsec` is vendored (its source is committed under
`lib/`), so there are no external dependencies to install or fetch — clone the
repo and `make`. Parses to a simple algebraic data type, serializes back to
minified or pretty-printed JSON, and ships with a tiny `jsonfmt` CLI.

Verified TDD-style on both **MLton** and **Poly/ML**.

## Features

- Full [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) value grammar:
  `null`, booleans, numbers, strings, arrays, objects.
- Strict number grammar: rejects leading zeros (`01`), explicit plus (`+1`),
  bare fractions (`.5`), and trailing dots (`1.`). Integers and reals are kept
  distinct (`JInt` vs `JReal`) so `42` round-trips as `42`, not `42.0`.
- Escape-aware string parsing: `\" \\ \/ \b \f \n \r \t` and `\uXXXX`
  (Basic Multilingual Plane; surrogate-pair decoding is a documented follow-up).
  Raw control characters inside strings are rejected.
- Whole-input parsing with precise line/column error reporting.
- Serialization with correct re-escaping and JSON-correct signs (`-3`, not the
  SML `~3`), in both compact and indented forms.

## AST

```sml
datatype json =
    JNull
  | JBool of bool
  | JInt  of int        (* JSON number with no '.', 'e', or 'E' *)
  | JReal of real       (* JSON number with a fraction/exponent *)
  | JStr  of string
  | JArr  of json list
  | JObj  of (string * json) list
```

Note: `json` contains a `real`, so it has no derived equality. For comparing
parsed values in tests, use a structural comparison with a tolerance on
`JReal` (see `test/test.sml`'s `jsonEq`).

## API

From `structure Json`:

```sml
val parseJson : string -> json CharParsec.result
```

`parseJson` skips leading whitespace, parses one JSON value, and requires
end-of-input (trailing garbage is an error). The result is `CharParsec`'s
`result`:

```sml
datatype 'a result = Ok of 'a | Err of error
```

On `Err e`, `CharParsec.errorToString e` produces a human-readable message with
line and column.

From `structure JsonPretty`:

```sml
val toString       : json -> string         (* compact / minified *)
val toStringIndent : int -> json -> string   (* pretty, n-space indent *)
```

Both guarantee their output re-parses to a structurally equal value.

### Example

```sml
open Json

val Ok v = parseJson "{ \"name\": \"ml\", \"nums\": [1, 2.5, -3] }"
(* v = JObj [("name", JStr "ml"),
             ("nums", JArr [JInt 1, JReal 2.5, JInt ~3])] *)

val compact = JsonPretty.toString v
(* {"name":"ml","nums":[1,2.5,-3]} *)

val pretty = JsonPretty.toStringIndent 2 v
(* {
     "name": "ml",
     "nums": [
       1,
       2.5,
       -3
     ]
   } *)
```

## CLI: `jsonfmt`

Reads JSON from stdin, validates it, and writes it back out.

```sh
make fmt                                  # builds bin/jsonfmt (MLton)

echo '{"b":2,"a":[1,2,3]}' | bin/jsonfmt        # pretty (2-space indent)
echo '{"b":2,"a":[1,2,3]}' | bin/jsonfmt -c      # compact / minified
echo '{"b":2,"a":[1,2,3]}' | bin/jsonfmt -i 4    # pretty, 4-space indent
```

Exits non-zero and prints a parse error to stderr on invalid input.

## Build & test

Requires [MLton](http://mlton.org/) and/or [Poly/ML](https://polyml.org/).

```sh
make test        # build + run the suite under MLton
make test-poly   # run the suite under Poly/ML
make all-tests   # both
make fmt         # build the jsonfmt CLI (MLton only)
make clean
```

## Layout

```
sml-json/
  sml.pkg                         smlpkg manifest (documents the upstream dep)
  Makefile                        MLton + Poly/ML targets
  .github/workflows/ci.yml        CI: MLton + Poly/ML
  lib/github.com/sjqtentacles/sml-parsec/   vendored sml-parsec (committed)
  src/
    json.sml         datatype json + parseJson
    jsonPretty.sml   JsonPretty: minified + indented serializers
    json.mlb         basis + vendored parsec.mlb + src files
  test/
    test.mlb
    test.sml         dependency-free check-based suite
  bin/
    jsonfmt.sml      CLI (MLton-only)
    jsonfmt.mlb
```

## Vendoring note

This repo vendors `sml-parsec` under
`lib/github.com/sjqtentacles/sml-parsec/` (committed, no network required to
build). `sml.pkg` records the upstream dependency
(`require github.com/sjqtentacles/sml-parsec`) for users who prefer
`smlpkg sync`, but the build uses the committed copy.

## License

MIT.
