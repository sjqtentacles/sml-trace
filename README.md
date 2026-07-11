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
  `addAttr`, `addEvent`, `setStatus`. Timestamps (`startTime`, `endTime`,
  event `time`) and the tracer clock are `IntInf.int`, so a real Unix
  *nanosecond* count (~1.7e18) is stored and exported losslessly.
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

Both compilers use a fixed-width default `int` (MLton 32-bit, Poly/ML
63-bit) -- neither is arbitrary precision. Timestamps and integer JSON
numbers therefore use `IntInf.int` (arbitrary precision on both), so a
Unix nanosecond timestamp serializes to the same exact digits on each and
never overflows MLton's 32-bit `int`.

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

## Example

`make example` builds and runs [`examples/demo.sml`](examples/demo.sml), which
generates trace/span ids from a fixed seed, round-trips a W3C traceparent
header, builds a two-span trace with attributes and events, and exports it
as OTLP/JSON (output is byte-identical under MLton and Poly/ML):

```
=== sml-trace demo ===

-- deterministic id generation from a seed --
  traceId = 1c948e1575796814ae9ef1ab67004bdb
  rootId  = 1464cc6881c5ee9f
  childId = d513e40e7e6987ac

-- W3C traceparent codec --
  traceparent = 00-1c948e1575796814ae9ef1ab67004bdb-1464cc6881c5ee9f-01
  decode roundtrips = true

-- building a two-span trace: start, addAttr, addEvent, finish --
  handle-request  span=1464cc6881c5ee9f  parent=-  [0..5]  attrs=2  events=1
  db-query  span=d513e40e7e6987ac  parent=1464cc6881c5ee9f  [1..4]  attrs=1  events=0

-- OTLP/JSON export --
{
  "resourceSpans": [
    {
      "resource": {
        "attributes": [
          {
            "key": "service.name",
            "value": {
              "stringValue": "sml-trace"
            }
          }
        ]
      },
      "scopeSpans": [
        {
          "scope": {
            "name": "sml-trace",
            "version": "0.1.0"
          },
          "spans": [
            {
              "traceId": "1c948e1575796814ae9ef1ab67004bdb",
              "spanId": "1464cc6881c5ee9f",
              "name": "handle-request",
              "kind": 2,
              "startTimeUnixNano": 0,
              "endTimeUnixNano": 5,
              "attributes": {
                "http.status_code": {
                  "intValue": 200
                },
                "http.method": {
                  "stringValue": "GET"
                }
              },
              "events": [
                {
                  "name": "dispatch",
                  "timeUnixNano": 1,
                  "attributes": {
                    "queue.size": {
                      "intValue": 3
                    }
                  }
                }
              ],
              "status": {
                "code": "STATUS_CODE_OK"
              }
            },
            {
              "traceId": "1c948e1575796814ae9ef1ab67004bdb",
              "spanId": "d513e40e7e6987ac",
              "name": "db-query",
              "kind": 3,
              "startTimeUnixNano": 1,
              "endTimeUnixNano": 4,
              "parentSpanId": "1464cc6881c5ee9f",
              "attributes": {
                "db.statement": {
                  "stringValue": "SELECT 1"
                }
              },
              "events": [],
              "status": {
                "code": "STATUS_CODE_OK"
              }
            }
          ]
        }
      ]
    }
  ]
}
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
- Large integers: a realistic Unix nanosecond timestamp (~1.7e18, past
  MLton's 2^31 `int` ceiling) used as `startTime`/`endTime`, plus a large
  integer attribute, serialize to their exact decimal digits with no
  overflow or truncation on either compiler.
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
