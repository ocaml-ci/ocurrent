(** Integration with Git. *)

module Commit_id : sig
  include Set.OrderedType

  val v : repo:string -> gref:string -> hash:string -> t
  (** [v ~repo ~gref ~hash] identifies a commit that can be fetched from [repo]
      using [gref] as the reference name and has hash [hash]. *)

  val repo : t -> string
  (** [repo t] is the Git URI of the repository. *)

  val gref : t -> string

  val hash : t -> string
  (* [hash t] is the Git commit hash. *)

  val equal : t -> t -> bool
  val pp : t Fmt.t

  val pp_user_clone : t Fmt.t
  (** Display a Git command a user could run to get this commit. *)

  val digest : t -> string
end

module Commit : sig
  include Set.OrderedType

  val id : t -> Commit_id.t
  val hash : t -> string
  val equal : t -> t -> bool
  val pp : t Fmt.t

  val pp_short : t Fmt.t
  (** [pp_short] shows just the start of the hash. *)

  val marshal : t -> string
  val unmarshal : string -> t
end

val clone : schedule:Current_cache.Schedule.t -> ?gref:string -> Eio.Process.mgr -> string -> Commit.t Current.t
(** [clone ~schedule ~gref uri] evaluates to the head commit of [uri]'s [gref] branch (default: "master"). *)

val fetch : Eio.Process.mgr -> Commit_id.t Current.t -> Commit.t Current.t

val with_checkout :
  ?pool:unit Current.Pool.t ->
  job:Current.Job.t ->
  fs:Eio.Fs.dir Eio.Path.t ->
  Eio.Process.mgr ->
  Commit.t ->
  (Eio.Fs.dir Eio.Path.t -> 'a Current.or_error) ->
  'a Current.or_error
(** [with_checkout ~job c fn] clones [c] to a temporary directory and runs [fn tmpdir].
    When it returns, the directory is deleted.
    @param pool Used to prevent too many clones from happening at once. *)

module Local : sig
  type t
  (** A local Git repository. *)

  val v : Eio.Process.mgr -> Fpath.t -> t
  (** [v path] is the local Git repository at [path]. *)

  val head : t -> [`Commit of Commit_id.t | `Ref of string ] Current.t
  (** [head] is the current branch ref (e.g. "/refs/heads/master"). *)

  val head_commit : t -> Commit.t Current.t
  (** [head_commit] is the commit at the head of the current branch. *)

  val commit_of_ref : t -> string -> Commit.t Current.t
  (** [commit_of_ref t gref] evaluates to the commit at the head of [gref].
      e.g. [commit_of_ref t "/refs/heads/master"] *)

  val repo : t -> Fpath.t
end
