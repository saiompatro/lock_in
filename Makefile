# Lock In — build helpers. Run `make help`.
APP_NAME   := Lock In
BUILD_DIR  := build
APP_PATH   := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL_TO := /Applications/$(APP_NAME).app

.PHONY: help project build test install run clean

help:
	@echo "make project  - regenerate LockIn.xcodeproj from project.yml (needs xcodegen)"
	@echo "make build    - Release build into ./build"
	@echo "make test     - run unit tests"
	@echo "make install  - build and copy to /Applications, then launch"
	@echo "make run      - launch the installed app"
	@echo "make clean    - remove ./build"

project:
	xcodegen generate

build: project
	xcodebuild -project LockIn.xcodeproj -scheme LockIn -configuration Release \
		-derivedDataPath $(BUILD_DIR) build -quiet

test: project
	xcodebuild -project LockIn.xcodeproj -scheme LockIn -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' test -quiet

install: build
	-@osascript -e 'tell application id "com.lockin.LockIn" to quit' 2>/dev/null; sleep 1
	rm -rf "$(INSTALL_TO)"
	ditto "$(APP_PATH)" "$(INSTALL_TO)"
	open "$(INSTALL_TO)"

run:
	open "$(INSTALL_TO)"

clean:
	rm -rf $(BUILD_DIR)
