#!/usr/bin/env bash
set -e

ARCH="${1:-$(uname -m)}"
GITREPO="${2}"
GITREF="${3}"

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

config=$(cat "${CONFIG}")

yq -e ".builds[\"${ARCH}\"]" >/dev/null <<< "${config}" \
 || err "Unsupported arch"

app_name=$(yq -r '.app.name' <<< "${config}")
app_rel=$(yq -r '.app.rel' <<< "${config}")
app_entry=$(yq -r '.app.entry' <<< "${config}")
git_repo="${GITREPO:-$(yq -r '.git.repo' <<< "${config}")}"
git_ref="${GITREF:-$(yq -r '.git.ref' <<< "${config}")}"

docker_image=$(yq -r ".builds[\"${ARCH}\"].image" <<< "${config}")
tag=$(yq -r ".builds[\"${ARCH}\"].tag" <<< "${config}")
abi=$(yq -r ".builds[\"${ARCH}\"].abi" <<< "${config}")

mkdir -p "${DIR_DIST}"

# shellcheck disable=SC2064
tempdir=$(mktemp -d) && trap "rm -rf -- '${tempdir}'" EXIT || exit 255
cd "${tempdir}"


# ----


get_docker_image() {
  log "Getting docker image"
  [[ -n "$(docker image ls -q "${docker_image}")" ]] \
    || docker image pull "${docker_image}"
}


get_sources() {
  log "Getting sources"
  git \
    -c advice.detachedHead=false \
    clone \
    -b "${git_ref}" \
    "${git_repo}" \
    "${tempdir}/source.git"

  log "Commit information"
  git \
    --no-pager \
    -C "${tempdir}/source.git" \
    log \
    -1 \
    --pretty=full
}


prepare_tempdir() {
  log "Copying container build files"
  cp -vt "${tempdir}" "${SCRIPT_DOCKER}"

  log "Building requirements.txt"
  yq -r ".builds[\"${ARCH}\"].dependencies | to_entries | .[] | \"\(.key)==\(.value)\"" <<< "${config}" \
    > "${tempdir}/requirements.txt"

  log "Installing AppDir files"
  install -Dm644 -t "${tempdir}/AppDir/usr/share/applications/" "${DIR_APP}/${app_name}.desktop"
  install -Dm644 -t "${tempdir}/AppDir/usr/share/icons/hicolor/scalable/apps/" "${DIR_APP}/${app_name}.svg"
  install -Dm644 -t "${tempdir}/AppDir/usr/share/metainfo/" "${DIR_APP}/${app_name}.appdata.xml"
  ln -sr "${tempdir}/AppDir/usr/share/applications/${app_name}.desktop" "${tempdir}/AppDir/${app_name}.desktop"
  ln -sr "${tempdir}/AppDir/usr/share/icons/hicolor/scalable/apps/${app_name}.svg" "${tempdir}/AppDir/${app_name}.svg"
  ln -sr "${tempdir}/AppDir/usr/share/icons/hicolor/scalable/apps/${app_name}.svg" "${tempdir}/AppDir/.DirIcon"
  cat > "${tempdir}/AppDir/AppRun" <<EOF
#!/usr/bin/env bash
HERE=\$(dirname -- "\$(readlink -f -- "\$0")")
PYTHON=\$(readlink -f -- "\${HERE}/usr/bin/python")
export PYTHONPATH=\$(realpath -- "\$(dirname -- "\${PYTHON}")/../lib/\$(basename -- "\${PYTHON}")/site-packages")
export SSL_CERT_FILE=\${SSL_CERT_FILE:-"\${PYTHONPATH}/certifi/cacert.pem"}
"\${PYTHON}" -m '${app_entry}' "\$@"
EOF
  chmod +x "${tempdir}/AppDir/AppRun"
}


build_app() {
  log "Building app inside container"
  local target=/app

  docker run \
    --interactive \
    --rm \
    --env SOURCE_DATE_EPOCH \
    --mount "type=bind,source=${tempdir},target=${target}" \
    "${docker_image}" \
    /usr/bin/bash <<EOF
set -e
trap "chown -R $(id -u):$(id -g) '${target}'" EXIT
cd '${target}'
'./$(basename -- "${SCRIPT_DOCKER}")' '${abi}' '${app_entry}'
EOF

  local versionstring versionplain versionmeta version
  versionstring=$(cat "${tempdir}/version.txt")
  versionplain="${versionstring%%+*}"
  versionmeta="${versionstring##*+}"

  # Not a custom git reference (assume that only tagged releases are used as source)
  # Use plain version string with app release number and no abbreviated commit ID
  if [[ -z "${GITREF}" ]]; then
    version="${versionplain}-${app_rel}"

  # Custom ref -> tagged release (no build metadata in version string)
  # Add abbreviated commit ID to the plain version string to distinguish it from regular releases, set 0 as app release number
  elif [[ "${versionstring}" != *+* ]]; then
    local _commit
    _commit="$(git -C "${tempdir}/source.git" -c core.abbrev=7 rev-parse --short HEAD)"
    version="${versionplain}-0-g${_commit}"

  # Custom ref -> arbitrary untagged commit (version string includes build metadata)
  # Translate into correct format
  else
    version="${versionplain}-${versionmeta/./-}"
  fi

  local name="${app_name}-${version}-${abi}-${tag}.AppImage"

  install -m777 "${tempdir}/out.AppImage" "${DIR_DIST}/${name}"
  ( cd "${DIR_DIST}"; sha256sum "${name}"; )
}


build() {
  get_docker_image
  get_sources
  prepare_tempdir
  build_app
}

build
