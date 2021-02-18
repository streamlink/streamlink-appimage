#!/usr/bin/env bash
set -e

PACKAGES="${1}"
ARCH="${2:-$(uname -m)}"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.json"

declare -A DEPS=(
  [jq]=jq
  [docker]=docker
)


# ----


SELF=$(basename "$(readlink -f "${0}")")
log() {
  echo "[${SELF}] $@"
}
err() {
  log >&2 "$@"
  exit 1
}


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" 2>&1 >/dev/null || err "${DEPS["${dep}"]} is required to build the installer. Aborting."
done

config=$(cat "${CONFIG}")


# ----


get_deps() {
  local docker_image=$(jq -r ".builds[\"${ARCH}\"].image" <<< "${config}")
  local docker_digest=$(jq -r ".builds[\"${ARCH}\"].digest" <<< "${config}")
  local abi=$(jq -r ".builds[\"${ARCH}\"].abi" <<< "${config}")
  local jq_url=$(jq -r ".dependencies.jq.url" <<< "${config}")
  local jq_sha256=$(jq -r ".dependencies.jq.sha256" <<< "${config}")

  log "Finding dependencies (${ARCH} / ${abi}) for ${PACKAGES}"
  docker run \
    --interactive \
    --rm \
    "${docker_image}@${docker_digest}" \
    /usr/bin/bash <<EOF
shopt -s nullglob

if ! yum -q -y install jq 2>/dev/null; then
  echo jq package missing, compiling from source...
  cd "\$(mktemp -d)"
  curl -sSL -o jq.tar.gz '${jq_url}'
  sha256sum --check <<< '${jq_sha256}  jq.tar.gz'
  tar --strip-components=1 -xzf jq.tar.gz
  (
    export MAKEFLAGS=-j\$(nproc)
    autoreconf -fi
    ./configure --prefix=/usr
    make
    make prefix=/usr install
  ) >/dev/null 2>&1
fi

cd "\$(mktemp -d)"
PYTHON="/opt/python/${abi}/bin/python"

"\${PYTHON}" -m pip download ${PACKAGES}
"\${PYTHON}" -m pip install --no-deps --no-compile * >/dev/null
echo

packages=\$("\${PYTHON}" -m pip list \
  --format json \
  --exclude setuptools \
  --exclude pip \
  --exclude wheel \
  | jq -r '.[] | "\(.name) \(.version)"'
)

while read -r name version; do
  hash=\$("\${PYTHON}" -m pip hash \
    "\${name}-\${version}"*.tar{,.gz} \
    "\${name//-/_}-\${version}-"*.whl \
    | tail -n1
  )
  echo "\${name}==\${version} \${hash}"
done <<< "\${packages}" \
  | jq -CRn '[(inputs | split("\n")) | .[] | split("==") | {key: .[0], value: .[1]}] | from_entries'
EOF
}

get_deps
