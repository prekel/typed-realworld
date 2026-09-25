all: build

PACKAGES = ./typed-realworld.opam
TYPED_ENDPOINT_VERSION = 0.1.1
TYPED_SQL_VERSION = 0.3.2
TYPED_ENDPOINT_DIR ?= ../typed-endpoint-v0.1.1
TYPED_SQL_DIR ?= ../typed-sql-v0.3.2
export NAME
export DBMATE_BIN ?= $(CURDIR)/.tools/bin/dbmate
export HURL_BIN ?= $(CURDIR)/.tools/bin/hurl

.PHONY: create_switch
create_switch:
	opam switch create . 5.5.1 --no-install -y
	opam install dune -y

.PHONY: pins
pins:
	opam pin add --kind=path typed-endpoint.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_DIR) -yn
	opam pin add --kind=path typed-endpoint-opium.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_DIR) -yn
	opam pin add --kind=path typed-endpoint-testing.$(TYPED_ENDPOINT_VERSION) $(TYPED_ENDPOINT_DIR) -yn
	opam pin add --kind=path typed-sql.$(TYPED_SQL_VERSION) $(TYPED_SQL_DIR) -yn
	opam pin add --kind=path typed-sql-caqti-lwt.$(TYPED_SQL_VERSION) $(TYPED_SQL_DIR) -yn

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
	# typed-endpoint-testing omits jsonschema from its published dependency metadata.
	opam install jsonschema -y
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
check: fmt build test api-test doc package schema-check

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
server:
	opam exec -- dune exec --root . bin/realworld_server.exe

.PHONY: api-test
api-test: build tools
	SERVER_BIN=$(CURDIR)/_build/default/bin/realworld_server.exe bash scripts/api-test.sh
