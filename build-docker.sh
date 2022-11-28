#!/usr/bin/env bash
set -e

ABI="${1}"
ENTRY="${2}"

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
  echo "[${SELF}] $@"
}
err() {
  log >&2 "$@"
  exit 1
}

[[ -f /.dockerenv ]] || err "This script is supposed to be run from build.sh inside a docker container"

declare -A excludelist
for lib in $(sed -e '/#.*/d; /^[[:space:]]*|[[:space:]]*$/d; /^$/d' /usr/local/share/appimage/excludelist); do
  excludelist["${lib}"]="${lib}"
done

libraries=()


# ----


# based on niess/python-appimage (GPLv3)
# https://github.com/niess/python-appimage/blob/d0d64c3316ced7660476d50b5c049f3939213519/python_appimage/appimage/relocate.py

DEST=out.AppImage

PYTHON="/opt/python/${ABI}/bin/python"
VERSION=$("${PYTHON}" -B -c 'import sys; print("{}.{}".format(*sys.version_info[:2]))')
PYTHON_X_Y="python${VERSION}"

APPDIR=AppDir
APPDIR_BIN="${APPDIR}/usr/bin"
APPDIR_LIB="${APPDIR}/usr/lib"

HOST_PREFIX=$("${PYTHON}" -c 'import sys; print(sys.prefix)')
HOST_BIN="${HOST_PREFIX}/bin"
HOST_INC="${HOST_PREFIX}/include/${PYTHON_X_Y}"
HOST_LIB="${HOST_PREFIX}/lib"
HOST_PKG="${HOST_LIB}/${PYTHON_X_Y}"

PYTHON_PREFIX="${APPDIR}/opt/${PYTHON_X_Y}"
PYTHON_BIN="${PYTHON_PREFIX}/bin"
PYTHON_INC="${PYTHON_PREFIX}/include/${PYTHON_X_Y}"
PYTHON_LIB="${PYTHON_PREFIX}/lib"
PYTHON_PKG="${PYTHON_LIB}/${PYTHON_X_Y}"


patch_binary() {
  local path="${1}"
  local libdir="${2}"
  local recursive="${3:-false}"

  local newrpath
  local rpath=$(patchelf --print-rpath "${path}")
  local relpath="$(realpath --relative-to="$(dirname -- "${path}")" "${libdir}")"
  if [[ "${relpath}" == "." ]]; then newrpath="\$ORIGIN"; else newrpath="\$ORIGIN/${relpath}"; fi

  if [[ "${rpath}" != "${newrpath}" ]]; then
    log "Patching RPATH: ${path} (\"${rpath}\" -> \"${newrpath}\")"
    patchelf --set-rpath "${newrpath}" "${path}"
  fi

  for dep in $(ldd "${path}" 2>/dev/null | grep -E ' => \S+' | sed -E 's/.+ => (.+) \(0x.+/\1/'); do
    local name=$(basename "${dep}")
    [[ -n "${excludelist[${name}]}" ]] && continue
    local target="${libdir}/${name}"
    if ! [[ -f "${target}" ]]; then
      log "Bundling library: ${dep} (${target})"
      libraries+=("${dep}")
      install -Dm777 "${dep}" "${target}"
      if [[ "${recursive}" == true ]]; then
        patch_binary "${target}" "${libdir}" true
      fi
    fi
  done
}


setup_python() {
  log "Setting up python install"

  install -Dm777 "${HOST_BIN}/${PYTHON_X_Y}" "${PYTHON_BIN}/${PYTHON_X_Y}"

  mkdir -p "${PYTHON_PKG}" "${PYTHON_INC}"
  cp -aT "${HOST_PKG}" "${PYTHON_PKG}"
  cp -aT "${HOST_INC}" "${PYTHON_INC}"
  rm -rf \
    "${PYTHON_LIB}/lib/${PYTHON_X_Y}.a" \
    "${PYTHON_PKG}/"{test,dist-packages,config-*-linux-*} \
    || true

  mkdir -p "${APPDIR_BIN}"
  ln -rs "${PYTHON_BIN}/${PYTHON_X_Y}" "${APPDIR_BIN}/${PYTHON_X_Y}"
  ln -sfT "${PYTHON_X_Y}" "${APPDIR_BIN}/python"
  ln -sfT "${PYTHON_X_Y}" "${APPDIR_BIN}/python3"

  mkdir -p "${APPDIR_LIB}"
  patch_binary "${PYTHON_BIN}/${PYTHON_X_Y}" "${APPDIR_LIB}" false
  for file in $(find "${PYTHON_PKG}/lib-dynload" -type f -name '*.so' -print); do
    patch_binary "${file}" "${APPDIR_LIB}" false
  done
  for file in $(find "${APPDIR_LIB}" -type f -name 'lib*.so*' -print); do
    patch_binary "${file}" "${APPDIR_LIB}" true
  done
}


install_application() {
  export PYTHONHASHSEED=0

  log "Installing dependencies"
  "${PYTHON_BIN}/${PYTHON_X_Y}" -B -m pip install \
    "${PIP_ARGS[@]}" \
    --require-hashes \
    -r requirements.txt

  log "Installing application"
  # fix git permission issue when getting version string via versioningit
  git config --global --add safe.directory /app/source.git
  "${PYTHON_BIN}/${PYTHON_X_Y}" -B -m pip install \
    --verbose \
    "${PIP_ARGS[@]}" \
    /app/source.git
}

get_version() {
  log "Reading version string"
  "${PYTHON_BIN}/${PYTHON_X_Y}" -Bsc "from importlib.metadata import version;print(version('${ENTRY}'))" \
    | tee version.txt
}

cleanup() {
  log "Removing unneeded dependencies"
  "${PYTHON_BIN}/${PYTHON_X_Y}" -B -m pip uninstall \
    -y \
    -r <("${HOST_BIN}/${PYTHON_X_Y}" -B -m pip list --format=freeze)

  log "Deleting bytecode"
  # Delete all bytecode, as the missing bytecode of the stdlib is being built undeterministically when running pip:
  # For some very weird reason, the PYTHONHASHSEED and PYTHONDONTWRITEBYTECODE env vars and the -B flag don't show any effect,
  # and recompiling bytecode using the compileall module is undeterministic as well.
  # So just delete all bytecode for now. :(
  # This seems to be only the case on cp38, cp38 and cp310
  find "${PYTHON_LIB}" -type d -name __pycache__ -print0 | xargs -0 rm -r
}


copy_licenses() {
  log "Finding library licenses"
  declare -A packages
  for library in "${libraries[@]}"; do
    local package=$(repoquery --installed --file "${library}")
    if [[ -z "${package}" ]]; then
      log "Could not find package for library ${library}"
      continue
    fi
    packages["${package}"]="${library}"
  done

  for package in "${!packages[@]}"; do
    if ! find_licenses "${package}" >/dev/null; then
      log "Could not find license files for package ${package}"
      for dependency in $(repoquery --installed --requires --resolve "${package}"); do
        if [[ -z "${packages["${dependency}"]}" ]]; then
          # ignore dependencies with files in the excludelist
          for depfile in $(repoquery --installed --list "${dependency}"); do
            [[ "${excludelist["$(basename "${depfile}")"]}" ]] && continue 2
          done
          echo "Attempting to find licenses in dependency ${dependency}"
          packages["${dependency}"]="${packages["${package}"]}"
        fi
      done
    fi
  done

  log "Re-installing packages without suppressing license files: ${!packages[@]}"
  yum reinstall -q -y --setopt=tsflags= "${!packages[@]}"

  for package in "${!packages[@]}"; do
    log "Copying license files for package ${package}"
    for file in $(find_licenses "${package}" || true); do
      install -vDm644 "${file}" "${APPDIR}${file}"
    done
  done
}

find_licenses() {
  repoquery --installed --list "${1}" \
    | grep -Ei '^/usr/share/(doc|licenses)/.*(copying|licen[cs]e|readme|terms).*'
}


build_appimage() {
  log "Building appimage"
  [ "${SOURCE_DATE_EPOCH}" ] && mtime="@${SOURCE_DATE_EPOCH}" || mtime=now
  find "${APPDIR}" -exec touch --no-dereference "--date=${mtime}" '{}' '+'
  ARCH=$(uname -m) /usr/local/bin/appimagetool \
    --verbose \
    --comp gzip \
    --no-appstream \
    "${APPDIR}" \
    "${DEST}"
  chmod +x "${DEST}"
}


build() {
  setup_python
  copy_licenses
  install_application
  get_version
  cleanup
  build_appimage

  log "Successfully built appimage"
}

build
