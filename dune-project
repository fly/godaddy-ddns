(lang dune 3.24)

(name godaddy-ddns)

(generate_opam_files true)

(package
 (name godaddy-ddns)
 (synopsis "Dynamic DNS updater for GoDaddy")
 (depends
    (ocaml (>= 5.0))
    dune
    http-lwt-client
    yojson))
