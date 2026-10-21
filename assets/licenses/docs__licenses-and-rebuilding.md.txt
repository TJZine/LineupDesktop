Lineup Desktop macOS — credits, source and library replacement

This software is based in part on the work of the Independent JPEG Group.
Portions of this software are copyright © 1996–2026 The FreeType Project
(https://freetype.org). All rights reserved.

The macOS runtime uses mpv, FFmpeg, libplacebo and FriBidi under the
LGPL-2.1-or-later terms included in their complete license documents. The Native
runtime section contains every bundled license/notice, including ancillary and
compiled-file notices. Flutter/package licenses and the font OFLs are separate.
This is an engineering description, not a legal sufficiency determination.

You may modify and replace these libraries under their accompanying terms.
The source inventory identifies exact upstream archives/Git commits, including
nested source pins; the lock file contains integrity pins and build flags. The
runtime build-information document identifies the prepared runtime's source and
patch hashes. Its dylib hashes precede app signing. The candidate's companion
manifest separately identifies the final candidate, engine and source archives.
Source materials are prepared locally; their existence here is not a claim
that a public mirror has been published. Keep the matching companion with the
candidate when distributing it. Do not use a source package from another build.

Rebuilding and replacing libraries in a modified copy

1. Work on a separate source checkout and a copy of the app, preserving your
   original app and saved data. Never replace a running app's libraries.
2. Obtain the exact source archives/snapshots listed in the source inventory or
   matching companion. Verify archive SHA-256 values and Git commits. The
   companion records nested submodule snapshots separately; restore them at
   their recorded paths. Keep all source notices with those snapshots.
3. Use the accompanying tool/macos build recipe, lock file, collector, smoke
   helpers and patch series. The build requires macOS with Xcode command-line
   tools, meson, ninja, pkg-config, cmake, Python 3 and Git. Read build-mpv.sh
   for path-neutral environment and prerequisites. The unmodified recipe fetches
   pinned upstream inputs and applies Lineup's patches. For modified sources,
   adapt a separate copy of the recipe/lock to your own source identities;
   do not present a modified runtime as the original verified runtime.
4. Run tool/macos/build-mpv.sh --clean --arch arm64 in that separate checkout.
   The output dist/arm64/lib closure consists of dynamically loaded libraries
   with @rpath install names and sibling @loader_path references. mpv uses
   libmpv.2.dylib; FFmpeg uses libavcodec.63.dylib, libavformat.63.dylib,
   libavutil.61.dylib, libavfilter.12.dylib, libswscale.10.dylib and
   libswresample.7.dylib; libplacebo uses libplacebo.360.dylib; FriBidi uses
   libfribidi.0.dylib. Use a complete compatible dependency closure, not one
   arbitrary dylib from a different architecture or ABI.
5. Build a modified app from source with that runtime selected, or replace the
   matching libraries in Contents/Frameworks of your non-running app copy.
   Include your modified runtime's matching notices, patches and build
   information in Contents/Resources/LineupNativeRuntime. The repository's
   embedder manages this tree as a whole. A changed library invalidates the
   copy's signatures; a locally modified copy requires an appropriate local
   signing/rebuild procedure before launch. App Store copies cannot be changed
   in place while preserving their distributor's signature. Use your own
   modified copy and local build environment. No signing is performed by the
   source-material preparation helper.
6. Retain the modified source, build commands, patches and notices with your
   modified distribution. Validate architecture, loading and behavior yourself;
   original candidate validation does not apply to changed code or libraries.

Flutter engine

The source inventory links the pinned Flutter framework. The engine's evaluated
DEPS graph and macOS patch series are included with the matching companion.
Follow tool/flutter_engine/README.md and desktop_accessibility.py for source
provisioning, patching, verification and local-engine selection. macOS uses the
accessibility repair and may use the separate Apple-linker build patch; its
receipt determines the actual selection. The Windows DirectComposition patch
does not apply to macOS. Dependency tools and SDKs have their own availability
and notices. Full source/patch delivery and this screen do not establish legal,
App Store, patent, trademark or signed-distribution approval.
