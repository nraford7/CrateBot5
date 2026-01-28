# Security & Code Quality Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address all critical, major, and minor issues identified in the Fresh Eyes code review, focusing on security vulnerabilities, crash-prone code, and code quality improvements.

**Architecture:** Swift-first fixes (Keychain for API keys, graceful error handling, proper logging), followed by Python backend hardening (path validation, CORS fixes, dependency updates).

**Tech Stack:** Swift, SwiftUI, Security.framework (Keychain), os.log, Python, FastAPI

---

## Phase 1: Critical Security Fixes (Swift)

### Task 1.1: Create KeychainManager for Secure API Key Storage

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Security/KeychainManager.swift`

**Step 1: Write the failing test**

Create a test file first (we'll test manually since this requires Keychain access):

```swift
// Manual test: After implementation, verify in app that:
// 1. API key can be saved to Keychain
// 2. API key can be retrieved from Keychain
// 3. API key can be deleted from Keychain
// 4. UserDefaults no longer contains API key
```

**Step 2: Create the KeychainManager**

```swift
import Foundation
import Security
import os.log

/// Secure storage for sensitive credentials using macOS Keychain
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let logger = Logger(subsystem: "com.cratebot", category: "KeychainManager")

    // Keychain service identifier
    private let service = "com.cratebot.credentials"

    // Known key names
    public enum Key: String, Sendable {
        case anthropicAPIKey = "anthropic_api_key"
    }

    private init() {}

    /// Save a string value to the Keychain
    /// - Parameters:
    ///   - value: The string to store
    ///   - key: The key identifier
    /// - Throws: KeychainError if the operation fails
    public func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (if any)
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Failed to save to Keychain: \(status)")
            throw KeychainError.saveFailed(status)
        }

        logger.info("Saved \(key.rawValue) to Keychain")
    }

    /// Retrieve a string value from the Keychain
    /// - Parameter key: The key identifier
    /// - Returns: The stored string, or nil if not found
    public func retrieve(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete a value from the Keychain
    /// - Parameter key: The key identifier
    public func delete(key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete from Keychain: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a key exists in the Keychain
    /// - Parameter key: The key identifier
    /// - Returns: True if the key exists
    public func exists(key: Key) -> Bool {
        retrieve(key: key) != nil
    }
}

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
```

**Step 3: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Security/KeychainManager.swift
git commit -m "feat(security): add KeychainManager for secure credential storage

Replaces insecure UserDefaults storage with macOS Keychain.
Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for maximum security."
```

---

### Task 1.2: Update LegacyImporter to Use Keychain

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Data/LegacyImporter.swift:113-116`

**Step 1: Update the import and migration code**

Replace lines 113-116:

```swift
        // Migrate to Keychain (secure) instead of UserDefaults
        if let apiKey = config.anthropicApiKey {
            do {
                try KeychainManager.shared.save(apiKey, for: .anthropicAPIKey)
                logger.info("Migrated API key to Keychain")
            } catch {
                logger.error("Failed to migrate API key to Keychain: \(error.localizedDescription)")
            }
        }
```

**Step 2: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/LegacyImporter.swift
git commit -m "fix(security): migrate API key storage to Keychain in LegacyImporter

BREAKING: API keys are no longer stored in UserDefaults (plaintext plist).
Now uses secure Keychain storage with device-only accessibility."
```

---

### Task 1.3: Update AppState/Settings to Use Keychain for API Key

**Files:**
- Modify: `CrateBot/App/AppState.swift` (add API key accessor)
- Modify: `CrateBot/Views/SettingsPanel.swift` (use Keychain)

**Step 1: Add API key accessor to AppState**

Add after line 45 in AppState.swift:

```swift
    // MARK: - Secure Credentials

    /// Get the Anthropic API key from Keychain
    var anthropicAPIKey: String? {
        KeychainManager.shared.retrieve(key: .anthropicAPIKey)
    }

    /// Set the Anthropic API key in Keychain
    func setAnthropicAPIKey(_ key: String?) throws {
        if let key = key, !key.isEmpty {
            try KeychainManager.shared.save(key, for: .anthropicAPIKey)
        } else {
            try KeychainManager.shared.delete(key: .anthropicAPIKey)
        }
    }

    /// Check if API key is configured
    var hasAnthropicAPIKey: Bool {
        KeychainManager.shared.exists(key: .anthropicAPIKey)
    }
```

**Step 2: Migrate any UserDefaults API key reads to use Keychain**

Search for `UserDefaults.standard.*anthropicAPIKey` and replace with `KeychainManager.shared.retrieve(key: .anthropicAPIKey)`.

**Step 3: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBot -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add CrateBot/App/AppState.swift CrateBot/Views/SettingsPanel.swift
git commit -m "fix(security): use Keychain for API key throughout app

All API key access now goes through KeychainManager.
Removed UserDefaults fallback for API key storage."
```

---

## Phase 2: Critical Crash Fixes (Swift)

### Task 2.1: Replace fatalError with Graceful Recovery in CrateBotApp

**Files:**
- Modify: `CrateBot/App/CrateBotApp.swift:48-60`

**Step 1: Replace fatalError with recovery logic**

Replace the sharedModelContainer property:

```swift
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedFeatures.self, TagOverride.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error
            Logger(subsystem: "com.cratebot", category: "App")
                .error("ModelContainer creation failed: \(error.localizedDescription). Attempting recovery...")

            // Try to recover by deleting corrupted database
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbPath = appSupport.appendingPathComponent("default.store")

            do {
                if FileManager.default.fileExists(atPath: dbPath.path) {
                    try FileManager.default.removeItem(at: dbPath)
                    Logger(subsystem: "com.cratebot", category: "App")
                        .info("Removed corrupted database, retrying...")
                }
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Last resort: use in-memory storage
                Logger(subsystem: "com.cratebot", category: "App")
                    .error("Recovery failed, using in-memory storage: \(error.localizedDescription)")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    // This should never happen with in-memory, but handle it
                    fatalError("Cannot create even in-memory ModelContainer: \(error)")
                }
            }
        }
    }()
```

**Step 2: Add import for os.log at top of file**

Add after existing imports:

```swift
import os.log
```

**Step 3: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBot -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add CrateBot/App/CrateBotApp.swift
git commit -m "fix(crash): graceful recovery for ModelContainer initialization

Instead of crashing on database corruption:
1. Try to delete corrupted database and retry
2. Fall back to in-memory storage if that fails
3. Only fatalError if in-memory also fails (should never happen)"
```

---

### Task 2.2: Fix Force Unwraps in ModelTrainer

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift:205-212`

**Step 1: Replace unsafe force unwraps with safe patterns**

Replace lines 205-212:

```swift
        // Filter tracks that have features (using safe unwrapping)
        let tracksWithFeatures = tracks.compactMap { track -> TaggedTrack? in
            guard let features = track.features, !features.isEmpty else { return nil }
            return track
        }

        guard let firstTrack = tracksWithFeatures.first,
              let features = firstTrack.features else {
            throw TrainerError.noFeaturesAvailable
        }

        // Determine feature count from first track (now safe)
        let featureCount = features.count
```

**Step 2: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift
git commit -m "fix(crash): replace force unwraps with safe optional handling in ModelTrainer

Uses compactMap and guard-let pattern to safely handle nil features.
Eliminates crash risk from malformed training data."
```

---

### Task 2.3: Fix Force Unwraps in TrainingCoordinator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`

**Step 1: Search for force unwraps and fix them**

Find all `!` force unwraps and replace with safe alternatives:

```swift
// Pattern to find: someOptional!
// Replace with: guard let value = someOptional else { ... }
// Or: someOptional ?? defaultValue
```

**Step 2: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git commit -m "fix(crash): eliminate force unwraps in TrainingCoordinator

All force unwraps replaced with safe optional handling patterns."
```

---

### Task 2.4: Fix Force Unwraps in ExperimentRunner

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ExperimentRunner.swift`

**Step 1: Search for force unwraps and fix them**

Same pattern as Task 2.3.

**Step 2: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ExperimentRunner.swift
git commit -m "fix(crash): eliminate force unwraps in ExperimentRunner"
```

---

## Phase 3: Major Code Quality Fixes (Swift)

### Task 3.1: Replace print() with os.log Throughout

**Files:**
- Modify: `CrateBot/App/AppState.swift` (10+ print statements)
- Modify: `CrateBot/Views/TaggingView.swift`
- Modify: `CrateBot/Views/TrainView.swift`
- Modify: `CrateBot/Views/Dialogs.swift`

**Step 1: Add Logger to AppState**

Add after line 3 in AppState.swift:

```swift
import os.log
```

Add after line 5:

```swift
    private let logger = Logger(subsystem: "com.cratebot", category: "AppState")
```

**Step 2: Replace all print() calls**

Replace pattern:
```swift
// Before
print("Failed to copy model into default location: \(error)")

// After
logger.error("Failed to copy model into default location: \(error.localizedDescription)")
```

Use these log levels:
- `logger.debug()` - Verbose debugging info
- `logger.info()` - Normal operations
- `logger.warning()` - Recoverable issues
- `logger.error()` - Errors that affect functionality

**Step 3: Repeat for other files**

Apply same pattern to TaggingView.swift, TrainView.swift, Dialogs.swift.

**Step 4: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBot -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add CrateBot/App/AppState.swift CrateBot/Views/TaggingView.swift CrateBot/Views/TrainView.swift CrateBot/Views/Dialogs.swift
git commit -m "refactor(logging): replace print() with os.log throughout app

Uses structured logging with appropriate log levels.
Debug info no longer exposed in production builds."
```

---

### Task 3.2: Make HTTP Base URL Configurable

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift:31`

**Step 1: Make URL configurable via UserDefaults with sensible default**

Replace the hardcoded URL:

```swift
    public static var defaultBaseURL: URL {
        if let customURL = UserDefaults.standard.string(forKey: "backendBaseURL"),
           let url = URL(string: customURL) {
            return url
        }
        return URL(string: "http://127.0.0.1:8742")!
    }
```

**Step 2: Add documentation comment**

```swift
    /// The base URL for the backend server.
    /// Defaults to localhost:8742 but can be overridden via UserDefaults key "backendBaseURL".
    /// For production, consider using HTTPS with a proper certificate.
```

**Step 3: Verify compilation**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBotCore -configuration Debug build 2>&1 | head -50`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift
git commit -m "feat(config): make backend URL configurable

Backend URL can now be set via UserDefaults 'backendBaseURL'.
Enables different deployment configurations."
```

---

## Phase 4: Python Backend Security Fixes

### Task 4.1: Fix CORS Configuration

**Files:**
- Modify: `backend/api_server.py:239-243`

**Step 1: Replace overly permissive CORS**

Replace the CORS middleware configuration:

```python
# Configure CORS for local Swift app
# Note: allow_credentials=True requires specific origins, not "*"
ALLOWED_ORIGINS = [
    "http://localhost:8742",
    "http://127.0.0.1:8742",
    "app://.",  # Electron/Tauri apps
]

# Allow additional origins from environment
if os.environ.get("CRATEBOT_CORS_ORIGINS"):
    ALLOWED_ORIGINS.extend(os.environ["CRATEBOT_CORS_ORIGINS"].split(","))

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)
```

**Step 2: Verify server starts**

Run: `cd backend && python -c "from api_server import app; print('OK')"`
Expected: OK

**Step 3: Commit**

```bash
git add backend/api_server.py
git commit -m "fix(security): restrict CORS to specific origins

BREAKING: Removed allow_origins=['*'] with credentials.
Now uses explicit origin whitelist with env var override."
```

---

### Task 4.2: Add Path Validation to Backup Restore

**Files:**
- Modify: `backend/api_server.py` (restore_migration_backup endpoint)
- Modify: `backend/migration.py:315-342`

**Step 1: Add path validation in migration.py**

Add before the restore_backup function:

```python
def validate_backup_path(backup_path: str) -> Path:
    """Validate that backup path is within allowed backup directory."""
    backup = Path(backup_path).resolve()
    backup_dir = BACKUP_DIR.resolve()

    # Ensure the path is within the backup directory
    try:
        backup.relative_to(backup_dir)
    except ValueError:
        raise ValueError(f"Backup path must be within {backup_dir}")

    if not backup.exists():
        raise FileNotFoundError(f"Backup not found: {backup}")

    return backup
```

**Step 2: Update restore_backup to use validation**

```python
def restore_backup(backup_path: str) -> bool:
    """Restore from a migration backup."""
    try:
        backup = validate_backup_path(backup_path)
    except (ValueError, FileNotFoundError) as e:
        logger.error(f"Invalid backup path: {e}")
        return False

    # ... rest of function
```

**Step 3: Verify server starts**

Run: `cd backend && python -c "from migration import validate_backup_path; print('OK')"`
Expected: OK

**Step 4: Commit**

```bash
git add backend/api_server.py backend/migration.py
git commit -m "fix(security): add path validation to backup restore

Prevents path traversal attacks by validating backup paths
are within the allowed backup directory."
```

---

### Task 4.3: Update Python Dependencies

**Files:**
- Modify: `python/requirements.txt`

**Step 1: Update to latest stable versions**

Update these packages:

```
anthropic>=0.25.0
fastapi>=0.115.0
uvicorn[standard]>=0.30.0
pydantic>=2.8.0
```

**Step 2: Test import**

Run: `cd python && pip install -r requirements.txt && python -c "import fastapi; print(fastapi.__version__)"`
Expected: 0.115.x or higher

**Step 3: Commit**

```bash
git add python/requirements.txt
git commit -m "chore(deps): update Python dependencies to latest stable

- anthropic: 0.18.1 -> 0.25.0
- fastapi: 0.109.2 -> 0.115.0
- uvicorn: 0.27.1 -> 0.30.0
- pydantic: 2.6.1 -> 2.8.0

Addresses potential security vulnerabilities in older versions."
```

---

### Task 4.4: Add Rate Limiting to Backend

**Files:**
- Modify: `backend/api_server.py`

**Step 1: Add slowapi for rate limiting**

Add to requirements.txt:
```
slowapi>=0.1.9
```

**Step 2: Configure rate limiting in api_server.py**

Add after imports:

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
```

**Step 3: Add rate limits to expensive endpoints**

```python
@app.post("/api/v1/training/start")
@limiter.limit("5/minute")
async def start_training(request: Request, training_request: TrainingRequest):
    ...

@app.post("/api/v1/vibe/file")
@limiter.limit("30/minute")
async def generate_vibe(request: Request, vibe_request: VibeRequest):
    ...
```

**Step 4: Verify server starts**

Run: `cd backend && python -c "from api_server import app; print('OK')"`
Expected: OK

**Step 5: Commit**

```bash
git add backend/api_server.py python/requirements.txt
git commit -m "feat(security): add rate limiting to backend API

Uses slowapi to prevent abuse:
- Training: 5 requests/minute
- Vibe generation: 30 requests/minute
- Other endpoints: default limits"
```

---

## Phase 5: Minor Fixes

### Task 5.1: Remove CrateBot4 Legacy Comments

**Files:**
- Modify: `backend/api_server.py` (search for "CrateBot4")

**Step 1: Remove or update legacy comments**

Search for `# CrateBot4` and either:
- Remove the comment if code is now standard
- Update to reflect current version

**Step 2: Commit**

```bash
git add backend/api_server.py
git commit -m "chore: remove legacy CrateBot4 comments

Code cleanup - removes outdated version references."
```

---

### Task 5.2: Complete SpectralExtractor TODOs

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Audio/SpectralExtractor.swift:113,134`

**Step 1: Implement proper MFCC calculation or document limitation**

Either implement proper MFCC or add clear documentation:

```swift
/// Note: This is a simplified MFCC approximation. For production audio analysis,
/// consider using the Essentia or CLAP extractors which provide more accurate features.
/// The spectral features here are used as supplementary information only.
```

**Step 2: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/SpectralExtractor.swift
git commit -m "docs: document SpectralExtractor limitations

Clarifies that spectral features are supplementary to main extractors."
```

---

## Summary

| Phase | Tasks | Priority | Est. Complexity |
|-------|-------|----------|-----------------|
| 1 | Security (Keychain) | CRITICAL | Medium |
| 2 | Crash Fixes | CRITICAL | Low |
| 3 | Code Quality (Swift) | MAJOR | Medium |
| 4 | Backend Security | MAJOR | Medium |
| 5 | Minor Fixes | MINOR | Low |

**Total Tasks:** 12
**Estimated Commits:** 12-15

---

## Verification Checklist

After completing all tasks:

- [ ] App builds without warnings: `xcodebuild -scheme CrateBot build`
- [ ] API key stored in Keychain (check via Keychain Access.app)
- [ ] No fatalError calls except last-resort in-memory fallback
- [ ] No force unwraps in ML code paths
- [ ] No print() statements in production code
- [ ] Backend starts with new CORS config
- [ ] Backend rate limits work (test with rapid requests)
- [ ] All dependencies at latest stable versions
