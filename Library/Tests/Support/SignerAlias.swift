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
//  SignerAlias.swift
//

import C2PA

/// A second reference to a signer that the compiler's region checks cannot
/// see, so the runtime guard on a consumed signer stays testable once the
/// signer itself has been passed as `sending`.
///
/// Unchecked because Signer is not Sendable. A test keeps its alias on the
/// thread that created it.
final class SignerAlias: @unchecked Sendable {
    let signer: Signer

    init(_ signer: Signer) {
        self.signer = signer
    }
}
