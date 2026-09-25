OPTIONS {{host}}/api/user
Origin: http://localhost:5173
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization, x-request-id
HTTP 204
[Asserts]
header "Access-Control-Allow-Origin" == "*"
header "Access-Control-Allow-Methods" contains "GET"
header "Access-Control-Allow-Headers" contains "Authorization"
header "Access-Control-Allow-Headers" contains "X-Request-Id"
header "Access-Control-Expose-Headers" contains "X-Request-Id"
header "X-Request-Id" exists

GET {{host}}/api/user
Origin: http://localhost:5173
HTTP 401
[Asserts]
header "Access-Control-Allow-Origin" == "*"
header "X-Request-Id" exists
