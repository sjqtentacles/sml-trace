(* trace.sig

   OpenTelemetry-aligned trace/span model for Standard ML, with W3C
   `traceparent` codec and OTLP/JSON export.

   The model is pure: a `Tracer` is an accumulator `{clock, spans, seed}`
   threaded through `startSpan`/`endSpan`, and identifiers are derived
   deterministically from the vendored `sml-prng` SplitMix64. A fixed seed
   reproduces an entire trace's identifier sequence byte-for-byte across
   MLton and Poly/ML.

   Modules:
     - TraceId (16 bytes) / SpanId (8 bytes): generate, toHex, fromHex
     - Span: start/finish/addAttr/addEvent; the record carries traceId,
       spanId, parentSpanId, name, kind, attributes, events, status, and
       logical start/end times.
     - Tracer: pure accumulator; startSpan/endSpan/currentSpan.
     - TraceContext: W3C traceparent codec (encode/decode).
     - OtlpExport: toJson : span list -> Json.json (ResourceSpans). *)

signature TRACE =
sig

  (* ============ TraceId (16 bytes) / SpanId (8 bytes) ============ *)

  structure TraceId :
  sig
    type t
    val generate : Word64.word -> t * Word64.word   (* seed -> (id, seed') *)
    val toHex    : t -> string                       (* 32 lowercase hex chars *)
    val fromHex  : string -> t option                (* NONE on bad length/chars *)
    val eq       : t * t -> bool
    val zero     : t                                 (* all-zero, invalid per W3C *)
  end

  structure SpanId :
  sig
    type t
    val generate : Word64.word -> t * Word64.word
    val toHex    : t -> string                       (* 16 lowercase hex chars *)
    val fromHex  : string -> t option
    val eq       : t * t -> bool
    val zero     : t
  end

  (* ============ Span ============ *)

  datatype spanKind = Internal | Server | Client | Producer | Consumer

  (* Attribute values are the OTLP AnyValue subset we need. *)
  datatype attrValue =
      AStr of string
    | AInt of int
    | ABool of bool
    | AReal of real

  (* Timestamps are `IntInf.int` (arbitrary precision) so a real Unix
     *nanosecond* count (~1.7e18) is exact and identical on both MLton and
     Poly/ML. Both compilers use a fixed-width default `int` (MLton 32-bit,
     Poly/ML 63-bit) -- NOT arbitrary precision -- so a nanosecond timestamp
     overflows MLton's `int` and is not representable in Poly/ML's `int`
     either once it passes 2^62. `IntInf` (arbitrary on both) sidesteps this
     and exports to `*UnixNano` JSON fields losslessly. Logical-clock ticks
     from `startSpan`/`endSpan` are small; the wide type just lets callers
     supply real nanosecond times without a latent overflow. *)
  type spanEvent = { name : string, time : IntInf.int, attributes : (string * attrValue) list }

  datatype spanStatus = Ok | Error of string | Unset

  type span =
    { traceId       : TraceId.t
    , spanId        : SpanId.t
    , parentSpanId  : SpanId.t option
    , name          : string
    , kind          : spanKind
    , attributes    : (string * attrValue) list
    , events        : spanEvent list
    , status        : spanStatus
    , startTime     : IntInf.int          (* logical tick or Unix nanos *)
    , endTime       : IntInf.int option   (* NONE until finished *)
    }

  (* `start` creates an unfinished span (endTime = NONE). *)
  val start : { traceId : TraceId.t, spanId : SpanId.t,
                parentSpanId : SpanId.t option, name : string,
                kind : spanKind, startTime : IntInf.int } -> span
  (* `finish s endTime` sets endTime and status (default Unset->Ok). *)
  val finish   : span * IntInf.int -> span
  val addAttr  : span * string * attrValue -> span
  val addEvent : span * spanEvent -> span
  val setStatus: span * spanStatus -> span

  (* ============ Tracer ============ *)

  type tracer =
    { clock : IntInf.int          (* logical tick, advances by one per startSpan *)
    , spans : span list           (* finished spans, newest-first *)
    , current : span list         (* active stack, head = innermost *)
    , seed : Word64.word
    }

  val init : Word64.word -> tracer    (* seed *)

  (* `startSpan (t, {name, kind, parent})` pushes a new span. If `parent` is
     NONE and the current stack is non-empty, the new span's parent is the
     current innermost span; if the stack is empty, the new span starts a
     fresh trace (a new TraceId). The Tracer's clock advances by one tick
     on each startSpan. Returns (tracer', spanId). *)
  val startSpan : tracer * { name : string, kind : spanKind,
                             parent : SpanId.t option } ->
                  tracer * SpanId.t

  (* `endSpan (t, status)` pops the innermost span, marks it finished at the
     current clock, and records it in `spans`. Returns (tracer', poppedSpan). *)
  val endSpan : tracer * spanStatus -> tracer * span

  (* Innermost active span, or NONE if the stack is empty. *)
  val currentSpan : tracer -> span option

  (* All finished spans (oldest-first for deterministic export). *)
  val finishedSpans : tracer -> span list

  (* ============ TraceContext (W3C traceparent) ============ *)

  structure TraceContext :
  sig
    (* `encode (traceId, spanId, flags)` produces the W3C traceparent string:
       `00-<32 hex traceId>-<16 hex spanId>-<2 hex flags>`. *)
    val encode : TraceId.t * SpanId.t * Word8.word -> string

    (* `decode s` parses a traceparent header. Returns SOME of the fields on
       a well-formed header (version 00, correct lengths, valid hex), or
       NONE otherwise. *)
    val decode : string ->
                   { traceId : TraceId.t, spanId : SpanId.t,
                     flags : Word8.word } option
  end

  (* ============ OtlpExport ============ *)

  structure OtlpExport :
  sig
    (* `toJson spans` produces the OTLP/JSON ResourceSpans structure with a
       single ResourceSpans / ScopeSpans / Spans list. Each span is encoded
       with traceId, spanId, parentSpanId (when present), name, kind,
       startTimeUnixNano, endTimeUnixNano, attributes, events, and status. *)
    val toJson : span list -> Json.json
  end
end
