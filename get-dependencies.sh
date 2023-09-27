#!/usr/bin/env bash
set -e

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
  echo "[${SELF}] $@"
}
err() {
  log >&2 "$@"
  exit 1
}


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" 2>&1 >/dev/null || err "Missing dependency: ${DEPS["${dep}"]}"
done

config=$(cat "${CONFIG}")

yq -e ".builds[\"${ARCH}\"]" >/dev/null <<< "${config}" \
 || err "Unsupported arch"

git_repo="${GITREPO:-$(yq -r '.git.repo' <<< "${config}")}"
git_ref="${GITREF:-$(yq -r '.git.ref' <<< "${config}")}"

dependency_override=($(yq -r ".builds[\"${ARCH}\"].dependency_override[]" <<< "${config}"))

docker_image=$(yq -r ".builds[\"${ARCH}\"].image" <<< "${config}")
abi=$(yq -r ".builds[\"${ARCH}\"].abi" <<< "${config}")


# ----


get_docker_image() {
  log "Getting docker image"
  [[ -n "$(docker image ls -q "${docker_image}")" ]] \
    || docker image pull "${docker_image}"
}


get_deps() {
  log "Finding dependencies (${ARCH} / ${abi}) for ${git_repo}@${git_ref}"
  local deps=("git+${git_repo}@${git_ref}" "${dependency_override[@]}" "${OPT_DEPSPEC[@]}")
  local script=$(cat <<EOF
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
    "${docker_image}" \
    /usr/bin/bash /dev/stdin "${deps[@]}" <<< "${script}"
}


get_docker_image
get_deps
