open! Base

include
  Realworld_application.Comment_repository.S
  with type 'a io = 'a Lwt.t
   and type connection = Caqti_lwt.connection
