# SnapLedger Architecture

SnapLedger is a multiplatform SwiftUI application with an iOS Share Extension. The main app owns ledger state, recognition, review, and persistence; the extension only stages shared images for the app to consume.

## Targets

- `SnapLedger`: the iOS and macOS application.
- `SnapLedgerShare`: an iOS UIKit Share Extension that accepts images from the system share sheet.
- `SnapLedgerTests`: unit tests built with Swift Testing.

The app and Share Extension share the `group.com.chenxuanchi.SnapLedger` App Group. The extension must not depend on in-memory app state or perform transaction recognition itself.

## Source layout

- `App/`: application entry point, root navigation, app-wide state, and shared-import coordination.
- `Domain/`: ledger, transaction, category, and other business models. This layer depends only on Foundation.
- `Features/`: SwiftUI screens and feature-specific integrations. `Features/Import/` also contains the App Intents used by the cloud-model Shortcuts workflow.
- `Infrastructure/Persistence/`: ledger file access, storage, and export.
- `Infrastructure/Recognition/`: Vision OCR, Foundation Models parsing, recognition prompts, and the recognition agent that coordinates them.
- `Shared/Components/`: reusable UI components shared by multiple features.
- `Support/`: low-level coding, date parsing, preview data, and error helpers.
- `SnapLedgerShare/`: Share Extension UI and image staging code.

When adding code, prefer one primary screen or responsibility per file. Keep feature-specific helpers beside their feature; move a helper to `Shared` only after it is used by more than one feature.

## Dependency direction

Dependencies should generally point inward:

```text
Features -> App / Domain / Infrastructure / Shared
App -> Domain / Infrastructure
Infrastructure -> Domain / Support
Domain -> Foundation

SnapLedgerShare -> UIKit / UniformTypeIdentifiers / shared App Group container
```

`SnapLedgerShare` and `SnapLedger` are separate processes. Their integration boundary is the App Group file container plus the `snapledger://import-shared-images` deep link; the extension does not link against the app's state or recognition pipeline.

## Import and recognition flows

### In-app and shared-image import

```text
Photo picker -> image data -------------------------+
                                                     |
Share Extension -> App Group batch                  |
    -> SharedImportInbox consumption ---------------+
                                                     |
    -> AppModel import queue
    -> TransactionRecognitionAgent
       -> multilingual Vision OCR
       -> image + OCR Foundation Models parsing when available
       -> OCR-text parsing fallback on failure or unsupported systems
    -> user review and confirmation
    -> LedgerStore persistence
```

The Share Extension loads the image representations it can read, writes them into a staging directory, and atomically renames that directory to a `batch-` directory after saving succeeds. `SharedImportInbox` processes completed batches in lexicographic filename order. It skips unreadable files and removes a batch after consuming at least one readable image; an empty or wholly unreadable batch remains in the inbox. If opening the deep link fails, a completed batch remains available for the next app launch.

`TransactionRecognitionAgent` is the orchestration boundary for local recognition. It receives immutable ledger context, reports progress through an async event sink, enriches parsed results with OCR diagnostics, and owns the fallback from visual parsing to OCR-text parsing.

### Cloud-model Shortcuts import

```text
GetSnapLedgerCloudPromptIntent
    -> Shortcuts cloud-model action
    -> ImportCloudModelResultIntent
    -> JSON validation and duplicate detection
    -> LedgerStore persistence
```

This path is intentionally separate from the local recognition agent. It rejects transactions explicitly marked as needing confirmation and validates the type, positive amount, currency, merchant, and date. A missing or unknown category is normalized to an available ledger category. Only valid, non-duplicate transactions are written to the current ledger.

## State and persistence boundaries

- `AppModel` owns observable UI state and coordinates feature operations in the running app.
- `Ledger` and its related domain types define business data and rules.
- `LedgerStore` is the durable storage boundary used by the app and App Intents.
- Recognition services return parsed candidates; they do not directly mutate the ledger.
- User-facing import flows persist candidates only after review, except the Shortcuts path, which validates required transaction values and applies category normalization before writing.

## Testing

Tests live in `SnapLedgerTests/` and should mirror the production responsibility they verify. Prioritize tests for domain rules, persistence encoding, cloud-result validation, duplicate detection, recognition fallback behavior, and App Group inbox batch consumption. Keep Share Extension code thin; test shared file-transfer rules through app-side abstractions where possible.
