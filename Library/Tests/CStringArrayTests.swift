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
//  CStringArrayTests.swift
//

import Testing

@testable import C2PA

@Suite struct CStringArrayTests {

    @Test func emptyArrayPassesNull() throws {
        let wasNil = try withCStringArray([]) { $0 == nil }
        #expect(wasNil, "an empty array should pass NULL rather than an empty list")
    }

    @Test func stringsAreNullTerminated() throws {
        let input = ["c2pa.actions", "cawg.training-mining"]
        let readBack = try withCStringArray(input) { pointer -> [String] in
            guard let pointer else { return [] }
            var result: [String] = []
            var index = 0
            // Read until the terminator, exactly as the C layer does.
            while let element = pointer[index] {
                result.append(String(cString: element))
                index += 1
            }
            return result
        }
        #expect(readBack == input, "the C layer must see every string, in order")
    }

    @Test func bodyErrorPropagates() {
        struct Sentinel: Error {}
        #expect(throws: Sentinel.self, "an error thrown by body should reach the caller unchanged") {
            try withCStringArray(["a"]) { _ -> Int in throw Sentinel() }
        }
    }
}
