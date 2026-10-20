#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product LaunchDock
BUILD_DIR="$(swift build --show-bin-path)"
swiftc -I "$BUILD_DIR/Modules" -I "$BUILD_DIR/ProcessSupport.build" \
    Sources/LaunchDock/AppModel.swift Sources/LaunchDock/LocalUpdateController.swift Sources/LaunchDock/ContentView.swift \
    Sources/LaunchDock/ProjectEditor.swift Sources/LaunchDock/LogOutputView.swift \
    Tests/ProjectDetailChecks.swift "$BUILD_DIR/LaunchDockCore.build/"*.o \
    "$BUILD_DIR/ProcessSupport.build/ProcessSupport.c.o" -o "$BUILD_DIR/project-detail-checks"
LAUNCHDOCK_CONFIG_PATH="$PWD/.build/detail-checks/projects.json" "$BUILD_DIR/project-detail-checks"
