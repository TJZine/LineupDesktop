#!/usr/bin/env bash
# Build Lineup Desktop's macOS libmpv runtime from pinned upstream sources.
#
# Usage: tool/macos/build-mpv.sh [--clean] [--arch ARCH] [STAGE...]
#
#   --clean      Remove the output directory first (a from-scratch build).
#   --arch ARCH  Build one architecture from LINEUP_RUNTIME_ARCHS (default:
#                every architecture in the pin file).
#   STAGE        Run only these stages (default: all, in order). Stages:
#                fetch moltenvk glslang openssl curl lcms2 dav1d freetype
#                fribidi harfbuzz libass ffmpeg libplacebo mpv dist verify
#
# Every source and flag comes from tool/macos/mpv-runtime.lock. The output
# directory defaults to build/macos-runtime (override with
# LINEUP_MACOS_RUNTIME_DIR):
#
#   downloads/          verified source archives
#   src/                extracted archives and pinned Git checkouts
#   work/ARCH/NAME/     per-component build trees
#   prefix/ARCH/        build-time install tree (absolute install names)
#   dist/ARCH/          shippable runtime: lib/ (@rpath dylibs), include/,
#                       licenses/, patches/, BUILD-INFO.txt
#
# Stages are idempotent: a stage is skipped when its stamp matches the
# current pin and flags. The dist stage always rebuilds dist/ARCH.
#
# Build tools (Xcode command-line tools, meson, ninja, pkg-config, cmake,
# python3, git) may come from anywhere; built libraries never link anything
# outside prefix/ARCH and the macOS SDK. The verify stage enforces that.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
lock_file="$script_dir/mpv-runtime.lock"
patch_dir="$script_dir/mpv-patches"
# shellcheck source=mpv-runtime.lock
source "$lock_file"

out_dir=${LINEUP_MACOS_RUNTIME_DIR:-"$repo_root/build/macos-runtime"}
all_stages=(fetch moltenvk glslang openssl curl lcms2 dav1d freetype fribidi
  harfbuzz libass ffmpeg libplacebo mpv dist verify)

log() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- Arguments ---------------------------------------------------------------

clean=false
archs=("${LINEUP_RUNTIME_ARCHS[@]}")
stages=()
while (($#)); do
  case "$1" in
    --clean) clean=true ;;
    --arch) shift; (($#)) || die "--arch needs a value"; archs=("$1") ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) stages+=("$1") ;;
  esac
  shift
done
((${#stages[@]})) || stages=("${all_stages[@]}")
for stage in "${stages[@]}"; do
  [[ " ${all_stages[*]} " == *" $stage "* ]] || die "unknown stage: $stage"
done
for arch in "${archs[@]}"; do
  [[ " ${LINEUP_RUNTIME_ARCHS[*]} " == *" $arch "* ]] ||
    die "architecture $arch is not listed in LINEUP_RUNTIME_ARCHS"
done

[[ "$(uname -s)" == Darwin ]] || die "this script builds on macOS only"
for tool in xcrun meson ninja pkg-config cmake python3 git curl shasum; do
  command -v "$tool" >/dev/null || die "required build tool not found: $tool"
done

if $clean; then
  log "Removing $out_dir"
  rm -rf "$out_dir"
fi
mkdir -p "$out_dir/downloads" "$out_dir/src"
src_root="$out_dir/src"
jobs=$(sysctl -n hw.ncpu)

# --- Environment -------------------------------------------------------------

# Nothing from the caller's environment may add include, library, or package
# search paths: every dependency must come from prefix/ARCH or the SDK.
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH \
  CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS CPPFLAGS LDFLAGS PKG_CONFIG_PATH \
  PKG_CONFIG_SYSROOT_DIR DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH \
  DYLD_INSERT_LIBRARIES CMAKE_PREFIX_PATH CMAKE_FRAMEWORK_PATH \
  CMAKE_APPBUNDLE_PATH ACLOCAL_PATH OPENSSL_CONF CURL_CA_BUNDLE SSL_CERT_FILE \
  SSL_CERT_DIR

# Use the system tools even if the caller's shell exports wrapper functions.
unset -f grep sed awk tail tr cut find 2>/dev/null || true

export MACOSX_DEPLOYMENT_TARGET=$LINEUP_RUNTIME_DEPLOYMENT_TARGET
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT
CC=$(xcrun --sdk macosx -f clang)
CXX=$(xcrun --sdk macosx -f clang++)
export CC CXX
export CMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/opt/local"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1760659200}
host_arch=$(uname -m)

# Sets the per-architecture variables used by the build stages.
select_arch() {
  arch=$1
  prefix="$out_dir/prefix/$arch"
  work="$out_dir/work/$arch"
  dist="$out_dir/dist/$arch"
  mkdir -p "$prefix/lib/pkgconfig" "$prefix/include" "$work"
  case "$arch" in
    arm64) triple=aarch64-apple-darwin; ffmpeg_arch=aarch64
      openssl_target=darwin64-arm64-cc ;;
    x86_64) triple=x86_64-apple-darwin; ffmpeg_arch=x86_64
      openssl_target=darwin64-x86_64-cc ;;
    *) die "unsupported architecture: $arch" ;;
  esac
  target_flags="-arch $arch -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
  export CFLAGS="$target_flags -O2 -I$prefix/include"
  export CXXFLAGS="$CFLAGS"
  export OBJCFLAGS="$CFLAGS"
  export LDFLAGS="$target_flags -L$prefix/lib -Wl,-headerpad_max_install_names"
  export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
  export PKG_CONFIG_PATH=
  export CMAKE_PREFIX_PATH="$prefix"
  # The SDK's zlib (/usr/lib/libz.1.dylib, part of macOS) has no pkg-config
  # file; libcurl.pc requires one.
  local zlib_version
  zlib_version=$(sed -n 's/^#define ZLIB_VERSION "\(.*\)"$/\1/p' "$SDKROOT/usr/include/zlib.h")
  cat > "$prefix/lib/pkgconfig/zlib.pc" <<EOF
Name: zlib
Description: zlib from the macOS SDK
Version: $zlib_version
Libs: -lz
EOF
  if [[ "$arch" == "$host_arch" ]]; then
    autotools_host=()
    ffmpeg_cross=()
  else
    autotools_host=(--host="$triple")
    ffmpeg_cross=(--enable-cross-compile)
  fi
}

# --- Stamps ------------------------------------------------------------------

# A stamp records the inputs of a stage; a stage reruns when they change.
stamp_value() {
  local name=$1
  {
    printf '%s\n' "$arch" "$MACOSX_DEPLOYMENT_TARGET" "$SDKROOT"
    local var
    for var in VERSION URL SHA256 GIT COMMIT; do
      local ref="${name}_${var}"
      printf '%s=%s\n' "$var" "${!ref:-}"
    done
    local flags_ref="${name}_FLAGS[@]"
    printf '%s\n' "${!flags_ref:-}"
    if [[ "$name" == MPV ]]; then
      cat "$patch_dir"/*.patch
    fi
  } | shasum -a 256 | cut -d' ' -f1
}
stage_done() {
  local stamp="$work/.stamp-$1"
  [[ -f "$stamp" && "$(cat "$stamp")" == "$(stamp_value "$2")" ]]
}
mark_done() { stamp_value "$2" > "$work/.stamp-$1"; }

# --- Sources -----------------------------------------------------------------

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# fetch_archive NAME: download NAME_URL, verify NAME_SHA256, extract to src/.
fetch_archive() {
  local name=$1 url_ref="${1}_URL" sha_ref="${1}_SHA256"
  local url=${!url_ref} sha=${!sha_ref}
  local file="$out_dir/downloads/$(basename "$url")"
  if [[ ! -f "$file" || "$(sha256_of "$file")" != "$sha" ]]; then
    log "Downloading $url"
    curl --fail --location --silent --show-error --retry 3 \
      --proto '=https' --tlsv1.2 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  local actual
  actual=$(sha256_of "$file")
  [[ "$actual" == "$sha" ]] ||
    die "SHA-256 mismatch for $file: expected $sha, got $actual"
  local dest="$src_root/$(archive_dir "$name")"
  local marker="$dest/.lineup-sha256"
  if [[ -f "$marker" && "$(cat "$marker")" == "$sha" ]]; then
    return
  fi
  rm -rf "$dest" "$dest.tmp"
  mkdir -p "$dest.tmp"
  tar -xf "$file" -C "$dest.tmp" --strip-components 1
  printf '%s\n' "$sha" > "$dest.tmp/.lineup-sha256"
  mv "$dest.tmp" "$dest"
}
archive_dir() {
  local version_ref="${1}_VERSION"
  printf '%s-%s' "$(tr '[:upper:]' '[:lower:]' <<<"$1")" "${!version_ref}"
}

# fetch_git NAME [--recursive]: check out NAME_COMMIT of NAME_GIT into src/.
fetch_git() {
  local name=$1 recursive=${2:-}
  local git_ref="${name}_GIT" commit_ref="${name}_COMMIT"
  local url=${!git_ref} commit=${!commit_ref}
  local dest="$src_root/$(archive_dir "$name")"
  if [[ -d "$dest/.git" ]] &&
    [[ "$(git -C "$dest" rev-parse HEAD)" == "$commit" ]] &&
    [[ -f "$dest/.lineup-fetched" ]]; then
    return
  fi
  log "Fetching $url at $commit"
  rm -rf "$dest"
  git init --quiet "$dest"
  git -C "$dest" remote add origin "$url"
  git -C "$dest" -c protocol.version=2 fetch --quiet --depth 1 origin "$commit"
  git -C "$dest" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
  [[ "$(git -C "$dest" rev-parse HEAD)" == "$commit" ]] ||
    die "$url did not check out $commit"
  if [[ "$recursive" == --recursive ]]; then
    git -C "$dest" submodule --quiet update --init --recursive --depth 1
  fi
  touch "$dest/.lineup-fetched"
}

stage_fetch() {
  local name
  for name in GLSLANG OPENSSL CURL LCMS2 DAV1D FREETYPE FRIBIDI HARFBUZZ \
      LIBASS FFMPEG; do
    fetch_archive "$name"
  done
  fetch_git MOLTENVK
  fetch_git LIBPLACEBO --recursive
  fetch_mpv
}

# The mpv checkout is pristine plus tool/macos/mpv-patches/*.patch, applied in
# order. Any patch change re-creates the checkout.
fetch_mpv() {
  local dest="$src_root/$(archive_dir MPV)"
  local patch_sum
  patch_sum=$(cat "$patch_dir"/*.patch | shasum -a 256 | cut -d' ' -f1)
  if [[ -f "$dest/.lineup-patches" && "$(cat "$dest/.lineup-patches")" == "$patch_sum" ]]; then
    return
  fi
  rm -rf "$dest"
  fetch_git MPV
  local patch
  for patch in "$patch_dir"/*.patch; do
    log "Applying $(basename "$patch")"
    git -C "$dest" apply --whitespace=nowarn "$patch"
  done
  printf '%s\n' "$patch_sum" > "$dest/.lineup-patches"
}

# --- Helpers -----------------------------------------------------------------

meson_build() {
  local name=$1 src=$2; shift 2
  local build="$work/$(tr '[:upper:]' '[:lower:]' <<<"$name")"
  rm -rf "$build"
  meson setup "$build" "$src" \
    --prefix="$prefix" --libdir=lib --buildtype=release \
    --default-library=shared --wrap-mode=nofallback \
    -Db_ndebug=true "$@"
  meson compile -C "$build" -j "$jobs"
  meson install -C "$build" --quiet
}

autotools_build() {
  local name=$1 src=$2; shift 2
  local build="$work/$(tr '[:upper:]' '[:lower:]' <<<"$name")"
  rm -rf "$build"
  mkdir -p "$build"
  (cd "$build" && "$src/configure" --prefix="$prefix" --libdir="$prefix/lib" \
    ${autotools_host[@]+"${autotools_host[@]}"} --enable-shared --disable-static "$@")
  make -C "$build" -j "$jobs"
  make -C "$build" install
}

# Stages run in dependency order, so once one stage rebuilds, every later
# stage of the same run rebuilds too.
rebuild_rest=false
run_stage() {
  local stage=$1 name=$2
  if ! $rebuild_rest && stage_done "$stage" "$name"; then
    log "$stage ($arch): up to date"
    return
  fi
  log "$stage ($arch): building"
  "build_$stage"
  mark_done "$stage" "$name"
  rebuild_rest=true
}

# --- Components --------------------------------------------------------------

moltenvk_src() { printf '%s/%s' "$src_root" "$(archive_dir MOLTENVK)"; }

# Checks MoltenVK's ExternalRevisions against the pin file.
check_moltenvk_revisions() {
  local src entry repo expected actual
  src=$(moltenvk_src)
  for entry in "${MOLTENVK_EXTERNAL_REVISIONS[@]}"; do
    repo=${entry%%=*}
    expected=${entry#*=}
    actual=$(tr -d '[:space:]' < "$src/ExternalRevisions/${repo}_repo_revision")
    [[ "$actual" == "$expected" ]] ||
      die "MoltenVK pins $repo at $actual; the pin file says $expected"
  done
}

build_moltenvk() {
  local src
  src=$(moltenvk_src)
  check_moltenvk_revisions
  # fetchDependencies clones the pinned revisions and builds MoltenVK's static
  # build dependencies (SPIRV-Cross, ...). Then build the macOS package the
  # same way MoltenVK's `make macos` does, with our deployment target.
  (cd "$src" && ./fetchDependencies --macos)
  (cd "$src" && xcodebuild build -quiet -project MoltenVKPackaging.xcodeproj \
    -scheme "MoltenVK Package (macOS only)" -destination generic/platform=macOS \
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET")
  local dylib="$src/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
  [[ -f "$dylib" ]] || die "MoltenVK build did not produce $dylib"
  lipo "$dylib" -verify_arch "$arch" || die "libMoltenVK.dylib lacks $arch"
  if [[ "$(lipo -archs "$dylib")" == "$arch" ]]; then
    cp "$dylib" "$prefix/lib/libMoltenVK.dylib"
  else
    lipo "$dylib" -thin "$arch" -output "$prefix/lib/libMoltenVK.dylib"
  fi
  # MoltenVK already installs as @rpath/libMoltenVK.dylib, without header
  # padding for longer load commands, so it is never rewritten.
  [[ "$(otool -D "$prefix/lib/libMoltenVK.dylib" | tail -n 1)" == @rpath/libMoltenVK.dylib ]] ||
    die "unexpected libMoltenVK.dylib install name"

  # Vulkan headers and registry from the exact Vulkan-Headers MoltenVK pins.
  local headers_build="$work/vulkan-headers"
  rm -rf "$headers_build"
  cmake -S "$src/External/Vulkan-Headers" -B "$headers_build" \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DVULKAN_HEADERS_ENABLE_MODULE=OFF \
    -DVULKAN_HEADERS_ENABLE_TESTS=OFF
  cmake --install "$headers_build"

  # libplacebo and mpv link MoltenVK directly instead of the Vulkan loader:
  # the app embeds exactly one Vulkan implementation and never searches for
  # ICD manifests at runtime.
  local api_version
  api_version=$(sed -n 's/^#define VK_HEADER_VERSION_COMPLETE VK_MAKE_API_VERSION(0, \([0-9]*\), \([0-9]*\), VK_HEADER_VERSION)/\1.\2/p' \
    "$prefix/include/vulkan/vulkan_core.h")
  local header_version
  header_version=$(sed -n 's/^#define VK_HEADER_VERSION \([0-9]*\)$/\1/p' \
    "$prefix/include/vulkan/vulkan_core.h")
  [[ -n "$api_version" && -n "$header_version" ]] ||
    die "could not read the Vulkan header version"
  cat > "$prefix/lib/pkgconfig/vulkan.pc" <<EOF
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Vulkan (MoltenVK)
Description: Vulkan provided directly by MoltenVK $MOLTENVK_VERSION
Version: $api_version.$header_version
Libs: -L\${libdir} -lMoltenVK
Cflags: -I\${includedir}
EOF
}

build_glslang() {
  local build="$work/glslang"
  rm -rf "$build"
  cmake -S "$src_root/$(archive_dir GLSLANG)" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON "${GLSLANG_FLAGS[@]}"
  cmake --build "$build" -j "$jobs"
  cmake --install "$build"
}

build_openssl() {
  local src="$src_root/$(archive_dir OPENSSL)"
  local build="$work/openssl"
  rm -rf "$build"
  mkdir -p "$build"
  (cd "$build" && "$src/Configure" "$openssl_target" shared \
    --prefix="$prefix" --libdir=lib \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" "${OPENSSL_FLAGS[@]}")
  make -C "$build" -j "$jobs" build_libs
  make -C "$build" install_dev
}

build_curl() {
  autotools_build CURL "$src_root/$(archive_dir CURL)" \
    "${CURL_FLAGS[@]/#--with-openssl/--with-openssl=$prefix}"
}

build_lcms2() { meson_build LCMS2 "$src_root/$(archive_dir LCMS2)" "${LCMS2_FLAGS[@]}"; }
build_dav1d() { meson_build DAV1D "$src_root/$(archive_dir DAV1D)" "${DAV1D_FLAGS[@]}"; }
build_freetype() { meson_build FREETYPE "$src_root/$(archive_dir FREETYPE)" "${FREETYPE_FLAGS[@]}"; }
build_fribidi() { meson_build FRIBIDI "$src_root/$(archive_dir FRIBIDI)" "${FRIBIDI_FLAGS[@]}"; }
build_harfbuzz() { meson_build HARFBUZZ "$src_root/$(archive_dir HARFBUZZ)" "${HARFBUZZ_FLAGS[@]}"; }
build_libass() { autotools_build LIBASS "$src_root/$(archive_dir LIBASS)" "${LIBASS_FLAGS[@]}"; }

build_ffmpeg() {
  local src="$src_root/$(archive_dir FFMPEG)"
  local build="$work/ffmpeg"
  rm -rf "$build"
  mkdir -p "$build"
  (cd "$build" && "$src/configure" --prefix="$prefix" --libdir="$prefix/lib" \
    --enable-shared --disable-static \
    --arch="$ffmpeg_arch" --target-os=darwin ${ffmpeg_cross[@]+"${ffmpeg_cross[@]}"} \
    --cc="$CC" --cxx="$CXX" --objcc="$CC" --pkg-config=pkg-config \
    --extra-cflags="$CFLAGS" --extra-objcflags="$OBJCFLAGS" \
    --extra-ldflags="$LDFLAGS" "${FFMPEG_FLAGS[@]}")
  make -C "$build" -j "$jobs"
  make -C "$build" install
}

build_libplacebo() {
  # libplacebo looks for the static glslang libraries by file in
  # vulkan-sdk/lib, except libglslang and its default resource limits, which
  # it only finds in compiler default directories. Since glslang 15 libglslang
  # holds the compiler (libSPIRV.a is an empty compatibility stub), so both
  # are linked explicitly.
  LDFLAGS="$LDFLAGS -lglslang -lglslang-default-resource-limits" \
  meson_build LIBPLACEBO "$src_root/$(archive_dir LIBPLACEBO)" \
    -Dvulkan-sdk="$prefix" \
    -Dvulkan-registry="$prefix/share/vulkan/registry/vk.xml" \
    "${LIBPLACEBO_FLAGS[@]}"
}

build_mpv() {
  meson_build MPV "$src_root/$(archive_dir MPV)" \
    -Dswift-flags="-target $arch-apple-macos$MACOSX_DEPLOYMENT_TARGET" \
    "${MPV_FLAGS[@]}"
}

# --- Distribution ------------------------------------------------------------

# Shipped libraries: everything the dynamic-link closure of libmpv needs.
# License texts cover each shipped library plus the code compiled into one:
# glslang and fast_float (libplacebo), SPIRV-Cross and cereal (MoltenVK), and
# the Vulkan headers (libplacebo, mpv, MoltenVK).
license_components=(mpv ffmpeg libplacebo glslang fast_float moltenvk
  spirv-cross cereal vulkan-headers openssl curl lcms2 dav1d freetype fribidi
  harfbuzz libass)
license_files() {
  case "$1" in
    mpv) echo "LICENSE.LGPL Copyright" ;;
    ffmpeg) echo "LICENSE.md COPYING.LGPLv2.1" ;;
    libplacebo) echo "LICENSE" ;;
    moltenvk) echo "LICENSE" ;;
    glslang) echo "LICENSE.txt" ;;
    fast_float) echo "LICENSE-MIT LICENSE-APACHE LICENSE-BOOST" ;;
    vulkan-headers) echo "LICENSE.md LICENSES/Apache-2.0.txt LICENSES/MIT.txt" ;;
    spirv-cross) echo "LICENSE LICENSES/Apache-2.0.txt LICENSES/MIT.txt" ;;
    cereal) echo "LICENSE" ;;
    openssl) echo "LICENSE.txt" ;;
    curl) echo "COPYING" ;;
    lcms2) echo "LICENSE" ;;
    dav1d) echo "COPYING" ;;
    freetype) echo "LICENSE.TXT docs/FTL.TXT" ;;
    fribidi) echo "COPYING" ;;
    harfbuzz) echo "COPYING" ;;
    libass) echo "COPYING" ;;
  esac
}

license_source_dir() {
  local src
  src=$(moltenvk_src)
  case "$1" in
    moltenvk) echo "$src" ;;
    vulkan-headers) echo "$src/External/Vulkan-Headers" ;;
    spirv-cross) echo "$src/External/SPIRV-Cross" ;;
    cereal) echo "$src/External/cereal" ;;
    fast_float) echo "$src_root/$(archive_dir LIBPLACEBO)/3rdparty/fast_float" ;;
    *) echo "$src_root/$(archive_dir "$(tr '[:lower:]-' '[:upper:]_' <<<"$1")")" ;;
  esac
}

build_dist() {
  rm -rf "$dist"
  mkdir -p "$dist/lib" "$dist/include" "$dist/licenses" "$dist/patches"

  # Collect the dylib closure of libmpv inside prefix/lib.
  local queue=("$prefix/lib/libmpv.2.dylib") seen=() lib dep
  while ((${#queue[@]})); do
    lib=${queue[0]}
    queue=("${queue[@]:1}")
    [[ " ${seen[*]-} " == *" $lib "* ]] && continue
    seen+=("$lib")
    while read -r dep; do
      [[ "$dep" == "$prefix/lib/"* || "$dep" == "@rpath/"* ]] || continue
      queue+=("$prefix/lib/$(basename "$dep")")
    done < <(otool -L "$lib" | tail -n +2 | awk '{print $1}')
  done

  for lib in "${seen[@]}"; do
    [[ -f "$lib" ]] || die "missing dependency $lib"
    cp -L "$lib" "$dist/lib/$(basename "$lib")"
  done

  # Install names become @rpath/NAME and dependencies inside the runtime
  # become @rpath/NAME. Build-machine rpaths are removed; a library that
  # depends on a sibling gets @loader_path (Contents/Frameworks in the app).
  # /usr/lib/swift stays: it is where the OS provides the Swift runtime.
  local file name changed
  for file in "$dist/lib/"*.dylib; do
    name=$(basename "$file")
    chmod u+w "$file"
    changed=false
    if [[ "$(otool -D "$file" | tail -n 1)" != "@rpath/$name" ]]; then
      install_name_tool -id "@rpath/$name" "$file"
      changed=true
    fi
    while read -r dep; do
      if [[ "$dep" == "$prefix/lib/"* ]]; then
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file"
        changed=true
      fi
    done < <(otool -L "$file" | tail -n +3 | awk '{print $1}')
    while read -r rpath; do
      case "$rpath" in
        /usr/lib/swift) ;;
        *) install_name_tool -delete_rpath "$rpath" "$file"; changed=true ;;
      esac
    done < <(otool -l "$file" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
    if otool -L "$file" | tail -n +3 | grep -q '@rpath/'; then
      install_name_tool -add_rpath @loader_path "$file"
      changed=true
    fi
    if $changed; then
      codesign --force --sign - "$file"
    fi
  done

  cp -R "$prefix/include/mpv" "$dist/include/mpv"
  cp "$patch_dir"/*.patch "$dist/patches/"

  local component dir f
  for component in "${license_components[@]}"; do
    dir=$(license_source_dir "$component")
    mkdir -p "$dist/licenses/$component"
    for f in $(license_files "$component"); do
      [[ -f "$dir/$f" ]] || die "license file $dir/$f not found"
      cp "$dir/$f" "$dist/licenses/$component/$(basename "$f")"
    done
  done

  write_build_info > "$dist/BUILD-INFO.txt"
}

write_build_info() {
  echo "Lineup Desktop macOS libmpv runtime ($arch)"
  echo "Pin file SHA-256: $(sha256_of "$lock_file")"
  echo "Patches:"
  local patch
  for patch in "$patch_dir"/*.patch; do
    echo "  $(basename "$patch") $(sha256_of "$patch")"
  done
  echo "Sources:"
  local name version_ref url_ref sha_ref git_ref commit_ref license_ref
  for name in MPV FFMPEG LIBPLACEBO GLSLANG MOLTENVK OPENSSL CURL LCMS2 DAV1D \
      FREETYPE FRIBIDI HARFBUZZ LIBASS; do
    version_ref="${name}_VERSION" url_ref="${name}_URL" sha_ref="${name}_SHA256"
    git_ref="${name}_GIT" commit_ref="${name}_COMMIT" license_ref="${name}_LICENSE"
    if [[ -n "${!url_ref:-}" ]]; then
      echo "  $name ${!version_ref} (${!license_ref}) ${!url_ref} sha256:${!sha_ref}"
    else
      echo "  $name ${!version_ref} (${!license_ref}) ${!git_ref} commit:${!commit_ref}"
    fi
  done
  echo "Deployment target: macOS $MACOSX_DEPLOYMENT_TARGET"
  echo "SDK: $(xcrun --sdk macosx --show-sdk-version) ($(xcodebuild -version | tr '\n' ' '))"
  echo "Libraries:"
  local file
  for file in "$dist/lib/"*.dylib; do
    echo "  $(basename "$file") $(sha256_of "$file")"
  done
}

# --- Verification ------------------------------------------------------------

stage_verify() {
  local file dep failed=false
  log "verify ($arch): link closure"
  for file in "$dist/lib/"*.dylib; do
    lipo "$file" -verify_arch "$arch" || { echo "$file lacks $arch"; failed=true; }
    while read -r dep; do
      case "$dep" in
        @rpath/*)
          [[ -f "$dist/lib/${dep#@rpath/}" ]] ||
            { echo "$file: $dep is not in the runtime"; failed=true; } ;;
        /usr/lib/*|/System/Library/*) ;;
        *) echo "$file: forbidden dependency $dep"; failed=true ;;
      esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
    [[ "$(otool -D "$file" | tail -n 1)" == "@rpath/$(basename "$file")" ]] ||
      { echo "$file: install name is not @rpath"; failed=true; }
    # (The first output line is the file's own path.)
    if otool -l "$file" | tail -n +2 | grep -E '/opt/homebrew|/usr/local|'"$out_dir" >/dev/null; then
      echo "$file: load commands reference a build-machine path"; failed=true
    fi
    local minos
    minos=$(otool -l "$file" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
    [[ "$minos" == "$MACOSX_DEPLOYMENT_TARGET" ]] ||
      echo "note: $(basename "$file") minimum macOS is $minos"
  done

  log "verify ($arch): license configuration"
  grep -q '^#define FFMPEG_LICENSE "LGPL version 2.1 or later"' \
    "$work/ffmpeg/config.h" || { echo "FFmpeg is not LGPL 2.1+"; failed=true; }
  grep -Eq '^#define CONFIG_(GPL|NONFREE|VERSION3) 1' "$work/ffmpeg/config.h" &&
    { echo "FFmpeg enables GPL, version3 or nonfree"; failed=true; }
  grep -q "^#define HAVE_GPL 0" "$work/mpv/config.h" ||
    { echo "mpv is not built with gpl=false"; failed=true; }
  if grep -Eq '^#define HAVE_(RUBBERBAND|VAPOURSYNTH|LIBBLURAY|DVDNAV|CDDA|LIBARCHIVE|LUA|JAVASCRIPT|CPLUGINS|UCHARDET|ZIMG|JPEG) 1' \
      "$work/mpv/config.h"; then
    echo "mpv enables an excluded feature"; failed=true
  fi

  log "verify ($arch): runtime loads through @rpath and reports LGPL"
  local smoke="$work/runtime-smoke"
  # The runtime ships only versioned dylib names, so link them by path.
  "$CC" $target_flags -O2 -Wall -Werror -I"$prefix/include" \
    "$script_dir/runtime-smoke.c" "$script_dir/runtime-smoke-layer.m" \
    -framework AppKit -framework Metal -framework QuartzCore \
    -o "$smoke" "$dist/lib"/libmpv.*.dylib \
    "$dist/lib"/libav{codec,format,util,filter}.*.dylib \
    "$dist/lib"/libsw{scale,resample}.*.dylib -Wl,-rpath,"$dist/lib"
  local licenses
  licenses=$("$smoke" --licenses)
  printf '%s\n' "$licenses"
  if grep -E '_license: ' <<<"$licenses" | grep -v 'LGPL version 2.1 or later' >/dev/null; then
    echo "an FFmpeg library does not report LGPL 2.1+"; failed=true
  fi
  if grep '^loaded: ' <<<"$licenses" | grep -v "^loaded: $dist/lib/\|^loaded: $smoke" >/dev/null; then
    echo "a library outside dist/$arch/lib was loaded"; failed=true
  fi

  $failed && die "runtime verification failed for $arch"
  log "verify ($arch): passed"
}

# --- Main --------------------------------------------------------------------

for stage in "${stages[@]}"; do
  if [[ "$stage" == fetch ]]; then
    log "fetch: sources"
    stage_fetch
  fi
done

for a in "${archs[@]}"; do
  select_arch "$a"
  rebuild_rest=false
  for stage in "${stages[@]}"; do
    case "$stage" in
      fetch) ;;
      moltenvk) run_stage moltenvk MOLTENVK ;;
      glslang) run_stage glslang GLSLANG ;;
      openssl) run_stage openssl OPENSSL ;;
      curl) run_stage curl CURL ;;
      lcms2) run_stage lcms2 LCMS2 ;;
      dav1d) run_stage dav1d DAV1D ;;
      freetype) run_stage freetype FREETYPE ;;
      fribidi) run_stage fribidi FRIBIDI ;;
      harfbuzz) run_stage harfbuzz HARFBUZZ ;;
      libass) run_stage libass LIBASS ;;
      ffmpeg) run_stage ffmpeg FFMPEG ;;
      libplacebo) run_stage libplacebo LIBPLACEBO ;;
      mpv) run_stage mpv MPV ;;
      dist) log "dist ($arch)"; build_dist ;;
      verify) stage_verify ;;
    esac
  done
done

log "Done: $out_dir/dist"
