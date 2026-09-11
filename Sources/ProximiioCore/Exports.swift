//
//  Exports.swift
//  ProximiioCore (binary distribution shim)
//
//  A NAME, NOT A BOUNDARY. This file is byte-for-byte the same re-export as
//  Sources/Proximiio/Exports.swift, because the binary distribution ships ONE
//  flattened module: `ProximiioBinary` contains every library module of the
//  source package. A target that writes `import ProximiioCore` therefore sees
//  the entire SDK surface — the positioning stack, `ProximiioConfiguration`,
//  everything — and links the whole dylib, exactly as `import Proximiio` does.
//
//  It exists so a downstream SwiftPM package (today: proximiio-ios-map-v6's
//  `ProximiioMapCore` target) can name a dependency that matches its own
//  structure and be version-tagged, instead of pinning `branch: "master"` on
//  the source SDK. Nothing more. Making `ProximiioCore` a real boundary means
//  shipping one xcframework per module — see docs/binary-distribution-analysis.md
//  for why that was measured and rejected.
//
//  In the SOURCE package `ProximiioCore` is a genuine module with a genuinely
//  smaller surface. Do not rely on the two behaving alike: code written against
//  the binary shim can use symbols the source product does not vend, and will
//  then fail to build against the source package.
//
@_exported import ProximiioBinary
