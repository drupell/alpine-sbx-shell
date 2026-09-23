ARG BASE_IMAGE=alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
FROM ${BASE_IMAGE}
USER root
ARG BASE_IMAGE

# Base overrides must remain Alpine 3.24; retain their repositories and CA roots.
RUN test "$(cut -d. -f1,2 /etc/alpine-release)" = 3.24

# Shell, sandbox integrations, Node.js and npm.
RUN apk add --no-cache \
    bash=5.3.9-r1 sudo=1.9.17_p2-r1 \
    ca-certificates=20260909-r0 curl=8.22.0-r0 \
    nodejs=24.18.1-r0 npm=11.12.1-r0 jq=1.8.2-r0 \
    tini=0.19.0-r3 openssh-client-default=10.3_p1-r1 socat=1.8.1.3-r0 \
    procps-ng=4.0.6-r0 \
    coreutils=9.11-r0 git=2.54.0-r0 git-daemon=2.54.0-r0
# coreutils supplies GNU realpath: uv's generated tool launcher uses `realpath --`,
# which BusyBox's realpath mishandles.
# git preserves BuildKit Git sources; its split daemon serves SBX clone remotes.
# jq is required by SBX's injected clipboard read/write shell helpers.

# Official binary-only uv image, pinned by multi-platform index digest.
# BuildKit selects ARM64 or AMD64; only /uv and /uvx enter this Alpine image.
# The pinned upstream ARM64 build sets jemalloc LG_PAGE=16 for larger pages.
COPY --from=ghcr.io/astral-sh/uv:0.11.19@sha256:b46b03ddfcfbf8f547af7e9eaefdf8a39c8cebcba7c98858d3162bd28cf536f6 /uv /uvx /usr/local/bin/

COPY --chown=0:0 --chmod=0644 licenses/uv/LICENSE-MIT licenses/uv/LICENSE-APACHE /usr/local/share/licenses/uv/

# Docker Engine and plugins from the same Alpine repositories.
RUN apk add --no-cache \
    docker-engine=29.5.3-r1 docker-cli=29.5.3-r1 \
    containerd=2.3.5-r5 runc=1.4.3-r1 iptables=1.8.13-r0 \
    docker-cli-buildx=0.34.1-r1 docker-cli-compose=5.1.4-r1

RUN <<'SANDBOX_CONFIG'
set -eu
umask 022
mkdir -p /tmp
cat > /tmp/sbx-identity.sh <<'IDENTITY_SCRIPT'
#!/bin/sh
# Reject incompatible inherited accounts without removing them.
set -eu
die() { echo "Incompatible base identity: $*" >&2; exit 1; }
if getent passwd agent >/dev/null; then
    test "$(id -u agent)" = 1000 || die 'agent must have UID 1000'
    test "$(id -g agent)" = 1000 || die 'agent primary GID must be 1000'
    test "$(getent passwd agent | cut -d: -f6)" = /home/agent || die 'agent home must be /home/agent'
    test "$(getent passwd agent | cut -d: -f7)" = /bin/bash || die 'agent shell must be /bin/bash'
    test "$(getent group 1000 | cut -d: -f1)" = agent || die 'GID 1000 must belong to agent'
else
    ! getent passwd 1000 >/dev/null || die 'UID 1000 belongs to another user'
    if getent group agent >/dev/null; then
        test "$(getent group agent | cut -d: -f3)" = 1000 || die 'agent group has conflicting GID'
    else
        ! getent group 1000 >/dev/null || die 'GID 1000 belongs to another group'
        addgroup -g 1000 agent
    fi
    adduser -D -u 1000 -G agent -h /home/agent -s /bin/bash agent
fi
getent group docker >/dev/null || addgroup -S docker
addgroup agent docker
for path in /home/agent /home/agent/workspace /home/agent/.local \
    /home/agent/.local/bin /home/agent/.local/share /home/agent/.local/state \
    /home/agent/.cache /home/agent/.cache/uv /home/agent/.docker \
    /home/agent/.docker/sandbox /home/agent/.docker/sandbox/locks \
    /usr/local/share/npm-global; do
    mkdir -p "$path"
    chown agent:agent "$path"
done
if [ ! -e /etc/sandbox-persistent.sh ]; then touch /etc/sandbox-persistent.sh; fi
chown agent:agent /etc/sandbox-persistent.sh
chmod 0644 /etc/sandbox-persistent.sh
# Preserve compatible inherited startup files.
login_file=/home/agent/.bash_profile
for candidate in /home/agent/.bash_profile /home/agent/.bash_login /home/agent/.profile; do
    if [ -r "$candidate" ]; then login_file=$candidate; break; fi
done
for file in /home/agent/.bashrc "$login_file"; do
    if [ ! -e "$file" ]; then
        touch "$file"
        if [ "$file" = /home/agent/.bash_profile ]; then
            printf '%s\n' 'if [ -r "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi' >> "$file"
        fi
    fi
    if ! grep -q '# SBX shell integration' "$file"; then
        printf '\n# SBX shell integration\n. /etc/profile.d/sbx-shell.sh\n' >> "$file"
    fi
    chown agent:agent "$file"
done
printf '\nPS1="\\u@\\h:\\W\\$ "\n' >> /home/agent/.bashrc
IDENTITY_SCRIPT
mkdir -p /etc/profile.d
cat > /etc/profile.d/sbx-shell.sh <<'SHELL_PROFILE'
# shellcheck shell=sh disable=SC1091
# Alpine /etc/profile resets PATH; restore the writable tool bins for login shells.
case ":$PATH:" in *:/usr/local/share/npm-global/bin:*) ;; *) PATH="/usr/local/share/npm-global/bin:$PATH" ;; esac
case ":$PATH:" in *:/home/agent/.local/bin:*) ;; *) PATH="/home/agent/.local/bin:$PATH" ;; esac
export PATH
export BASH_ENV=/etc/sandbox-persistent.sh
if [ -r /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi
SHELL_PROFILE
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/sbx-agent <<'SUDOERS_AGENT'
agent ALL=(ALL) NOPASSWD: ALL
Defaults:agent env_keep += "http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY all_proxy SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE CURL_CA_BUNDLE UV_SYSTEM_CERTS UV_NATIVE_TLS SSH_AUTH_SOCK"
SUDOERS_AGENT
sh /tmp/sbx-identity.sh
chmod 0440 /etc/sudoers.d/sbx-agent
chmod 0644 /etc/profile.d/sbx-shell.sh
visudo -c
# Empty defaults leave daemon flags, proxy and storage to SBX.
# Preserve an inherited daemon configuration.
mkdir -p /etc/docker
if [ ! -e /etc/docker/daemon.json ]; then printf '{}\n' > /etc/docker/daemon.json; fi
rm /tmp/sbx-identity.sh
SANDBOX_CONFIG

ENV HOME=/home/agent SHELL=/bin/bash \
    NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/home/agent/.local/bin:/usr/local/share/npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    BASH_ENV=/etc/sandbox-persistent.sh \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    UV_SYSTEM_CERTS=true
# SBX injects proxy settings, runtime certificates and Docker storage.
LABEL com.docker.sandboxes="templates" \
    com.docker.sandboxes.base="${BASE_IMAGE}" \
    com.docker.sandboxes.flavor="shell-docker" \
    com.docker.sandboxes.start-docker="true" \
    org.opencontainers.image.title="Alpine SBX shell" \
    org.opencontainers.image.description="Alpine shell for Docker Sandboxes with Node.js, uv and nested Docker"
USER agent
WORKDIR /home/agent/workspace
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/bash"]
