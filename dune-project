(lang dune 3.23)

(name typed-realworld)

(generate_opam_files true)

(source
 (github prekel/typed-realworld))

(authors "Vladislav Prekel")

(maintainers "Vladislav Prekel")

(license MIT)

(pin
 (url ../typed-endpoint)
 (package
  (name typed-endpoint)))

(pin
 (url ../typed-endpoint)
 (package
  (name typed-endpoint-opium)))

(pin
 (url ../typed-endpoint)
 (package
  (name typed-endpoint-testing)))

(pin
 (url ../typed-sql)
 (package
  (name typed-sql)))

(pin
 (url ../typed-sql)
 (package
  (name typed-sql-caqti-lwt)))

(package
 (name typed-realworld)
 (synopsis "RealWorld backend built with typed-endpoint and typed-sql")
 (description
  "A RealWorld/Conduit backend foundation with repository ports, versioned SQLite migrations, and generated typed SQL descriptors.")
 (depends
  (ocaml (>= 5.5.1))
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
  uri
  cohttp
  (opium (= 0.18.0))
  typed-endpoint
  typed-endpoint-opium
  typed-sql
  typed-sql-caqti-lwt
  (ppx_let (>= v0.17.1))
  (ppx_deriving_yojson :build)
  (ppx_deriving_jsonschema (>= 0.0.8))
  (typed-endpoint-testing :with-test)
  (jsonschema :with-test)
  (ppx_expect :with-test)
  (ocamlformat (and (= 0.29.0) :with-dev-setup))
  (ocaml-lsp-server :with-dev-setup)
  (odoc :with-doc))
 (tags
  (realworld conduit http api sql sqlite)))
