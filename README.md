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


[appimage]: https://appimage.org/
[streamlink]: https://github.com/streamlink/streamlink
[appimagelauncher]: https://github.com/TheAssassin/AppImageLauncher
