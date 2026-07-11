(* demo.sml - deterministic id generation from a fixed seed, a W3C
   traceparent round-trip, building a small two-span trace (root + child)
   with attributes and events, and exporting it as OTLP/JSON. No wall clock,
   no unseeded randomness: identical output on every run and both compilers. *)

structure Tr = Trace

val () = print "=== sml-trace demo ===\n\n"

val () = print "-- deterministic id generation from a seed --\n"
val (traceId, seed1) = Tr.TraceId.generate 0wx1234567890ABCDEF
val (rootSpanId, seed2) = Tr.SpanId.generate seed1
val (childSpanId, _)    = Tr.SpanId.generate seed2
val () = print ("  traceId = " ^ Tr.TraceId.toHex traceId ^ "\n")
val () = print ("  rootId  = " ^ Tr.SpanId.toHex rootSpanId ^ "\n")
val () = print ("  childId = " ^ Tr.SpanId.toHex childSpanId ^ "\n")

val () = print "\n-- W3C traceparent codec --\n"
val tp = Tr.TraceContext.encode (traceId, rootSpanId, 0w1)
val () = print ("  traceparent = " ^ tp ^ "\n")
val () = print ("  decode roundtrips = "
                ^ (case Tr.TraceContext.decode tp of
                       SOME { traceId = t', spanId = s', ... } =>
                         Bool.toString (Tr.TraceId.eq (t', traceId)
                                        andalso Tr.SpanId.eq (s', rootSpanId))
                     | NONE => "PARSE FAILED")
                ^ "\n")

val () = print "\n-- building a two-span trace: start, addAttr, addEvent, finish --\n"
val root = Tr.start { traceId = traceId, spanId = rootSpanId, parentSpanId = NONE,
                       name = "handle-request", kind = Tr.Server, startTime = 0 }
val root1 = Tr.addAttr (root, "http.method", Tr.AStr "GET")
val root2 = Tr.addAttr (root1, "http.status_code", Tr.AInt 200)
val root3 = Tr.addEvent (root2, { name = "dispatch", time = 1,
                                   attributes = [("queue.size", Tr.AInt 3)] })

val child = Tr.start { traceId = traceId, spanId = childSpanId, parentSpanId = SOME rootSpanId,
                        name = "db-query", kind = Tr.Client, startTime = 1 }
val child1 = Tr.addAttr (child, "db.statement", Tr.AStr "SELECT 1")
val childDone = Tr.finish (child1, 4)
val rootDone  = Tr.finish (root3, 5)

fun fmtSpan s =
  "  " ^ #name s ^ "  span=" ^ Tr.SpanId.toHex (#spanId s)
  ^ "  parent=" ^ (case #parentSpanId s of SOME p => Tr.SpanId.toHex p | NONE => "-")
  ^ "  [" ^ IntInf.toString (#startTime s) ^ ".."
  ^ (case #endTime s of SOME e => IntInf.toString e | NONE => "?") ^ "]"
  ^ "  attrs=" ^ Int.toString (List.length (#attributes s))
  ^ "  events=" ^ Int.toString (List.length (#events s))

val () = print (fmtSpan rootDone ^ "\n")
val () = print (fmtSpan childDone ^ "\n")

val () = print "\n-- OTLP/JSON export --\n"
val exported = Tr.OtlpExport.toJson [rootDone, childDone]
val () = print (JsonPretty.toStringIndent 2 exported ^ "\n")
