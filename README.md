# sml-trace

[![CI](https://github.com/sjqtentacles/sml-trace/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-trace/actions/workflows/ci.yml)

OpenTelemetry-aligned trace/span model for Standard ML, with W3C
`traceparent` codec and OTLP/JSON export. No I/O, no wall clock, no
threads -- a `Tracer` is a pure accumulator `{clock, spans, seed}`
threaded through `startSpan`/`endSpan`, and identifiers are derived
deterministically from the vendored `sml-prng` SplitMix64.

Part of the `sjqtentacles` monorepo of SML libraries. It builds on
[`sml-prng`](https://github.com/sjqtentacles/sml-prng) (vendored) for
identifier generation and
[`sml-json`](https://github.com/sjqtentacles/sml-json) (vendored, which
itself vendors `sml-parsec`) for OTLP/JSON export.

## Features

- **TraceId** (16 bytes) / **SpanId** (8 bytes): `generate : seed -> id *
  seed`, `toHex`, `fromHex`. Hex output is lowercase; `fromHex` accepts
  any case.
- **Span**: `{traceId, spanId, parentSpanId, name, kind, attributes,
  events, status, startTime, endTime option}`. `start`, `finish`,
  `addAttr`, `addEvent`, `setStatus`.
- **Tracer**: pure accumulator. `startSpan` pushes a span (inheriting the
  current traceId/parent when the stack is non-empty, starting a fresh
  trace otherwise); `endSpan` pops and records it.
- **TraceContext**: W3C `traceparent` codec. `encode : traceId * spanId *
  flags -> string` produces `00-<32 hex>-<16 hex>-<2 hex>`; `decode`
  validates version, lengths, hex, and rejects all-zero IDs.
- **OtlpExport**: `toJson : span list -> Json.json` produces the OTLP/JSON
  `ResourceSpans` structure with a `service.name` resource, a single
  scope, and one entry per span carrying `traceId`, `spanId`,
  `parentSpanId`, `name`, `kind`, `startTimeUnixNano`,
  `endTimeUnixNano`, `attributes`, `events`, and `status`.

## Status

Complete and tested. The model is the pure "tracer + logical clock"
shape; wiring it to real I/O (OTLP/HTTP export, wall-clock timestamps)
is the caller's job.

## Dependencies

- `sml-prng` (vendored at `lib/github.com/sjqtentacles/sml-prng/`)
- `sml-json` (vendored at `lib/github.com/sjqtentacles/sml-json/`, which
  vendors `sml-parsec`)
- Standard ML Basis only -- no FFI, no threads.

## Portability

Pure Standard ML. Verified on **MLton** and **Poly/ML**, with identical,
deterministic output across both.

## Usage

```sml
(* Seed the tracer for a deterministic identifier sequence. *)
val tr0 = Trace.init 0w123

(* Start a root span; a fresh TraceId is derived from the seed. *)
val (tr1, rootSid) =
  Trace.startSpan (tr0, { name = "GET /", kind = Trace.Server, parent = NONE })

(* A child span inherits the root's traceId and parentSpanId. *)
val (tr2, _) =
  Trace.startSpan (tr1, { name = "db.query", kind = Trace.Client, parent = NONE })

val (tr3, _) = Trace.endSpan (tr2, Trace.Ok)   (* pop child *)
val (tr4, _) = Trace.endSpan (tr3, Trace.Ok)   (* pop root  *)

(* W3C traceparent for the root. *)
val tp = Trace.TraceContext.encode
           (#traceId (valOf (Trace.currentSpan tr1)),
            rootSid, 0w1)
(* "00-<32 hex>-<16 hex>-01" *)

(* OTLP/JSON export of the finished spans. *)
val otlp = Trace.OtlpExport.toJson (Trace.finishedSpans tr4)
```

## Building and testing

```sh
make test        # build + run the suite under MLton (default)
make test-poly   # run the suite under Poly/ML
make all-tests   # run under both
make clean
```

## Test coverage

- TraceId: hex round-trip (generated and known vectors); 32-char lowercase
  hex; `fromHex` rejects bad length and bad chars.
- SpanId: hex round-trip; 16-char hex; known vector.
- TraceContext: `encode` matches the W3C example
  (`00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`); `decode`
  recovers all fields; round-trip with flags=0; rejects all-zero
  traceId/spanId and bad length.
- Span lifecycle: `start` produces an unfinished span; `addAttr` /
  `addEvent` accumulate; `finish` sets `endTime` and promotes `Unset` to
  `Ok`.
- Parent-child nesting: a child started under a root inherits the root's
  `traceId` and has `parentSpanId = root.spanId`; `endSpan` pops the
  stack; `finishedSpans` returns spans oldest-start-first.
- OTLP JSON: one `resourceSpans` entry with a `service.name` resource and
  a single scope; two spans; the root has `name = "root"`; the child has
  `parentSpanId`.
- Determinism: same seed -> same `TraceId` / `SpanId` sequence; same-seed
  `Tracer` produces the same spanId sequence.

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-trace
smlpkg sync
```

Then reference the library basis from your own `.mlb`:

```
lib/github.com/sjqtentacles/sml-trace/sml-trace.mlb
```

For Poly/ML, `use` the sources listed in `sources.mlb` in order (the
vendored `sml-prng`, then `sml-json` + `sml-parsec`, then `trace.sig`
and `trace.sml`).

## License

MIT. See [LICENSE](LICENSE).
