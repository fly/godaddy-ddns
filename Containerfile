FROM docker.io/ocaml/opam:debian-13-ocaml-5.4 AS build
WORKDIR /src

COPY --chown=opam:opam godaddy-ddns.opam .
RUN opam install --deps-only -y .

COPY --chown=opam:opam . .
RUN opam exec -- dune build --profile release && \
    chmod +w _build/default/bin/main.exe && \
    strip _build/default/bin/main.exe

FROM scratch
COPY --from=build /src/_build/default/bin/main.exe /godaddy-ddns
