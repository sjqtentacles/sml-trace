(* trace.sml

   OpenTelemetry-aligned trace/span model.

   Conventions
   -----------
   - Identifiers are derived deterministically from the vendored `sml-prng`
     SplitMix64: a TraceId consumes two 64-bit words (16 bytes), a SpanId
     consumes one (8 bytes). The seed is threaded through every generator.
   - The Tracer is a pure accumulator: thread it through `startSpan` /
     `endSpan`; no mutation, no I/O, no wall-clock.
   - Hex output is lowercase; `fromHex` accepts any case. *)

structure Trace :> TRACE =
struct

  structure R = SplitMix64
  structure W = Word64
  structure W8 = Word8

  (* ---- hex helpers ---- *)

  val hexLower = "0123456789abcdef"

  fun nibble c =
    if c >= #"0" andalso c <= #"9" then SOME (Char.ord c - Char.ord #"0")
    else if c >= #"a" andalso c <= #"f" then SOME (Char.ord c - Char.ord #"a" + 10)
    else if c >= #"A" andalso c <= #"F" then SOME (Char.ord c - Char.ord #"A" + 10)
    else NONE

  (* Convert a Word64 to a lowercase hex string of the given byte width
     (1-8). Most-significant byte first. *)
  fun wordToHexBytes (w, byteWidth) =
    let
      fun byteAt i = W8.fromLarge (W.toLarge (W.>> (w, Word.fromInt (i * 8))))
      fun oneByte b =
        let
          val hi = Word8.>> (b, 0w4)
          val lo = Word8.andb (b, 0wxF)
        in
          String.str (String.sub (hexLower, Word8.toInt hi)) ^
          String.str (String.sub (hexLower, Word8.toInt lo))
        end
      val bytes = List.tabulate (byteWidth, fn i => byteAt (byteWidth - 1 - i))
    in
      String.concat (List.map oneByte bytes)
    end

  (* Parse `byteWidth` bytes (2*byteWidth hex chars) into a Word64. Returns
     NONE on bad length or non-hex chars. *)
  fun hexToWord (s, byteWidth) =
    let
      val expected = byteWidth * 2
    in
      if String.size s <> expected then NONE
      else
        let
          (* Read two hex chars (one byte) per iteration; shift the
             accumulator left by 8 bits to make room. *)
          fun loop (i, acc) =
            if i >= expected then SOME acc
            else
              case (nibble (String.sub (s, i)), nibble (String.sub (s, i + 1))) of
                  (SOME hi, SOME lo) =>
                    loop (i + 2,
                          W.orb (W.<< (acc, 0w8),
                                 W.fromInt (hi * 16 + lo)))
                | _ => NONE
        in
          loop (0, 0w0)
        end
    end

  (* ============ TraceId (16 bytes) ============ *)

  structure TraceId =
  struct
    (* 16 bytes = two Word64s, high (bytes 0-7) and low (bytes 8-15). *)
    type t = W.word * W.word

    val zero : t = (0w0, 0w0)

    fun generate (seedw : W.word) : t * W.word =
      let
        val s = R.seed seedw
        val (hi, s1) = R.next s
        val (lo, s2) = R.next s1
        (* The next seed returned: derive a Word64 from the next state. *)
        val (w, _) = R.next s2
      in
        ((hi, lo), w)
      end

    fun toHex ((hi, lo) : t) : string =
      wordToHexBytes (hi, 8) ^ wordToHexBytes (lo, 8)

    fun fromHex (s : string) : t option =
      if String.size s <> 32 then NONE
      else
        let
          val hi = hexToWord (String.substring (s, 0, 16), 8)
          val lo = hexToWord (String.substring (s, 16, 16), 8)
        in
          case (hi, lo) of
              (SOME h, SOME l) => SOME (h, l)
            | _ => NONE
        end

    fun eq (a : t, b : t) = a = b
  end

  (* ============ SpanId (8 bytes) ============ *)

  structure SpanId =
  struct
    type t = W.word

    val zero : t = 0w0

    fun generate (seedw : W.word) : t * W.word =
      let
        val s = R.seed seedw
        val (w, s1) = R.next s
        val (next, _) = R.next s1
      in
        (w, next)
      end

    fun toHex (w : t) : string = wordToHexBytes (w, 8)

    fun fromHex (s : string) : t option = hexToWord (s, 8)

    fun eq (a : t, b : t) = a = b
  end

  (* ============ Span ============ *)

  datatype spanKind = Internal | Server | Client | Producer | Consumer

  datatype attrValue =
      AStr of string
    | AInt of int
    | ABool of bool
    | AReal of real

  (* Timestamps are `IntInf.int` (arbitrary precision) so a real Unix
     nanosecond count (~1.7e18) is exact and identical on MLton and Poly/ML,
     both of which use a fixed-width default `int` (MLton 32-bit, Poly/ML
     63-bit) that a nanosecond value would overflow. See trace.sig. *)
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
    , startTime     : IntInf.int
    , endTime       : IntInf.int option
    }

  fun setAttrs (s : span) v : span =
    { traceId = #traceId s, spanId = #spanId s, parentSpanId = #parentSpanId s,
      name = #name s, kind = #kind s, attributes = v,
      events = #events s, status = #status s,
      startTime = #startTime s, endTime = #endTime s }
  fun setEvents (s : span) v : span =
    { traceId = #traceId s, spanId = #spanId s, parentSpanId = #parentSpanId s,
      name = #name s, kind = #kind s, attributes = #attributes s,
      events = v, status = #status s,
      startTime = #startTime s, endTime = #endTime s }
  fun setStatus' (s : span) v : span =
    { traceId = #traceId s, spanId = #spanId s, parentSpanId = #parentSpanId s,
      name = #name s, kind = #kind s, attributes = #attributes s,
      events = #events s, status = v,
      startTime = #startTime s, endTime = #endTime s }
  fun setEndTime (s : span) v : span =
    { traceId = #traceId s, spanId = #spanId s, parentSpanId = #parentSpanId s,
      name = #name s, kind = #kind s, attributes = #attributes s,
      events = #events s, status = #status s,
      startTime = #startTime s, endTime = v }

  fun start { traceId, spanId, parentSpanId, name, kind, startTime } : span =
    { traceId = traceId, spanId = spanId, parentSpanId = parentSpanId,
      name = name, kind = kind, attributes = [], events = [],
      status = Unset, startTime = startTime, endTime = NONE }

  fun finish (s : span, endTime : IntInf.int) : span =
    let
      val st =
        case #status s of
            Unset => Ok
          | other => other
    in
      setStatus' (setEndTime s (SOME endTime)) st
    end

  fun addAttr (s : span, k : string, v : attrValue) : span =
    setAttrs s ((k, v) :: #attributes s)

  fun addEvent (s : span, e : spanEvent) : span =
    setEvents s (e :: #events s)

  fun setStatus (s : span, st : spanStatus) : span = setStatus' s st

  (* ============ Tracer ============ *)

  type tracer =
    { clock : IntInf.int
    , spans : span list
    , current : span list
    , seed : W.word
    }

  fun init (seedw : W.word) : tracer =
    { clock = 0, spans = [], current = [], seed = seedw }

  fun startSpan (t : tracer, { name, kind, parent }) : tracer * SpanId.t =
    let
      val clock = #clock t + 1
      (* Determine traceId and parentSpanId. *)
      val (traceId, parentSpanId, seed1) =
        case #current t of
            inner :: _ =>
              (* Child of the innermost span; inherit its traceId. *)
              let val ps = SOME (#spanId inner)
              in (#traceId inner, ps, #seed t) end
          | [] =>
              (* No active span: start a fresh trace. *)
              let val (tid, s1) = TraceId.generate (#seed t)
              in (tid, NONE, s1) end
      val (spanId, seed2) = SpanId.generate seed1
      val sp = start { traceId = traceId, spanId = spanId,
                       parentSpanId = parentSpanId, name = name, kind = kind,
                       startTime = clock }
      val t' =
        { clock = clock, spans = #spans t, current = sp :: #current t,
          seed = seed2 }
    in
      (t', spanId)
    end

  fun endSpan (t : tracer, status : spanStatus) : tracer * span =
    case #current t of
        [] => raise Fail "Tracer.endSpan: no active span"
      | inner :: rest =>
          let
            val finished = setStatus' (setEndTime inner (SOME (#clock t))) status
            val t' =
              { clock = #clock t
              , spans = finished :: #spans t
              , current = rest
              , seed = #seed t }
          in
            (t', finished)
          end

  fun currentSpan (t : tracer) : span option =
    case #current t of
        s :: _ => SOME s
      | [] => NONE

  fun finishedSpans (t : tracer) : span list =
    (* Return spans in ascending startTime order for deterministic export.
       Ties broken by spanId hex (stable enough for tests). *)
    let
      val all = #spans t
      fun cmp (a, b) =
        case IntInf.compare (#startTime a, #startTime b) of
            EQUAL => String.compare (SpanId.toHex (#spanId a),
                                     SpanId.toHex (#spanId b))
          | o' => o'
      (* Insertion sort (Basis has no List.sort). *)
      fun ins (x, []) = [x]
        | ins (x, y :: ys) =
            case cmp (x, y) of
                GREATER => y :: ins (x, ys)
              | _ => x :: y :: ys
    in
      List.foldr (fn (x, acc) => ins (x, acc)) [] all
    end

  (* ============ TraceContext (W3C traceparent) ============ *)

  structure TraceContext =
  struct
    (* Format: 00-<32 hex traceId>-<16 hex spanId>-<2 hex flags> *)
    fun encode (traceId : TraceId.t, spanId : SpanId.t, flags : W8.word) : string =
      let
        val fhi = W8.>> (flags, 0w4)
        val flo = W8.andb (flags, 0wxF)
        val flagStr =
          String.str (String.sub (hexLower, W8.toInt fhi)) ^
          String.str (String.sub (hexLower, W8.toInt flo))
      in
        "00-" ^ TraceId.toHex traceId ^ "-" ^ SpanId.toHex spanId ^ "-" ^ flagStr
      end

    fun decode (s : string) :
        { traceId : TraceId.t, spanId : SpanId.t, flags : W8.word } option =
      let
        (* Expected length: 2 + 1 + 32 + 1 + 16 + 1 + 2 = 55. *)
        val expected = 55
      in
        if String.size s <> expected then NONE
        else if String.sub (s, 0) <> #"0" orelse String.sub (s, 1) <> #"0"
             orelse String.sub (s, 2) <> #"-"
             orelse String.sub (s, 35) <> #"-"
             orelse String.sub (s, 52) <> #"-"
        then NONE
        else
          let
            val tidStr = String.substring (s, 3, 32)
            val sidStr = String.substring (s, 36, 16)
            val flagStr = String.substring (s, 53, 2)
          in
            case (TraceId.fromHex tidStr, SpanId.fromHex sidStr,
                  nibble (String.sub (flagStr, 0)),
                  nibble (String.sub (flagStr, 1))) of
                (SOME tid, SOME sid, SOME fhi, SOME flo) =>
                  (* Reject the invalid traceId (all-zero) and spanId (all-zero)
                     per W3C. *)
                  if TraceId.eq (tid, TraceId.zero) orelse
                     SpanId.eq (sid, SpanId.zero)
                  then NONE
                  else SOME { traceId = tid, spanId = sid,
                              flags = W8.fromInt (fhi * 16 + flo) }
              | _ => NONE
          end
      end
  end

  (* ============ OtlpExport ============ *)

  structure OtlpExport =
  struct
    open Json

    fun kindToInt k =
      case k of
          Internal => 1 | Server => 2 | Client => 3
        | Producer => 4 | Consumer => 5

    fun statusToObj st =
      case st of
          Unset => JObj [("code", JStr "STATUS_CODE_UNSET")]
        | Ok => JObj [("code", JStr "STATUS_CODE_OK")]
        | Error msg =>
            JObj [("code", JStr "STATUS_CODE_ERROR"),
                  ("message", JStr msg)]

    fun attrValueToJson v =
      case v of
          AStr s => JObj [("stringValue", JStr s)]
          (* AInt carries a machine `int`; widen losslessly to the JSON
             IntInf payload (no truncation of the value the int already holds). *)
        | AInt i => JObj [("intValue", JInt (IntInf.fromInt i))]
        | ABool b => JObj [("boolValue", JBool b)]
        | AReal r => JObj [("doubleValue", JReal r)]

    fun attrsToJson attrs =
      JObj (List.map (fn (k, v) => (k, attrValueToJson v)) attrs)

    fun eventToJson ({name, time, attributes} : spanEvent) =
      JObj [("name", JStr name),
            ("timeUnixNano", JInt time),
            ("attributes", attrsToJson attributes)]

    fun spanToJson (s : span) : json =
      let
        val parent =
          case #parentSpanId s of
              NONE => []
            | SOME sid => [("parentSpanId", JStr (SpanId.toHex sid))]
        val endTime =
          case #endTime s of
              NONE => [("endTimeUnixNano", JInt 0)]
            | SOME t => [("endTimeUnixNano", JInt t)]
        val body =
          [("traceId", JStr (TraceId.toHex (#traceId s))),
           ("spanId", JStr (SpanId.toHex (#spanId s))),
           ("name", JStr (#name s)),
           ("kind", JInt (IntInf.fromInt (kindToInt (#kind s)))),
           ("startTimeUnixNano", JInt (#startTime s))]
          @ endTime
          @ parent
          @ [("attributes", attrsToJson (#attributes s)),
             ("events", JArr (List.map eventToJson (#events s))),
             ("status", statusToObj (#status s))]
      in
        JObj body
      end

    fun toJson (spans : span list) : json =
      let
        val serviceAttr =
          JObj [("key", JStr "service.name"),
                ("value", JObj [("stringValue", JStr "sml-trace")])]
        val resource =
          JObj [("attributes", JArr [serviceAttr])]
        val scope =
          JObj [("name", JStr "sml-trace"),
                ("version", JStr "0.1.0")]
        val scopeSpansEntry =
          JObj [("scope", scope),
                ("spans", JArr (List.map spanToJson spans))]
        val resourceSpansEntry =
          JObj [("resource", resource),
                ("scopeSpans", JArr [scopeSpansEntry])]
      in
        JObj [("resourceSpans", JArr [resourceSpansEntry])]
      end
  end
end
