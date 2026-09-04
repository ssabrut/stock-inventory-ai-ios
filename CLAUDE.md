# CLAUDE.md

## Rules

- Do not build the project (no `xcodebuild`, no Xcode build/run). Only modify code.
- Backend-related code (API calls, request/response models, endpoint URLs, params): always fetch `http://127.0.0.1:8000/docs` (or its `openapi.json`) first to confirm current API shape before writing or changing code.
