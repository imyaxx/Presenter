# Canonical commands (CLAUDE.md). `verify` is the gate before every commit and in CI.

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := verify

PROJECT := PresenterApp.xcodeproj
SCHEME := PresenterApp
MODEKIT_PATH := Packages/ModeKit
SWIFT_SOURCE_ROOTS := App Packages
DERIVED_DATA := .build/DerivedData
# Naming the architecture avoids xcodebuild's "multiple matching destinations" warning on Apple silicon.
DESTINATION := platform=macOS,arch=$(shell uname -m)
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA) -quiet
REQUIRE_TOOLS := Scripts/require-tools.sh

.PHONY: generate lint format build test verify

generate:
	$(REQUIRE_TOOLS) xcodegen
	xcodegen generate --spec project.yml --quiet

$(PROJECT): project.yml
	$(MAKE) generate

lint:
	$(REQUIRE_TOOLS) swiftlint
	swiftlint lint --strict --quiet

format:
	$(REQUIRE_TOOLS) swift-format
	swift-format format --in-place --recursive --parallel $(SWIFT_SOURCE_ROOTS)

build: $(PROJECT)
	$(REQUIRE_TOOLS) xcodebuild
	$(XCODEBUILD) build

test: $(PROJECT)
	$(REQUIRE_TOOLS) xcodebuild
	swift test --package-path $(MODEKIT_PATH) --quiet
	$(XCODEBUILD) test

verify:
	$(MAKE) generate
	$(MAKE) lint
	$(REQUIRE_TOOLS) swift-format
	swift-format lint --strict --recursive --parallel $(SWIFT_SOURCE_ROOTS)
	$(MAKE) build
	$(MAKE) test
