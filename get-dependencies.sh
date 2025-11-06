#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

ARCH="$(uname -m)"
GITREPO=""
GITREF=""
OPT_DEPSPEC=()

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.yml"

declare -A DEPS=(
  [jq]=jq
  [yq]=yq
  [docker]=docker
)

_OPTS=$(getopt --name "$0" --long 'help,arch:,gitrepo:,gitref:' --options 'help,a:' -- "$@")
eval set -- "${_OPTS}"
unset _OPTS


# ----


SELF=$(basename -- "$(readlink -f -- "${0}")")
log() {
  echo "[${SELF}]" "$@"
}
err() {
  log >&2 "$@"
  exit 1
}

print_help() {
  echo "Usage: ${0} [options] [depspec]"
  echo
  echo "Options:"
  echo "  -a, --arch <arch>    Target architecture"
  echo "      --gitrepo <url>  Source"
  echo "      --gitref <ref>   Git branch/tag/commit"
  exit 0
}


# ----


while true; do
  case "${1}" in
    -h | --help)
      print_help
      ;;
    -a | --arch)
      ARCH="${2}"
      shift 2
      ;;
    --gitrepo)
      GITREPO="${2}"
      shift 2
      ;;
    --gitref)
      GITREF="${2}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      err "Invalid option: ${1}"
      ;;
  esac
done

OPT_DEPSPEC+=("${@}")


# ----


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" >/dev/null 2>&1 || err "Missing dependency: ${DEPS["${dep}"]}"
done

CONFIGJSON=$(cat "${CONFIG}")

yq -e --arg a "${ARCH}" '.builds[$a]' >/dev/null <<< "${CONFIGJSON}" \
 || err "Unsupported arch"

read -r appname \
  < <(yq -r '.app | "\(.name)"' <<< "${CONFIGJSON}")
read -r gitrepo gitref \
  < <(yq -r '.git | "\(.repo) \(.ref)"' <<< "${CONFIGJSON}")
read -r image abi \
  < <(yq -r --arg a "${ARCH}" '.builds[$a] | "\(.image) \(.abi)"' <<< "${CONFIGJSON}")

optional_dependencies=$(yq \
  -e -r \
  --arg a "${ARCH}" \
  '.builds[$a].optional_dependencies | "[\(. | join(","))]"' \
  <<< "${CONFIGJSON}" \
  2>/dev/null || true
)

# shellcheck disable=SC2207
dependency_override=($(yq \
  -e -r \
  --arg a "${ARCH}" \
  '.builds[$a].dependency_override[]' \
  <<< "${CONFIGJSON}" \
  2>/dev/null || true
))

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
  deps=("${appname}${optional_dependencies}@git+${gitrepo}@${gitref}" "${dependency_override[@]}" "${OPT_DEPSPEC[@]}")
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
