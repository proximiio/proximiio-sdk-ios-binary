//
//  Exports.swift
//  Proximiio (binary distribution wrapper)
//
//  This is the ONLY source file in the binary distribution package. It re-exports
//  the precompiled `ProximiioBinary` module under the public `Proximiio` name so
//  integrators write a single `import Proximiio`; a binaryTarget cannot be
//  imported under a different name, so a one-line source target does the
//  renaming. It declares no dependencies — the framework is self-contained.
//  No proprietary code lives here — the entire SDK implementation ships inside
//  ProximiioBinary.xcframework.
//
@_exported import ProximiioBinary
