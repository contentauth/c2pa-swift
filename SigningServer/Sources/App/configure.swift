// This file is licensed to you under the Apache License, Version 2.0 
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license 
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is 
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF 
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE 
// files for the specific language governing permissions and limitations under
// each license.

import Vapor

public func configure(_ app: Application) async throws {
    // Loopback unless told otherwise; make signing-server-start-lan binds the
    // Mac's LAN address so a phone test run can reach it.
    app.http.server.configuration.hostname = Environment.get("SIGNING_SERVER_HOST") ?? "127.0.0.1"
    app.routes.defaultMaxBodySize = "50mb"
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.certificateService = CertificateSigningService()

    try routes(app)
}

extension Application {
    struct CertificateServiceKey: StorageKey {
        typealias Value = CertificateSigningService
    }

    var certificateService: CertificateSigningService {
        get { self.storage[CertificateServiceKey.self]! }
        set { self.storage[CertificateServiceKey.self] = newValue }
    }
}
