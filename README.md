# godaddy-ddns

Keeps a GoDaddy A record pointed at the machine's current public IP.

I needed this kind of tool on my home server, and around the same time I wanted
an excuse to try OCaml. This project is the result.

## Configuration

Read from the environment at startup:

| Variable                | Meaning                                     |
|-------------------------|---------------------------------------------|
| `DOMAIN`                | The zone, e.g. `example.com`                |
| `SUBDOMAIN`             | The record name, e.g. `vpn`                 |
| `CREDENTIALS_DIRECTORY` | Directory containing a `GODADDY_TOKEN` file |

`CREDENTIALS_DIRECTORY` is set automatically by systemd when the unit uses
`LoadCredentialEncrypted=`. The token file holds a GoDaddy Personal Access Token.

An unset variable, a missing token file, or a 401 from GoDaddy is fatal: the
process logs and exits. Transport errors and other HTTP failures are retried.

## Build

The binary is built in a container and extracted; nothing needs to be installed
on the target host.

```shell
podman build --output type=local,dest=./out .
```

Build and run hosts must have compatible glibc versions. The Containerfile
targets Debian 13, which I have on the target host.

## Install

```shell
sudo install -m 755 out/godaddy-ddns /usr/local/bin/
sudo systemctl edit --force --full ddns.service
```

```ini
[Unit]
Description=Dynamic DNS updater
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=3600
StartLimitBurst=5

[Service]
ExecStart=/usr/local/bin/godaddy-ddns
Environment=DOMAIN=example.com
Environment=SUBDOMAIN=vpn
LoadCredentialEncrypted=GODADDY_TOKEN:/etc/credstore.encrypted/godaddy-ddns.cred

Restart=on-failure
RestartSec=60

# 1. Identity & Privileges
DynamicUser=yes
PrivateTmp=yes

# 2. File System Restrictions (Completely Read-Only)
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=
ProtectControlGroups=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes

# 3. Network Restrictions
RestrictAddressFamilies=AF_INET
RestrictNamespaces=yes

# 4. Kernel & System Call Hardening
NoNewPrivileges=yes
SystemCallFilter=@system-service @network-io
SystemCallArchitectures=native
CapabilityBoundingSet=
MemoryDenyWriteExecute=yes
RestrictRealtime=yes

# 5. Resource Controls
MemoryMax=50M

[Install]
WantedBy=multi-user.target
```

`StartLimitBurst` stops the restart loop when the failure is unrecoverable,
such as an expired token. Clear the failed state with
`systemctl reset-failed ddns.service` once it's fixed.

## Credentials

The GoDaddy Personal Access Token is stored encrypted at rest and decrypted by
systemd at service start. Encryption is bound to the host, so the file is only
usable on the machine that created it.

```shell
sudo systemd-creds encrypt --name=GODADDY_TOKEN - /etc/credstore.encrypted/godaddy-ddns.cred
```
Paste the token, then Ctrl+D twice - the first flushes the unterminated line,
the second signals EOF.

```shell
sudo chmod 600 /etc/credstore.encrypted/godaddy-ddns.cred
```

The `--name` must match the credential name in `LoadCredentialEncrypted=`, or
systemd refuses to decrypt.

Verify:

```shell
sudo systemd-creds decrypt --name=GODADDY_TOKEN /etc/credstore.encrypted/godaddy-ddns.cred
```

To rotate, re-run the encrypt command and restart the service.

## Development

Requires opam and dune.

```shell
opam install --deps-only .
dune build
dune exec godaddy-ddns
```
