open Lwt.Infix

type t = {
  mutable confirm : Level.t option;
  level_cond : unit Lwt_condition.t;
}

let set_confirm t level =
  Log.info (fun f -> f "Confirmation threshold is now %a" (Fmt.Dump.option Level.pp) level);
  t.confirm <- level;
  Lwt_condition.broadcast t.level_cond ()

let get_confirm t = t.confirm

(* If the level isn't changed manually within [duration], remove limiter. *)
let slow_start_thread t duration =
  Lwt.async
    (fun () ->
       let changed = Lwt_condition.wait t.level_cond in
       Lwt.choose [Lwt_unix.sleep (Duration.to_f duration); changed] >|= fun () ->
       if Lwt.state changed = Lwt.Sleep then (
         Log.info (fun f -> f "Slow start period over; removing limiter");
         set_confirm t None;
       )
    )

let v ?auto_release ?confirm ?state_dir () =
  let level_cond = Lwt_condition.create () in
  let t = { confirm; level_cond } in
  Option.iter (slow_start_thread t) auto_release;
  let state_dir =
    match state_dir with
    | None -> Disk_store.state_dir_root ()
    | Some default -> Disk_store.state_dir_root ~default () in
  Log.info (fun f -> f "State dir set to %a." Fpath.pp state_dir);
  t

let (default : t) = v ()

let active_config : t option Current_incr.var = Current_incr.var None

let now = Current_incr.of_var active_config

let rec confirmed l t =
  match t.confirm with
  | Some threshold when Level.compare l threshold >= 0 ->
    Lwt_condition.wait t.level_cond >>= fun () ->
    confirmed l t
  | _ ->
    Lwt.return_unit

open Cmdliner

let cmdliner_confirm =
  let levels = List.map (fun l -> Level.to_string l, Some l) Level.values in
  let enum = ("none", None) :: levels in
  let doc =
    Fmt.str
      "Confirm before starting operations at or above this level (%s)."
      (Arg.doc_alts_enum enum)
  in
  Arg.opt (Arg.enum enum) None @@
  Arg.info ~doc ["confirm"]

let auto_release =
  Arg.value @@
  Arg.(opt (some int)) None @@
  Arg.info
    ~doc:"Remove confirm threshold after this many seconds from start-up"
    ~docv:"SEC"
    ["confirm-auto-release"]

let state_dir =
  Arg.value @@
  Arg.(opt string) (Disk_store.state_dir_root () |> Fpath.to_string) @@
  Arg.info
    ~doc:"Set the state directory for the current pipeline."
    ~docv:"DIR"
    ["current-state-dir"]

let cmdliner =
  let make auto_release confirm state_dir =
    let auto_release = Option.map Duration.of_sec auto_release in
    let state_dir = Fpath.v state_dir in
    v ?auto_release ?confirm ~state_dir () in
  Term.(const make $ auto_release $ Arg.value cmdliner_confirm $ state_dir)
