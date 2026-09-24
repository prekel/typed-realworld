open! Base

type t = (string * string list) list

let field name message = [ name, [ message ] ]
let combine = List.concat
let is_empty = List.is_empty
let blank value = String.is_empty (String.strip value)

let normalized_identity field_name value =
  let value = String.strip value |> String.lowercase in
  if blank value then
    Error (field field_name "can't be blank")
  else if not (String.for_all value ~f:(fun character -> Char.to_int character < 128))
  then
    Error (field field_name "must contain only ASCII characters")
  else
    Ok value
;;

let email value =
  match normalized_identity "email" value with
  | Error _ as error -> error
  | Ok value ->
    Realworld_domain.Domain.User.Email.of_string value
    |> Result.of_option ~error:(field "email" "is invalid")
;;

let normalized_optional_text = function
  | Realworld_domain.Domain.Patch.Keep -> Realworld_domain.Domain.Patch.Keep
  | Clear -> Realworld_domain.Domain.Patch.Clear
  | Set value ->
    let value = String.strip value in
    if String.is_empty value then
      Realworld_domain.Domain.Patch.Clear
    else
      Realworld_domain.Domain.Patch.Set value
;;

let password value =
  if blank value then
    Error (field "password" "can't be blank")
  else if String.length value < 8 then
    Error (field "password" "is too short")
  else
    Ok value
;;

let article_create (article : Realworld_domain.Domain.Article.create) =
  let errors =
    [ (if blank article.title then
         Some (field "title" "can't be blank")
       else
         None)
    ; (if blank article.description then
         Some (field "description" "can't be blank")
       else
         None)
    ; (if blank article.body then
         Some (field "body" "can't be blank")
       else
         None)
    ]
    |> List.filter_map ~f:Fn.id
    |> combine
  in
  if is_empty errors then
    Ok article
  else
    Error errors
;;

let article_update (article : Realworld_domain.Domain.Article.update) =
  let validate name = function
    | Some value when blank value -> Some (field name "can't be blank")
    | None | Some _ -> None
  in
  let errors =
    [ validate "title" article.title
    ; validate "description" article.description
    ; validate "body" article.body
    ]
    |> List.filter_map ~f:Fn.id
    |> combine
  in
  if is_empty errors then
    Ok article
  else
    Error errors
;;
