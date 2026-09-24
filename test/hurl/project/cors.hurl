OPTIONS {{host}}/api/user
Origin: http://localhost:5173
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
HTTP 204
[Asserts]
header "Access-Control-Allow-Origin" == "*"
header "Access-Control-Allow-Methods" contains "GET"
header "Access-Control-Allow-Headers" contains "Authorization"

GET {{host}}/api/user
Origin: http://localhost:5173
HTTP 401
[Asserts]
header "Access-Control-Allow-Origin" == "*"
