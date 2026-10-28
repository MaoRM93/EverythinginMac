CXX = clang++
CXXFLAGS = -std=c++20 -O2 -Wall -Wextra
FRAMEWORKS = -framework CoreServices
CORE_SRCS = $(wildcard MacEverything/Core/*.cpp)
RE2_PREFIX = /opt/homebrew/opt/re2
RE2_CFLAGS = -I$(RE2_PREFIX)/include
RE2_LDFLAGS = -L$(RE2_PREFIX)/lib -lre2

# === Build targets ===
.PHONY: test test-fast test-slow test-all test-asan test-tsan build clean app sign dmg daemon help

test_all: test_all.cpp $(CORE_SRCS)
	$(CXX) $(CXXFLAGS) $(RE2_CFLAGS) $(FRAMEWORKS) $(RE2_LDFLAGS) -IMacEverything/Core $^ -o $@

benchmark: benchmark.cpp $(CORE_SRCS)
	$(CXX) $(CXXFLAGS) $(RE2_CFLAGS) $(FRAMEWORKS) $(RE2_LDFLAGS) $^ -o $@

maceverything-daemon: MacEverything/CLI/daemon_main.cpp $(CORE_SRCS)
	$(CXX) $(CXXFLAGS) $(RE2_CFLAGS) $(FRAMEWORKS) $(RE2_LDFLAGS) -IMacEverything/Core $^ -o $@

daemon: maceverything-daemon

# === Lint targets ===
lint-bridge:
	$(CXX) $(CXXFLAGS) -fsyntax-only -fobjc-arc -x objective-c++ \
		-IMacEverything/Core -IMacEverything/Bridge \
		MacEverything/Bridge/MacSearchBridge.mm \
		MacEverything/Bridge/MacSearchBridge+Content.mm

# === Sanitizer targets ===
test-asan: test_all.cpp $(CORE_SRCS)
	$(CXX) -std=c++20 -O1 -g -fsanitize=address -fno-omit-frame-pointer $(RE2_CFLAGS) $(FRAMEWORKS) $(RE2_LDFLAGS) -IMacEverything/Core $^ -o test_all_asan
	./test_all_asan --fast

test-tsan: test_all.cpp $(CORE_SRCS)
	$(CXX) -std=c++20 -O1 -g -fsanitize=thread $(RE2_CFLAGS) $(FRAMEWORKS) $(RE2_LDFLAGS) -IMacEverything/Core $^ -o test_all_tsan
	./test_all_tsan --fast

# === Test targets ===
test: test-fast

test-fast: test_all lint-bridge
	./test_all --fast

test-slow: test_all
	./test_all --slow

test-all: test_all
	./test_all

# === Xcode build ===
app:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
		-project MacEverything.xcodeproj -scheme MacEverything \
		-configuration Release build SYMROOT=build

# === Signing ===
# A stable identity is required for Full Disk Access to survive rebuilds.
# Ad-hoc signing ties the TCC grant to the binary hash, so every rebuild
# silently invalidates the permission. Sign with the local self-signed
# "MacEverything Local Signing" identity instead.
SIGN_IDENTITY ?= MacEverything Local Signing
SIGN_KEYCHAIN ?= $(HOME)/Library/Keychains/me-local.keychain-db
APP_BUNDLE = build/Release/MacEverything.app

# The dedicated keychain keeps its password in a 0600 file next to it, so
# packaging never prompts for it and does not depend on remembering it.
SIGN_PASS ?= $(shell cat $(HOME)/Library/Keychains/.me-local-pass 2>/dev/null)

# SIGN_PASS is the local keychain password; it is filled in automatically from
# the password file, or can be overridden on the command line, e.g.
# `make dmg SIGN_PASS='…'`.
sign: app
	@test -n "$(SIGN_PASS)" || { \
		echo "SIGN_PASS is not set; refusing to ad-hoc sign (it breaks Full Disk Access)."; \
		echo "Re-run as: make dmg SIGN_PASS='<signing keychain password>'"; \
		exit 1; }
	@security unlock-keychain -p "$(SIGN_PASS)" "$(SIGN_KEYCHAIN)"
	codesign --force --sign "$(SIGN_IDENTITY)" --keychain "$(SIGN_KEYCHAIN)" \
		--timestamp=none "$(APP_BUNDLE)/Contents/MacOS/MacEverythingMCP"
	codesign --force --sign "$(SIGN_IDENTITY)" --keychain "$(SIGN_KEYCHAIN)" \
		--timestamp=none --entitlements MacEverything/MacEverything.entitlements "$(APP_BUNDLE)"
	codesign --verify --deep --strict "$(APP_BUNDLE)"

# === Package ===
# The DMG contains the app plus an Applications shortcut so the user can drag
# it into place in one gesture.
dmg: sign
	@rm -rf build/dmg-staging
	@mkdir -p build/dmg-staging
	@ditto "$(APP_BUNDLE)" build/dmg-staging/MacEverything.app
	@ln -s /Applications build/dmg-staging/Applications
	-hdiutil detach /Volumes/MacEverything 2>/dev/null
	hdiutil create -volname MacEverything \
		-srcfolder build/dmg-staging \
		-ov -format UDZO MacEverything.dmg

# === Cleanup ===
clean:
	rm -f test_all test_all_asan test_all_tsan benchmark maceverything-daemon
	rm -rf build/

# === Help ===
help:
	@echo "Available targets:"
	@echo "  make test       - Run fast unit tests (alias for test-fast)"
	@echo "  make test-fast  - Run fast unit tests (Part 3, 3b, 3c, 3d, 3e, 5)"
	@echo "  make test-slow  - Run slow integration tests (Part 1, 4, 6)"
	@echo "  make test-all   - Run all tests"
	@echo "  make app        - Build MacEverything.app via Xcode"
	@echo "  make dmg        - Build + package into DMG"
	@echo "  make daemon     - Build CLI daemon (maceverything-daemon)"
	@echo "  make benchmark  - Build benchmark binary"
	@echo "  make clean      - Remove build artifacts"
