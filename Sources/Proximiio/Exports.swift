//
//  Exports.swift
//  Proximiio (binary distribution wrapper)
//
//  This is the ONLY source file in the binary distribution package. It re-exports
//  the precompiled `ProximiioBinary` module under the public `Proximiio` name so
//  integrators write a single `import Proximiio`, and it exists as a source
//  target so SPM links the GRDB dependency into the customer's app (a
//  binaryTarget cannot declare dependencies of its own). No proprietary code
//  lives here — the entire SDK implementation ships inside ProximiioBinary.xcframework.
//
@_exported import ProximiioBinary
