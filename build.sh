#!/usr/bin/env bash
set -e

ARCH="${1:-$(uname -m)}"
GITREPO="${2}"
GITREF="${3}"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.json"
DIR_APP="${ROOT}/app"
DIR_DIST="${ROOT}/dist"
SCRIPT_DOCKER="${ROOT}/build-docker.sh"
GIT_FETCHDEPTH=300

declare -A DEPS=(
  [git]=git
  [jq]=jq
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

jq -e ".builds[\"${ARCH}\"]" >/dev/null <<< "${config}" \
 || err "Unsupported arch"

app_name=$(jq -r '.app.name' <<< "${config}")
app_version=$(jq -r '.app.version' <<< "${config}")
app_entry=$(jq -r '.app.entry' <<< "${config}")
git_repo="${GITREPO:-$(jq -r '.git.repo' <<< "${config}")}"
git_ref="${GITREF:-$(jq -r '.git.ref' <<< "${config}")}"

docker_image=$(jq -r ".builds[\"${ARCH}\"].image" <<< "${config}")
tag=$(jq -r ".builds[\"${ARCH}\"].tag" <<< "${config}")
abi=$(jq -r ".builds[\"${ARCH}\"].abi" <<< "${config}")

mkdir -p "${DIR_DIST}"
tempdir=$(mktemp -d) && trap "rm -rf ${tempdir}" EXIT || exit 255
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
  GIT_PAGER=cat git \
    -C "${tempdir}/source.git" \
    log \
    -1 \
    --pretty=full
}


prepare_tempdir() {
  log "Copying container build files"
  cp -vt "${tempdir}" "${SCRIPT_DOCKER}"

  log "Building requirements.txt"
  jq -r ".builds[\"${ARCH}\"].dependencies | to_entries | .[] | \"\(.key)==\(.value)\"" <<< "${config}" \
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
"\${PYTHON}" -m '${app_entry}' "\$@"
EOF
  chmod +x "${tempdir}/AppDir/AppRun"
}


build_app() {
  log "Building app inside container"
  local target=/app
  local name="${app_name}-${app_version}-${abi}-${tag}.AppImage"

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
'./$(basename -- "${SCRIPT_DOCKER}")' '${name}' '${abi}'
EOF

  install -m777 "${tempdir}/${name}" "${DIR_DIST}/${name}"
}


build() {
  get_docker_image
  get_sources
  prepare_tempdir
  build_app
}

build
