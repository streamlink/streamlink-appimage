#!/usr/bin/env bash
set -e

DEST="${1}"
APPDIR="${2}"
ABI="${3}"
APPIMAGETOOL="${4}"
EXCLUDELIST="${5}"
SQUASHFSTOOLS="${6}"
REQUIREMENTSFILE="${7}"


# ----


SELF=$(basename "$(readlink -f "${0}")")
log() {
  echo "[${SELF}] $@"
}
err() {
  log >&2 "$@"
  exit 1
}

[[ -f /.dockerenv ]] || err "This script is supposed to be run from build.sh inside a docker container"

declare -A excludelist
for lib in $(cat "${EXCLUDELIST}" | sed -e '/#.*/d; /^[[:space:]]*|[[:space:]]*$/d; /^$/d'); do
  excludelist["${lib}"]="${lib}"
done

export MAKEFLAGS=-j$(nproc)


# ----


# based on niess/python-appimage (GPLv3)
# https://github.com/niess/python-appimage/blob/d0d64c3316ced7660476d50b5c049f3939213519/python_appimage/appimage/relocate.py


PYTHON="/opt/python/${ABI}/bin/python"
VERSION=$("${PYTHON}" -c 'import sys; print("{}.{}".format(*sys.version_info[:2]))')
PYTHON_X_Y="python${VERSION}"

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

  local rpath=$(patchelf --print-rpath "${path}")
  local relpath="$(realpath --relative-to="$(dirname "${path}")" "${libdir}")"
  if [[ "${relpath}" == "." ]]; then local relpath=""; else local relpath="/${relpath}"; fi
  local expected="\$ORIGIN${relpath}"

  if ! [[ "${rpath}" == "${expected}" ]]; then
    log "Patching RPATH: ${path} (${rpath} -> ${expected})"
    patchelf --set-rpath "${expected}" "${path}"
  fi

  for dep in $(ldd "${path}" 2>/dev/null | grep -E ' => \S+' | sed -E 's/.+ => (.+) \(0x.+/\1/'); do
    local name=$(basename "${dep}")
    [[ -n "${excludelist[${name}]}" ]] && continue
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
  "${PYTHON_BIN}/${PYTHON_X_Y}" -m pip install \
    --disable-pip-version-check \
    --no-cache-dir \
    --no-compile \
    --no-deps \
    --require-hashes \
    -r "${REQUIREMENTSFILE}"
}


build_squashfstools() {
  log "Building squashfs-tools"
  local tempdir=$(mktemp -d)
  tar -C "${tempdir}" --strip-components=1 -xzf "${SQUASHFSTOOLS}"
  yum install -q -y zlib-devel libattr-devel 2>/dev/null
  pushd "${tempdir}/squashfs-tools"
  make \
    GZIP_SUPPORT=1 \
    XZ_SUPPORT=0 \
    LZO_SUPPORT=0 \
    LZMA_XZ_SUPPORT=0 \
    LZ4_SUPPORT=0 \
    ZSTD_SUPPORT=0 \
    XATTR_SUPPORT=1
  make install \
    INSTALL_DIR=/usr/local/bin
  /usr/local/bin/mksquashfs -version | head -n1
  popd
  rm -rf "${tempdir}"
}


build_appimage() {
  log "Fixing appimagetool"
  "./${APPIMAGETOOL}" --appimage-extract >/dev/null

  # replace appimagetool's internal mksquashfs tool with the system's one
  cat > ./squashfs-root/usr/lib/appimagekit/mksquashfs <<EOF
#!/bin/sh
args=\$(echo "\$@" | sed -e 's/-mkfs-fixed-time 0//')
/usr/local/bin/mksquashfs \${args}
EOF

  log "Building appimage"
  [ "${SOURCE_DATE_EPOCH}" ] && mtime="@${SOURCE_DATE_EPOCH}" || mtime=now
  find "${APPDIR}" -exec touch --no-dereference "--date=${mtime}" '{}' '+'
  ARCH=$(uname -m) ./squashfs-root/AppRun \
    --verbose \
    --comp gzip \
    --no-appstream \
    "${APPDIR}" \
    "${DEST}"
  chmod +x "${DEST}"

  log "Successfully built appimage"
  sha256sum "${DEST}"
}


build() {
  build_squashfstools
  setup_python
  install_application
  build_appimage
}

build
