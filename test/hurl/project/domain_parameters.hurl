# Authentication setup for the protected comment route.
POST {{host}}/api/users
{
  "user": {
    "username": "parameters_{{uid}}",
    "email": "parameters_{{uid}}@test.com",
    "password": "password123"
  }
}
HTTP 201
[Captures]
token: jsonpath "$.user.token"

# Negative page limit is rejected by the endpoint codec.
GET {{host}}/api/articles?limit=-1
HTTP 400
[Asserts]
jsonpath "$.errors.limit[0]" == "is invalid"

# Non-integer page offset is rejected by the endpoint codec.
GET {{host}}/api/articles?offset=not-an-integer
HTTP 400
[Asserts]
jsonpath "$.errors.offset[0]" == "is invalid"

# Repeated scalar query parameters are rejected by typed-endpoint 0.2.0.
GET {{host}}/api/articles?limit=1&limit=2
HTTP 400
[Asserts]
jsonpath "$.errors.limit[0]" == "must occur once"

# Blank tags are rejected by Domain.Article.Tag.
GET {{host}}/api/articles?tag=%20
HTTP 400
[Asserts]
jsonpath "$.errors.tag[0]" == "is invalid"

# Article slugs are decoded into Domain.Article.Slug before the handler runs.
GET {{host}}/api/articles/invalid%20slug
HTTP 400
[Asserts]
jsonpath "$.errors.slug[0]" == "is invalid"

# Usernames are decoded into Domain.User.Username before the handler runs.
GET {{host}}/api/profiles/%C3%A9
HTTP 400
[Asserts]
jsonpath "$.errors.username[0]" == "is invalid"

# Comment IDs are decoded into Domain.Comment.Id before dispatch.
DELETE {{host}}/api/articles/valid-slug/comments/0
Authorization: Token {{token}}
HTTP 400
[Asserts]
jsonpath "$.errors.id[0]" == "is invalid"
