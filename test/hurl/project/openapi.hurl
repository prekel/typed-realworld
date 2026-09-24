GET {{host}}/openapi.json
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.openapi" == "3.1.0"
jsonpath "$.info.title" == "RealWorld API"
jsonpath "$.paths['/api/articles'].get.operationId" == "listArticles"
jsonpath "$.components.schemas.ArticleResponse.type" == "object"

GET {{host}}/docs
HTTP 200
[Asserts]
body contains "Five renderers"

GET {{host}}/docs/
HTTP 200
[Asserts]
body contains "RealWorld API"

GET {{host}}/docs/swagger
HTTP 200
[Asserts]
body contains "SwaggerUIBundle"

GET {{host}}/docs/scalar
HTTP 200
[Asserts]
body contains "Scalar.createApiReference"

GET {{host}}/docs/rapidoc
HTTP 200
[Asserts]
body contains "<rapi-doc"

GET {{host}}/docs/redoc
HTTP 200
[Asserts]
body contains "<redoc"

GET {{host}}/docs/elements
HTTP 200
[Asserts]
body contains "<elements-api"
