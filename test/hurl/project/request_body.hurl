# JSON DTO bodies reject a non-JSON media type through the configured decode policy.
POST {{host}}/api/users
Content-Type: text/plain

{
  "user": {
    "username": "wrong_media_{{uid}}",
    "email": "wrong_media_{{uid}}@test.com",
    "password": "password123"
  }
}
HTTP 415
[Asserts]
jsonpath "$.errors.contentType[0]" == "is unsupported"
