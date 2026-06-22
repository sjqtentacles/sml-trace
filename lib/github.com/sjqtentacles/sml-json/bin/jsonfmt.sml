(* bin/jsonfmt.sml -- a tiny CLI that reads JSON from stdin, validates it, and
 * pretty-prints it to stdout. MLton-only (uses TextIO/CommandLine/OS.Process);
 * kept out of the Poly/ML test path.
 *
 * Usage:
 *   jsonfmt            read stdin, pretty-print with 2-space indent
 *   jsonfmt -c         read stdin, print minified (compact)
 *   jsonfmt -i N       read stdin, pretty-print with N-space indent
 *
 * Exit code 0 on valid JSON, 1 on a parse error (message on stderr). *)

structure Main =
struct
  fun readAll () =
      let
        fun loop acc =
            case TextIO.inputLine TextIO.stdIn of
                NONE => String.concat (List.rev acc)
              | SOME line => loop (line :: acc)
      in
        loop []
      end

  datatype mode = Compact | Indent of int

  fun parseArgs args =
      case args of
          [] => Indent 2
        | ["-c"] => Compact
        | ["-i", n] =>
            (case Int.fromString n of
                 SOME k => Indent (Int.max (0, k))
               | NONE => Indent 2)
        | _ => Indent 2

  fun render Compact json    = JsonPretty.toString json
    | render (Indent n) json = JsonPretty.toStringIndent n json

  fun main () =
      let
        val mode = parseArgs (CommandLine.arguments ())
        val input = readAll ()
      in
        case Json.parseJson input of
            CharParsec.Ok json =>
              (print (render mode json); print "\n"; OS.Process.exit OS.Process.success)
          | CharParsec.Err e =>
              (TextIO.output (TextIO.stdErr,
                              "jsonfmt: parse error: " ^ CharParsec.errorToString e ^ "\n");
               OS.Process.exit OS.Process.failure)
      end
end

val () = Main.main ()
