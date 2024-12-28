Changelog - streamlink/streamlink-appimage
====

## 7.1.1-1 (2024-12-28)

- Updated Streamlink to 7.1.1

## 7.1.0-1 (2024-12-28)

- Updated Streamlink to 7.1.0, updated its dependencies
- Updated build images, with Python 3.12.8
- Fixed missing license files after the manylinux\_2\_28 switch

## 7.0.0-1 (2024-11-04)

- Updated Streamlink to 7.0.0, updated its dependencies
- Switched from EOL manylinux2014 to manylinux\_2\_28 (glibc 2.28+ is now required)
- Dropped i686 ("32 bit") builds (unsupported on manylinux\_2\_28)
- Updated build images, with Python 3.12.7

## 6.11.0-1 (2024-10-01)

- Updated Streamlink to 6.11.0, updated its dependencies
- Updated build images, with Python 3.12.6

## 6.10.0-1 (2024-09-06)

- Updated Streamlink to 6.10.0, updated its dependencies

## 6.9.0-1 (2024-08-12)

- Updated Streamlink to 6.9.0, updated its dependencies
- Updated build images, with Python 3.12.5

## 6.8.3-1 (2024-07-11)

- Updated Streamlink to 6.8.3, updated its dependencies

## 6.8.2-2 (2024-07-04)

- Updated build images

## 6.8.2-1 (2024-07-04)

- Updated Streamlink to 6.8.2, updated its dependencies

## 6.8.1-1 (2024-06-18)

- Updated Streamlink to 6.8.1

## 6.8.0-1 (2024-06-17)

- Updated Streamlink to 6.8.0, updated its dependencies
- Updated build images, with Python 3.12.4
- Made AppImages use the bundled cert file from `certifi` (unless `SSL_CERT_FILE` env var is set to a different path)
- Fixed rpath patch issue in build script

## 6.7.4-1 (2024-05-12)

- Updated Streamlink to 6.7.4, updated its dependencies

## 6.7.3-1 (2024-04-14)

- Updated Streamlink to 6.7.3, updated its dependencies
- Updated build images, with Python 3.12.3

## 6.7.1-1 (2024-03-19)

- Updated Streamlink to 6.7.1, updated its dependencies

## 6.7.0-1 (2024-03-09)

- Updated Streamlink to 6.7.0, updated its dependencies

## 6.6.2-1 (2024-02-20)

- Updated Streamlink to 6.6.2

## 6.6.1-1 (2024-02-17)

- Updated Streamlink to 6.6.1

## 6.6.0-1 (2024-02-16)

- Updated Streamlink to 6.6.0, updated its dependencies
- Updated build images, with Python 3.12.2

## 6.5.1-1 (2024-01-16)

- Updated Streamlink to 6.5.1, updated its dependencies
- Switched from Python 3.11 to Python 3.12

## 6.5.0-1 (2023-12-16)

- Updated Streamlink to 6.5.0, updated its dependencies
- Updated build images, with Python 3.11.7
- Added brotli dependency

## 6.4.2-1 (2023-11-28)

- Updated Streamlink to 6.4.2

## 6.4.1-1 (2023-11-22)

- Updated Streamlink to 6.4.1

## 6.4.0-1 (2023-11-21)

- Updated Streamlink to 6.4.0, updated its dependencies

## 6.3.1-1 (2023-10-26)

- Updated Streamlink to 6.3.1

## 6.3.0-1 (2023-10-25)

- Updated Streamlink to 6.3.0, updated its dependencies
- Updated build images, with Python 3.11.6

## 6.2.1-1 (2023-10-03)

- Updated Streamlink to 6.2.1, updated its dependencies
- Updated build images, with Python 3.11.5 and OpenSSL 3.0.11
- Switched build-config format from JSON to YML

## 6.2.0-1 (2023-09-14)

- Updated Streamlink to 6.2.0, updated its dependencies

## 6.1.0-2 (2023-08-28)

- Updated build images, with Python 3.11.5

## 6.1.0-1 (2023-08-16)

- Updated Streamlink to 6.1.0, updated its dependencies
- Added param to get-dependencies script for optional dependency overrides

## 6.0.1-1 (2023-08-02)

- Updated Streamlink to 6.0.1, updated its dependencies

## 6.0.0-1 (2023-07-20)

- Updated Streamlink to 6.0.0, updated its dependencies
- Updated build images, with Python 3.11.4

## 5.5.1-2 (2023-05-22)

- Updated dependencies ([urllib3 2.x](https://urllib3.readthedocs.io/en/2.0.2/v2-migration-guide.html#what-are-the-important-changes), [requests 2.31.0](https://github.com/psf/requests/releases/tag/v2.31.0))

## 5.5.1-1 (2023-05-08)

- Updated Streamlink to 5.5.1, updated its dependencies

## 5.5.0-1 (2023-05-05)

- Updated Streamlink to 5.5.0, updated its dependencies

## 5.4.0-1 (2023-04-12)

- Updated Streamlink to 5.4.0, updated its dependencies
- Updated build images, with Python 3.11.3

## 5.3.1-1 (2023-02-25)

- Updated Streamlink to 5.3.1

## 5.3.0-1 (2023-02-18)

- Updated Streamlink to 5.3.0, updated its dependencies
- Updated build images, with Python 3.11.2

## 5.2.1-1 (2023-01-23)

- Updated Streamlink to 5.2.1, updated its dependencies

## 5.1.2-2 (2022-12-14)

- Switched from Python 3.10 to Python 3.11
- Updated build images, with Python 3.11.1
- Added back compiled Python bytecode of stdlib and site-packages

## 5.1.2-1 (2022-12-03)

- Rewritten the build config and scripts in order to be more consistent with the window-builds repository
- Switched to building Streamlink from git instead of PyPI
- Updated Streamlink to 5.1.2, updated its dependencies
- Updated build images, with new SquashFS and appimagetool versions
- Added nightly builds
- Added changelog

## 5.1.1-3 (2022-11-23)

- Updated Streamlink to 5.1.1
- Removed bytecode from AppImages due to non-deterministic builds
- Renamed `build` dir to `dist`

## 5.1.0-1 (2022-11-14)

- Updated Streamlink to 5.0.0, updated its dependencies
- Updated build images, with Python 3.10.8
- Fixed outdated Python version number in AppImage's appdata

## 5.0.0-1 (2022-09-16)

- Updated Streamlink to 5.0.0, updated its dependencies
- Updated build images, with Python 3.10.7

## 4.3.0-1 (2022-08-15)

- Updated Streamlink to 4.3.0, updated its dependencies
- Updated build images, with Python 3.10.6

## 4.2.0-1 (2022-07-09)

- Updated Streamlink to 4.2.0, updated its dependencies
- Updated build images, with Python 3.10.5

## 4.1.0-2 (2022-06-01)

- Updated dependencies (fixed lxml)

## 4.1.0-1 (2022-05-30)

- Updated Streamlink to 4.1.0, updated its dependencies

## 4.0.0-1 (2022-05-01)

- Updated Streamlink to 4.0.0

## 3.2.0-2 (2022-04-05)

- Updated dependencies
- Updated build images, with Python 3.10.4

## 3.2.0-1 (2022-03-05)

- Updated Streamlink to 3.2.0, updated its dependencies
- Updated build images, with Python 3.10.2

## 3.1.1-2 (2022-02-14)

- Updated dependencies (fixed charset-normalizer)

## 3.1.1-1 (2022-01-25)

- Updated Streamlink to 3.1.1, updated its dependencies

## 3.1.0-1 (2022-01-22)

- Updated Streamlink to 3.1.0, updated its dependencies
- Updated build images, with Python 3.10.1

## 3.0.3-1 (2021-11-28)

- Updated Streamlink to 3.0.3

## 3.0.2-1 (2021-11-25)

- Updated Streamlink to 3.0.2, updated its dependencies

## 3.0.1-1 (2021-11-17)

- Updated Streamlink to 3.0.1, updated its dependencies
- Updated build images

## 2.4.0-1 (2021-09-07)

- Updated Streamlink to 2.4.0, updated its dependencies

## 2.3.0-1 (2021-07-26)

- Updated Streamlink to 2.3.0, updated its dependencies

## 2.2.0-1 (2021-06-19)

- Updated Streamlink to 2.2.0, updated its dependencies

## 2.1.2-1 (2021-05-20)

- Moved build dependencies to new docker images stored on GitHub's new container registry
- Updated Streamlink to 2.1.2, updated its dependencies

## 2.1.1-1 (2021-03-25)

- Updated Streamlink to 2.1.1

## 2.1.0-1 (2021-03-23)

- Updated Streamlink to 2.1.0, updated its dependencies

## 2.0.0-1 (2021-03-07)

- Initial release, based on Streamlink 2.0.0 and Python 3.9
