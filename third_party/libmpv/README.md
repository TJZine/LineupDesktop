# libmpv runtime licenses

These immutable license texts are copied into the Windows package. `tool/windows/prepare-mpv.ps1` verifies their SHA-256 values before packaging.

When updating the pinned runtime, update the corresponding source text and hash together:

- `licenses/mpv-LICENSE.LGPL`: <https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/LICENSE.LGPL>
- `licenses/FFmpeg-COPYING.LGPLv3`: <https://github.com/FFmpeg/FFmpeg/blob/884590dd4aad5fcc7a91fbbb7af8a5da80b61d96/COPYING.LGPLv3>
- `licenses/FFmpeg-COPYING.GPLv3`: <https://github.com/FFmpeg/FFmpeg/blob/884590dd4aad5fcc7a91fbbb7af8a5da80b61d96/COPYING.GPLv3>
- `licenses/libplacebo-LICENSE`: <https://github.com/haasn/libplacebo/blob/3330a515d62139259c26239014f286e233bd3a5c/LICENSE>
