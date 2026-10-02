(lang dune 3.23)

(name typed-realworld)

(generate_opam_files true)

(source
 (github prekel/typed-realworld))

(authors "Vladislav Prekel")

(maintainers "Vladislav Prekel")

(license MIT)

(package
 (name typed-realworld)
 (synopsis "RealWorld backend built with typed-endpoint and typed-sql")
 (description
  "A RealWorld/Conduit backend with SQLite and PostgreSQL migrations and generated typed SQL descriptors.")
 (depends
  (ocaml (>= 5.1.1))
  base
  ptime
  yojson
  base64
  digestif
  mirage-crypto-rng
  kdf
  lwt
  caqti
  caqti-lwt
  caqti-driver-sqlite3
  caqti-driver-postgresql
  uri
  cohttp
  (opium (= 0.18.0))
  (typed-endpoint (= 0.2.0))
  (typed-endpoint-opium (= 0.2.0))
  (typed-sql (= 0.3.5))
  (typed-sql-caqti-lwt (= 0.3.5))
  ppx_fields_conv
  (ppx_let (>= v0.17.1))
  (ppx_deriving_yojson :build)
  (typed-endpoint-ppx (and (= 0.2.0) :build))
  (typed-endpoint-testing (and (= 0.2.0) :with-test))
  (jsonschema :with-test)
  (ppx_expect :with-test)
  (ocamlformat (and (= 0.29.0) :with-dev-setup))
  (ocaml-lsp-server :with-dev-setup)
  (odoc :with-doc))
 (tags
  (realworld conduit http api sql sqlite postgresql)))
