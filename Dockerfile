# syntax=docker/dockerfile:1
#
# scopes-static-files worker image — the static-files scope built on the lean
# gRPC worker bridge. The bridge dials over gRPC and runs the bash entrypoint
# on each package-exec action; this image adds the cloud tooling the scope's
# steps need and bakes the scope in.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:2.0.1

# Tooling the static-files workflows call: aws + gomplate from apk, az from pip
# (Alpine has no azure-cli package). az is needed by network/azure_dns/setup
# and by the Front Door purge in distribution/front-door.
RUN apk add --no-cache aws-cli gomplate py3-pip \
    && pip3 install --no-cache-dir --break-system-packages azure-cli \
    && az version

# OpenTofu >= 1.10 — the scope inits its S3 backend with use_lockfile=true.
ARG TOFU_VERSION=1.13.1
ARG TARGETARCH
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu \
    && tofu version

# Bake the scope in and point the bridge at its entrypoint + service path.
# Bake the service in. --chown so the files belong to the uid this image runs
# as: `np` chmods the action script in place at runtime, and a root-owned tree
# would be read-only for the non-root user.
COPY --chown=10001:10001 . /app/pkg
ENV NP_PACKAGE_NAME=scopes-static-files \
    NP_SERVICE_PATH=/app/pkg/static-files \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint

# Hand HOME to the runtime user. The RUN steps above ran as root with HOME
# already set to /home/app by the base, so tools invoked at build time left
# root-owned config and cache dirs there (tofu: ~/.terraform.d, az: ~/.azure)
# that the non-root user could not write to at runtime.
RUN chown -R 10001:10001 /home/app

# Drop root for the runtime. Everything above installs as root, as usual; the
# base (worker-bridge 2.0.0+) ships the app user, np on PATH and a writable
# HOME, and leaves the switch to each image. Numeric on purpose: k8s
# admission with runAsNonRoot resolves USER to a numeric id to prove it
# isn't root, and a name doesn't satisfy that check.
USER 10001:10001
