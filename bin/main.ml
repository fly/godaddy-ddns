open Yojson.Basic.Util

let log fmt = Printf.eprintf (fmt ^^ "\n%!")

module Config = struct
  let require_env name =
    match Sys.getenv_opt name with
    | Some value -> value
    | None -> failwith @@ Printf.sprintf "%s is not set" name

  let ipify_interval = 60

  let get_record_interval = 300

  let main_loop_interval = 300

  let domain = require_env "DOMAIN"

  let subdomain = require_env "SUBDOMAIN"

  let token =
    let dir = require_env "CREDENTIALS_DIRECTORY" in
    let path = Filename.concat dir "GODADDY_TOKEN" in
    let ic = open_in path in
    let content = In_channel.input_all ic in
    close_in ic;
    String.trim content
end

type dns_record = {
  record_id : string;
  ip : string;
}

let record_of_json json =
  { record_id = member "recordId" json |> to_string; ip = member "data" json |> to_string }

let parse_record body =
  match Yojson.Basic.from_string body |> member "items" |> to_list with
  | [ record ] -> record_of_json record
  | items -> failwith @@ Printf.sprintf "Expected exactly 1 record. Got %d" (List.length items)

let http_request ~meth ?(headers = []) ?body url =
  let request_result =
    Http_lwt_client.request ~meth ~headers ?body url
      (fun _resp acc chunk -> Lwt.return (acc ^ chunk))
      ""
  in
  match Lwt_main.run request_result with
  | Ok (resp, body) -> Ok (H2.Status.to_code resp.status, String.trim body)
  | Error (`Msg e) -> Error e

let rec get_current_ip () =
  let repeat () =
    Unix.sleep Config.ipify_interval;
    get_current_ip ()
  in
  match http_request ~meth:`GET "https://api.ipify.org/" with
  | Ok (200, ip) -> ip
  | Ok (status, body) ->
      log "Failed to get current IP (%d): %s" status body;
      repeat ()
  | Error err ->
      log "Failed to get current IP: %s" err;
      repeat ()

let godaddy_url =
  Printf.sprintf "https://api.godaddy.com/v3/domains/zones/%s/dns-records" Config.domain

let godaddy_headers = [ ("Authorization", Printf.sprintf "Bearer %s" Config.token) ]

let rec get_dns_record () =
  let url = Printf.sprintf "%s?name=%s&type=A" godaddy_url Config.subdomain in
  let repeat () =
    Unix.sleep Config.get_record_interval;
    get_dns_record ()
  in
  match http_request ~meth:`GET ~headers:godaddy_headers url with
  | Ok (200, body) -> parse_record body
  | Ok (401, body) -> failwith @@ Printf.sprintf "GoDaddy authorization failed %s" body
  | Ok (status, body) ->
      log "Failed to get DNS record (%d): %s" status body;
      repeat ()
  | Error err ->
      log "Failed to get DNS record: %s" err;
      repeat ()

let build_payload ip =
  `Assoc
    [
      ("data", `String ip);
      ("name", `String Config.subdomain);
      ("type", `String "A");
      ("ttl", `Int 600);
    ]
  |> Yojson.Basic.to_string

let update_dns_record ~ip ~record_id =
  let url = Printf.sprintf "%s/%s" godaddy_url record_id
  and headers = ("Content-Type", "application/json") :: godaddy_headers
  and payload = build_payload ip in
  match http_request ~meth:`PUT ~headers ~body:payload url with
  | Ok (200, body) -> Some (Yojson.Basic.from_string body |> record_of_json)
  | Ok (401, body) -> failwith @@ Printf.sprintf "GoDaddy authorization failed: %s" body
  | Ok (status, body) ->
      log "Failed to update DNS record (%d): %s" status body;
      None
  | Error err ->
      log "Failed to update DNS record: %s" err;
      None

let rec main_loop state =
  let current_ip = get_current_ip () in
  log "Current IP: %s, DNS IP: %s" current_ip state.ip;

  let state' =
    if current_ip = state.ip then
      state
    else begin
      log "Updating DNS IP address from %s to %s" state.ip current_ip;
      update_dns_record ~ip:current_ip ~record_id:state.record_id |> Option.value ~default:state
    end
  in
  Unix.sleep Config.main_loop_interval;
  main_loop state'

let main () = main_loop (get_dns_record ())

let () = main ()