# ``C2PA``

Swift bindings for the C2PA (Coalition for Content Provenance and Authenticity) specification.

## Overview

C2PA is a Swift framework that provides a native iOS and macOS interface to the C2PA standard, enabling you to read, create, and verify content provenance information in digital media files.

The library wraps the Rust-based C2PA implementation via C bindings, providing a type-safe Swift API for working with content credentials.

## Topics

### Reading Content Credentials

- ``C2PA/readFile(at:)``
- ``Reader``

### Creating and Signing Content

- ``C2PA/signFile(source:destination:manifestJSON:signerInfo:)``
- ``Builder``
- ``Signer``

### Signing Methods

- ``KeychainSigner``
- ``SecureEnclaveSigner``
- ``WebServiceSigner``

### Certificate Management

- ``CertificateManager``
- ``SignerInfo``
- ``SigningAlgorithm``

### Data Streaming

- ``Stream``
- ``StreamOptions``

### Error Handling

- ``C2PAError``

## Getting Started

### Reading Content Credentials

To read C2PA manifest data from a file:

```swift
import C2PA

do {
    let manifestJSON = try C2PA.readFile(at: imageURL)
    print("Manifest: \(manifestJSON)")
} catch {
    print("Failed to read manifest: \(error)")
}
```

### Signing Content

To sign a file with content credentials:

```swift
import C2PA

let signerInfo = SignerInfo(
    certificatePEM: certPEM,
    privateKeyPEM: keyPEM,
    algorithm: .es256,
    tsaURL: "http://timestamp.digicert.com"
)

do {
    try C2PA.signFile(
        source: sourceURL,
        destination: destURL,
        manifestJSON: manifestJSON,
        signerInfo: signerInfo
    )
} catch {
    print("Failed to sign file: \(error)")
}
```

### Using Hardware-Backed Signing

For enhanced security using the Secure Enclave:

```swift
import C2PA

let signer = try SecureEnclaveSigner(
    keyTag: "com.example.c2pa.key",
    certificateChainPEM: certChainPEM,
    tsaURL: "http://timestamp.digicert.com"
)

let builder = try Builder(manifestJSON: manifestJSON)
try builder.sign(
    format: "image/jpeg",
    source: sourceStream,
    destination: destStream,
    signer: signer
)
```

## Platform Requirements

- iOS 16.0+ / macOS 14.0+
- Xcode 13.0+
- Swift 5.9+

## See Also

- [C2PA Specification](https://c2pa.org/specifications/specifications/1.0/specs/C2PA_Specification.html)
- [Content Authenticity Initiative](https://contentauthenticity.org/)
