all: build

PACKAGES = ./typed-realworld.opam
TYPED_ENDPOINT_VERSION = 0.2.0
TYPED_SQL_VERSION = 0.4.5
TYPED_ENDPOINT_DIR ?= ../typed-endpoint
TYPED_SQL_DIR ?= ../typed-sql
TYPED_ENDPOINT_GIT ?= git+file://$(abspath $(TYPED_ENDPOINT_DIR))
TYPED_SQL_GIT ?= git+file://$(abspath $(TYPED_SQL_DIR))
export NAME
export DBMATE_BIN ?= $(CURDIR)/.tools/bin/dbmate
export HURL_BIN ?= $(CURDIR)/.tools/bin/hurl

.PHONY: create_switch
create_switch:
	opam switch create . 5.5.1 --no-install -y
	opam install dune -y

.PHONY: pins
pins:
	opam pin add --kind=git typed-endpoint.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_GIT)#v$(TYPED_ENDPOINT_VERSION) -yn
	opam pin add --kind=git typed-endpoint-opium.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_GIT)#v$(TYPED_ENDPOINT_VERSION) -yn
	opam pin add --kind=git typed-endpoint-testing.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_GIT)#v$(TYPED_ENDPOINT_VERSION) -yn
	opam pin add --kind=git typed-endpoint-ppx.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_GIT)#v$(TYPED_ENDPOINT_VERSION) -yn
	opam pin add --kind=git typed-sql.$(TYPED_SQL_VERSION) $(TYPED_SQL_GIT)#v$(TYPED_SQL_VERSION) -yn
	opam pin add --kind=git typed-sql-caqti-lwt.$(TYPED_SQL_VERSION) $(TYPED_SQL_GIT)#v$(TYPED_SQL_VERSION) -yn
	opam pin add --kind=git typed-sql-schema.$(TYPED_SQL_VERSION) $(TYPED_SQL_GIT)#v$(TYPED_SQL_VERSION) -yn
	opam pin add --kind=git typed-sql-schema-caqti-lwt.$(TYPED_SQL_VERSION) $(TYPED_SQL_GIT)#v$(TYPED_SQL_VERSION) -yn

.PHONY: metadata
metadata:
	rm -f typed-realworld.opam
	opam exec -- dune build --root . typed-realworld.opam
	install -m 644 _build/default/typed-realworld.opam.generated typed-realworld.opam

.PHONY: deps
deps: pins metadata
	opam install --deps-only $(PACKAGES) -y

.PHONY: deps_all
deps_all: pins metadata
	opam install --deps-only --with-test --with-doc --with-dev-setup $(PACKAGES) -y

.PHONY: build
build:
	opam exec -- dune build --root . @all

.PHONY: test
test:
	opam exec -- dune runtest --root .

.PHONY: fmt
fmt:
	opam exec -- dune build --root . @fmt

.PHONY: doc
doc:
	opam exec -- dune build --root . @doc

.PHONY: package
package:
	opam exec -- dune build --root . @install
	opam lint $(PACKAGES)

.PHONY: check
check: fmt build test frontend-test api-test doc package schema-check

.PHONY: release-check
release-check: check
	git diff --check

.PHONY: clean
clean:
	opam exec -- dune clean --root .

.PHONY: tools
tools: dbmate-tools hurl-tools

.PHONY: dbmate-tools
dbmate-tools:
	bash scripts/install-dbmate.sh

.PHONY: hurl-tools
hurl-tools:
	bash scripts/install-hurl.sh

.PHONY: migration
migration:
	bash scripts/new-migration.sh

.PHONY: migrate
migrate:
	bash scripts/dbmate.sh up

.PHONY: db-status
db-status:
	bash scripts/dbmate.sh status

.PHONY: schema
schema:
	bash scripts/schema.sh update

.PHONY: schema-check
schema-check:
	bash scripts/schema.sh check

.PHONY: server
server: frontend-build
	opam exec -- dune exec --root . bin/realworld_server.exe

.PHONY: server-postgres
server-postgres: frontend-build
	opam exec -- dune exec --root . bin/realworld_server_postgres.exe

.PHONY: frontend-deps
frontend-deps: frontend/node_modules/.package-lock.json

frontend/node_modules/.package-lock.json: frontend/package.json frontend/package-lock.json
	cd frontend && bash ../scripts/linux-npm.sh ci

.PHONY: frontend-types
frontend-types: frontend-deps
	cd frontend && OPENAPI_URL="$(or $(OPENAPI_URL),http://127.0.0.1:3000/openapi.json)" bash ../scripts/linux-npm.sh run generate:api

.PHONY: frontend-build
frontend-build: frontend-deps
	cd frontend && bash ../scripts/linux-npm.sh run build

.PHONY: frontend-test
frontend-test: frontend-deps
	cd frontend && bash ../scripts/linux-npm.sh test

.PHONY: api-test
api-test: build tools frontend-build
	SERVER_BIN=$(CURDIR)/_build/default/bin/realworld_server.exe bash scripts/api-test.sh

.PHONY: test-postgres
test-postgres: build tools frontend-build
	SERVER_BIN=$(CURDIR)/_build/default/bin/realworld_server_postgres.exe bash scripts/postgres-test.sh
