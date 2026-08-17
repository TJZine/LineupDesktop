# libmpv runtime licenses

These immutable license texts are copied into the Windows package. `tool/windows/prepare-mpv.ps1` verifies their SHA-256 values before packaging.

When updating the pinned runtime, update the corresponding source text and hash together:

- `licenses/mpv-LICENSE.LGPL`: <https://github.com/mpv-player/mpv/blob/7b8915bc1d04c7e1b61184e00c7fbfaab1911e75/LICENSE.LGPL>
- `licenses/FFmpeg-COPYING.LGPLv3`: <https://github.com/FFmpeg/FFmpeg/blob/8b4fad11acfc958dfde29fb0799d3ca1818bbbf7/COPYING.LGPLv3>
- `licenses/libplacebo-LICENSE`: <https://github.com/haasn/libplacebo/blob/22ee762e8e0890fc54068beb670310f0edce7263/LICENSE>
