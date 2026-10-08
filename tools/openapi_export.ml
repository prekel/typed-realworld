open! Base

let unused () = Stdlib.failwith "service handler was called while generating OpenAPI"

module Users : Realworld_application.User_service.S with type database = unit = struct
  type database = unit

  let register ~database:_ _ = unused ()
  let login ~database:_ ~email:_ ~password:_ = unused ()
  let current ~database:_ _ = unused ()
  let update ~database:_ ~user_id:_ _ = unused ()
  let profile ~database:_ ~viewer_id:_ ~username:_ = unused ()
  let follow ~database:_ ~follower_id:_ ~username:_ = unused ()
  let unfollow ~database:_ ~follower_id:_ ~username:_ = unused ()
end

module Articles : Realworld_application.Article_service.S with type database = unit =
struct
  type database = unit

  let list ~database:_ ~viewer_id:_ ~filters:_ ~page:_ = unused ()
  let feed ~database:_ ~viewer_id:_ ~page:_ = unused ()
  let find ~database:_ ~viewer_id:_ ~slug:_ = unused ()
  let create ~database:_ ~author_id:_ _ = unused ()
  let update ~database:_ ~author_id:_ ~slug:_ _ = unused ()
  let delete ~database:_ ~author_id:_ ~slug:_ = unused ()
  let favorite ~database:_ ~user_id:_ ~slug:_ = unused ()
  let unfavorite ~database:_ ~user_id:_ ~slug:_ = unused ()
  let tags ~database:_ = unused ()
end

module Comments : Realworld_application.Comment_service.S with type database = unit =
struct
  type database = unit

  let list ~database:_ ~viewer_id:_ ~slug:_ = unused ()
  let create ~database:_ ~author_id:_ ~slug:_ ~body:_ = unused ()
  let delete ~database:_ ~author_id:_ ~slug:_ ~comment_id:_ = unused ()
end

module Http = Realworld_http.App.Make (Typed_endpoint_opium) (Users) (Articles) (Comments)

let () =
  Http.compile ~database:() ~issue:(fun ~user_id:_ -> "token") ~verify:(fun _ -> None)
  |> Http.Endpoint.Compiled.openapi ~config:Realworld_http.App.openapi_config
  |> Yojson.Safe.pretty_to_string
  |> Stdlib.print_endline
;;
