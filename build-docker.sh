#!/usr/bin/env bash
# shellcheck disable=SC2269
set -euo pipefail


FILENAME="${FILENAME}"
GITREF="${GITREF}"
ABI="${ABI}"
ENTRY="${ENTRY}"


PIP_ARGS=(
  --disable-pip-version-check
  --root-user-action=ignore
  --isolated
  --no-cache-dir
  --no-deps
)


# ----


SELF=$(basename -- "$(readlink -f -- "${0}")")
log() {
  echo "[${SELF}]" "${@}"
}
err() {
  log >&2 "$@"
  exit 1
}

[[ -f /.dockerenv ]] || err "This script is supposed to be run from build.sh inside a docker container"

declare -A excludelist
while read -r lib; do
  excludelist["${lib}"]="${lib}"
done <<< "$(sed -e '/#.*/d; /^[[:space:]]*|[[:space:]]*$/d; /^$/d' /usr/local/share/appimage/excludelist)"


# ----


PYTHON="/opt/python/${ABI}/bin/python"
PYTHON_X_Y=$("${PYTHON}" -B -c 'import sys; print("python{}.{}".format(*sys.version_info[:2]))')
PYTHON_PREFIX=$("${PYTHON}" -B -c 'import sys; print(sys.prefix)')

APPDIR=AppDir
PREFIX="${APPDIR}/usr"


patch_binary() {
  local path="${1}"
  local libdir="${2}"
  local recursive="${3:-false}"

  local newrpath rpath relpath deps
  rpath=$(patchelf --print-rpath "${path}")
  relpath="$(realpath --relative-to="$(dirname -- "${path}")" "${libdir}")"
  if [[ "${relpath}" == "." ]]; then newrpath="\$ORIGIN"; else newrpath="\$ORIGIN/${relpath}"; fi

  mapfile -t deps < <(ldd "${path}" 2>/dev/null | grep -E ' => \S+' | sed -E 's/.+ => (.+) \(0x.+/\1/')

  if [[ "${rpath}" != "${newrpath}" ]]; then
    log "Patching RPATH: ${path} (\"${rpath}\" -> \"${newrpath}\")"
    patchelf --set-rpath "${newrpath}" "${path}"
  fi

  for dep in "${deps[@]}"; do
    local name
    name=$(basename "${dep}")
    [[ -n "${excludelist[${name}]:-}" ]] && continue
    local target="${libdir}/${name}"
    if ! [[ -f "${target}" ]]; then
      log "Bundling library: ${dep} (${target})"
      install -Dm777 "${dep}" "${target}"
      if [[ "${recursive}" == true ]]; then
        patch_binary "${target}" "${libdir}" true
      fi
    fi
  done
}


setup_python() {
  log "Setting up Python environment"

  if [[ -d "${PREFIX}/bin" ]]; then
    mv "${PREFIX}/bin" "${PREFIX}/_bin"
  fi

  "${PYTHON}" -m venv --copies --without-pip --without-scm-ignore-files "${PREFIX}"

  ln -frsT "${PREFIX}/bin/${PYTHON_X_Y}" "${PREFIX}/bin/python"
  ln -frsT "${PREFIX}/bin/${PYTHON_X_Y}" "${PREFIX}/bin/python3"
  cp -a --no-preserve=ownership -t "${PREFIX}" "${PYTHON_PREFIX}"/{include,lib}

  local file
  patch_binary "${PREFIX}/bin/${PYTHON_X_Y}" "${PREFIX}/lib" false
  while read -r file; do
    patch_binary "${file}" "${PREFIX}/lib" false
  done <<< "$(find "${PREFIX}/lib/${PYTHON_X_Y}/lib-dynload" -type f -name '*.so' -print)"
  while read -r file; do
    patch_binary "${file}" "${PREFIX}/lib" true
  done <<< "$(find "${PREFIX}/lib" -type f -name 'lib*.so*' -print)"
}


install_application() {
  export PYTHONHASHSEED=0

  log "Installing dependencies"
  rm -rf "${PREFIX}/lib/${PYTHON_X_Y}/site-packages/"*
  "${PYTHON}" -B -m pip install --prefix "${PREFIX}" \
    "${PIP_ARGS[@]}" \
    --no-compile \
    --require-hashes \
    -r requirements.txt

  log "Installing application"
  # fix git permission issue when getting version string via versioningit
  git config --global --add safe.directory /app/source.git
  "${PYTHON}" -B -m pip install --prefix "${PREFIX}" \
    --verbose \
    "${PIP_ARGS[@]}" \
    --no-compile \
    /app/source.git
}

finalize() {
  log "Removing unneeded files"
  rm -rf \
    "${PREFIX}/pyvenv.cfg" \
    "${PREFIX}/include" \
    "${PREFIX}/lib/pkgconfig" \
    "${PREFIX}/lib/${PYTHON_X_Y}/"{test,config-*-linux-*}
  find "${PREFIX}/bin/" -type f ! -name "python*" -delete

  if [[ -d "${PREFIX}/_bin" ]]; then
    cp -a "${PREFIX}/_bin/." "${PREFIX}/bin/"
    rm -rf "${PREFIX}/_bin"
  fi
}

build_bytecode() {
  log "Building bytecode"
  "${PYTHON}" -B -m compileall -q -j1 -f -r9999 -x 'lib2to3|test' "${PREFIX}/lib"
}


copy_licenses() {
  log "Copying library licenses"
  cp -av -t "${APPDIR}" /usr/local/share/appimage/licenses/*
}


build_appimage() {
  log "Building AppImage"

  find "${APPDIR}" -exec touch --no-dereference "--date=${SOURCE_DATE_EPOCH:+@}${SOURCE_DATE_EPOCH:-now}" '{}' '+'

  /usr/local/bin/mksquashfs "${APPDIR}" AppDir.sqfs -comp zstd -root-owned -noappend -b 128k

  local filename version
  version="$("${PREFIX}/bin/python" -Bsc "from importlib.metadata import version;print(version('${ENTRY}'))")"
  # custom gitrefs that point to a tag should use the same file filename format as builds from untagged commits
  if [[ -n "${GITREF}" && "${version}" != *+* ]]; then
    version="${version%%+*}+0.g$(git -C "/app/source.git" -c core.abbrev=7 rev-parse --short HEAD)"
  fi

  # shellcheck disable=SC2059
  filename="$(printf "${FILENAME}" "${version}")"

  cat /usr/local/share/appimage/runtime AppDir.sqfs > "${filename}"
  chmod +x "${filename}"

  sha256sum "${filename}"
}


build() {
  setup_python
  install_application
  copy_licenses
  finalize
  build_bytecode
  build_appimage

  log "Successfully built appimage"
}

build
