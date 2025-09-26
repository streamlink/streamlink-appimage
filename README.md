Streamlink AppImage
====

Linux [AppImage][appimage] build config for [Streamlink][streamlink]

### Contents

- [a Python environment](https://github.com/streamlink/appimage-buildenv)
- [Streamlink and its dependencies](https://github.com/streamlink/streamlink)
- [FFmpeg, for muxing streams (optional)](https://github.com/streamlink/FFmpeg-Builds)

### Supported architectures

- x86\_64
- aarch64

### How to

1. Verify that the system is running on at least [glibc][glibc-wikipedia] [2.28 (Aug 2018)][glibc-release-distro-mapping] (see `ld.so --version`)

2. [Download the AppImage file matching the system's CPU architecture][releases] (see `uname --machine`)

3. Set the executable flag via a file browser or `chmod +x filename` from a command-line shell

   ```bash
   # AppImage file names include the release version,
   # the Python version, platform name and CPU architecture
   chmod +x streamlink-7.0.0-1-cp312-cp312-manylinux_2_28_x86_64.AppImage
   ```

4. Run the AppImage with any command-line parameters supported by Streamlink

   ```bash
   ./streamlink-7.0.0-1-cp312-cp312-manylinux_2_28_x86_64.AppImage --loglevel=debug
   ```

### What are AppImages

AppImages are portable applications which are independent of the Linux distribution in use and its package management. Just set the executable flag on the AppImage file and run it.

The only requirement is having [FUSE][appimage-fuse] installed for being able to mount the contents of the AppImage's SquashFS, which is done automatically. Also, only glibc-based systems are currently supported.

Note: Check out [AppImageLauncher][appimagelauncher], which automates the setup and system integration of AppImages. AppImageLauncher may also be available via your distro's package management.

Additional information, like for example how to inspect the AppImage contents or how to extract the contents if [FUSE][appimage-fuse] is not available on your system, can be found in the [AppImage documentation][appimage-documentation].

### About

These AppImages are built using the [`streamlink/appimage-buildenv-*`][streamlink-appimage-buildenv] docker images, which are based on the [`pypa/manylinux`][manylinux] project and the [`manylinux_2_28`][manylinux_2_28] platform, which is based on AlmaLinux 8. The pre-built Python install and its needed runtime libraries are copied from the docker image (see the manylinux build files) into the AppImages, in addition to the main Python application code, namely Streamlink and its dependencies, which are pulled from GitHub and PyPI. Streamlink's AppImages optionally bundle third-party software, like [Streamlink's own FFmpeg builds][ffmpeg-builds].

### Build

Requirements: `git`, `jq`, `yq`, `docker`  
Supported architectures: `x86_64`, `aarch64`  
Optionally bundled software: `ffmpeg`

```bash
# Build
./build.sh [--arch=$ARCH] [--gitrepo=$GITREPO] [--gitref=$GITREF] [--bundle=...] [--updinfo]

# Get new list of Python dependencies (for updating config.yml)
./get-dependencies.sh [--arch=$ARCH] [--gitrepo=$GITREPO] [--gitref=$GITREF] [depspec...]
```

The AppImages are reproducible when `SOURCE_DATE_EPOCH` is set:

```bash
export SOURCE_DATE_EPOCH=$(git show -s --format=%ct)
```


[appimage]: https://appimage.org/
[appimage-documentation]: https://docs.appimage.org/user-guide/run-appimages.html
[appimage-fuse]: https://docs.appimage.org/user-guide/troubleshooting/fuse.html
[streamlink]: https://github.com/streamlink/streamlink
[streamlink-appimage-buildenv]: https://github.com/streamlink/appimage-buildenv
[ffmpeg-builds]: https://github.com/streamlink/FFmpeg-Builds
[releases]: https://github.com/streamlink/streamlink-appimage/releases
[appimagelauncher]: https://github.com/TheAssassin/AppImageLauncher
[manylinux]: https://github.com/pypa/manylinux
[manylinux_2_28]: https://github.com/pypa/manylinux#manylinux_2_28-almalinux-8-based
[glibc-wikipedia]: https://en.wikipedia.org/wiki/Glibc
[glibc-release-distro-mapping]: https://sourceware.org/glibc/wiki/Release#Distribution_Branch_Mapping
