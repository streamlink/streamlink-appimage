#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

ARCH="$(uname -m)"
GITREPO=""
GITREF=""

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.yml"
DIR_APP="${ROOT}/app"
DIR_DIST="${ROOT}/dist"
SCRIPT_DOCKER="${ROOT}/build-docker.sh"

declare -A DEPS=(
  [git]=git
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
  echo "Usage: ${0} [options]"
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


# ----


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" >/dev/null 2>&1 || err "Missing dependency: ${DEPS["${dep}"]}"
done

[[ -f "${CONFIG}" ]] \
  || err "Missing config file: ${CONFIG}"
CONFIGJSON=$(cat "${CONFIG}")

yq -e --arg a "${ARCH}" '.builds[$a]' >/dev/null <<< "${CONFIGJSON}" \
 || err "Unsupported arch"

read -r appname apprel appentry \
  < <(yq -r '.app | "\(.name) \(.rel) \(.entry)"' <<< "${CONFIGJSON}")
read -r gitrepo gitref \
  < <(yq -r '.git | "\(.repo) \(.ref)"' <<< "${CONFIGJSON}")
read -r image tag abi \
  < <(yq -r --arg a "${ARCH}" '.builds[$a] | "\(.image) \(.tag) \(.abi)"' <<< "${CONFIGJSON}")

gitrepo="${GITREPO:-${gitrepo}}"
gitref="${GITREF:-${gitref}}"


# ----


# shellcheck disable=SC2064
TEMP=$(mktemp -d) && trap "rm -rf -- '${TEMP}'" EXIT || exit 255
cd "${TEMP}"

mkdir -p \
  "${DIR_DIST}"


get_docker_image() {
  log "Getting docker image"
  [[ -n "$(docker image ls -q "${image}")" ]] \
    || docker image pull "${image}"
}


get_sources() {
  log "Getting sources"
  mkdir -p "${TEMP}/source.git"
  pushd "${TEMP}/source.git"

  # TODO: re-investigate and optimize this
  git clone --depth 1 "${gitrepo}" .
  git fetch origin --depth 300 "${gitref}"
  git ls-remote --tags --sort=version:refname 2>&- \
    | awk "END{printf \"+%s:%s\\n\",\$2,\$2}" \
    | git fetch origin --depth=300
  git -c advice.detachedHead=false checkout --force "${gitref}"
  git fetch origin --depth=300 --update-shallow

  log "Commit information"
  git describe --tags --long --dirty
  git --no-pager log -1 --pretty=full

  popd
}


prepare_tempdir() {
  log "Copying container build files"
  cp -vt "${TEMP}" "${SCRIPT_DOCKER}"

  log "Building requirements.txt"
  yq -r --arg a "${ARCH}" '.builds[$a].dependencies | to_entries | .[] | "\(.key)==\(.value)"' <<< "${CONFIGJSON}" \
    > "${TEMP}/requirements.txt"

  log "Installing AppDir files"
  install -Dm644 -t "${TEMP}/AppDir/usr/share/applications/" "${DIR_APP}/${appname}.desktop"
  install -Dm644 -t "${TEMP}/AppDir/usr/share/icons/hicolor/scalable/apps/" "${DIR_APP}/${appname}.svg"
  install -Dm644 -t "${TEMP}/AppDir/usr/share/metainfo/" "${DIR_APP}/${appname}.appdata.xml"
  ln -sr "${TEMP}/AppDir/usr/share/applications/${appname}.desktop" "${TEMP}/AppDir/${appname}.desktop"
  ln -sr "${TEMP}/AppDir/usr/share/icons/hicolor/scalable/apps/${appname}.svg" "${TEMP}/AppDir/${appname}.svg"
  ln -sr "${TEMP}/AppDir/usr/share/icons/hicolor/scalable/apps/${appname}.svg" "${TEMP}/AppDir/.DirIcon"
  cat > "${TEMP}/AppDir/AppRun" <<EOF
#!/usr/bin/env bash
HERE=\$(dirname -- "\$(readlink -f -- "\$0")")
PYTHON=\$(readlink -f -- "\${HERE}/usr/bin/python")
export PYTHONPATH=\$(realpath -- "\$(dirname -- "\${PYTHON}")/../lib/\$(basename -- "\${PYTHON}")/site-packages")
export SSL_CERT_FILE=\${SSL_CERT_FILE:-"\${PYTHONPATH}/certifi/cacert.pem"}
"\${PYTHON}" -m '${appentry}' "\$@"
EOF
  chmod +x "${TEMP}/AppDir/AppRun"
}


build_app() {
  log "Building app inside container"
  local target=/app

  docker run \
    --interactive \
    --rm \
    --env SOURCE_DATE_EPOCH \
    --mount "type=bind,source=${TEMP},target=${target}" \
    "${image}" \
    /usr/bin/bash <<EOF
set -e
trap "chown -R $(id -u):$(id -g) '${target}'" EXIT
cd '${target}'
'./$(basename -- "${SCRIPT_DOCKER}")' '${abi}' '${appentry}'
EOF

  local versionstring versionplain versionmeta version
  versionstring=$(cat "${TEMP}/version.txt")
  versionplain="${versionstring%%+*}"
  versionmeta="${versionstring##*+}"

  # Not a custom git reference (assume that only tagged releases are used as source)
  # Use plain version string with app release number and no abbreviated commit ID
  if [[ -z "${GITREF}" ]]; then
    version="${versionplain}-${apprel}"

  # Custom ref -> tagged release (no build metadata in version string)
  # Add abbreviated commit ID to the plain version string to distinguish it from regular releases, set 0 as app release number
  elif [[ "${versionstring}" != *+* ]]; then
    local _commit
    _commit="$(git -C "${TEMP}/source.git" -c core.abbrev=7 rev-parse --short HEAD)"
    version="${versionplain}-0-g${_commit}"

  # Custom ref -> arbitrary untagged commit (version string includes build metadata)
  # Translate into correct format
  else
    version="${versionplain}-${versionmeta/./-}"
  fi

  local name="${appname}-${version}-${abi}-${tag}.AppImage"

  install -m777 "${TEMP}/out.AppImage" "${DIR_DIST}/${name}"
  ( cd "${DIR_DIST}"; sha256sum "${name}"; )
}


build() {
  get_docker_image
  get_sources
  prepare_tempdir
  build_app
}

build
