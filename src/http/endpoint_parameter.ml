open! Base
open Typed_endpoint
module Domain = Realworld_domain.Domain

let entity_id
      (type id)
      (module Id : Domain.ID with type t = id)
      ~schema_name
      ~description
      ()
  =
  Parameter.v
    ~schema:(Json_schema.integer_exn ~format:`Int64 ~minimum:1 ())
    ~schema_name
    ~description
    ~of_string:(fun value ->
      Id.of_string value
      |> Result.of_option ~error:"expected a positive 64-bit identifier")
    ()
;;

let string_value
      (type value)
      (module Value : Domain.STRING_VALUE with type t = value)
      ~schema_name
      ~description
      ()
  =
  Parameter.v
    ~schema:(Json_schema.string_exn ~min_length:1 ())
    ~schema_name
    ~description
    ~of_string:(fun raw -> Value.of_string raw |> Result.of_option ~error:"invalid value")
    ()
;;

let page_value
      (type value)
      (module Value : Domain.Page.VALUE with type t = value)
      ~schema_name
      ~description
      ()
  =
  Parameter.v
    ~schema:(Json_schema.integer_exn ~minimum:0 ())
    ~schema_name
    ~description
    ~of_string:(fun raw ->
      Value.of_string raw |> Result.of_option ~error:"expected a non-negative integer")
    ()
;;
