open! Base
open Bonsai_web
module Node = Vdom.Node
module Attr = Vdom.Attr

type article =
  { slug : string
  ; title : string
  ; description : string
  ; author : string
  }

type model =
  { articles : article list
  ; token : string option
  ; username : string
  ; email : string
  ; password : string
  ; title : string
  ; description : string
  ; body : string
  ; busy : bool
  ; message : string option
  ; error : bool
  }

let initial =
  { articles = []
  ; token = None
  ; username = ""
  ; email = ""
  ; password = ""
  ; title = ""
  ; description = ""
  ; body = ""
  ; busy = false
  ; message = None
  ; error = false
  }
;;

let member name json =
  match json with
  | `Assoc fields ->
    List.Assoc.find fields ~equal:String.equal name |> Option.value ~default:`Null
  | _ -> `Null
;;

let string json =
  match json with
  | `String value -> Some value
  | _ -> None
;;

let error_details json =
  match member "errors" json with
  | `Assoc fields ->
    List.concat_map fields ~f:(fun (field, messages) ->
      match messages with
      | `List values ->
        List.filter_map values ~f:string
        |> List.map ~f:(fun message -> field ^ " " ^ message)
      | _ -> [])
    |> String.concat ~sep:", "
  | _ -> ""
;;

let article_of_json json =
  match
    ( string (member "slug" json)
    , string (member "title" json)
    , string (member "description" json)
    , string (member "username" (member "author" json)) )
  with
  | Some slug, Some title, Some description, Some author ->
    Some { slug; title; description; author }
  | _ -> None
;;

let articles_of_json json =
  match member "articles" json with
  | `List values -> Ok (List.filter_map values ~f:article_of_json)
  | _ -> Error "Unexpected articles response"
;;

let token_of_json json =
  match string (member "token" (member "user" json)) with
  | Some token -> Ok token
  | None -> Error "Unexpected user response"
;;

let json_object fields = `Assoc fields
let json_string value = `String value

let http_raw ~headers ~method_ ~path ~body () =
  let open Js_of_ocaml in
  let response = Async_kernel.Ivar.create () in
  let xhr = XmlHttpRequest.create () in
  xhr##_open (Js.string method_) (Js.string path) Js._true;
  List.iter headers ~f:(fun (name, value) ->
    xhr##setRequestHeader (Js.string name) (Js.string value));
  xhr##.onerror
  := Dom.handler (fun _ ->
       Async_kernel.Ivar.fill_if_empty response (Error "Network error");
       Js._true);
  xhr##.ontimeout
  := Dom.handler (fun _ ->
       Async_kernel.Ivar.fill_if_empty response (Error "Request timed out");
       Js._true);
  xhr##.onreadystatechange
  := Js.wrap_callback (fun _ ->
       match xhr##.readyState with
       | DONE ->
         let text =
           Js.Opt.to_option xhr##.responseText
           |> Option.value_map ~default:"" ~f:Js.to_string
         in
         Async_kernel.Ivar.fill_if_empty response (Ok (xhr##.status, text))
       | _ -> ());
  xhr##send
    (Option.value_map body ~default:Js.null ~f:(fun body -> Js.some (Js.string body)));
  Async_kernel.Ivar.read response
;;

let request ?token method_ path body =
  let headers =
    (match token with
     | None -> []
     | Some token -> [ "Authorization", "Token " ^ token ])
    @
    match body with
    | None -> []
    | Some _ -> [ "Content-Type", "application/json" ]
  in
  let method_ =
    match method_ with
    | `Get -> "GET"
    | `Post -> "POST"
  in
  let body = Option.map body ~f:Yojson.Basic.to_string in
  Effect.of_deferred_fun
    (fun () ->
       let open Async_kernel.Deferred.Let_syntax in
       let%map response = http_raw ~headers ~method_ ~path ~body () in
       match response with
       | Error error -> Error error
       | Ok (code, body) ->
         let parsed =
           try Ok (Yojson.Basic.from_string body) with
           | _ -> Error "Invalid JSON response"
         in
         if code < 200 || code >= 300 then (
           let details =
             match parsed with
             | Ok json -> error_details json
             | Error _ -> ""
           in
           Error
             (if String.is_empty details then
                "HTTP " ^ Int.to_string code
              else
                details))
         else
           parsed)
    ()
;;

let finish set_model model result ~decode ~on_success =
  match result with
  | Error error ->
    set_model { model with busy = false; message = Some error; error = true }
  | Ok json ->
    (match decode json with
     | Error error ->
       set_model { model with busy = false; message = Some error; error = true }
     | Ok value -> on_success value)
;;

let load_articles model set_model =
  let%bind.Effect () =
    set_model
      { model with busy = true; message = Some "Loading articles..."; error = false }
  in
  let%bind.Effect result = request `Get "/api/articles?limit=20&offset=0" None in
  finish set_model model result ~decode:articles_of_json ~on_success:(fun articles ->
    set_model { model with articles; busy = false; message = None; error = false })
;;

let authenticate model set_model kind =
  let fields =
    [ "email", json_string model.email; "password", json_string model.password ]
  in
  let fields =
    match kind with
    | `Login -> fields
    | `Register -> ("username", json_string model.username) :: fields
  in
  let path =
    match kind with
    | `Login -> "/api/users/login"
    | `Register -> "/api/users"
  in
  let%bind.Effect () =
    set_model { model with busy = true; message = Some "Signing in..."; error = false }
  in
  let%bind.Effect result =
    request `Post path (Some (json_object [ "user", json_object fields ]))
  in
  finish set_model model result ~decode:token_of_json ~on_success:(fun token ->
    set_model
      { model with
        token = Some token
      ; password = ""
      ; busy = false
      ; message = Some "Signed in. You can publish an article."
      ; error = false
      })
;;

let publish model set_model =
  match model.token with
  | None -> set_model { model with message = Some "Sign in first"; error = true }
  | Some token ->
    let body =
      json_object
        [ ( "article"
          , json_object
              [ "title", json_string model.title
              ; "description", json_string model.description
              ; "body", json_string model.body
              ; "tagList", `List []
              ] )
        ]
    in
    let%bind.Effect () =
      set_model { model with busy = true; message = Some "Publishing..."; error = false }
    in
    let%bind.Effect result = request ~token `Post "/api/articles" (Some body) in
    finish
      set_model
      model
      result
      ~decode:(fun json ->
        match article_of_json (member "article" json) with
        | Some article -> Ok article
        | None -> Error "Unexpected article response")
      ~on_success:(fun article ->
        set_model
          { model with
            articles = article :: model.articles
          ; title = ""
          ; description = ""
          ; body = ""
          ; busy = false
          ; message = Some "Article published"
          ; error = false
          })
;;

let field ?(kind = "text") label value update =
  Node.div
    [ Node.label [ Node.text label ]
    ; Node.input
        ~attrs:
          [ Attr.type_ kind
          ; Attr.value_prop value
          ; Attr.on_input (fun _ value -> update value)
          ]
        ()
    ]
;;

let button ?(secondary = false) ?(disabled = false) label action =
  Node.button
    ~attrs:
      ([ Attr.type_ "button"; Attr.on_click (fun _ -> action) ]
       @ (if secondary then
            [ Attr.class_ "secondary" ]
          else
            [])
       @
       if disabled then
         [ Attr.disabled ]
       else
         [])
    [ Node.text label ]
;;

let view model set_model =
  let update f value = set_model (f model value) in
  let article (article : article) =
    Node.div
      ~attrs:[ Attr.class_ "article" ]
      [ Node.h3 [ Node.text article.title ]
      ; Node.p [ Node.text article.description ]
      ; Node.small [ Node.text ("by " ^ article.author ^ " · " ^ article.slug) ]
      ]
  in
  Node.main
    [ Node.header
        [ Node.h1 [ Node.text "RealWorld" ]
        ; Node.span
            ~attrs:[ Attr.class_ "muted" ]
            [ Node.text
                (if Option.is_some model.token then
                   "Signed in"
                 else
                   "Guest")
            ]
        ]
    ; (match model.message with
       | None -> Node.none
       | Some message ->
         Node.div
           ~attrs:
             [ Attr.class_
                 (if model.error then
                    "message error"
                  else
                    "message")
             ]
           [ Node.text message ])
    ; Node.div
        ~attrs:[ Attr.class_ "grid" ]
        [ Node.div
            ~attrs:[ Attr.class_ "panel" ]
            [ Node.h2 [ Node.text "Account" ]
            ; field
                "Username (for registration)"
                model.username
                (update (fun m v -> { m with username = v }))
            ; field "Email" model.email (update (fun m v -> { m with email = v }))
            ; field
                ~kind:"password"
                "Password"
                model.password
                (update (fun m v -> { m with password = v }))
            ; button ~disabled:model.busy "Log in" (authenticate model set_model `Login)
            ; button
                ~secondary:true
                ~disabled:model.busy
                "Register"
                (authenticate model set_model `Register)
            ]
        ; Node.div
            ~attrs:[ Attr.class_ "panel" ]
            [ Node.h2 [ Node.text "New article" ]
            ; field "Title" model.title (update (fun m v -> { m with title = v }))
            ; field
                "Description"
                model.description
                (update (fun m v -> { m with description = v }))
            ; Node.label [ Node.text "Body" ]
            ; Node.textarea
                ~attrs:
                  [ Attr.value_prop model.body
                  ; Attr.on_input (fun _ value ->
                      update (fun m v -> { m with body = v }) value)
                  ]
                []
            ; button ~disabled:model.busy "Publish" (publish model set_model)
            ]
        ]
    ; Node.div
        ~attrs:[ Attr.class_ "panel" ]
        ([ Node.h2 [ Node.text "Articles" ]
         ; button
             ~secondary:true
             ~disabled:model.busy
             "Refresh"
             (load_articles model set_model)
         ]
         @
         if List.is_empty model.articles then
           [ Node.p ~attrs:[ Attr.class_ "muted" ] [ Node.text "No articles yet" ] ]
         else
           List.map model.articles ~f:article)
    ]
;;

let app =
  let open Bonsai.Let_syntax in
  let%sub model, set_model = Bonsai.state initial ~equal:phys_equal in
  let%sub () =
    Bonsai.Edge.lifecycle
      ~on_activate:
        (let%map model = model
         and set_model = set_model in
         load_articles model set_model)
      ()
  in
  let%arr model = model
  and set_model = set_model in
  view model set_model
;;

let () =
  Async_js.init ();
  Bonsai_web.Start.start app
;;
