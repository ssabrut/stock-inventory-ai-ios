# CLAUDE.md

## Build policy

Never run builds — no `xcodebuild`, no `swift build`, no simulator launches, no `xed --build`, nothing that compiles the project. Only modify source files.

User builds and runs in Xcode themselves and reports back errors/results.
