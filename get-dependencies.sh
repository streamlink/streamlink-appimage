#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

ARCH="${1:-$(uname -m)}"
GITREPO="${2:-}"
GITREF="${3:-}"
OPT_DEPSPEC=("${@}")
OPT_DEPSPEC=("${OPT_DEPSPEC[@]:3}")

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.yml"

declare -A DEPS=(
  [jq]=jq
  [yq]=yq
  [docker]=docker
)


# ----


SELF=$(basename -- "$(readlink -f -- "${0}")")
log() {
  echo "[${SELF}]" "$@"
}
err() {
  log >&2 "$@"
  exit 1
}


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" >/dev/null 2>&1 || err "Missing dependency: ${DEPS["${dep}"]}"
done

CONFIGJSON=$(cat "${CONFIG}")

yq -e --arg a "${ARCH}" '.builds[$a]' >/dev/null <<< "${CONFIGJSON}" \
 || err "Unsupported arch"

read -r gitrepo gitref \
  < <(yq -r '.git | "\(.repo) \(.ref)"' <<< "${CONFIGJSON}")
read -r image abi \
  < <(yq -r --arg a "${ARCH}" '.builds[$a] | "\(.image) \(.abi)"' <<< "${CONFIGJSON}")

# shellcheck disable=SC2207
dependency_override=($(yq -r --arg a "${ARCH}" '.builds[$a].dependency_override[]' <<< "${CONFIGJSON}"))

gitrepo="${GITREPO:-${gitrepo}}"
gitref="${GITREF:-${gitref}}"


# ----


get_docker_image() {
  log "Getting docker image"
  [[ -n "$(docker image ls -q "${image}")" ]] \
    || docker image pull "${image}"
}


get_deps() {
  log "Finding dependencies (${ARCH} / ${abi}) for ${gitrepo}@${gitref}"
  local deps script
  deps=("git+${gitrepo}@${gitref}" "${dependency_override[@]}" "${OPT_DEPSPEC[@]}")
  script=$(cat <<EOF
PYTHON="/opt/python/${abi}/bin/python"
REPORT=\$(mktemp)

"\${PYTHON}" -m pip install \
  --disable-pip-version-check \
  --root-user-action=ignore \
  --isolated \
  --no-cache-dir \
  --check-build-dependencies \
  --ignore-installed \
  --dry-run \
  --report="\${REPORT}" \
  "\$@"

yq -y -C \
  '
    [
     .install[]
     | select(.is_direct != true)
     | .download_info.archive_info.hash |= sub("^(?<hash>[^=]+)="; "\(.hash):")
     | {
       key: .metadata.name,
       value: "\(.metadata.version) --hash=\(.download_info.archive_info.hash)"
     }
    ]
    | sort_by(.key | ascii_upcase)
    | from_entries
    | {"dependencies": .}
  ' \
  "\${REPORT}"
EOF
  )

  docker run \
    --interactive \
    --rm \
    "${image}" \
    /usr/bin/bash /dev/stdin "${deps[@]}" <<< "${script}"
}


get_docker_image
get_deps
