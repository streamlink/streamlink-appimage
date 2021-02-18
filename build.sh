#!/usr/bin/env bash
set -e

ARCH="${1:-$(uname -m)}"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(readlink -f "${0}")")
CONFIG="${ROOT}/config.json"
DIR_APP="${ROOT}/app"
DIR_BUILD="${ROOT}/build"
DIR_CACHE="${ROOT}/cache"
SCRIPT_DOCKER="${ROOT}/build-docker.sh"

declare -A DEPS=(
  [curl]=curl
  [jq]=jq
  [mksquashfs]=squashfs-tools
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
[ "${SOURCE_DATE_EPOCH}" ] && mtime="@${SOURCE_DATE_EPOCH}" || mtime=now

jq -e ".builds[\"${ARCH}\"]" >/dev/null <<< "${config}" \
 || jq -e ".dependencies.appimagekit.appimagetool[\"${ARCH}\"]" >/dev/null <<< "${config}" \
 || err "Unsupported arch"

app_name=$(jq -r '.app.name' <<< "${config}")
app_version=$(jq -r '.app.version' <<< "${config}")
app_entry=$(jq -r '.app.entry' <<< "${config}")
docker_image=$(jq -r ".builds[\"${ARCH}\"].image" <<< "${config}")
docker_digest=$(jq -r ".builds[\"${ARCH}\"].digest" <<< "${config}")
tag=$(jq -r ".builds[\"${ARCH}\"].tag" <<< "${config}")
abi=$(jq -r ".builds[\"${ARCH}\"].abi" <<< "${config}")
appimagetool=$(jq -r ".dependencies.appimagekit.appimagetool[\"${ARCH}\"]" <<< "${config}")
excludelist=$(jq -r ".dependencies.excludelist.file" <<< "${config}")

mkdir -p "${DIR_BUILD}" "${DIR_CACHE}"
tempdir=$(mktemp -d) && trap "rm -rf ${tempdir}" EXIT || exit 255
cd "${tempdir}"


# ----


get_appimagekit() {
  log "Checking AppImageKit assets"

  if ! [[ -f "${DIR_CACHE}/${appimagetool}" ]]; then
    log "Getting AppImageKit assets list from ${source}@${tag}"
    local source=$(jq -r '.dependencies.appimagekit.source' <<< "${config}")
    local tag=$(jq -r '.dependencies.appimagekit.tag' <<< "${config}")
    local url="https://api.github.com/repos/${source}/releases/tags/${tag}"
    local curl_gh_api_args=(
      -H "Accept: application/vnd.github.v3+json"
      -H "User-Agent: ${GITHUB_REPOSITORY:-"streamlink/streamlink-appimage"}"
    )
    local data=$(curl -sSL "${curl_gh_api_args[@]}" "${url}")
    log "Downloading: ${appimagetool}"
    curl -SL "${curl_gh_api_args[@]}" \
      -o "${DIR_CACHE}/${appimagetool}" \
      "$(jq -r ".assets[] | select(.name == \"${appimagetool}\") | .browser_download_url" <<< "${data}")"
  fi

  log "Validating: ${appimagetool}"
  local hash=$(jq -r ".dependencies.appimagekit.files[\"${appimagetool}\"]" <<< "${config}")
  sha256sum --check <<< "${hash}  ${DIR_CACHE}/${appimagetool}"
}


get_excludelist() {
  log "Checking library excludelist"
  local url=$(jq -r '.dependencies.excludelist.url' <<< "${config}")
  local file=$(jq -r '.dependencies.excludelist.file' <<< "${config}")
  local hash=$(jq -r '.dependencies.excludelist.sha256' <<< "${config}")
  if ! [[ -f "${DIR_CACHE}/${file}" ]]; then
    log "Downloading: ${file}"
    curl -SL -o "${DIR_CACHE}/${file}" "${url}"
  fi
  log "Validating: ${file}"
  sha256sum --check <<< "${hash}  ${DIR_CACHE}/${file}"
}


get_docker_image() {
  log "Checking docker image"
  local image="${docker_image}@${docker_digest}"
  docker image ls --digests "${docker_image}" | grep "${docker_digest}" 2>&1 >/dev/null \
    || docker image pull "${image}"
}


prepare_tempdir() {
  log "Copying container build files"
  cp -vt "${tempdir}" \
    "${SCRIPT_DOCKER}" \
    "${DIR_CACHE}/${excludelist}"

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
HERE=\$(dirname "\$(readlink -f "\$0")")
PYTHON=\$(readlink -f "\${HERE}/usr/bin/python")
export PYTHONPATH=\$(realpath "\$(dirname "\${PYTHON}")/../lib/\$(basename "\${PYTHON}")/site-packages")
"\${PYTHON}" -m '${app_entry}' "\$@"
EOF
  chmod +x "${tempdir}/AppDir/AppRun"
}


build_app() {
  log "Building app in container"
  local target=/app
  local uid=$(id -u)
  local gid=$(id -g)
  docker run \
    --interactive \
    --rm \
    --mount "type=bind,source=${tempdir},target=${target}" \
    "${docker_image}@${docker_digest}" \
    /usr/bin/bash <<EOF
'${target}/$(basename "${SCRIPT_DOCKER}")' '${target}/AppDir' '${abi}' '${target}/${excludelist}' '${target}/requirements.txt'
chown -R ${uid}:${gid} '${target}/AppDir'
EOF
}


build_appimage() {
  log "Fixing appimagetool"
  install -Dm777 "${DIR_CACHE}/${appimagetool}" "${tempdir}/${appimagetool}"
  "./${appimagetool}" --appimage-extract >/dev/null

  # replace appimagetool's internal mksquashfs tool with the system's one
  cat > ./squashfs-root/usr/lib/appimagekit/mksquashfs <<EOF
#!/bin/sh
args=\$(echo "\$@" | sed -e 's/-mkfs-fixed-time 0//')
"$(command -v mksquashfs)" \${args}
EOF

  log "Building appimage"
  local dest="${DIR_BUILD}/${app_name}-${app_version}-${abi}-${tag}.AppImage"
  find ./AppDir -exec touch --no-dereference "--date=${mtime}" '{}' '+'
  ARCH="${ARCH}" ./squashfs-root/AppRun \
    --verbose \
    --comp gzip \
    --no-appstream \
    ./AppDir \
    "${dest}"
  chmod +x "${dest}"

  log "Successfully built appimage"
  sha256sum "${dest}"
}


build() {
  get_appimagekit
  get_excludelist
  get_docker_image

  prepare_tempdir
  build_app
  build_appimage
}

build
