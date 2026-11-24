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
//  ValidationStatusCode.swift
//

import Foundation

/// Validation status codes that c2pa-rs reports, as defined by the C2PA 2.3 specification
/// (Section 15) and the CAWG identity assertion specification.
///
/// These codes indicate the result of various validation checks performed on manifests.
/// Codes are organized into three categories: success, informational, and failure.
///
/// The set of codes is open: a newer SDK or another validator can report a code that is
/// not listed here. ``ValidationStatus/code`` therefore holds the code as a string, and
/// ``ValidationStatus/statusCode`` resolves it to a case of this enum when there is one.
///
/// - SeeAlso: [C2PA Specification: returning_validation_results](https://spec.c2pa.org/specifications/specifications/2.3/specs/C2PA_Specification.html#_returning_validation_results)
public enum ValidationStatusCode: String, CaseIterable, Sendable {

    // MARK: - Success Codes

    /// A non-embedded (remote) assertion was accessible at the time of validation.
    case assertionAccessible = "assertion.accessible"

    /// The alternative content representation hash matches.
    case assertionAltContentMatch = "assertion.alternativeContentRepresentation.match"

    /// Hash of a box-based asset matches the hash declared in the BMFF hash assertion.
    case assertionBmffHashMatch = "assertion.bmffHash.match"

    /// The box hash matches the asset.
    case assertionBoxesHashMatch = "assertion.boxesHash.match"

    /// The collection hash matches.
    case assertionCollectionHashMatch = "assertion.collectionHash.match"

    /// Hash of a byte range of the asset matches the hash declared in the data hash assertion.
    case assertionDataHashMatch = "assertion.dataHash.match"

    /// The hash of the referenced assertion in the ingredient's manifest matches the corresponding hash in the assertion's hashed URI in the claim.
    case assertionHashedUriMatch = "assertion.hashedURI.match"

    /// The multi-asset hash matches.
    case assertionMultiAssetHashMatch = "assertion.multiAssetHash.match"

    /// The claim signature is within its validity period.
    case claimSignatureInsideValidity = "claimSignature.insideValidity"

    /// The claim signature referenced in the ingredient's claim validated.
    case claimSignatureValidated = "claimSignature.validated"

    /// The ingredient's claim signature has been validated.
    case ingredientClaimSignatureValidated = "ingredient.claimSignature.validated"

    /// The ingredient's manifest has been validated.
    case ingredientManifestValidated = "ingredient.manifest.validated"

    /// The signing credential's OCSP status is not revoked.
    case signingCredentialOcspNotRevoked = "signingCredential.ocsp.notRevoked"

    /// The signing credential is listed on the validator's trust list.
    case signingCredentialTrusted = "signingCredential.trusted"

    /// The time-stamp credential is listed on the validator's trust list.
    case timeStampTrusted = "timeStamp.trusted"

    /// The time-stamp has been validated.
    case timeStampValidated = "timeStamp.validated"

    /// A CAWG identity claims aggregation credential was validated.
    case cawgIcaCredentialValid = "cawg.ica.credential_valid"

    /// The CAWG identity claims aggregation timestamp was validated.
    case cawgIcaTimeStampValidated = "cawg.ica.time_stamp.validated"

    /// The CAWG identity assertion is well formed.
    case cawgIdentityWellFormed = "cawg.identity.well-formed"

    /// A chain of trust from the CAWG identity assertion's X.509 signing certificate to a trust anchor was verified.
    case cawgX509CredentialTrusted = "cawg.x509.credential.trusted"

    /// The signature over a CAWG identity assertion using an X.509 credential was validated against the signing certificate.
    case cawgX509SignatureValidated = "cawg.x509.signature.validated"

    // MARK: - Informational Codes

    /// The algorithm used is deprecated.
    case algorithmDeprecated = "algorithm.deprecated"

    /// The BMFF hash has additional exclusions present.
    case assertionBmffHashAdditionalExclusions = "assertion.bmffHash.additionalExclusionsPresent"

    /// The box hash has additional exclusions present.
    case assertionBoxesHashAdditionalExclusions = "assertion.boxesHash.additionalExclusionsPresent"

    /// The data hash has additional exclusions present.
    case assertionDataHashAdditionalExclusions = "assertion.dataHash.additionalExclusionsPresent"

    /// The ingredient has unknown provenance.
    case ingredientUnknownProvenance = "ingredient.unknownProvenance"

    /// The OCSP responder for the signing credential is inaccessible.
    case signingCredentialOcspInaccessible = "signingCredential.ocsp.inaccessible"

    /// OCSP checking was skipped for the signing credential.
    case signingCredentialOcspSkipped = "signingCredential.ocsp.skipped"

    /// The OCSP status of the signing credential is unknown.
    case signingCredentialOcspUnknown = "signingCredential.ocsp.unknown"

    /// The time of signing is within the credential validity period.
    case timeOfSigningInsideValidity = "timeOfSigning.insideValidity"

    /// The time of signing is outside the credential validity period.
    case timeOfSigningOutsideValidity = "timeOfSigning.outsideValidity"

    /// The time-stamp credential is invalid.
    case timeStampCredentialInvalid = "timeStamp.credentialInvalid"

    /// The time-stamp is malformed.
    case timeStampMalformed = "timeStamp.malformed"

    /// The time-stamp does not correspond to the contents of the claim.
    case timeStampMismatch = "timeStamp.mismatch"

    /// The signed time-stamp attribute in the signature falls outside the validity window of the signing certificate or the TSA's certificate.
    case timeStampOutsideValidity = "timeStamp.outsideValidity"

    /// The time-stamp credential is not listed on the validator's trust list.
    case timeStampUntrusted = "timeStamp.untrusted"

    /// The issuer of a CAWG identity claims aggregation credential is not on the validator's list of trusted issuers.
    case cawgIcaUntrustedIssuer = "cawg.ica.untrusted_issuer"

    /// The asset manifest cannot be interpreted by this version of the SDK.
    case manifestUnknownProvenance = "manifest.unknownProvenance"

    // MARK: - Failure Codes

    /// The value of an alg header, or other header that specifies an algorithm used to compute the value of another field, is unknown or unsupported.
    case algorithmUnsupported = "algorithm.unsupported"

    /// The action assertion has an ingredient mismatch.
    case assertionActionIngredientMismatch = "assertion.action.ingredientMismatch"

    /// The action assertion is malformed.
    case assertionActionMalformed = "assertion.action.malformed"

    /// The action assertion has missing information.
    case assertionActionMissing = "assertion.action.missing"

    /// An action assertion was redacted when the ingredient's claim was created.
    case assertionActionRedacted = "assertion.action.redacted"

    /// The action assertion has a redaction mismatch.
    case assertionActionRedactionMismatch = "assertion.action.redactionMismatch"

    /// The action assertion is missing a required soft binding.
    case assertionActionSoftBindingMissing = "assertion.action.softBindingMissing"

    /// The alternative content representation is malformed.
    case assertionAltContentMalformed = "assertion.alternativeContentRepresentation.malformed"

    /// The alternative content representation hash does not match.
    case assertionAltContentHashMismatch = "assertion.alternativeContentRepresentation.hashMismatch"

    /// The alternative content representation is missing.
    case assertionAltContentMissing = "assertion.alternativeContentRepresentation.missing"

    /// The BMFF hash is malformed.
    case assertionBmffHashMalformed = "assertion.bmffHash.malformed"

    /// The hash of a box-based asset does not match the hash declared in the BMFF hash assertion.
    case assertionBmffHashMismatch = "assertion.bmffHash.mismatch"

    /// The box hash is malformed.
    case assertionBoxesHashMalformed = "assertion.boxesHash.malformed"

    /// The box hash does not match.
    case assertionBoxesHashMismatch = "assertion.boxesHash.mismatch"

    /// An unknown box was encountered in the box hash.
    case assertionBoxesHashUnknownBox = "assertion.boxesHash.unknownBox"

    /// The CBOR assertion data is invalid.
    case assertionCborInvalid = "assertion.cbor.invalid"

    /// An update manifest contains a cloud data assertion referencing an actions assertion.
    case assertionCloudDataActions = "assertion.cloud-data.actions"

    /// A hard binding assertion is in a cloud data assertion.
    case assertionCloudDataHardBinding = "assertion.cloud-data.hardBinding"

    /// Cloud data assertion label does not match.
    case assertionCloudDataLabelMismatch = "assertion.cloud-data.labelMismatch"

    /// Cloud data assertion is malformed.
    case assertionCloudDataMalformed = "assertion.cloud-data.malformed"

    /// The collection hash has an incorrect file count.
    case assertionCollectionHashIncorrectFileCount = "assertion.collectionHash.incorrectFileCount"

    /// The collection hash has an invalid URI.
    case assertionCollectionHashInvalidUri = "assertion.collectionHash.invalidURI"

    /// The collection hash is malformed.
    case assertionCollectionHashMalformed = "assertion.collectionHash.malformed"

    /// The collection hash does not match.
    case assertionCollectionHashMismatch = "assertion.collectionHash.mismatch"

    /// The data hash is malformed.
    case assertionDataHashMalformed = "assertion.dataHash.malformed"

    /// The hash of a byte range of the asset does not match the hash declared in the data hash assertion.
    case assertionDataHashMismatch = "assertion.dataHash.mismatch"

    /// The external reference has incorrect actions.
    case assertionExternalReferenceActions = "assertion.external-reference.actions"

    /// The external reference was created incorrectly.
    case assertionExternalReferenceCreated = "assertion.external-reference.created"

    /// The external reference has incorrect hard binding.
    case assertionExternalReferenceHardBinding = "assertion.external-reference.hardBinding"

    /// The external reference is malformed.
    case assertionExternalReferenceMalformed = "assertion.external-reference.malformed"

    /// A hard binding assertion was redacted.
    case assertionHardBindingRedacted = "assertion.hardBinding.redacted"

    /// The hash of the referenced assertion in the manifest does not match the corresponding hash in the assertion's hashed URI in the claim.
    case assertionHashedUriMismatch = "assertion.hashedURI.mismatch"

    /// A non-embedded (remote) assertion was inaccessible at the time of validation.
    case assertionInaccessible = "assertion.inaccessible"

    /// The ingredient assertion is malformed.
    case assertionIngredientMalformed = "assertion.ingredient.malformed"

    /// The JSON assertion data is invalid.
    case assertionJsonInvalid = "assertion.json.invalid"

    /// An assertion listed in the ingredient's claim is missing from the ingredient's manifest.
    case assertionMissing = "assertion.missing"

    /// The C2PA metadata assertion contains a field that is not allowed.
    case assertionMetadataDisallowed = "assertion.metadata.disallowed"

    /// The multi-asset hash is malformed.
    case assertionMultiAssetHashMalformed = "assertion.multiAssetHash.malformed"

    /// The multi-asset hash has a missing part.
    case assertionMultiAssetHashMissingPart = "assertion.multiAssetHash.missingPart"

    /// The multi-asset hash does not match.
    case assertionMultiAssetHashMismatch = "assertion.multiAssetHash.mismatch"

    /// Multiple hard bindings were found.
    case assertionMultipleHardBindings = "assertion.multipleHardBindings"

    /// A required field is not present in an assertion.
    case assertionRequiredMissing = "assertion.required.missing"

    /// An assertion was declared as redacted in the ingredient's claim but is still present in the ingredient's manifest.
    case assertionNotRedacted = "assertion.notRedacted"

    /// The assertion is outside the manifest.
    case assertionOutsideManifest = "assertion.outsideManifest"

    /// An assertion was declared as redacted by its own claim.
    case assertionSelfRedacted = "assertion.selfRedacted"

    /// The assertion timestamp is malformed.
    case assertionTimestampMalformed = "assertion.timestamp.malformed"

    /// An assertion was found in the ingredient's manifest that was not explicitly declared in the ingredient's claim.
    case assertionUndeclared = "assertion.undeclared"

    /// The claim CBOR data is invalid.
    case claimCborInvalid = "claim.cbor.invalid"

    /// No hard bindings are present in the claim.
    case claimHardBindingsMissing = "claim.hardBindings.missing"

    /// The claim is malformed.
    case claimMalformed = "claim.malformed"

    /// The referenced claim in the ingredient's manifest cannot be found.
    case claimMissing = "claim.missing"

    /// More than one claim box is present in the manifest.
    case claimMultiple = "claim.multiple"

    /// A required field is not present in the claim.
    case claimRequiredMissing = "claim.required.missing"

    /// The claim signature referenced in the ingredient's claim failed to validate.
    case claimSignatureMismatch = "claimSignature.mismatch"

    /// The claim signature referenced in the ingredient's claim cannot be found in its manifest.
    case claimSignatureMissing = "claimSignature.missing"

    /// The claim signature is outside its validity period.
    case claimSignatureOutsideValidity = "claimSignature.outsideValidity"

    /// A general error occurred.
    case generalError = "general.error"

    /// A hashed URI reference does not match.
    case hashedUriMismatch = "hashedURI.mismatch"

    /// A hashed URI reference is missing.
    case hashedUriMissing = "hashedURI.missing"

    /// The ingredient's claim signature does not match.
    case ingredientClaimSignatureMismatch = "ingredient.claimSignature.mismatch"

    /// The ingredient's claim signature is missing.
    case ingredientClaimSignatureMissing = "ingredient.claimSignature.missing"

    /// The hash of the referenced ingredient claim in the manifest does not match the corresponding hash in the ingredient's hashed URI in the claim.
    case ingredientHashedUriMismatch = "ingredient.hashedURI.mismatch"

    /// The ingredient's manifest does not match.
    case ingredientManifestMismatch = "ingredient.manifest.mismatch"

    /// The ingredient's manifest is missing.
    case ingredientManifestMissing = "ingredient.manifest.missing"

    /// A compressed manifest is invalid.
    case manifestCompressedInvalid = "manifest.compressed.invalid"

    /// The manifest is inaccessible.
    case manifestInaccessible = "manifest.inaccessible"

    /// The manifest is missing.
    case manifestMissing = "manifest.missing"

    /// The manifest has more than one ingredient whose relationship is parentOf.
    case manifestMultipleParents = "manifest.multipleParents"

    /// The manifest timestamp is invalid.
    case manifestTimestampInvalid = "manifest.timestamp.invalid"

    /// The manifest timestamp has wrong parents.
    case manifestTimestampWrongParents = "manifest.timestamp.wrongParents"

    /// The manifest is not referenced via an ingredient assertion.
    case manifestUnreferenced = "manifest.unreferenced"

    /// The manifest is an update manifest, but it contains hard binding or actions assertions.
    case manifestUpdateInvalid = "manifest.update.invalid"

    /// The manifest is an update manifest, but it contains either zero or multiple parentOf ingredients.
    case manifestUpdateWrongParents = "manifest.update.wrongParents"

    /// The signing credential has expired.
    case signingCredentialExpired = "signingCredential.expired"

    /// The signing credential is not valid for signing.
    case signingCredentialInvalid = "signingCredential.invalid"

    /// The signing credential has been revoked (via OCSP).
    case signingCredentialOcspRevoked = "signingCredential.ocsp.revoked"

    /// The signing credential has been revoked by the issuer.
    case signingCredentialRevoked = "signingCredential.revoked"

    /// The signing credential is not listed on the validator's trust list.
    case signingCredentialUntrusted = "signingCredential.untrusted"

    // CAWG identity assertion failures

    /// The DID document for a CAWG identity claims aggregation credential is unavailable.
    case cawgIcaDidUnavailable = "cawg.ica.did_unavailable"

    /// A CAWG identity claims aggregation credential uses an invalid algorithm.
    case cawgIcaInvalidAlg = "cawg.ica.invalid_alg"

    /// A CAWG identity claims aggregation credential has an invalid content type.
    case cawgIcaInvalidContentType = "cawg.ica.invalid_content_type"

    /// A CAWG identity claims aggregation COSE_Sign1 structure is invalid.
    case cawgIcaInvalidCoseSign1 = "cawg.ica.invalid_cose_sign1"

    /// The DID document for a CAWG identity claims aggregation credential is invalid.
    case cawgIcaInvalidDidDocument = "cawg.ica.invalid_did_document"

    /// A CAWG identity claims aggregation issuer is invalid.
    case cawgIcaInvalidIssuer = "cawg.ica.invalid_issuer"

    /// A CAWG identity claims aggregation verifiable credential is invalid.
    case cawgIcaInvalidVerifiableCredential = "cawg.ica.invalid_verifiable_credential"

    /// The CAWG identity claims aggregation signature does not match.
    case cawgIcaSignatureMismatch = "cawg.ica.signature_mismatch"

    /// A CAWG identity claims aggregation signer payload does not match the asset.
    case cawgIcaSignerPayloadMismatch = "cawg.ica.signer_payload.mismatch"

    /// The CAWG identity claims aggregation timestamp is invalid.
    case cawgIcaTimeStampInvalid = "cawg.ica.time_stamp.invalid"

    /// The valid-from time in a CAWG identity claims aggregation credential is invalid.
    case cawgIcaValidFromInvalid = "cawg.ica.valid_from.invalid"

    /// The valid-from time is missing from a CAWG identity claims aggregation credential.
    case cawgIcaValidFromMissing = "cawg.ica.valid_from.missing"

    /// The valid-until time in a CAWG identity claims aggregation credential is invalid.
    case cawgIcaValidUntilInvalid = "cawg.ica.valid_until.invalid"

    /// A CAWG identity assertion references the same assertion more than once.
    case cawgIdentityAssertionDuplicate = "cawg.identity.assertion.duplicate"

    /// A referenced CAWG identity assertion is missing or has a mismatched hash.
    case cawgIdentityAssertionMismatch = "cawg.identity.assertion.mismatch"

    /// The CAWG identity assertion CBOR is not valid.
    case cawgIdentityCborInvalid = "cawg.identity.cbor.invalid"

    /// A CAWG identity assertion does not reference a hard-binding assertion.
    case cawgIdentityHardBindingMissing = "cawg.identity.hard_binding_missing"

    /// The CAWG identity assertion padding is invalid.
    case cawgIdentityPadInvalid = "cawg.identity.pad.invalid"

    /// The CAWG identity assertion signature type is unknown.
    case cawgIdentitySigTypeUnknown = "cawg.identity.sig_type.unknown"

    /// The algorithm that signed a CAWG identity assertion with an X.509 credential is neither allowed nor deprecated.
    case cawgX509AlgorithmUnsupported = "cawg.x509.algorithm.unsupported"

    /// The X.509 certificate that signed a CAWG identity assertion, or its chain, does not meet the certificate profile.
    case cawgX509CredentialInvalid = "cawg.x509.credential.invalid"

    /// No chain of trust leads from the X.509 certificate that signed a CAWG identity assertion to a configured trust anchor.
    case cawgX509CredentialUntrusted = "cawg.x509.credential.untrusted"

    /// The signature over a CAWG identity assertion using an X.509 credential could not be validated against the signing certificate.
    case cawgX509SignatureMismatch = "cawg.x509.signature.mismatch"

    /// The time of signing falls outside the validity period of the X.509 certificate that signed a CAWG identity assertion.
    case cawgX509SignatureOutsideValidity = "cawg.x509.signature.outside_validity"
}
