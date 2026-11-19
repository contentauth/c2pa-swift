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
//  CoreTests.swift
//

import C2PA
import Testing

@Suite struct CoreTests {

    @Test func libraryVersion() {
        // For example "c2pa-c/0.91.3 c2pa-rs/0.91.3".
        #expect(C2PA.version.range(of: #"c2pa-rs/\d+\.\d+\.\d+"#, options: .regularExpression) != nil, "version: \(C2PA.version)")
    }

    @Test func errorEnumCases() {
        #expect(C2PAError.api("Test error").localizedDescription == "C2PA API error: Test error")
        #expect(C2PAError.nilPointer.localizedDescription == "Unexpected NULL pointer")
        #expect(C2PAError.utf8.localizedDescription == "Invalid UTF-8 from C2PA")
        #expect(C2PAError.negative(42).localizedDescription == "C2PA negative status 42")
    }
}
