#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

ARCH="$(uname -m)"
GITREPO=""
GITREF=""
BUNDLES=()

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.yml"
DIR_APP="${ROOT}/app"
DIR_CACHE="${ROOT}/cache"
DIR_DIST="${ROOT}/dist"
SCRIPT_DOCKER="${ROOT}/build-docker.sh"

declare -A DEPS=(
  [git]=git
  [jq]=jq
  [yq]=yq
  [docker]=docker
)

_OPTS=$(getopt --name "$0" --long 'help,arch:,gitrepo:,gitref:,bundle:' --options 'help,a:,b:' -- "$@")
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
  echo "  -b, --bundle <name>  Comma-separated list of bundled software"
  exit 0
}

in_array() {
  local item elem
  item="${1}"
  shift
  for elem in "${@}"; do
    [[ "${elem}" == "${item}" ]] && return 0
  done
  return 1
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
    -b | --bundle)
      IFS=',' read -r -a BUNDLES <<< "${2}"
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

mapfile -t bundles < \
  <(yq -r --arg a "${ARCH}" '.builds[$a].bundles | keys[]' <<< "${CONFIGJSON}")
for bundle in "${BUNDLES[@]}"; do
  in_array "${bundle}" "${bundles[@]}" || err "Invalid bundle name: ${bundle}"
done

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

DIR_APPDIR="${TEMP}/AppDir"
DIR_BUNDLES="${TEMP}/bundles"

mkdir -p \
  "${DIR_CACHE}" \
  "${DIR_DIST}" \
  "${DIR_APPDIR}" \
  "${DIR_BUNDLES}"


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


get_bundles() {
  local bundle
  for bundle in "${bundles[@]}"; do
    in_array "${bundle}" "${BUNDLES[@]}" || continue
    local filename url sha256
    read -r filename url sha256 \
      < <(yq -r --arg a "${ARCH}" --arg b "${bundle}" '.builds[$a].bundles[$b] | "\(.filename) \(.url) \(.sha256)"' <<< "${CONFIGJSON}")
    if ! [[ -f "${DIR_CACHE}/${filename}" ]]; then
      log "Downloading bundle: ${bundle}"
      curl -SLo "${DIR_CACHE}/${filename}" "${url}"
    fi
    log "Checking bundle: ${bundle}"
    sha256sum -c - <<< "${sha256} ${DIR_CACHE}/${filename}"
  done
}


prepare_bundles() {
  log "Preparing bundles"
  local bundle
  for bundle in "${bundles[@]}"; do
    in_array "${bundle}" "${BUNDLES[@]}" || continue
    log "Preparing bundle: ${bundle}"
    local type filename sourcedir
    read -r type filename sourcedir \
      < <(yq -r --arg a "${ARCH}" --arg b "${bundle}" '.builds[$a].bundles[$b] | "\(.type) \(.filename) \(.sourcedir)"' <<< "${CONFIGJSON}")
    case "${type}" in
      tar)
        mkdir -p "${DIR_BUNDLES}/${bundle}"
        tar -C "${DIR_BUNDLES}/${bundle}" -xvf "${DIR_CACHE}/${filename}"
        sourcedir="${DIR_BUNDLES}/${bundle}/${sourcedir}"
        ;;
      zip)
        mkdir -p "${DIR_BUNDLES}/${bundle}"
        unzip "${DIR_CACHE}/${filename}" -d "${DIR_BUNDLES}/${bundle}"
        sourcedir="${DIR_BUNDLES}/${bundle}/${sourcedir}"
        ;;
      *)
        sourcedir="${DIR_CACHE}"
        ;;
    esac
    while read -r from to; do
      install -vDT "${sourcedir}/${from}" "${DIR_APPDIR}/${to}"
    done < <(yq -r --arg a "${ARCH}" --arg b "${bundle}" '.builds[$a].bundles[$b].files[] | "\(.from) \(.to)"' <<< "${CONFIGJSON}")
  done
}


prepare_tempdir() {
  log "Copying container build files"
  cp -vt "${TEMP}" "${SCRIPT_DOCKER}"

  log "Building requirements.txt"
  yq -r --arg a "${ARCH}" '.builds[$a].dependencies | to_entries | .[] | "\(.key)==\(.value)"' <<< "${CONFIGJSON}" \
    > "${TEMP}/requirements.txt"

  log "Installing AppDir files"
  install -Dm644 -t "${DIR_APPDIR}/usr/share/applications/" "${DIR_APP}/${appname}.desktop"
  install -Dm644 -t "${DIR_APPDIR}/usr/share/icons/hicolor/scalable/apps/" "${DIR_APP}/${appname}.svg"
  install -Dm644 -t "${DIR_APPDIR}/usr/share/metainfo/" "${DIR_APP}/${appname}.appdata.xml"
  ln -sr "${DIR_APPDIR}/usr/share/applications/${appname}.desktop" "${DIR_APPDIR}/${appname}.desktop"
  ln -sr "${DIR_APPDIR}/usr/share/icons/hicolor/scalable/apps/${appname}.svg" "${DIR_APPDIR}/${appname}.svg"
  ln -sr "${DIR_APPDIR}/usr/share/icons/hicolor/scalable/apps/${appname}.svg" "${DIR_APPDIR}/.DirIcon"
  cat > "${DIR_APPDIR}/AppRun" <<EOF
#!/usr/bin/env bash
HERE=\$(dirname -- "\$(readlink -f -- "\$0")")
PYTHON=\$(readlink -f -- "\${HERE}/usr/bin/python")
export PYTHONPATH=\$(realpath -- "\$(dirname -- "\${PYTHON}")/../lib/\$(basename -- "\${PYTHON}")/site-packages")
export SSL_CERT_FILE=\${SSL_CERT_FILE:-"\${PYTHONPATH}/certifi/cacert.pem"}

ARGS=()
if [[ -f "\${HERE}/usr/bin/ffmpeg" ]]; then
  ARGS+=(--ffmpeg-ffmpeg "\${HERE}/usr/bin/ffmpeg")
fi

"\${PYTHON}" -m '${appentry}' "\${ARGS[@]}" "\$@"
EOF
  chmod +x "${DIR_APPDIR}/AppRun"
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

  local versionstring version
  versionstring=$(cat "${TEMP}/version.txt")

  # custom gitrefs that point to a tag should use the same file name format as builds from untagged commits
  if [[ -n "${GITREF}" && "${versionstring}" != *+* ]]; then
    local _commit
    _commit="$(git -C "${TEMP}/source.git" -c core.abbrev=7 rev-parse --short HEAD)"
    version="${versionstring%%+*}+0+g${_commit}"
  else
    version="${versionstring}"
  fi

  local bundle
  for bundle in "${BUNDLES[@]}"; do
    appname+="+${bundle}"
  done

  local name="${appname}-${version}-${apprel}-${abi}-${tag}.AppImage"

  install -m777 "${TEMP}/out.AppImage" "${DIR_DIST}/${name}"
  ( cd "${DIR_DIST}"; sha256sum "${name}"; )
}


build() {
  get_docker_image
  get_sources
  get_bundles
  prepare_bundles
  prepare_tempdir
  build_app
}

build
