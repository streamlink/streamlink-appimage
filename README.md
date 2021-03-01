Streamlink AppImage
====

Linux [AppImage][appimage] build config for [Streamlink][streamlink]

### How to

1. [Download the latest Streamlink AppImage from the Github releases page.][releases]  
   *Streamlink-AppImages have not been released yet. Check the Github actions build artifacts for now.*
2. **Set the executable flag**  
   This can either be done via a GUI or command line shell.  
   ```bash
   # Note that all AppImage release file names include the
   # release version, Python version, platform name and CPU architecture
   chmod +x ./streamlink-2.0.0-cp39-cp39-manylinux2014_x86_64.AppImage
   ```
3. **Run the AppImage**  
   ```
   ./streamlink-2.0.0-cp39-cp39-manylinux2014_x86_64.AppImage --version
   ```

### What are AppImages

AppImages are portable apps which are independent of the distro and package management. Just set the executable flag on the AppImage file and run it.

Note: Check out [AppImageLauncher][appimagelauncher], which automates the setup and system integration of AppImages. AppImageLauncher may also be available via your distro's package management.

Additional information, like for example how to inspect the AppImage contents or how to extract the contents if [FUSE][appimage-fuse] is not available on your system, can be found in the [AppImage documentation][appimage-documentation].

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
[appimage-documentation]: https://docs.appimage.org/user-guide/run-appimages.html
[appimage-fuse]: https://docs.appimage.org/user-guide/troubleshooting/fuse.html
[streamlink]: https://github.com/streamlink/streamlink
[releases]: https://github.com/bastimeyer/streamlink-appimage/releases
[appimagelauncher]: https://github.com/TheAssassin/AppImageLauncher
[manylinux]: https://github.com/pypa/manylinux
[manylinux2014]: https://github.com/pypa/manylinux#manylinux2014-centos-7-based
