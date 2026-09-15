open! Base
module Domain = Realworld_domain.Domain
module Password = Realworld_security.Password_scrypt
module Jwt = Realworld_security.Jwt_hs256

let () =
  Mirage_crypto_rng_unix.use_default ();
  let encoded = Password.hash "password123" |> Result.ok_or_failwith in
  assert (Password.verify ~encoded "password123");
  assert (not (Password.verify ~encoded "wrong-password"));
  let module Token = (val Jwt.create ~secret:"test-secret") in
  let token = Token.issue ~user_id:42 in
  assert (Option.value_map (Token.verify token) ~default:false ~f:(Int.equal 42));
  assert (Option.is_none (Token.verify (token ^ "x")));
  assert (String.equal (Domain.Article.slugify "Hello, OCaml world!") "hello-ocaml-world")
;;
