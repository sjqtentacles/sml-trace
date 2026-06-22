(* Tests for sml-trace.

   All identifier sequences are deterministic given a fixed seed, so the
   suite is byte-identical on MLton and Poly/ML. *)

structure TraceTests =
struct
  open Harness

  (* Structural JSON equality (from sml-json's own test suite). *)
  open Json
  fun jsonEq (a, b) =
      case (a, b) of
          (JNull, JNull) => true
        | (JBool x, JBool y) => x = y
        | (JInt x, JInt y) => x = y
        | (JReal x, JReal y) => Real.abs (x - y) < 1E~9
        | (JStr x, JStr y) => x = y
        | (JArr xs, JArr ys) => listEq (xs, ys)
        | (JObj xs, JObj ys) => memEq (xs, ys)
        | _ => false
  and listEq (xs, ys) =
      length xs = length ys andalso ListPair.all jsonEq (xs, ys)
  and memEq (xs, ys) =
      length xs = length ys andalso
      ListPair.all (fn ((k1, v1), (k2, v2)) => k1 = k2 andalso jsonEq (v1, v2))
                   (xs, ys)

  fun checkJson name (expected, actual) =
    checkBool name (true, jsonEq (expected, actual))

  (* Look up a key in a JObj; returns NONE if the json isn't an object. *)
  fun lookup k (JObj obj) =
    (case List.find (fn (k', _) => k' = k) obj of
         SOME (_, v) => SOME v
       | NONE => NONE)
    | lookup _ _ = NONE

  fun run () =
    let
      val () = section "TraceId hex round-trip"

      val tid = (#1 (Trace.TraceId.generate 0w42))
      val tidHex = Trace.TraceId.toHex tid
      val () = checkInt "TraceId hex length = 32" (32, String.size tidHex)
      val () = checkBool "TraceId hex is lowercase hex" (true,
        CharVector.all (fn c => Char.isHexDigit c andalso
                                 (not (Char.isAlpha c) orelse Char.isLower c))
                        tidHex)
      val tidRound = Trace.TraceId.fromHex tidHex
      val () = checkBool "TraceId round-trip" (true,
        case tidRound of SOME t => Trace.TraceId.eq (t, tid) | NONE => false)

      (* Known fixed vector: fromHex of a literal round-trips to same string. *)
      val known = "0123456789abcdef0123456789abcdef"
      val () = checkBool "TraceId known vector round-trip" (true,
        case Trace.TraceId.fromHex known of
            SOME t => Trace.TraceId.toHex t = known
          | NONE => false)
      (* Bad inputs: NONE. *)
      val () = checkBool "TraceId fromHex bad length = NONE" (true,
        not (Option.isSome (Trace.TraceId.fromHex "abc")))
      val () = checkBool "TraceId fromHex bad chars = NONE" (true,
        not (Option.isSome (Trace.TraceId.fromHex "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")))

      val () = section "SpanId hex round-trip"

      val sid = #1 (Trace.SpanId.generate 0w42)
      val sidHex = Trace.SpanId.toHex sid
      val () = checkInt "SpanId hex length = 16" (16, String.size sidHex)
      val () = checkBool "SpanId round-trip" (true,
        case Trace.SpanId.fromHex sidHex of
            SOME s => Trace.SpanId.eq (s, sid) | NONE => false)
      val known2 = "0123456789abcdef"
      val () = checkBool "SpanId known vector round-trip" (true,
        case Trace.SpanId.fromHex known2 of
            SOME s => Trace.SpanId.toHex s = known2
          | NONE => false)

      val () = section "TraceContext encode/decode (W3C traceparent)"

      (* W3C example: version 00, 32-hex traceId, 16-hex spanId, 2-hex flags. *)
      val tid2 = valOf (Trace.TraceId.fromHex
                          "4bf92f3577b34da6a3ce929d0e0e4736")
      val sid2 = valOf (Trace.SpanId.fromHex "00f067aa0ba902b7")
      val tp = Trace.TraceContext.encode (tid2, sid2, 0w1)
      val () = checkString "encode matches W3C example"
        ("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", tp)

      val dec = Trace.TraceContext.decode tp
      val () = checkBool "decode W3C example succeeds" (true,
        Option.isSome dec)
      val {traceId = dtid, spanId = dsid, flags = dflags} = valOf dec
      val () = checkBool "decode traceId matches" (true,
        Trace.TraceId.eq (dtid, tid2))
      val () = checkBool "decode spanId matches" (true,
        Trace.SpanId.eq (dsid, sid2))
      val () = checkBool "decode flags = 1" (true, dflags = 0w1)

      (* Round-trip: encode then decode preserves fields. *)
      val tp2 = Trace.TraceContext.encode (tid2, sid2, 0w0)
      val dec2 = Trace.TraceContext.decode tp2
      val () = checkBool "round-trip flags=0" (true,
        case dec2 of
            SOME {flags, ...} => flags = 0w0
          | NONE => false)

      (* Invalid: all-zero traceId is rejected by decode. *)
      val badTp = "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
      val () = checkBool "decode rejects all-zero traceId" (true,
        not (Option.isSome (Trace.TraceContext.decode badTp)))
      (* Invalid: all-zero spanId is rejected. *)
      val badTp2 = "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"
      val () = checkBool "decode rejects all-zero spanId" (true,
        not (Option.isSome (Trace.TraceContext.decode badTp2)))
      (* Invalid: bad length. *)
      val () = checkBool "decode rejects bad length" (true,
        not (Option.isSome (Trace.TraceContext.decode "garbage")))

      val () = section "Span lifecycle"

      val s0 = Trace.start
        { traceId = tid2, spanId = sid2, parentSpanId = NONE,
          name = "root", kind = Trace.Server, startTime = 10 }
      val () = checkBool "start: endTime = NONE" (true, #endTime s0 = NONE)
      val () = checkString "start: name" ("root", #name s0)
      val () = checkBool "start: status = Unset" (true, #status s0 = Trace.Unset)
      val () = checkInt "start: no attrs" (0, List.length (#attributes s0))

      val s1 = Trace.addAttr (s0, "http.method", Trace.AStr "GET")
      val s1 = Trace.addAttr (s1, "http.status", Trace.AInt 200)
      val () = checkInt "after addAttr: 2 attrs" (2, List.length (#attributes s1))

      val s2 = Trace.addEvent (s1, { name = "dispatch", time = 12,
                                      attributes = [] })
      val () = checkInt "after addEvent: 1 event" (1, List.length (#events s2))

      val s3 = Trace.finish (s2, 15)
      val () = checkBool "finish: endTime = SOME 15" (true, #endTime s3 = SOME 15)
      val () = checkBool "finish: Unset -> Ok" (true, #status s3 = Trace.Ok)

      val () = section "parent-child nesting"

      val tr0 = Trace.init 0w123
      val (tr1, _) = Trace.startSpan (tr0,
        { name = "root", kind = Trace.Server, parent = NONE })
      val rootSpan = valOf (Trace.currentSpan tr1)
      val rootTid = #traceId rootSpan
      val rootSid = #spanId rootSpan
      val () = checkBool "root has no parent" (true,
        not (Option.isSome (#parentSpanId rootSpan)))

      val (tr2, childSid) = Trace.startSpan (tr1,
        { name = "child", kind = Trace.Client, parent = NONE })
      val childSpan = valOf (Trace.currentSpan tr2)
      val () = checkBool "child parentSpanId = root spanId" (true,
        case #parentSpanId childSpan of
            SOME s => Trace.SpanId.eq (s, rootSid)
          | NONE => false)
      val () = checkBool "child inherits root traceId" (true,
        Trace.TraceId.eq (#traceId childSpan, rootTid))
      val () = checkBool "child spanId != root spanId" (true,
        not (Trace.SpanId.eq (childSid, rootSid)))

      val (tr3, _) = Trace.endSpan (tr2, Trace.Ok)
      val () = checkBool "after endSpan: stack back to root" (true,
        case Trace.currentSpan tr3 of
            SOME s => Trace.SpanId.eq (#spanId s, rootSid)
          | NONE => false)
      val (tr4, _) = Trace.endSpan (tr3, Trace.Ok)
      val () = checkBool "after endSpan: stack empty" (true,
        not (Option.isSome (Trace.currentSpan tr4)))
      val () = checkInt "finishedSpans count = 2" (2,
        List.length (Trace.finishedSpans tr4))
      (* finishedSpans is oldest-first, so root is first. *)
      val finished = Trace.finishedSpans tr4
      val () = checkBool "first finished is root" (true,
        #name (List.hd finished) = "root")
      val () = checkBool "second finished is child" (true,
        #name (List.nth (finished, 1)) = "child")

      val () = section "OTLP JSON structure"

      val otlp = Trace.OtlpExport.toJson finished
      (* Top-level shape: { resourceSpans: [ { resource, scopeSpans } ] }. *)
      val rsArr : Json.json list =
        case otlp of
            JObj [("resourceSpans", JArr rs)] => rs
          | _ => []
      val () = checkInt "one resourceSpans entry" (1, List.length rsArr)
      val rsObj : Json.json =
        case rsArr of
            [o'] => o'
          | _ => JNull
      val hasResource = Option.isSome (lookup "resource" rsObj)
      val () = checkBool "resourceSpans has resource" (true, hasResource)
      val scopeSpans =
        case lookup "scopeSpans" rsObj of
            SOME (JArr ss) => ss
          | _ => []
      val () = checkInt "one scopeSpans entry" (1, List.length scopeSpans)
      val spans =
        (case scopeSpans of
             [jobj] =>
               (case lookup "spans" jobj of
                    SOME (JArr s) => s | _ => [])
           | _ => [])
      val () = checkInt "two spans in OTLP" (2, List.length spans)
      (* Each span has traceId, spanId, name, kind, startTimeUnixNano, ... *)
      val firstSpan =
        case spans of
            (JObj _) :: _ => SOME (List.hd spans)
          | _ => NONE
      val () = checkBool "first span has traceId" (true,
        case firstSpan of
            SOME jobj => Option.isSome (lookup "traceId" jobj)
          | NONE => false)
      val () = checkBool "first span has name = root" (true,
        case firstSpan of
            SOME jobj =>
              (case lookup "name" jobj of SOME (JStr n) => n = "root" | _ => false)
          | NONE => false)

      (* Explicit shape check: the second span has parentSpanId = root's. *)
      val secondSpan =
        case spans of
            [_, s2'] => SOME s2'
          | _ => NONE
      val () = checkBool "second span has parentSpanId" (true,
        case secondSpan of
            SOME jobj =>
              (case lookup "parentSpanId" jobj of
                   SOME (JStr _) => true | _ => false)
          | NONE => false)

      val () = section "deterministic seeded sequence"

      (* Same seed -> same TraceId sequence. *)
      val (tidA1, seedA1) = Trace.TraceId.generate 0w99
      val (tidA2, _) = Trace.TraceId.generate seedA1
      val (tidB1, seedB1) = Trace.TraceId.generate 0w99
      val (tidB2, _) = Trace.TraceId.generate seedB1
      val () = checkBool "same seed -> same first TraceId" (true,
        Trace.TraceId.eq (tidA1, tidB1))
      val () = checkBool "same seed -> same second TraceId" (true,
        Trace.TraceId.eq (tidA2, tidB2))
      val () = checkBool "first != second" (true,
        not (Trace.TraceId.eq (tidA1, tidA2)))

      (* Same seed -> same SpanId. *)
      val (sidA, _) = Trace.SpanId.generate 0w7
      val (sidB, _) = Trace.SpanId.generate 0w7
      val () = checkBool "same seed -> same SpanId" (true,
        Trace.SpanId.eq (sidA, sidB))

      (* Tracer determinism: two tracers with the same seed produce the
         same spanId sequence. *)
      val (tt1, ts1) = Trace.startSpan (Trace.init 0w500,
        { name = "a", kind = Trace.Internal, parent = NONE })
      val (tt2, ts2) = Trace.startSpan (Trace.init 0w500,
        { name = "a", kind = Trace.Internal, parent = NONE })
      val () = checkBool "tracer: same seed -> same first spanId" (true,
        Trace.SpanId.eq (ts1, ts2))
      val (_, ts1') = Trace.startSpan (tt1,
        { name = "b", kind = Trace.Internal, parent = NONE })
      val (_, ts2') = Trace.startSpan (tt2,
        { name = "b", kind = Trace.Internal, parent = NONE })
      val () = checkBool "tracer: same seed -> same second spanId" (true,
        Trace.SpanId.eq (ts1', ts2'))
    in
      ()
    end
end
