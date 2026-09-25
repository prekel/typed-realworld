open! Base
module Access_log = Realworld_server_support.Access_log

let field name = function
  | `Assoc fields -> List.Assoc.find_exn fields name ~equal:String.equal
  | _ -> failwith "access log event must be an object"
;;

let () =
  let lines = ref [] in
  let times = ref [ 1_700_000_000.; 1_700_000_000.125 ] in
  let now () =
    match !times with
    | time :: remaining ->
      times := remaining;
      time
    | [] -> failwith "unexpected clock read"
  in
  let logger =
    Access_log.create
      ~now
      ~write:(fun line -> lines := line :: !lines)
      ~fresh_id:(fun () -> "generated-id")
      ()
  in
  let request =
    Access_log.start
      logger
      ~method_:"GET"
      ~target:"/articles/private-slug?token=secret"
      ~request_id:(Some "gateway-42")
  in
  assert (String.equal (Access_log.request_id request) "gateway-42");
  Access_log.finish request ~status:200;
  let line = List.hd_exn !lines in
  let event = Yojson.Safe.from_string line in
  assert (String.equal (Yojson.Safe.to_string (field "event" event)) "\"http_request\"");
  assert (
    String.equal (Yojson.Safe.to_string (field "path" event)) "\"/articles/private-slug\"");
  assert (String.equal (Yojson.Safe.to_string (field "status" event)) "200");
  assert (String.equal (Yojson.Safe.to_string (field "request_id" event)) "\"gateway-42\"");
  assert (String.equal (Yojson.Safe.to_string (field "duration_ms" event)) "125.0");
  assert (not (String.is_substring line ~substring:"secret"));
  assert (
    String.equal (Access_log.ensure_request_id logger (Some "gateway_43")) "gateway_43");
  assert (
    String.equal (Access_log.ensure_request_id logger (Some "bad\nvalue")) "generated-id");
  let error_lines = ref [] in
  let error_logger =
    Access_log.create
      ~now:(fun () -> 1_700_000_000.)
      ~write:(fun line -> error_lines := line :: !error_lines)
      ()
  in
  let failed =
    Access_log.start error_logger ~method_:"POST" ~target:"/users" ~request_id:None
  in
  Access_log.fail failed (Failure "database unavailable");
  let error = Yojson.Safe.from_string (List.hd_exn !error_lines) in
  assert (String.equal (Yojson.Safe.to_string (field "level" error)) "\"error\"");
  assert (
    String.is_substring
      (Yojson.Safe.to_string (field "error" error))
      ~substring:"database unavailable");
  let broken_logger = Access_log.create ~write:(fun _ -> failwith "broken sink") () in
  let request =
    Access_log.start broken_logger ~method_:"GET" ~target:"/" ~request_id:None
  in
  Access_log.finish request ~status:200
;;
