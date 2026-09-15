open! Base

include
  Realworld_application.User_repository.S
  with type 'a io = 'a Lwt.t
   and type connection = Caqti_lwt.connection
