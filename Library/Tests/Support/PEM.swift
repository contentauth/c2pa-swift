// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.
//
//  PEM.swift
//

import Foundation
import Security

/// Splits PEM text into the DER bodies of its blocks with the given label.
enum PEM {
    static func blocks(_ label: String, in pem: String) -> [Data] {
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        var result: [Data] = []
        var rest = pem[...]
        while let start = rest.range(of: begin), let stop = rest.range(of: end, range: start.upperBound..<rest.endIndex) {
            let body = rest[start.upperBound..<stop.lowerBound].filter { !$0.isWhitespace }
            if let der = Data(base64Encoded: String(body)) { result.append(der) }
            rest = rest[stop.upperBound...]
        }
        return result
    }

    /// The certificates of a PEM chain, parsed by Security.
    static func certificates(in chain: String) -> [SecCertificate] {
        blocks("CERTIFICATE", in: chain).compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }
}
