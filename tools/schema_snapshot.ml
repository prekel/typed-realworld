open! Base
module Schema_ir = Typed_sql_schema.Schema_ir
module Schema_codegen = Typed_sql_schema.Schema_codegen
module Schema_snapshot = Typed_sql_schema.Schema_snapshot
open Typed_sql

let application_schema schema =
  Schema_ir.tables schema
  |> List.filter ~f:(fun table ->
    not
      (String.equal
         (Identifier.to_string (Schema_ir.table_name table))
         "schema_migrations"))
  |> Schema_ir.v
;;

let run uri =
  let open Lwt.Let_syntax in
  let%bind connected = Caqti_lwt_unix.connect uri in
  match connected with
  | Error error -> Lwt.return (Error (Caqti.Error.show error))
  | Ok conn ->
    let module Connection = (val conn : Caqti_lwt.CONNECTION) in
    Lwt.finalize
      (fun () ->
         let%map discovered = Typed_sql_schema_caqti_lwt.introspect ~conn in
         let open Result.Let_syntax in
         let%bind schema =
           Result.map_error discovered ~f:Typed_sql_schema_caqti_lwt.error_to_string
         in
         let schema = application_schema schema in
         (* Reject unsupported database types before replacing the saved snapshot. *)
         let%map _ =
           Schema_codegen.generate schema
           |> Result.map_error ~f:Schema_codegen.error_to_string
         in
         Schema_snapshot.to_string schema)
      (fun () -> Connection.disconnect ())
;;

let () =
  match Stdlib.Sys.argv with
  | [| _; url |] ->
    (match Lwt_main.run (run (Uri.of_string url)) with
     | Ok snapshot -> Stdlib.print_string snapshot
     | Error message ->
       Stdlib.prerr_endline ("schema-snapshot: " ^ message);
       Stdlib.exit 1)
  | _ ->
    Stdlib.prerr_endline "Usage: schema_snapshot SQLITE_URL";
    Stdlib.exit 2
;;
