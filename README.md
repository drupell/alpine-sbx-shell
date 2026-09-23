# Alpine SBX shell

An unofficial Alpine 3.24 shell template for Docker Sandboxes, with Bash, Node/npm,
uv/uvx, and a Docker Engine inside each sandbox. No coding agent is preinstalled.

## Compared with shell-docker

Comparison is against Docker’s `shell-docker-0.5.0`.

| Component | Docker shell-docker | This template |
| --- | --- | --- |
| Base / C library | Ubuntu 26.04 / glibc | Alpine 3.24 / musl |
| Bash, passwordless sudo, non-root `agent`, tini | Included | Included |
| Node / npm | 22 / 9 | 24 / 11 |
| uv / uvx | uv 0.9.26; no uvx executable | Both, 0.11.19 |
| Nested Docker, Buildx, Compose | Included | Included, from Alpine packages |
| Proxy / CA trust, SSH forwarding, workspace mounts and Git clones | Supported | Supported |
| Python + pip, Go, Java, make | Preinstalled | Omitted; uv can download Python |
| GitHub CLI, ripgrep, rsync, GnuPG, bubblewrap, full DNS/man tools | Preinstalled | Omitted |
| Git, curl, jq, SSH client, socat, coreutils | Included | Included |
| Native clipboard image bridge | Included | Omitted |

The [clipboard bridge shipped with Docker’s template](https://github.com/dvdksn/clipboardbridge)
is a third-party shim for native **PNG** clipboard pasting into agents. This
template omits it; ordinary terminal text paste and SBX’s HTTP clipboard helpers
remain available. Alpine’s musl also means glibc-only binaries may need alternatives.

## Build

Run from this directory with Docker running. uv/uvx come from the pinned official
Astral image; their license files are copied from `licenses/uv/`.

```sh
docker build -t alpine-sbx-shell:local .
```

Package versions are pinned and need maintenance as Alpine repositories change.

## Use with SBX

Import the image into SBX’s separate image store:

```sh
docker image save alpine-sbx-shell:local -o /tmp/alpine-sbx-shell.tar
sbx template load /tmp/alpine-sbx-shell.tar
```

Then, from the project directory you want to work in:

```sh
sbx run --template alpine-sbx-shell:local shell "$PWD"
```
