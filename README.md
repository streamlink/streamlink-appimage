Streamlink AppImage
====

Linux [AppImage][appimage] build config for [Streamlink][streamlink]

### WORK IN PROGRESS

Until the build config has been finalized, available AppImages can be downloaded as build artifacts from Github actions.

### What are AppImages

AppImages are portable apps which are independent of the distro and package management. Just set the executable flag on the AppImage file and run it.

Note: Check out [AppImageLauncher][appimagelauncher], which automates the setup and system integration of AppImages. AppImageLauncher may also be available via your distro's package management.

Download the AppImage which matches your system's architecture.

```bash
# make AppImage file executable
# note that AppImage release file names include the release version
chmod +x ./streamlink-123.45.67-x86_64.AppImage
# run the app
./streamlink-123.45.67-x86_64.AppImage
```

### About

These AppImages are built using the [`pypa/manylinux`][manylinux] project and the [`manylinux2014`][manylinux2014] platform (based on CentOS 7). The pre-built Python 3.9 install and its needed runtime libraries are copied from the docker container (see the manylinux build files and CentOS 7 packages for the available sources) into the AppImages, in addition to the main Python application code, namely Streamlink and its dependencies, which are pulled from PyPI.

### Build

Requirements: `curl`, `jq`, `docker`

```bash
# Build
./build.sh x86_86
./build.sh i686
./build.sh aarch64

# Get new list of Python dependencies (for updating config.json)
./get-dependencies.sh streamlink==VERSION x86_64
./get-dependencies.sh streamlink==VERSION i686
./get-dependencies.sh streamlink==VERSION aarch64
```

The AppImages are reproducible when `SOURCE_DATE_EPOCH` is set:

```bash
export SOURCE_DATE_EPOCH=$(git show -s --format=%ct)
```


[appimage]: https://appimage.org/
[streamlink]: https://github.com/streamlink/streamlink
[appimagelauncher]: https://github.com/TheAssassin/AppImageLauncher
[manylinux]: https://github.com/pypa/manylinux
[manylinux2014]: https://github.com/pypa/manylinux#manylinux2014-centos-7-based
