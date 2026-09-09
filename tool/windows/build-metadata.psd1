@{
  # Source revisions and integrity anchors owned by the Windows build.
  FlutterFrameworkRevision = 'd3b14c876900e553bc736ca19295fc09e3853e8e'
  FlutterEngineRevision = 'a804b261645ef8c13eb3d5c44a5c2fb0340c5539'
  FlutterManagerPath = 'engine/src/flutter/shell/platform/windows/egl/manager.cc'
  FlutterManagerBlob = '64fb765bf546190fa610a9bdff007fc881c3cc7e'
  # SHA-256 after applying the owned patch, with text normalized to LF.
  FlutterPatchedManagerSha256 = '805D56051BA6FDACFFC5FCDFE35DD1778E7B3B6BFC6513DCE1C214D1F8703C37'
  FlutterStandardGclientBlob = 'a05a39e336335389321b8a6d855b13bd3fc7892c'
  FlutterEnginePatchPath = 'tool/flutter_engine/0001-windows-direct-composition.patch'
  FlutterEnginePatchSha256 = '6B77FFB23EE3D943717CD8A2D35937A14DA73ACCD027CD4771DB301F324860E5'
  DepotToolsRevision = '13febbee9ece9e03df923f69d540afc63c6db93e'

  # Descriptive component revisions. Integrity hashes remain independently
  # pinned at each build consumer so generated provenance is never trusted.
  MpvVersion = 'mpv-v0.41.0-1042-g7e4cb538a'
  FfmpegVersion = 'N-126474-g1de77bb89'
  LibplaceboVersion = 'v7.371.0 (v7.360.0-124-g3330a51-dirty)'
}
