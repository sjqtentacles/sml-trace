(* Test suite for sml-json, standardized on the shared sml-test Harness. *)

structure Tests =
struct
  open Harness

  infix 1 >>= >>
  infix 1 <*
  infix 4 <*> <$>
  infixr 1 <|>
  infix 0 <?>

  open CharParsec
  open Json

(* json has no derived equality (it contains real), so tests use this:
 * JInt exact, JReal within a small tolerance, JObj compared as ordered
 * key/value lists (duplicate keys preserved, order significant). *)
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
    length xs = length ys andalso
    ListPair.all jsonEq (xs, ys)
and memEq (xs, ys) =
    length xs = length ys andalso
    ListPair.all (fn ((k1, v1), (k2, v2)) => k1 = k2 andalso jsonEq (v1, v2))
                 (xs, ys)

fun okJson (r, expected) =
    case r of Ok v => jsonEq (v, expected) | Err _ => false

fun isErr r = case r of Err _ => true | Ok _ => false

fun errOff r = case r of Err e => SOME (#off (#pos e)) | Ok _ => NONE

(* ---- literals ---- *)
fun runLiteralTests () =
  let
    val () = check "null parses to JNull"
                   (okJson (parseJson "null", JNull))
    val () = check "true parses to JBool true"
                   (okJson (parseJson "true", JBool true))
    val () = check "false parses to JBool false"
                   (okJson (parseJson "false", JBool false))
    val () = check "leading/trailing whitespace around literal"
                   (okJson (parseJson "  null  ", JNull))
    val () = check "bare garbage literal fails"
                   (isErr (parseJson "nul"))
  in () end

(* ---- numbers ---- *)
fun runNumberTests () =
  let
    val () = check "0 -> JInt 0"        (okJson (parseJson "0", JInt 0))
    val () = check "-3 -> JInt ~3"      (okJson (parseJson "-3", JInt ~3))
    val () = check "42 -> JInt 42"      (okJson (parseJson "42", JInt 42))
    val () = check "3.14 -> JReal"      (okJson (parseJson "3.14", JReal 3.14))
    val () = check "1e10 -> JReal"      (okJson (parseJson "1e10", JReal 1E10))
    val () = check "-2.5E-3 -> JReal"   (okJson (parseJson "-2.5E-3", JReal (~2.5E~3)))
    val () = check "0.5 -> JReal"       (okJson (parseJson "0.5", JReal 0.5))
    val () = check "whitespace around number"
                   (okJson (parseJson "  -3  ", JInt ~3))
    (* rejects *)
    val () = check "reject leading-zero 01" (isErr (parseJson "01"))
    val () = check "reject +1"              (isErr (parseJson "+1"))
    val () = check "reject .5"              (isErr (parseJson ".5"))
    val () = check "reject 1."              (isErr (parseJson "1."))
  in () end

(* ---- strings ----
 * Note on SML string literals below: a backslash in JSON must be written as a
 * doubled backslash in the SML source. So the JSON text  "a\nb"  is the SML
 * literal  "\"a\\nb\"". *)
fun runStringTests () =
  let
    val () = check "empty string"
                   (okJson (parseJson "\"\"", JStr ""))
    val () = check "simple string"
                   (okJson (parseJson "\"hello\"", JStr "hello"))
    val () = check "string with spaces"
                   (okJson (parseJson "\"hello world\"", JStr "hello world"))
    val () = check "escaped quote and backslash"
                   (okJson (parseJson "\"a\\\"b\\\\c\"", JStr "a\"b\\c"))
    val () = check "escaped solidus"
                   (okJson (parseJson "\"a\\/b\"", JStr "a/b"))
    val () = check "control escapes \\b\\f\\n\\r\\t"
                   (okJson (parseJson "\"\\b\\f\\n\\r\\t\"",
                            JStr (implode [#"\b", #"\f", #"\n", #"\r", #"\t"])))
    val () = check "unicode escape \\u0041 -> A"
                   (okJson (parseJson "\"\\u0041\"", JStr "A"))
    val () = check "unicode escape lowercase hex \\u006a -> j"
                   (okJson (parseJson "\"\\u006a\"", JStr "j"))
    val () = check "string trailing whitespace tolerated"
                   (okJson (parseJson "  \"hi\"  ", JStr "hi"))
    (* rejects *)
    val () = check "reject unterminated string"
                   (isErr (parseJson "\"abc"))
    val () = check "reject raw control char (literal newline)"
                   (isErr (parseJson "\"a\nb\""))
    val () = check "reject bad escape"
                   (isErr (parseJson "\"a\\xb\""))
  in () end

(* ---- arrays + objects ---- *)
fun runArrayObjectTests () =
  let
    val () = check "empty array"
                   (okJson (parseJson "[]", JArr []))
    val () = check "array of ints"
                   (okJson (parseJson "[1,2,3]", JArr [JInt 1, JInt 2, JInt 3]))
    val () = check "array with whitespace"
                   (okJson (parseJson "[ 1 , 2 , 3 ]", JArr [JInt 1, JInt 2, JInt 3]))
    val () = check "mixed array"
                   (okJson (parseJson "[null,true,\"x\",1.5]",
                            JArr [JNull, JBool true, JStr "x", JReal 1.5]))
    val () = check "nested array"
                   (okJson (parseJson "[[1],[2,[3]]]",
                            JArr [JArr [JInt 1], JArr [JInt 2, JArr [JInt 3]]]))
    val () = check "empty object"
                   (okJson (parseJson "{}", JObj []))
    val () = check "single-member object"
                   (okJson (parseJson "{\"a\":1}", JObj [("a", JInt 1)]))
    val () = check "multi-member object"
                   (okJson (parseJson "{\"a\":1,\"b\":2}",
                            JObj [("a", JInt 1), ("b", JInt 2)]))
    val () = check "object with whitespace"
                   (okJson (parseJson "{ \"a\" : 1 , \"b\" : 2 }",
                            JObj [("a", JInt 1), ("b", JInt 2)]))
    val () = check "nested object"
                   (okJson (parseJson "{\"a\":{\"b\":[1,2]}}",
                            JObj [("a", JObj [("b", JArr [JInt 1, JInt 2])])]))
    val () = check "duplicate keys preserved in order"
                   (okJson (parseJson "{\"a\":1,\"a\":2}",
                            JObj [("a", JInt 1), ("a", JInt 2)]))
    val () = check "deeply nested smoke"
                   (okJson (parseJson "[[[[[1]]]]]",
                            JArr [JArr [JArr [JArr [JArr [JInt 1]]]]]))
    (* rejects *)
    val () = check "reject trailing comma in array"
                   (isErr (parseJson "[1,2,]"))
    val () = check "reject unclosed array"
                   (isErr (parseJson "[1,2"))
    val () = check "reject object with non-string key"
                   (isErr (parseJson "{1:2}"))
    val () = check "reject missing colon"
                   (isErr (parseJson "{\"a\" 1}"))
  in () end

(* ---- driver / errors ---- *)
fun errString r = case r of Err e => errorToString e | Ok _ => ""
fun errPos r = case r of Err e => SOME (#pos e) | Ok _ => NONE

fun runDriverTests () =
  let
    val () = check "reject trailing garbage after value"
                   (isErr (parseJson "true false"))
    val () = check "reject trailing garbage after array"
                   (isErr (parseJson "[1,2,3] x"))
    val () = check "empty input is an error"
                   (isErr (parseJson ""))
    val () = check "whitespace-only input is an error"
                   (isErr (parseJson "   "))
    (* errorToString is non-empty on failure *)
    val () = check "errorToString non-empty on failure"
                   (errString (parseJson "@") <> "")
    (* error reports position on the offending second line *)
    val () = check "error reports line/column"
                   (case errPos (parseJson "[1,\n2,\nx]") of
                        SOME p => #line p = 3 andalso #col p = 1
                      | NONE => false)
    (* deep nesting still parses (smoke) *)
    val () = check "deep nesting driver smoke"
                   (okJson (parseJson "[[[[[[[[1]]]]]]]]",
                            JArr [JArr [JArr [JArr [JArr [JArr [JArr [JArr [JInt 1]]]]]]]]))
  in () end

(* ---- serializer + round-trips ---- *)
fun runSerializerTests () =
  let
    open JsonPretty
    fun eqStr (a, b) = (a = b)
    (* minified output *)
    val () = check "toString null"   (eqStr (toString JNull, "null"))
    val () = check "toString true"   (eqStr (toString (JBool true), "true"))
    val () = check "toString JInt"   (eqStr (toString (JInt 42), "42"))
    val () = check "toString negative JInt uses -"
                   (eqStr (toString (JInt ~3), "-3"))
    val () = check "toString simple string"
                   (eqStr (toString (JStr "hi"), "\"hi\""))
    val () = check "toString re-escapes quote/backslash/newline"
                   (eqStr (toString (JStr "a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\""))
    val () = check "toString array"
                   (eqStr (toString (JArr [JInt 1, JInt 2]), "[1,2]"))
    val () = check "toString object"
                   (eqStr (toString (JObj [("a", JInt 1)]), "{\"a\":1}"))
    val () = check "toString empty array/object"
                   (eqStr (toString (JArr []) ^ toString (JObj []), "[]{}"))

    (* indented output: empty containers stay on one line *)
    val () = check "toStringIndent empty array one line"
                   (eqStr (toStringIndent 2 (JArr []), "[]"))
    val () = check "toStringIndent simple object"
                   (eqStr (toStringIndent 2 (JObj [("a", JInt 1)]),
                           "{\n  \"a\": 1\n}"))

    (* round-trips via jsonEq: parse o toString = identity *)
    val samples =
        [ JNull, JBool true, JBool false, JInt 0, JInt ~17, JInt 1000,
          JReal 3.14, JReal (~2.5E~3), JStr "", JStr "hello\nworld\t!",
          JStr "quote\"and\\slash/and\u0001ctrl",
          JArr [], JArr [JInt 1, JStr "x", JBool false, JNull],
          JObj [], JObj [("k", JArr [JInt 1, JInt 2]), ("nested", JObj [("z", JNull)])],
          JArr [JObj [("a", JInt 1)], JObj [("a", JInt 2)]] ]

    fun roundTripMin v =
        case parseJson (toString v) of
            Ok v' => jsonEq (v, v')
          | Err _ => false
    fun roundTripPretty v =
        case parseJson (toStringIndent 2 v) of
            Ok v' => jsonEq (v, v')
          | Err _ => false

    val () = check "round-trip (minified) all samples"
                   (List.all roundTripMin samples)
    val () = check "round-trip (indented) all samples"
                   (List.all roundTripPretty samples)
  in () end

  fun run () =
    (runLiteralTests ();
     runNumberTests ();
     runStringTests ();
     runArrayObjectTests ();
     runDriverTests ();
     runSerializerTests ();
     Harness.run ())
end
