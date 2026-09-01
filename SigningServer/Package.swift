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
    name: "SigningServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SigningServer", targets: ["SigningServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.19.4"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.7.1"),
        // 4.5.1 is the lowest version outside the CVE-2026-43823 range (>= 3.2.0, <= 4.5.0).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1")
    ],
    targets: [
        .executableTarget(
            name: "SigningServer",
            dependencies: [
                .target(name: "App")
            ],
            path: "Sources/Run"
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
