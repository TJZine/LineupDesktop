# libmpv runtime licenses

These immutable license texts are copied into the Windows package. `tool/windows/prepare-mpv.ps1` verifies their SHA-256 values before packaging.

When updating the pinned runtime, update the corresponding source text and hash together:

- `licenses/mpv-LICENSE.LGPL`: <https://github.com/mpv-player/mpv/blob/7e4cb538a3f30d25920ad8e87ba6571540fb729f/LICENSE.LGPL>
- `licenses/FFmpeg-COPYING.LGPLv3`: <https://github.com/FFmpeg/FFmpeg/blob/1de77bb8987e2c7364302c91b9f13958e419124e/COPYING.LGPLv3>
- `licenses/FFmpeg-COPYING.GPLv3`: <https://github.com/FFmpeg/FFmpeg/blob/1de77bb8987e2c7364302c91b9f13958e419124e/COPYING.GPLv3>
- `licenses/libplacebo-LICENSE`: <https://github.com/haasn/libplacebo/blob/3330a515d62139259c26239014f286e233bd3a5c/LICENSE>
