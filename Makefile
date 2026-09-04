.PHONY: all clean library test-shared test-app example-app publish tests coverage help \
        run-test-app run-example-app signing-server-start signing-server-stop signing-server-status \
        tests-with-server workspace-build test-library test-library-macos lint signing-server-wait signing-server-verify \
        test-summary coverage-lcov validate-version release-tests \
        package-swift update-package-swift create-release-tag docs \
        use-dev-package use-release-package

# Build configuration
CONFIGURATION := Release
SDK := iphoneos
# Default destination - can be overridden from command line
DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
MACOS_DESTINATION ?= platform=macOS

# Disable code signing for unit-test invocations so CI runners without
# a Mac Development certificate can still build and run the test bundles.
TEST_CODE_SIGN_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS=""

# Optional. Build the C2PAC framework from archives in this directory instead
# of downloading them from a c2pa-rs release. Expects the seven
# c2pa-<version>-<triple>.zip files exactly as upstream's
# `make release TARGET=<triple>` produces them; .github/scripts/build-c2pa-archives.sh
# builds that set from a c2pa-rs checkout. Run `make clean` when switching
# directories: Xcode may not re-run the framework build phase when only the
# archive contents changed.
C2PA_ARCHIVE_DIR ?=
C2PA_ARCHIVE_FLAGS := $(if $(C2PA_ARCHIVE_DIR),C2PA_ARCHIVE_DIR="$(abspath $(C2PA_ARCHIVE_DIR))",)

# Default target
all: workspace-build

# Lint the codebase
lint:
	@echo "Running SwiftLint..."
	@swiftlint lint --strict
	@echo "Linting completed."

# Build the C2PA multi-platform library (iOS device + iOS simulator + Mac Catalyst + macOS).
# Produces Library/Frameworks/C2PAC.xcframework and output/C2PAC.xcframework.zip.
library:
	@echo "Building C2PA multi-platform library (iOS device + iOS simulator + Mac Catalyst + macOS)..."
	@SYMROOT=$$(xcodebuild -workspace C2PA.xcworkspace -scheme Library -showBuildSettings 2>/dev/null | grep "^    SYMROOT = " | head -1 | sed 's/.*SYMROOT = //'); \
	echo "Build root: $$SYMROOT"; \
	echo "Building for iOS device..."; \
	xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination "generic/platform=iOS" $(C2PA_ARCHIVE_FLAGS) build; \
	echo "Building for iOS simulator..."; \
	xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination "generic/platform=iOS Simulator" $(C2PA_ARCHIVE_FLAGS) build; \
	echo "Building for Mac Catalyst..."; \
	xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination "generic/platform=macOS,variant=Mac Catalyst" $(C2PA_ARCHIVE_FLAGS) build; \
	echo "Building for macOS..."; \
	xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination "generic/platform=macOS" $(C2PA_ARCHIVE_FLAGS) build; \
	echo "Creating XCFramework from all platform builds..."; \
	DEVICE_DIR="$$SYMROOT/$(CONFIGURATION)-iphoneos"; \
	SIMULATOR_DIR="$$SYMROOT/$(CONFIGURATION)-iphonesimulator"; \
	CATALYST_DIR="$$SYMROOT/$(CONFIGURATION)-maccatalyst"; \
	MACOS_DIR="$$SYMROOT/$(CONFIGURATION)"; \
	if [ -d "$$DEVICE_DIR/C2PAC.framework" ] && [ -d "$$SIMULATOR_DIR/C2PAC.framework" ] && [ -d "$$CATALYST_DIR/C2PAC.framework" ] && [ -d "$$MACOS_DIR/C2PAC.framework" ]; then \
		mkdir -p Library/Frameworks; \
		rm -rf Library/Frameworks/C2PAC.xcframework; \
		xcodebuild -create-xcframework \
			-framework "$$DEVICE_DIR/C2PAC.framework" \
			-framework "$$SIMULATOR_DIR/C2PAC.framework" \
			-framework "$$CATALYST_DIR/C2PAC.framework" \
			-framework "$$MACOS_DIR/C2PAC.framework" \
			-output Library/Frameworks/C2PAC.xcframework; \
		echo "C2PAC.xcframework created in Library/Frameworks/"; \
		echo "Packaging XCFramework for distribution..."; \
		mkdir -p output; \
		rm -rf output/C2PAC.xcframework output/C2PAC.xcframework.zip; \
		cp -R Library/Frameworks/C2PAC.xcframework output/; \
		cd output && zip -ry C2PAC.xcframework.zip C2PAC.xcframework > /dev/null; \
		echo "XCFramework packaged to output/C2PAC.xcframework.zip"; \
	else \
		echo "::error::Failed to find frameworks for all platforms"; \
		echo "Device framework: $$DEVICE_DIR/C2PAC.framework"; \
		ls -la "$$DEVICE_DIR" 2>/dev/null || echo "Device directory not found"; \
		echo "Simulator framework: $$SIMULATOR_DIR/C2PAC.framework"; \
		ls -la "$$SIMULATOR_DIR" 2>/dev/null || echo "Simulator directory not found"; \
		echo "Catalyst framework: $$CATALYST_DIR/C2PAC.framework"; \
		ls -la "$$CATALYST_DIR" 2>/dev/null || echo "Catalyst directory not found"; \
		echo "macOS framework: $$MACOS_DIR/C2PAC.framework"; \
		ls -la "$$MACOS_DIR" 2>/dev/null || echo "macOS directory not found"; \
		exit 1; \
	fi
	@echo "Library build completed."


# Build entire workspace
workspace-build: library test-shared
	@echo "Building entire workspace..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "Workspace build completed."

# Build TestShared framework
test-shared: library
	@echo "Building TestShared framework..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestShared -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "TestShared build completed."

# Build TestApp
test-app: test-shared
	@echo "Building TestApp..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "TestApp build completed."

# Build ExampleApp
example-app: library
	@echo "Building ExampleApp..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "ExampleApp build completed."

# Run library tests only
test-library: library
	@echo "Running library unit tests..."
	@rm -rf TestResults.xcresult
	@xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme Library \
		-destination '$(DESTINATION)' \
		-resultBundlePath TestResults.xcresult \
		-enableCodeCoverage YES \
		$(TEST_CODE_SIGN_FLAGS) \
		$(C2PA_ARCHIVE_FLAGS)
	@echo "Library tests completed."

# Run library tests on macOS
test-library-macos:
	@echo "Building C2PA library for macOS..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination '$(MACOS_DESTINATION)' $(TEST_CODE_SIGN_FLAGS) $(C2PA_ARCHIVE_FLAGS) build
	@echo "Running library unit tests on macOS..."
	@rm -rf TestResults.xcresult
	@xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme Library \
		-destination '$(MACOS_DESTINATION)' \
		-resultBundlePath TestResults.xcresult \
		-enableCodeCoverage YES \
		$(TEST_CODE_SIGN_FLAGS) \
		$(C2PA_ARCHIVE_FLAGS)
	@echo "macOS library tests completed."

# Run all tests including unit and UI tests
tests: test-app
	@echo "Running all tests..."
	@rm -rf TestResults.xcresult
	@xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme TestApp \
		-destination '$(DESTINATION)' \
		-resultBundlePath TestResults.xcresult \
		-enableCodeCoverage YES \
		$(TEST_CODE_SIGN_FLAGS)

# Quick test run (alias for test-library)
test: test-library

# Generate code coverage report
coverage: library
	@echo "Running tests with coverage..."
	@rm -rf TestResults.xcresult
	@xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme Library \
		-configuration Debug \
		-enableCodeCoverage YES \
		-destination '$(DESTINATION)' \
		-resultBundlePath TestResults.xcresult
	@echo "Coverage report generated."

# Run test app
run-test-app: test-app
	@echo "Running test app..."
	@xcrun simctl boot "iPhone 16 Pro" || true
	@xcrun simctl install "iPhone 16 Pro" "$(shell xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs)/TestApp.app"
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.TestApp

# Run example app
run-example-app: example-app
	@echo "Running example app..."
	@xcrun simctl boot "iPhone 16 Pro" || true
	@xcrun simctl install "iPhone 16 Pro" "$(shell xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs)/ExampleApp.app"
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.ExampleApp

# Archive library for distribution
publish: library
	@echo "Archiving library..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration Release archive
	@echo "Library archived. Ready for distribution."

# Swap Package.swift to use the local Library/Frameworks/C2PAC.xcframework
# (so a downstream Mac/iOS app can consume this checkout directly via SPM
# "Add Local Package" without requiring a published release).
use-dev-package:
	@if [ ! -f Package.release.swift.bak ]; then \
		cp Package.swift Package.release.swift.bak; \
		echo "Backed up release Package.swift -> Package.release.swift.bak"; \
	fi
	@cp Package.dev.swift Package.swift
	@echo "Package.swift now points at local Library/Frameworks/C2PAC.xcframework"
	@echo "Run 'make library' first if the XCFramework does not yet exist."
	@echo "Run 'make use-release-package' to restore the release manifest."

# Restore Package.swift to the release variant (URL-based binary target).
use-release-package:
	@if [ -f Package.release.swift.bak ]; then \
		mv Package.release.swift.bak Package.swift; \
		echo "Package.swift restored to release variant (URL-based binary target)"; \
	else \
		echo "No backup at Package.release.swift.bak; assuming Package.swift is already the release variant."; \
	fi

# Validate version format (expects VERSION environment variable)
validate-version:
	@echo "Validating version format..."
	@if [ -z "$(VERSION)" ]; then \
		echo "::error::VERSION environment variable is required"; \
		exit 1; \
	fi
	@if ! echo "$(VERSION)" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+(\.[0-9]+)?)?$$' > /dev/null; then \
		echo "::error::Version must be in format vX.Y.Z or vX.Y.Z-pre.N (e.g., v1.0.0 or v0.9.0-beta.7)"; \
		exit 1; \
	fi
	@echo "Version $(VERSION) is valid."

# Run release tests
release-tests:
	@echo "Running release tests..."
	@if [ -d "example" ]; then \
		cd example && xcodebuild test \
			-scheme C2PAExample \
			-destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
			| xcpretty --test --color || true; \
	else \
		echo "Example directory not found, running library tests instead"; \
		$(MAKE) test-library; \
	fi


# Compute checksum for XCFramework
compute-checksum:
	@echo "Computing checksum for XCFramework..."
	@if [ -f "output/C2PAC.xcframework.zip" ]; then \
		cd output && swift package compute-checksum C2PAC.xcframework.zip; \
	else \
		echo "::error::C2PAC.xcframework.zip not found in output directory"; \
		exit 1; \
	fi

# Package Swift sources
package-swift:
	@echo "Packaging Swift sources..."
	@if [ -d "Library/Sources" ]; then \
		mkdir -p output/C2PA-Swift/Sources/C2PA; \
		cp -R Library/Sources/*.swift output/C2PA-Swift/Sources/C2PA/; \
		cd output && zip -r C2PA-Swift-Package.zip C2PA-Swift/; \
		echo "Swift sources packaged successfully"; \
	else \
		echo "Swift sources packaged (skipped - no sources found)"; \
	fi

# Update Package.swift for release (in-place update)
update-package-swift:
	@echo "Updating Package.swift for release..."
	@if [ -z "$(VERSION)" ]; then \
		echo "::error::VERSION environment variable is required"; \
		exit 1; \
	fi
	@if [ -z "$(CHECKSUM)" ]; then \
		echo "::error::CHECKSUM environment variable is required"; \
		exit 1; \
	fi
	@if [ -z "$(GITHUB_REPOSITORY)" ]; then \
		echo "::error::GITHUB_REPOSITORY environment variable is required"; \
		exit 1; \
	fi
	@if [ -f "Package.swift" ]; then \
		sed -i '' 's#https://github.com/[^/]*/[^/]*/releases/download/v[^/]*/C2PAC.xcframework.zip#https://github.com/$(GITHUB_REPOSITORY)/releases/download/$(VERSION)/C2PAC.xcframework.zip#g' Package.swift; \
		sed -i '' 's#checksum: "[a-f0-9]\{64\}"#checksum: "$(CHECKSUM)"#g' Package.swift; \
		echo "Package.swift updated successfully for release $(VERSION)"; \
	else \
		echo "::error::Package.swift not found"; \
		exit 1; \
	fi

# Tests with signing server
tests-with-server: signing-server-start signing-server-wait test-library signing-server-stop
	@echo "Tests with server completed."

# Start the signing server (setup is handled by Xcode scheme)
signing-server-start:
	@echo "Building and starting signing server..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme SigningServer -configuration Debug build
	@cd SigningServer && SIGNING_SERVER_URL=http://127.0.0.1:8080 SIGNING_SERVER_TOKEN=test-bearer-token-12345 nohup .build/debug/SigningServer > ../signing-server.log 2>&1 &
	@echo "Signing server started"
	@echo "Server running at http://127.0.0.1:8080 with bearer token authentication"

# Stop the signing server
signing-server-stop:
	@echo "Stopping signing server..."
	@pkill -f "SigningServer" || true
	@pkill -f ".build/debug/SigningServer" || true
	@echo "Server stopped."

# Check signing server status
signing-server-status:
	@echo "Checking signing server status..."
	@ps aux | grep -v grep | grep "SigningServer" || echo "Server is not running"

# Wait for signing server to be ready
signing-server-wait:
	@echo "Waiting for signing server to be ready..."
	@max_attempts=30; \
	attempt=0; \
	while [ $$attempt -lt $$max_attempts ]; do \
		if curl -s http://127.0.0.1:8080/health > /dev/null 2>&1; then \
			echo "Signing server is ready"; \
			break; \
		fi; \
		echo "Waiting for server... (attempt $$((attempt + 1))/$$max_attempts)"; \
		sleep 2; \
		attempt=$$((attempt + 1)); \
	done; \
	if [ $$attempt -eq $$max_attempts ]; then \
		echo "Server failed to start after $$max_attempts attempts"; \
		exit 1; \
	fi

# Verify signing server endpoints
signing-server-verify:
	@echo "Testing server endpoints..."
	@curl -v http://127.0.0.1:8080/health || echo "Health check failed"
	@echo ""
	@echo "Server is listening on:"
	@lsof -i :8080 || echo "No process on port 8080"

# Generate test summary from xcresult
test-summary:
	@echo "Generating test summary..."
	@if [ -d "TestResults.xcresult" ]; then \
		echo "=== Test Summary ==="; \
		xcrun xcresulttool get test-results summary --path TestResults.xcresult || true; \
		echo ""; \
		echo "=== Test Results ==="; \
		xcrun xcresulttool get test-results tests --path TestResults.xcresult || true; \
		echo ""; \
		echo "Test results available in TestResults.xcresult"; \
	else \
		echo "TestResults.xcresult not found"; \
		echo "Run 'make test-library' or 'make tests' first to generate test results"; \
	fi

# Export coverage to LCOV format
coverage-lcov:
	@echo "Exporting coverage to LCOV and JSON formats..."
	@if [ ! -d "TestResults.xcresult" ]; then \
		echo "ERROR: TestResults.xcresult not found. Run tests first with 'make test-library'"; \
		exit 1; \
	fi
	@echo "Finding coverage data in xcresult bundle..."
	@PROFDATA_PATH=$$(find TestResults.xcresult -name "*.profdata" -type f 2>/dev/null | head -1); \
	if [ -z "$$PROFDATA_PATH" ]; then \
		echo "Trying DerivedData for profdata..."; \
		DERIVED_DATA=$$(xcodebuild -workspace C2PA.xcworkspace -scheme Library -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs | sed 's|/Build/Products.*||'); \
		PROFDATA_PATH=$$(find "$$DERIVED_DATA" -path "*/Build/ProfileData/*/Coverage.profdata" -type f 2>/dev/null | head -1); \
	fi; \
	echo "Coverage.profdata path: $$PROFDATA_PATH"; \
	BINARY_PATH=$$(find TestResults.xcresult -path "*/Products/Debug-iphonesimulator/C2PA.framework/C2PA" -type f 2>/dev/null | head -1); \
	if [ -z "$$BINARY_PATH" ]; then \
		echo "Trying to find test binary..."; \
		BINARY_PATH=$$(find TestResults.xcresult -name "*.xctest" -type d 2>/dev/null | head -1); \
		if [ -n "$$BINARY_PATH" ]; then \
			BINARY_NAME=$$(basename "$$BINARY_PATH" .xctest); \
			BINARY_PATH="$$BINARY_PATH/$$BINARY_NAME"; \
		fi; \
	fi; \
	if [ -z "$$BINARY_PATH" ]; then \
		echo "Trying DerivedData for binary..."; \
		DERIVED_DATA=$$(xcodebuild -workspace C2PA.xcworkspace -scheme Library -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs | sed 's|/Build/Products.*||'); \
		BINARY_PATH=$$(find "$$DERIVED_DATA" -path "*/C2PATests.xctest/C2PATests" -o -path "*/LibraryTests.xctest/LibraryTests" -type f 2>/dev/null | head -1); \
	fi; \
	echo "Binary path: $$BINARY_PATH"; \
	if [ -n "$$PROFDATA_PATH" ] && [ -n "$$BINARY_PATH" ] && [ -f "$$PROFDATA_PATH" ] && [ -f "$$BINARY_PATH" ]; then \
		echo "Generating LCOV format..."; \
		xcrun llvm-cov export \
			-format=lcov \
			-instr-profile="$$PROFDATA_PATH" \
			"$$BINARY_PATH" \
			> coverage.lcov 2>/dev/null; \
		if [ -s "coverage.lcov" ]; then \
			echo "LCOV coverage report generated ($$(wc -c < coverage.lcov) bytes)"; \
		else \
			echo "LCOV generation failed"; \
		fi; \
		echo "Generating JSON format..."; \
		xcrun xccov view --report --json TestResults.xcresult > coverage.json 2>/dev/null || true; \
		if [ -s "coverage.json" ]; then \
			echo "JSON coverage report generated ($$(wc -c < coverage.json) bytes)"; \
		fi; \
	else \
		echo "Could not find profdata or binary, using xccov for JSON only..."; \
		xcrun xccov view --report --json TestResults.xcresult > coverage.json 2>/dev/null || true; \
		if [ -s "coverage.json" ]; then \
			echo "JSON coverage report generated ($$(wc -c < coverage.json) bytes)"; \
		fi; \
	fi

# Clean test and coverage artifacts
clean-coverage:
	@echo "Cleaning test and coverage artifacts..."
	@rm -rf TestResults.xcresult
	@rm -f coverage.json coverage.lcov coverage.txt
	@rm -f coverage-*.lcov
	@rm -f signing-server.log
	@echo "Test artifacts cleaned."

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestShared clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme SigningServer clean
	@rm -rf SigningServer/.build
	@rm -rf build
	@rm -rf Library/Frameworks/C2PAC.xcframework
	@rm -rf output
	@$(MAKE) clean-coverage
	@echo "Clean complete."

# Build documentation using xcodebuild
docs:
	@echo "Building documentation..."
	@xcodebuild docbuild \
		-workspace C2PA.xcworkspace \
		-scheme Library \
		-destination '$(DESTINATION)' \
		-derivedDataPath .build/DerivedData
	@echo "Documentation built successfully."
	@echo "To view the documentation, open:"
	@echo ".build/DerivedData/Build/Products/Debug-iphonesimulator/C2PA.doccarchive"

# Help target
help:
	@echo "Available targets:"
	@echo "  make              - Build the library (default)"
	@echo "  make lint         - Run SwiftLint on the codebase"
	@echo "  make library      - Build multi-platform XCFramework (iOS device + simulator + Mac Catalyst + macOS)"
	@echo "  make use-dev-package - Swap Package.swift to local-path variant (for testing this checkout as a SPM dependency)"
	@echo "  make use-release-package - Restore Package.swift to URL-based release variant"
	@echo "  make test-shared  - Build the TestShared framework"
	@echo "  make test-app     - Build the TestApp"
	@echo "  make example-app  - Build the ExampleApp"
	@echo "  make workspace-build - Build entire workspace"
	@echo "  make test-library - Run library unit tests only (iOS)"
	@echo "  make test-library-macos - Run library unit tests on macOS"
	@echo "  C2PA_ARCHIVE_DIR=<dir> - With library/test-library/test-library-macos targets: build C2PAC from local c2pa archives instead of a release"
	@echo "  make tests        - Run all tests"
	@echo "  make release-tests - Run tests for release validation"
	@echo "  make test-summary - Generate test summary from xcresult"
	@echo "  make coverage     - Generate test coverage report"
	@echo "  make coverage-lcov - Export coverage to LCOV format"
	@echo "  make run-test-app - Build and run the test app in simulator"
	@echo "  make run-example-app - Build and run the example app in simulator"
	@echo "  make publish      - Prepare library for publishing"
	@echo "  make validate-version - Validate version format (VERSION=vX.Y.Z or vX.Y.Z-pre.N)"
	@echo "  make compute-checksum - Compute checksum for XCFramework"
	@echo "  make package-swift - Package Swift sources"
	@echo "  make update-package-swift - Update Package.swift for release"
	@echo "  make signing-server-start - Start the signing server"
	@echo "  make signing-server-stop  - Stop the signing server"
	@echo "  make signing-server-status - Check server status"
	@echo "  make signing-server-wait - Wait for server to be ready"
	@echo "  make signing-server-verify - Verify server endpoints"
	@echo "  make tests-with-server - Run tests with signing server"
	@echo "  make clean-coverage - Clean test and coverage artifacts"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make docs         - Build API documentation"
	@echo "  make help         - Show this help message"
