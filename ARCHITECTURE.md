# SnapLedger Architecture

The source tree is organized by responsibility:

- `App/`: application entry point, root navigation, and app-wide state.
- `Domain/`: business models and domain rules. This layer should not depend on UI or infrastructure.
- `Features/`: SwiftUI screens grouped by user-facing feature.
- `Infrastructure/Persistence/`: file access, ledger storage, and export.
- `Infrastructure/Recognition/`: OCR and transaction parsing.
- `Shared/Components/`: reusable UI components shared by multiple features.
- `Support/`: low-level coding, date parsing, and error helpers.

Dependencies should generally point inward:

```text
Features -> App / Domain / Shared
App -> Domain / Infrastructure
Infrastructure -> Domain / Support
Domain -> Foundation only
```

When adding code, prefer one primary screen or responsibility per file. Keep feature-specific helpers beside their feature; move a helper to `Shared` only after it is used by more than one feature.

Tests live in `SnapLedgerTests/` and should mirror the production responsibility they verify as the suite grows.
