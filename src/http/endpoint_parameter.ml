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
  let schema : id Json_schema.t =
    Json_schema.Deriver.type_schema Json_schema.Deriver.Integer
    |> Json_schema.Deriver.with_minimum_int 1
    |> Json_schema.Deriver.with_format "int64"
  in
  Parameter.v
    ~schema
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
  let schema : value Json_schema.t =
    Json_schema.Deriver.type_schema Json_schema.Deriver.String
    |> Json_schema.Deriver.with_string_lengths ~minimum:1
  in
  Parameter.v
    ~schema
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
  let schema : value Json_schema.t =
    Json_schema.Deriver.type_schema Json_schema.Deriver.Integer
    |> Json_schema.Deriver.with_minimum_int 0
  in
  Parameter.v
    ~schema
    ~schema_name
    ~description
    ~of_string:(fun raw ->
      Value.of_string raw |> Result.of_option ~error:"expected a non-negative integer")
    ()
;;
