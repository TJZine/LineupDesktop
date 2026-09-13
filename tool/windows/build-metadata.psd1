@{
  # Source revisions and integrity anchors owned by the Windows build.
  FlutterFrameworkRevision = '9584c6713b324636289d067944a46fd6b49df14b'
  FlutterEngineRevision = '06a2e2a110089dff50fe635cffd2a61e1b24fbcd'
  FlutterManagerPath = 'engine/src/flutter/shell/platform/windows/egl/manager.cc'
  FlutterManagerBlob = '64fb765bf546190fa610a9bdff007fc881c3cc7e'
  # SHA-256 after applying the owned patch, with text normalized to LF.
  FlutterPatchedManagerSha256 = '3F4EEE4CA2D9F07C3FF15F56A4FC28596B18B8AF91FCA5E255A01351E0DEE4DD'
  FlutterStandardGclientBlob = 'a05a39e336335389321b8a6d855b13bd3fc7892c'
  FlutterEnginePatchPath = 'tool/flutter_engine/0001-windows-direct-composition.patch'
  FlutterEnginePatchSha256 = '3A6AA524780826F250352425BE146C6D2549FCCB11B87F993F250EFD4DBC1DCB'
  DepotToolsRevision = '13febbee9ece9e03df923f69d540afc63c6db93e'

  # Descriptive component revisions. Integrity hashes remain independently
  # pinned at each build consumer so generated provenance is never trusted.
  MpvVersion = 'mpv-v0.41.0-1042-g7e4cb538a'
  FfmpegVersion = 'N-126474-g1de77bb89'
  LibplaceboVersion = 'v7.371.0 (v7.360.0-124-g3330a51-dirty)'
}
