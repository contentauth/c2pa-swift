// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.

import TestShared
import XCTest

@testable import C2PA

// XCTest wrappers for TestShared implementations

// Helper to convert TestResult to XCTest assertions
private func assertTestResult(_ result: TestResult, file: StaticString = #file, line: UInt = #line) throws {
    if result.skipped {
        throw XCTSkip(result.message)
    }
    XCTAssertTrue(result.passed, result.message, file: file, line: line)
}

// MARK: - Stream Tests

final class StreamTests: XCTestCase {
    private let tests = TestShared.StreamTests()

    func testStreamOperations() throws {
        let result = tests.testStreamOperations()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamFileOperations() throws {
        let result = tests.testStreamFileOperations()
        XCTAssertTrue(result.passed, result.message)
    }

    func testWriteOnlyStreams() throws {
        let result = tests.testWriteOnlyStreams()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCustomStreamCallbacks() throws {
        let result = tests.testCustomStreamCallbacks()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamWithLargeData() throws {
        let result = tests.testStreamWithLargeData()
        XCTAssertTrue(result.passed, result.message)
    }

    func testMultipleStreams() throws {
        let result = tests.testMultipleStreams()
        XCTAssertTrue(result.passed, result.message)
    }

    func testFileStreamOptions() throws {
        let result = tests.testFileStreamOptions()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamWithReader() throws {
        let result = tests.testStreamWithReader()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamWithBuilder() throws {
        let result = tests.testStreamWithBuilder()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Builder Tests

final class BuilderTests: XCTestCase {
    private let tests = TestShared.BuilderTests()

    func testBuilderAPI() throws {
        let result = tests.testBuilderAPI()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderNoEmbed() throws {
        let result = tests.testBuilderNoEmbed()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderAddResource() throws {
        let result = tests.testBuilderAddResource()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderAddIngredient() throws {
        let result = tests.testBuilderAddIngredient()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderFromArchive() throws {
        let result = tests.testBuilderFromArchive()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderRemoteURL() throws {
        let result = tests.testBuilderRemoteURL()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderSetIntentCreate() throws {
        let result = tests.testBuilderSetIntentCreate()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderSetIntentEdit() throws {
        let result = tests.testBuilderSetIntentEdit()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderSetIntentUpdate() throws {
        let result = tests.testBuilderSetIntentUpdate()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadIngredient() throws {
        let result = tests.testReadIngredient()
        XCTAssertTrue(result.passed, result.message)
    }

    func testNeedsPlaceholder() throws {
        let result = tests.testNeedsPlaceholder()
        XCTAssertTrue(result.passed, result.message)
    }

    func testDataHashSigningWorkflow() throws {
        let result = tests.testDataHashSigningWorkflow()
        XCTAssertTrue(result.passed, result.message)
    }

    func testDataHashedPlaceholder() throws {
        let result = tests.testDataHashedPlaceholder()
        XCTAssertTrue(result.passed, result.message)
    }

    func testFormatEmbeddable() throws {
        let result = tests.testFormatEmbeddable()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignDataHashedEmbeddable() throws {
        let result = tests.testSignDataHashedEmbeddable()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderHashType() throws {
        let result = tests.testBuilderHashType()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBmffMerkleHashing() throws {
        let result = tests.testBmffMerkleHashing()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Reader Tests

final class ReaderTests: XCTestCase {
    private let tests = TestShared.ReaderTests()

    func testReaderResourceErrorHandling() throws {
        let result = tests.testReaderResourceErrorHandling()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderWithManifestData() throws {
        let result = tests.testReaderWithManifestData()
        XCTAssertTrue(result.passed, result.message)
    }

    func testResourceReading() throws {
        let result = tests.testResourceReading()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderValidation() throws {
        let result = tests.testReaderValidation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderThumbnailExtraction() throws {
        let result = tests.testReaderThumbnailExtraction()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderIngredientExtraction() throws {
        let result = tests.testReaderIngredientExtraction()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderJSONParsing() throws {
        let result = tests.testReaderJSONParsing()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderWithMultipleStreams() throws {
        let result = tests.testReaderWithMultipleStreams()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderRemoteURL() throws {
        let result = tests.testReaderRemoteURL()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderIsEmbedded() throws {
        let result = tests.testReaderIsEmbedded()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderDetailedJSON() throws {
        let result = tests.testReaderDetailedJSON()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderDetailedJSONComparison() throws {
        let result = tests.testReaderDetailedJSONComparison()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Signing Tests

final class SigningTests: XCTestCase {
    private let tests = TestShared.SigningTests()

    func testSignerCreation() throws {
        let result = tests.testSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerWithCallback() throws {
        let result = tests.testSignerWithCallback()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSigningAlgorithms() throws {
        let result = tests.testSigningAlgorithms()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerWithTimestampAuthority() throws {
        let result = tests.testSignerWithTimestampAuthority()
        XCTAssertTrue(result.passed, result.message)
    }

    func testWebServiceSignerCreation() async throws {
        let result = await tests.testWebServiceSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerWithActualSigning() throws {
        let result = tests.testSignerWithActualSigning()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerFromSettingsTOML() throws {
        let result = tests.testSignerFromSettingsTOML()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerFromSettingsJSON() throws {
        let result = tests.testSignerFromSettingsJSON()
        XCTAssertTrue(result.passed, result.message)
    }

    // Edge case tests
    func testDoubleSigningImage() throws {
        let result = tests.testDoubleSigningImage()
        XCTAssertTrue(result.passed, result.message)
    }

    func testZeroByteFile() throws {
        let result = tests.testZeroByteFile()
        XCTAssertTrue(result.passed, result.message)
    }

    func testInvalidCertificateChain() throws {
        let result = tests.testInvalidCertificateChain()
        XCTAssertTrue(result.passed, result.message)
    }

    func testInvalidPrivateKey() throws {
        let result = tests.testInvalidPrivateKey()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Comprehensive Tests

final class ComprehensiveTests: XCTestCase {
    private let tests = TestShared.ComprehensiveTests()

    func testLibraryVersion() throws {
        let result = tests.testLibraryVersion()
        XCTAssertTrue(result.passed, result.message)
    }

    func testErrorHandling() throws {
        let result = tests.testErrorHandling()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadImageWithManifest() throws {
        let result = tests.testReadImageWithManifest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamFromData() throws {
        let result = tests.testStreamFromData()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamFromFile() throws {
        let result = tests.testStreamFromFile()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderCreation() throws {
        let result = tests.testBuilderCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderNoEmbed() throws {
        let result = tests.testBuilderNoEmbed()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderRemoteURL() throws {
        let result = tests.testBuilderRemoteURL()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderAddResource() throws {
        let result = tests.testBuilderAddResource()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderCreation() throws {
        let result = tests.testReaderCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReaderWithTestImage() throws {
        let result = tests.testReaderWithTestImage()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSigningAlgorithms() throws {
        let result = tests.testSigningAlgorithms()
        XCTAssertTrue(result.passed, result.message)
    }

    func testErrorEnumCases() throws {
        let result = tests.testErrorEnumCases()
        XCTAssertTrue(result.passed, result.message)
    }

    func testEndToEndSigning() throws {
        let result = tests.testEndToEndSigning()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadIngredient() throws {
        let result = tests.testReadIngredient()
        XCTAssertTrue(result.passed, result.message)
    }

    func testInvalidFileHandling() throws {
        let result = tests.testInvalidFileHandling()
        XCTAssertTrue(result.passed, result.message)
    }

    func testFileOperationsWithDataDir() throws {
        let result = tests.testFileOperationsWithDataDir()
        XCTAssertTrue(result.passed, result.message)
    }

    func testStreamFileOptions() throws {
        let result = tests.testStreamFileOptions()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Hardware Signing Tests
// These tests require real hardware (Secure Enclave) and keychain entitlements.
// On macOS, the xctest runner lacks the entitlements to access the Secure Enclave
// and Keychain, so these tests are skipped. They run via TestApp on iOS devices.

final class HardwareSigningTests: XCTestCase {
    private let tests = TestShared.HardwareSigningTests()

    private func skipOnMacOS() throws {
        #if os(macOS)
        throw XCTSkip("Hardware signing tests require a host app with Keychain entitlements")
        #endif
    }

    func testSecureEnclaveSignerCreation() throws {
        try skipOnMacOS()
        try assertTestResult(tests.testSecureEnclaveSignerCreation())
    }

    func testSecureEnclaveCSRSigning() async throws {
        try skipOnMacOS()
        try assertTestResult(await tests.testSecureEnclaveCSRSigning())
    }

    func testKeychainSignerCreation() throws {
        try skipOnMacOS()
        try assertTestResult(tests.testKeychainSignerCreation())
    }
}

// MARK: - Manifest Tests

final class ManifestTests: XCTestCase {
    private let tests = TestShared.ManifestTests()

    func testMinimal() throws {
        let result = tests.testMinimal()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCreated() throws {
        let result = tests.testCreated()
        XCTAssertTrue(result.passed, result.message)
    }

    func testEnumRendering() throws {
        let result = tests.testEnumRendering()
        XCTAssertTrue(result.passed, result.message)
    }

    func testRegionOfInterest() throws {
        let result = tests.testRegionOfInterest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testResourceRef() throws {
        let result = tests.testResourceRef()
        XCTAssertTrue(result.passed, result.message)
    }

    func testHashedUri() throws {
        let result = tests.testHashedUri()
        XCTAssertTrue(result.passed, result.message)
    }

    func testUriOrResource() throws {
        let result = tests.testUriOrResource()
        XCTAssertTrue(result.passed, result.message)
    }

    func testMassInit() throws {
        let result = tests.testMassInit()
        XCTAssertTrue(result.passed, result.message)
    }
    func testNewPredefinedActions() throws {
        XCTAssertTrue(tests.testNewPredefinedActions().passed)
    }
    func testActionV2SoftwareAgent() throws {
        XCTAssertTrue(tests.testActionV2SoftwareAgent().passed)
    }
    func testActionNewFields() throws {
        XCTAssertTrue(tests.testActionNewFields().passed)
    }
    func testValidateAndLog() throws {
        XCTAssertTrue(tests.testValidateAndLog().passed)
    }
    func testCustomAssertionLabelValidation() throws {
        XCTAssertTrue(tests.testCustomAssertionLabelValidation().passed)
    }
    func testCreatedFactory() throws {
        XCTAssertTrue(tests.testCreatedFactory().passed)
    }
    func testEditedFactory() throws {
        XCTAssertTrue(tests.testEditedFactory().passed)
    }
    func testMixedAssertions() throws {
        XCTAssertTrue(tests.testMixedAssertions().passed)
    }
    func testAssertionLabels() throws {
        XCTAssertTrue(tests.testAssertionLabels().passed)
    }
    func testToJSON() throws {
        XCTAssertTrue(tests.testToJSON().passed)
    }
    func testToPrettyJSON() throws {
        XCTAssertTrue(tests.testToPrettyJSON().passed)
    }
    func testFromJSON() throws {
        XCTAssertTrue(tests.testFromJSON().passed)
    }
    func testDescription() throws {
        XCTAssertTrue(tests.testDescription().passed)
    }
    func testIngredientParentFactory() throws {
        XCTAssertTrue(tests.testIngredientParentFactory().passed)
    }
    func testIngredientComponentFactory() throws {
        XCTAssertTrue(tests.testIngredientComponentFactory().passed)
    }
    func testIngredientInputToFactory() throws {
        XCTAssertTrue(tests.testIngredientInputToFactory().passed)
    }
    func testValidatorEmptyTitle() throws {
        XCTAssertTrue(tests.testValidatorEmptyTitle().passed)
    }
    func testValidatorEmptyClaimGeneratorInfo() throws {
        XCTAssertTrue(tests.testValidatorEmptyClaimGeneratorInfo().passed)
    }
    func testValidatorOldClaimVersion() throws {
        XCTAssertTrue(tests.testValidatorOldClaimVersion().passed)
    }
    func testValidatorDeprecatedAssertionLabels() throws {
        XCTAssertTrue(tests.testValidatorDeprecatedAssertionLabels().passed)
    }
    func testValidatorCawgAssertionAccepted() throws {
        XCTAssertTrue(tests.testValidatorCawgAssertionAccepted().passed)
    }
    func testValidatorMultipleParents() throws {
        XCTAssertTrue(tests.testValidatorMultipleParents().passed)
    }
    func testValidateJSON() throws {
        XCTAssertTrue(tests.testValidateJSON().passed)
    }
    func testValidateJSONInvalid() throws {
        XCTAssertTrue(tests.testValidateJSONInvalid().passed)
    }
    func testBuilderInitManifestValid() throws {
        XCTAssertTrue(tests.testBuilderInitManifestValid().passed)
    }
    func testBuilderInitManifestInvalid() throws {
        XCTAssertTrue(tests.testBuilderInitManifestInvalid().passed)
    }
    func testBuilderInitJSONInvalid() throws {
        XCTAssertTrue(tests.testBuilderInitJSONInvalid().passed)
    }
}

// MARK: - Certificate Manager Tests

final class CertificateManagerTests: XCTestCase {
    private let tests = TestShared.CertificateManagerTests()

    func testSelfSignedCertificateChainCreation() throws {
        let result = tests.testSelfSignedCertificateChainCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCSRCreationWithPublicKey() throws {
        let result = tests.testCSRCreationWithPublicKey()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCSRCreationWithKeyTag() throws {
        let result = tests.testCSRCreationWithKeyTag()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCSRCreationWithInvalidKeyTag() throws {
        let result = tests.testCSRCreationWithInvalidKeyTag()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSelfSignedChainDirectCall() throws {
        let result = tests.testSelfSignedChainDirectCall()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCSRCreationRejectsEphemeralKeys() throws {
        let result = tests.testCSRCreationRejectsEphemeralKeys()
        XCTAssertTrue(result.passed, result.message)
    }

    func testPersistentKeychainKey() throws {
        let result = tests.testPersistentKeychainKey()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSelfSignedChainWithPersistentKey() throws {
        let result = tests.testSelfSignedChainWithPersistentKey()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Keychain Signer Tests

final class KeychainSignerTests: XCTestCase {
    private let tests = TestShared.KeychainSignerTests()

    func testEd25519RejectedByKeychainSigner() throws {
        let result = tests.testEd25519RejectedByKeychainSigner()
        XCTAssertTrue(result.passed, result.message)
    }

    func testNonExistentKeyFailure() throws {
        let result = tests.testNonExistentKeyFailure()
        XCTAssertTrue(result.passed, result.message)
    }

    func testES256WithKeychainKey() throws {
        let result = tests.testES256WithKeychainKey()
        XCTAssertTrue(result.passed, result.message)
    }

    func testES384AlgorithmMismatchDetection() throws {
        let result = tests.testES384AlgorithmMismatchDetection()
        XCTAssertTrue(result.passed, result.message)
    }

    func testES512AlgorithmMismatchDetection() throws {
        let result = tests.testES512AlgorithmMismatchDetection()
        XCTAssertTrue(result.passed, result.message)
    }

    func testPS256AlgorithmMismatchDetection() throws {
        let result = tests.testPS256AlgorithmMismatchDetection()
        XCTAssertTrue(result.passed, result.message)
    }

    func testPS384AlgorithmMismatchDetection() throws {
        let result = tests.testPS384AlgorithmMismatchDetection()
        XCTAssertTrue(result.passed, result.message)
    }

    func testPS512AlgorithmMismatchDetection() throws {
        let result = tests.testPS512AlgorithmMismatchDetection()
        XCTAssertTrue(result.passed, result.message)
    }

    func testKeychainSigningWorkflow() throws {
        let result = tests.testKeychainSigningWorkflow()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Secure Enclave Signer Tests
// Tests that touch real Secure Enclave hardware are skipped on macOS xctest runner
// (no Keychain entitlements). They run via TestApp on iOS devices.

final class SecureEnclaveSignerTests: XCTestCase {
    private let tests = TestShared.SecureEnclaveSignerTests()

    private func skipHardwareOnMacOS() throws {
        #if os(macOS)
        throw XCTSkip("Secure Enclave tests require a host app with Keychain entitlements")
        #endif
    }

    func testSecureEnclaveSignerConfigCreation() throws {
        try assertTestResult(tests.testSecureEnclaveSignerConfigCreation())
    }

    func testNonES256RejectedBySecureEnclave() throws {
        try assertTestResult(tests.testNonES256RejectedBySecureEnclave())
    }

    func testDeleteNonExistentKey() throws {
        try skipHardwareOnMacOS()
        try assertTestResult(tests.testDeleteNonExistentKey())
    }

    func testDeleteKeyIdempotent() throws {
        try skipHardwareOnMacOS()
        try assertTestResult(tests.testDeleteKeyIdempotent())
    }

    func testSecureEnclaveAvailabilityCheck() throws {
        try skipHardwareOnMacOS()
        try assertTestResult(tests.testSecureEnclaveAvailabilityCheck())
    }

    func testCreateKeyAccessControlValidation() throws {
        try skipHardwareOnMacOS()
        try assertTestResult(tests.testCreateKeyAccessControlValidation())
    }

    func testES256AcceptedBySecureEnclave() throws {
        try skipHardwareOnMacOS()
        try assertTestResult(tests.testES256AcceptedBySecureEnclave())
    }
}

// MARK: - C2PA Convenience Tests

final class ConvenienceTests: XCTestCase {
    private let tests = TestShared.ConvenienceTests()

    func testReadFileWithManifest() throws {
        let result = tests.testReadFileWithManifest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadFileWithDataDir() throws {
        let result = tests.testReadFileWithDataDir()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadFileWithoutManifest() throws {
        let result = tests.testReadFileWithoutManifest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadFileNonExistent() throws {
        let result = tests.testReadFileNonExistent()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadIngredientWithManifest() throws {
        let result = tests.testReadIngredientWithManifest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadIngredientWithoutManifest() throws {
        let result = tests.testReadIngredientWithoutManifest()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReadIngredientWithoutDataDir() throws {
        let result = tests.testReadIngredientWithoutDataDir()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignFile() throws {
        let result = tests.testSignFile()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignFileWithDataDir() throws {
        let result = tests.testSignFileWithDataDir()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignFileWithInvalidManifest() throws {
        let result = tests.testSignFileWithInvalidManifest()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Signer Extended Tests

final class SignerExtendedTests: XCTestCase {
    private let tests = TestShared.SignerExtendedTests()

    func testReserveSizeES256() throws {
        let result = tests.testReserveSizeES256()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReserveSizeWithTSA() throws {
        let result = tests.testReserveSizeWithTSA()
        XCTAssertTrue(result.passed, result.message)
    }

    func testReserveSizeWithCallback() throws {
        let result = tests.testReserveSizeWithCallback()
        XCTAssertTrue(result.passed, result.message)
    }

    func testExportPublicKeyPEM() throws {
        let result = tests.testExportPublicKeyPEM()
        XCTAssertTrue(result.passed, result.message)
    }

    func testExportPublicKeyPEMNonExistentKey() throws {
        let result = tests.testExportPublicKeyPEMNonExistentKey()
        XCTAssertTrue(result.passed, result.message)
    }

    func testLoadSettingsJSON() throws {
        let result = tests.testLoadSettingsJSON()
        XCTAssertTrue(result.passed, result.message)
    }

    func testLoadSettingsTOML() throws {
        let result = tests.testLoadSettingsTOML()
        XCTAssertTrue(result.passed, result.message)
    }

    func testLoadSettingsInvalidJSON() throws {
        let result = tests.testLoadSettingsInvalidJSON()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerFromSignerInfo() throws {
        let result = tests.testSignerFromSignerInfo()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerFromSignerInfoWithTSA() throws {
        let result = tests.testSignerFromSignerInfoWithTSA()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerCallbackInvocation() throws {
        let result = tests.testSignerCallbackInvocation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSignerCallbackErrorPropagation() throws {
        let result = tests.testSignerCallbackErrorPropagation()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Web Service Signer Tests

final class WebServiceSignerTests: XCTestCase {
    private let tests = TestShared.WebServiceSignerTests()

    func testWebServiceSignerCreation() throws {
        let result = tests.testWebServiceSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCreateSignerInvalidURL() async throws {
        let result = await tests.testCreateSignerInvalidURL()
        XCTAssertTrue(result.passed, result.message)
    }

    func testCreateSignerConnectionFailure() async throws {
        let result = await tests.testCreateSignerConnectionFailure()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAsyncSignerCreation() async throws {
        let result = await tests.testAsyncSignerCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAsyncSignerWithTSA() throws {
        let result = tests.testAsyncSignerWithTSA()
        XCTAssertTrue(result.passed, result.message)
    }

    func testWebServiceSignerWithLocalServer() async throws {
        let result = await tests.testWebServiceSignerWithLocalServer()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Assertion Definition Tests

final class AssertionDefinitionTests: XCTestCase {
    private let tests = TestShared.AssertionDefinitionTests()

    func testActionsAssertionDecoding() throws {
        let result = tests.testActionsAssertionDecoding()
        XCTAssertTrue(result.passed, result.message)
    }

    func testActionsAssertionEncoding() throws {
        let result = tests.testActionsAssertionEncoding()
        XCTAssertTrue(result.passed, result.message)
    }

    func testEmptyActionsAssertion() throws {
        let result = tests.testEmptyActionsAssertion()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAssertionMetadataDecoding() throws {
        let result = tests.testAssertionMetadataDecoding()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAssetRefDecoding() throws {
        let result = tests.testAssetRefDecoding()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAllAssertionTypesEncoding() throws {
        let result = tests.testAllAssertionTypesEncoding()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAllAssertionTypesRoundTrip() throws {
        let result = tests.testAllAssertionTypesRoundTrip()
        XCTAssertTrue(result.passed, result.message)
    }

    func testAssertionEquality() throws {
        let result = tests.testAssertionEquality()
        XCTAssertTrue(result.passed, result.message)
    }
    func testCustomAssertionRoundTrip() throws {
        XCTAssertTrue(tests.testCustomAssertionRoundTrip().passed)
    }
    func testTrainingMiningAssertion() throws {
        XCTAssertTrue(tests.testTrainingMiningAssertion().passed)
    }
    func testCawgTrainingMiningAssertion() throws {
        XCTAssertTrue(tests.testCawgTrainingMiningAssertion().passed)
    }
    func testCawgIdentityAssertion() throws {
        XCTAssertTrue(tests.testCawgIdentityAssertion().passed)
    }
    func testCreativeWorkAssertion() throws {
        XCTAssertTrue(tests.testCreativeWorkAssertion().passed)
    }
    func testAnyCodableTypes() throws {
        XCTAssertTrue(tests.testAnyCodableTypes().passed)
    }
    func testAnyCodableEquality() throws {
        XCTAssertTrue(tests.testAnyCodableEquality().passed)
    }
    func testActionsV2Decoding() throws {
        XCTAssertTrue(tests.testActionsV2Decoding().passed)
    }
}

// MARK: - Context Tests

final class ContextTests: XCTestCase {
    private let tests = TestShared.ContextTests()

    func testContextDefaultCreation() throws {
        let result = tests.testContextDefaultCreation()
        XCTAssertTrue(result.passed, result.message)
    }

    func testContextFromSettings() throws {
        let result = tests.testContextFromSettings()
        XCTAssertTrue(result.passed, result.message)
    }

    func testContextCancel() throws {
        let result = tests.testContextCancel()
        XCTAssertTrue(result.passed, result.message)
    }

    func testBuilderFromContext() throws {
        let result = tests.testBuilderFromContext()
        XCTAssertTrue(result.passed, result.message)
    }

    func testSettingsFlowRoundtrip() throws {
        let result = tests.testSettingsFlowRoundtrip()
        XCTAssertTrue(result.passed, result.message)
    }
}

// MARK: - Settings Definition Tests

final class SettingsDefinitionTests: XCTestCase {
    private let tests = TestShared.SettingsDefinitionTests()

    func testRoundTrip() throws {
        XCTAssertTrue(tests.testRoundTrip().passed)
    }
    func testFromJSON() throws {
        XCTAssertTrue(tests.testFromJSON().passed)
    }
    func testPartialSettings() throws {
        XCTAssertTrue(tests.testPartialSettings().passed)
    }
    func testSignerLocalSerialization() throws {
        XCTAssertTrue(tests.testSignerLocalSerialization().passed)
    }
    func testSignerRemoteSerialization() throws {
        XCTAssertTrue(tests.testSignerRemoteSerialization().passed)
    }
    func testIntentSerialization() throws {
        XCTAssertTrue(tests.testIntentSerialization().passed)
    }
    func testEnumValues() throws {
        XCTAssertTrue(tests.testEnumValues().passed)
    }
    func testExistingSettingsJSON() throws {
        XCTAssertTrue(tests.testExistingSettingsJSON().passed)
    }
    func testPrettyJSON() throws {
        XCTAssertTrue(tests.testPrettyJSON().passed)
    }
    func testTrustSettings() throws {
        XCTAssertTrue(tests.testTrustSettings().passed)
    }
    func testCoreSettings() throws {
        XCTAssertTrue(tests.testCoreSettings().passed)
    }
    func testVerifySettings() throws {
        XCTAssertTrue(tests.testVerifySettings().passed)
    }
    func testBuilderSettings() throws {
        XCTAssertTrue(tests.testBuilderSettings().passed)
    }
    func testFullDefinitionRoundTrip() throws {
        XCTAssertTrue(tests.testFullDefinitionRoundTrip().passed)
    }
    func testC2PASettingsFromDefinition() throws {
        XCTAssertTrue(tests.testC2PASettingsFromDefinition().passed)
    }
    func testC2PASettingsLoadDefinition() throws {
        XCTAssertTrue(tests.testC2PASettingsLoadDefinition().passed)
    }
    func testC2PASettingsSetValue() throws {
        XCTAssertTrue(tests.testC2PASettingsSetValue().passed)
    }
    func testC2PASettingsSetValueErrors() throws {
        XCTAssertTrue(tests.testC2PASettingsSetValueErrors().passed)
    }
    func testSignerWithRoles() throws {
        XCTAssertTrue(tests.testSignerWithRoles().passed)
    }
    func testActionTemplateWithIndex() throws {
        XCTAssertTrue(tests.testActionTemplateWithIndex().passed)
    }
    func testTimestampParentScope() throws {
        XCTAssertTrue(tests.testTimestampParentScope().passed)
    }
}

