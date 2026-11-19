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
//  DataText.swift
//

import Foundation

extension Data {
    /// The bytes as UTF-8 text, or a description of them when they are not,
    /// so a failed expectation still prints something readable.
    var utf8Text: String {
        String(bytes: self, encoding: .utf8) ?? "<\(count) bytes, not UTF-8>"
    }
}
