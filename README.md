Streamlink AppImage
====

Linux [AppImage][appimage] build config for [Streamlink][streamlink]

### Contents

- a Python environment
- Streamlink and its dependencies

### Supported architectures

- x86_64
- i686
- aarch64

### How to

1. [Download the latest Streamlink AppImage matching your CPU architecture][releases]

   If unsure, run `uname -m` to check the CPU's architecture.

2. **Set the executable flag**

   This can either be done in a regular file browser, or a command line shell via `chmod +x filename`.

   ```bash
   # AppImage file names include the release version, Python version, platform name and CPU architecture
   chmod +x ./streamlink-2.0.0-1-cp39-cp39-manylinux2014_x86_64.AppImage
   ```

3. **Run the AppImage**

   Set any command-line parameters supported by Streamlink, e.g. `--version`:

   ```bash
   # Run the Streamlink AppImage with any parameter supported by Streamlink
   ./streamlink-2.0.0-1-cp39-cp39-manylinux2014_x86_64.AppImage --version
   ```

### What are AppImages

AppImages are portable apps which are independent of the distro and package management. Just set the executable flag on the AppImage file and run it.

The only requirement is having [FUSE][appimage-fuse] installed for being able to mount the contents of the AppImage's SquashFS, which is done automatically. Also, only glibc-based systems are supported.

Note: Check out [AppImageLauncher][appimagelauncher], which automates the setup and system integration of AppImages. AppImageLauncher may also be available via your distro's package management.

Additional information, like for example how to inspect the AppImage contents or how to extract the contents if [FUSE][appimage-fuse] is not available on your system, can be found in the [AppImage documentation][appimage-documentation].

### About

These AppImages are built using the [`streamlink/appimage-buildenv-*`][streamlink-appimage-buildenv] docker images, which are based on the [`pypa/manylinux`][manylinux] project and the [`manylinux2014`][manylinux2014] platform, which is based on CentOS 7. The pre-built Python install and its needed runtime libraries are copied from the docker image (see the manylinux build files) into the AppImages, in addition to the main Python application code, namely Streamlink and its dependencies, which are pulled from GitHub and PyPI.

### Build

Requirements: `git`, `jq`, `yq`, `docker`  
Supported architectures: `x86_64`, `i686`, `aarch64`

```bash
# Build
./build.sh [$ARCH] [$GITREPO] [$GITREF]

# Get new list of Python dependencies (for updating config.yml)
./get-dependencies.sh [$ARCH] [$GITREPO] [$GITREF] [$OPT_DEPS]
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
[releases]: https://github.com/streamlink/streamlink-appimage/releases
[appimagelauncher]: https://github.com/TheAssassin/AppImageLauncher
[manylinux]: https://github.com/pypa/manylinux
[manylinux2014]: https://github.com/pypa/manylinux#manylinux2014-centos-7-based
