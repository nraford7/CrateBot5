# Bug Report: File Write Permissions Failure in CrateBot Tagging

## Summary

CrateBot fails to write ID3 tags to MP3 files with the error:
```
Could not open() the item: [1: Operation not permitted]
```

This occurs even when files are selected via NSOpenPanel's "Browse Files" button, which should grant security-scoped access.

---

## Environment

- **macOS Version**: Darwin 25.1.0 (macOS Sequoia+)
- **App Sandbox**: Disabled (`com.apple.security.app-sandbox` = false)
- **Files Location**: `/Users/noahraford/Desktop/new tracks/`
- **File Attribute**: Files have `com.apple.macl` extended attribute (macOS access control)

## Entitlements (CrateBot/App/CrateBot.entitlements)

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## What We Tried

### Attempt 1: Security-Scoped Bookmarks

**Theory**: Files need security-scoped bookmarks to persist access.

**Changes Made**:
- Added `bookmarkData` property to `QueuedFile` struct
- Created bookmarks when files selected via NSOpenPanel
- Restored bookmarks on app launch via `BookmarkManager.restoreAllAccess()`

**Result**: Still failed. Bookmarks were created but didn't help.

**Files Changed**:
- `CrateBot/App/AppState.swift` - Added bookmark storage to QueuedFile
- `CrateBot/Views/TaggingView.swift` - Create bookmarks on file selection
- `CrateBot/App/CrateBotApp.swift` - Restore bookmarks on launch

### Attempt 2: Start Security Access Immediately

**Theory**: NSOpenPanel's security grant expires after the callback returns. Must call `startAccessingSecurityScopedResource()` immediately while grant is active.

**Changes Made**:
- Modified `QueuedFile` to accept `startAccessImmediately: true`
- Called `url.startAccessingSecurityScopedResource()` in the initializer
- Tracked active access state with `securityAccessActive` flag
- Created bookmarks while access was active

**Result**: Still failed.

**Files Changed**:
- `CrateBot/App/AppState.swift` - QueuedFile now starts access in init
- `CrateBot/Views/TaggingView.swift` - Pass `startAccessImmediately: true`

### Attempt 3: Remove isWritableFile Check

**Theory**: `FileManager.default.isWritableFile(atPath:)` doesn't work with security-scoped resources.

**Changes Made**:
- Removed the `isWritableFile` guard in `ID3Manager.writeTags()`

**Result**: Still failed. The actual write operation still errored.

**Files Changed**:
- `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift`

### Attempt 4: Bypass ID3TagEditor's File I/O (CURRENT STATE)

**Theory**: The ID3TagEditor library creates NEW URLs from path strings internally, which loses security-scoped access.

**Root Cause Identified**:
```swift
// In ID3TagEditor's Mp3FileWriter.swift:
func write(mp3: Data, path: String) throws {
    try mp3.write(to: URL(fileURLWithPath: path))  // <-- NEW URL, NO SECURITY SCOPE
}
```

Security-scoped access is tied to the **specific URL object** from NSOpenPanel. When the library creates `URL(fileURLWithPath: path)`, it's a completely new URL with no security context.

**Changes Made**:
- Rewrote `ID3Manager` to handle all file I/O directly
- Read file: `let data = try Data(contentsOf: url)` (using security-scoped URL)
- Parse tags: `editor.read(mp3: data)` (in-memory only)
- Modify tags: `editor.write(tag: newTag, mp3: data)` (returns Data)
- Write file: `try modifiedData.write(to: url)` (using security-scoped URL)

**Result**: STILL FAILED with same error.

**Files Changed**:
- `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift`

---

## Current Code State

### QueuedFile (AppState.swift)

```swift
struct QueuedFile: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    var error: String?
    var bookmarkData: Data?
    var securityAccessActive: Bool = false
    var writtenTags: WrittenTags?

    init(url: URL, startAccessImmediately: Bool = false, status: Status = .pending, error: String? = nil) {
        self.url = url
        self.status = status
        self.error = error

        if startAccessImmediately {
            self.securityAccessActive = url.startAccessingSecurityScopedResource()
            if self.securityAccessActive {
                self.bookmarkData = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        }
    }

    mutating func startAccess() -> Bool { ... }
    mutating func stopAccess() { ... }
}
```

### File Selection (TaggingView.swift)

```swift
private func addFilesWithBookmarks(from urls: [URL]) {
    var filesToAdd: [URL] = []

    for url in urls {
        if url.hasDirectoryPath {
            _ = url.startAccessingSecurityScopedResource()
            do {
                try appState.bookmarkManager.addFolderAccess(url)
            } catch {
                print("Failed to bookmark folder: \(error)")
            }
            let mp3s = findMP3Files(in: url)
            filesToAdd.append(contentsOf: mp3s)
        } else if url.pathExtension.lowercased() == "mp3" {
            filesToAdd.append(url)
        }
    }

    let existingURLs = Set(appState.queuedFiles.map(\.url))
    let newFiles = filesToAdd
        .filter { !existingURLs.contains($0) }
        .map { AppState.QueuedFile(url: $0, startAccessImmediately: true) }

    appState.queuedFiles.append(contentsOf: newFiles)
}
```

### ID3Manager.writeTags (Current)

```swift
public func writeTags(_ tags: TagsToWrite, to url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ID3Error.fileNotFound(url)
    }
    guard url.pathExtension.lowercased() == "mp3" else {
        throw ID3Error.invalidFormat(url)
    }
    guard !tags.isEmpty else { return }

    do {
        // Read file data directly using the URL (preserves security-scoped access)
        let mp3Data = try Data(contentsOf: url)

        // Read existing tags (using Data-based method)
        let existingTag = try editor.read(mp3: mp3Data)

        // ... build new tag ...

        let newTag = builder.build()

        // Use Data-based write method (returns modified Data)
        let modifiedMp3Data = try editor.write(tag: newTag, mp3: mp3Data)

        // Write data directly using the URL (preserves security-scoped access)
        try modifiedMp3Data.write(to: url)  // <-- THIS STILL FAILS
    } catch { ... }
}
```

---

## Theories for Why It Still Fails

### 1. Security Access Not Actually Active

Even though we call `startAccessingSecurityScopedResource()`, it might be returning `false` silently. We don't have logging to confirm.

**To verify**: Add logging to check the return value of `startAccessingSecurityScopedResource()`.

### 2. URL Object Being Copied/Lost

Swift structs are value types. When `QueuedFile` is copied (e.g., in a `for` loop), the URL might lose its security association.

**To verify**: Pass the URL by reference or use the URL directly from the array.

### 3. Async/Actor Boundary Issue

`ID3Manager` is an actor. When we pass the URL across actor boundaries, something might be lost.

**To verify**: Try making the write synchronous or on the main actor.

### 4. com.apple.macl Cannot Be Bypassed

The `com.apple.macl` extended attribute might be stricter than standard security-scoped access. It may require:
- Full Disk Access permission
- The file to be modified by the same app that created it
- Some other TCC (Transparency, Consent, Control) permission

**To verify**:
```bash
xattr -l "/Users/noahraford/Desktop/new tracks/somefile.mp3"
```

### 5. Data.write(to:) Creates New File Handle

Even though we use the security-scoped URL, `Data.write(to:)` might internally create a new file descriptor that doesn't inherit security scope.

**To verify**: Try using `FileHandle` with the URL directly:
```swift
let handle = try FileHandle(forWritingTo: url)
try handle.write(contentsOf: modifiedMp3Data)
try handle.close()
```

### 6. NSOpenPanel Not Granting Write Access

NSOpenPanel might only be granting read access, not write access.

**To verify**: Check if reading works but writing fails. Add explicit read test before write.

---

## Suggested Next Steps

1. **Add comprehensive logging** to trace:
   - Return value of `startAccessingSecurityScopedResource()`
   - Whether `Data(contentsOf: url)` succeeds (read test)
   - Exact point of failure in the write process

2. **Try FileHandle instead of Data.write(to:)**:
   ```swift
   let handle = try FileHandle(forWritingTo: url)
   try handle.truncate(atOffset: 0)
   try handle.write(contentsOf: modifiedMp3Data)
   try handle.close()
   ```

3. **Test with a file NOT on Desktop** - try a file in Documents or Downloads to rule out Desktop-specific protections

4. **Check TCC permissions** - The app may need additional permissions in System Preferences → Privacy & Security

5. **Try atomic write option**:
   ```swift
   try modifiedMp3Data.write(to: url, options: .atomic)
   ```

6. **Test if the user previously granted Full Disk Access** - The user mentioned they've written to these files before, possibly with FDA enabled

---

## Relevant Files

| File | Purpose |
|------|---------|
| `CrateBot/App/AppState.swift` | QueuedFile struct with security access handling |
| `CrateBot/Views/TaggingView.swift` | File selection and tagging orchestration |
| `CrateBot/App/CrateBotApp.swift` | App entry point, bookmark restoration |
| `CrateBot/App/CrateBot.entitlements` | App permissions |
| `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift` | ID3 tag reading/writing |
| `CrateBotCore/Sources/CrateBotCore/Data/BookmarkManager.swift` | Security-scoped bookmark management |

---

## How to Reproduce

1. Build and run CrateBot
2. Go to Tag view
3. Click "Browse Files"
4. Select MP3 files from `/Users/noahraford/Desktop/new tracks/`
5. Click "Start Tagging"
6. Observe error: "Could not open() the item: [1: Operation not permitted]"

---

## User Notes

- User says they have written to these files before (possibly with different app or Full Disk Access)
- Files have `com.apple.macl` attribute
- App sandbox is disabled
- Using NSOpenPanel for file selection
