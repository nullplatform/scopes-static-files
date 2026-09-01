# syntax=docker/dockerfile:1
#
# scopes-static-files worker image — the static-files scope built on the lean
# gRPC worker bridge. The bridge dials over gRPC and runs the bash entrypoint
# on each package-exec action; this image adds the cloud tooling the scope's
# steps need and bakes the scope in.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# Tooling the static-files workflows call: aws + gomplate from apk.
# bash, jq, np, base64 and curl ship in the base.
RUN apk add --no-cache aws-cli gomplate

# OpenTofu >= 1.10 — the scope inits its S3 backend with use_lockfile=true.
ARG TOFU_VERSION=1.10.10
ARG TARGETARCH
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu \
    && tofu version

# Bake the scope in and point the bridge at its entrypoint + service path.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=scopes-static-files \
    NP_SERVICE_PATH=/app/pkg/static-files \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
