// swift-tools-version:5.9

// This file is licensed to you under the Apache License, Version 2.0 
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license 
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is 
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF 
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE 
// files for the specific language governing permissions and limitations under
// each license.

import PackageDescription

let package = Package(
    name: "C2PA",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "C2PA",
            targets: ["C2PA"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-certificates.git", .upToNextMajor(from: "1.19.4")),
        .package(url: "https://github.com/apple/swift-asn1.git", .upToNextMajor(from: "1.7.1")),
        // 4.5.1 is the lowest version outside the CVE-2026-43823 range (>= 3.2.0, <= 4.5.0).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "4.5.1"))
    ],
    targets: [
        .binaryTarget(
            name: "C2PAC",
            url: "https://github.com/contentauth/c2pa-swift/releases/download/v0.0.12/C2PAC.xcframework.zip",
            checksum: "a038bc316f7a890d1233e156cc743854cee98e24359a6176fb107088359fe0a8"
        ),
        .target(
            name: "C2PA",
            dependencies: [
                "C2PAC",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Library/Sources"
        )
    ]
)
