GET {{host}}/
HTTP 200
[Asserts]
header "Content-Type" contains "text/html"
body contains "id=\"app\""
body contains "src=\"/app.js\""

GET {{host}}/app
HTTP 200
[Asserts]
header "Content-Type" contains "text/html"

GET {{host}}/app.js
HTTP 200
[Asserts]
header "Content-Type" contains "text/javascript"
body contains "RealWorld"
