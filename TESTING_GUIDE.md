# ClipboardGuard - Comprehensive Testing Guide

**Version:** 1.0
**Last Updated:** October 19, 2025
**Purpose:** Use this guide for every iteration to ensure all features work correctly

---

## Pre-Testing Checklist

### 1. Permissions Setup ✅

Before testing, ensure all required permissions are granted:

- [ ] **Accessibility Permissions** (Required for paste blocking)
  - Go to: `System Settings → Privacy & Security → Accessibility`
  - Enable: `Clipboard.app`
  - Or run: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`

- [ ] **Notification Permissions** (Optional for system notifications)
  - Go to: `System Settings → Notifications → Clipboard`
  - Enable: `Allow Notifications`

### 2. License Activation ✅

- [ ] Launch ClipboardGuard
- [ ] Enter test license credentials:
  - **Email:** `test@example.com`
  - **License Key:** `TEST-LICENSE-KEY-12345`
- [ ] Verify activation success
- [ ] Confirm dashboard appears

### 3. Check Console Output ✅

- [ ] Open Xcode or Console.app
- [ ] Filter for process: `Clipboard`
- [ ] Look for startup messages:
  ```
  ✅ [PasteBlocker] Accessibility permissions granted
  ⚡️ [PasteBlocker] Started paste event interception
  ✅ [PasteDetector] Accessibility permissions granted
  ⚡️ ClipboardMonitor: Started ULTRA-FAST monitoring (5ms = 200 checks/second)
  ```

---

## Test Suite

### Test 1: Copy Detection - Bitcoin ⚡️

**Objective:** Verify Bitcoin address detection and copy animation

#### Test Addresses:
```
1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq
3J98t1WpEZ73CNmYviecrnyiWrnqRhWNLy
```

#### Steps:
1. Copy a Bitcoin address from above
2. **Expected Console Output:**
   ```
   📋 [DEBUG] Clipboard changed!
   🔍 [PatternMatcher] Testing: "1A1zP1..."
   ✅ MATCHED: Bitcoin
   👁️  COPY EVENT - Showing monitoring indicator
   📋 COPY: Bitcoin address copied
   ```
3. **Expected UI:**
   - Blue floating indicator appears near cursor
   - Shows checkmark ✓ icon (NOT eye icon)
   - Text: "Bitcoin"
   - Smooth scale animation
   - Auto-dismisses after 2 seconds

#### Success Criteria:
- [ ] Blue indicator appears instantly (<50ms)
- [ ] Animation is smooth and professional
- [ ] No "spy" icons (eye, etc.)
- [ ] Console shows "Bitcoin" detection
- [ ] `copyCount` increments in dashboard

---

### Test 2: Copy Detection - Ethereum ⚡️

**Objective:** Verify Ethereum address detection (0x prefix handling)

#### Test Addresses:
```
0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC
0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
0xdAC17F958D2ee523a2206206994597C13D831ec7
```

#### Steps:
1. Copy an Ethereum address (must be exactly 42 characters!)
2. **Expected Console Output:**
   ```
   📋 [DEBUG] Clipboard changed!
   Length: 42
   🧪 Testing pattern: Ethereum Standard
   ✅ MATCH! Type: Ethereum
   ```
3. **Expected UI:**
   - Blue floating indicator with "Ethereum" text
   - Checkmark icon

#### Success Criteria:
- [ ] Ethereum pattern detected first (before Bitcoin)
- [ ] 42-character addresses work correctly
- [ ] Blue copy indicator shows
- [ ] Console confirms "Ethereum" match

---

### Test 3: Copy Detection - Solana ⚡️

**Objective:** Verify Solana address detection (Base58 encoding)

#### Test Addresses:
```
7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV
DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK
EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

#### Steps:
1. Copy a Solana address
2. **Expected Console Output:**
   ```
   📋 [DEBUG] Clipboard changed!
   Length: 44
   🧪 Testing pattern: Solana
   ✅ MATCH! Type: Solana
   ```
3. **Expected UI:**
   - Blue floating indicator with "Solana" text

#### Success Criteria:
- [ ] Solana addresses (43-44 chars) detected
- [ ] Base58 validation works
- [ ] Blue copy indicator shows

---

### Test 4: Paste Verification - Safe Paste ✅

**Objective:** Verify instant green verification when pasting unmodified address

#### Steps:
1. Copy a Bitcoin address: `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`
2. Wait for blue copy indicator
3. Open TextEdit or any text editor
4. Press **Command+V** to paste
5. **Expected Console Output:**
   ```
   🚨 [PasteBlocker] Command+V intercepted - checking if safe to paste...
      ✅ Safe to paste - allowing
   ✅ INSTANT PASTE VERIFICATION for Bitcoin
   ```
6. **Expected UI:**
   - **GREEN** floating indicator appears **INSTANTLY** (no delay!)
   - Shimmer/glow animation
   - Text: "Bitcoin Verified ✓"
   - Bigger checkmark with glow effect
   - Address pastes successfully into editor

#### Success Criteria:
- [ ] Green indicator shows **immediately** when Command+V pressed
- [ ] NO delay waiting for clipboard change
- [ ] Paste completes successfully
- [ ] `pasteCount` increments in dashboard
- [ ] Console shows "INSTANT PASTE VERIFICATION"

---

### Test 5: Hijack Detection - Clipboard Replacement 🚨

**Objective:** Verify hijack detection when clipboard is manually changed

#### Steps:
1. Copy a Bitcoin address: `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`
2. Wait for blue copy indicator
3. **Manually copy a different address** (simulating malware):
   ```
   0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC
   ```
4. **Expected Console Output:**
   ```
   ⚠️ HIJACK DETECTED!
      Original:  1A1zP1...vfNa
      Attempted: 0x742d...bEbC
   ✅ Clipboard restored
   ```
5. **Expected UI:**
   - System notification: "⚠️ Clipboard Hijack Blocked!"
   - Clipboard is automatically restored to original Bitcoin address
6. Press Command+V in TextEdit
7. **Expected Result:**
   - Original Bitcoin address pastes (not Ethereum)
   - Green verification shows

#### Success Criteria:
- [ ] Hijack detected within 5ms (ultra-fast)
- [ ] Original content restored automatically
- [ ] Notification shows hijack details
- [ ] `threatsBlocked` increments
- [ ] Paste still works with original address

---

### Test 6: Paste Blocking - Hijack Prevention 🛑

**Objective:** Verify paste is BLOCKED when clipboard is hijacked (different network)

#### Steps:
1. Copy a Bitcoin address: `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`
2. Wait for blue copy indicator
3. **Disable clipboard restoration temporarily** (for testing only):
   - Comment out `restoreClipboard()` in `handleHijackDetected()`
4. Manually copy different address: `0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC`
5. Press **Command+V** in TextEdit
6. **Expected Console Output:**
   ```
   🚨 [PasteBlocker] Command+V intercepted - checking if safe to paste...
      🛑 BLOCKING PASTE - Clipboard has been hijacked!
      Original:  1A1zP1...vfNa
      Hijacked:  0x742d...bEbC
   🚨 PASTE BLOCKED - Showing red alert at cursor!
   ```
7. **Expected UI:**
   - **RED alert window** appears at cursor position
   - Shake animation for urgency
   - Shows:
     - Red X icon
     - Title: "🛑 Paste Blocked!"
     - Original address (green): `1A1zP1...vfNa`
     - Blocked address (red): `0x742d...bEbC`
     - "Got it" dismiss button
   - **Paste operation DOES NOT HAPPEN** - no text inserted!
   - Auto-dismisses after 5 seconds

#### Success Criteria:
- [ ] Paste is completely blocked (no text inserted)
- [ ] Red alert shows at cursor position
- [ ] Shows both original and hijacked addresses
- [ ] Shake animation plays
- [ ] `threatsBlocked` increments
- [ ] User can click "Got it" to dismiss

---

### Test 7: Performance - CPU Usage 📊

**Objective:** Verify ultra-fast monitoring doesn't consume excessive CPU

#### Steps:
1. Open Activity Monitor
2. Filter for "Clipboard" process
3. Let app run for 2 minutes while monitoring
4. **Expected CPU Usage:** <3% average

#### Success Criteria:
- [ ] CPU usage stays below 3%
- [ ] No memory leaks (memory stable)
- [ ] No thermal issues
- [ ] Polling at 5ms intervals (200 checks/second)

---

### Test 8: Pattern Priority - Ethereum vs Bitcoin 🔍

**Objective:** Verify Ethereum is checked BEFORE Bitcoin (more specific pattern)

#### Steps:
1. Copy: `0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC`
2. **Expected Console Output:**
   ```
   🧪 Testing pattern: Ethereum Standard  ← FIRST
   ✅ MATCH! Type: Ethereum
   ```
   (Should NOT test Bitcoin patterns)

#### Success Criteria:
- [ ] Ethereum pattern tested first
- [ ] No false Bitcoin match for 0x addresses
- [ ] Pattern order: Ethereum → Bitcoin → Solana

---

### Test 9: Edge Cases - Non-Crypto Content ❌

**Objective:** Verify app ignores non-crypto clipboard content

#### Test Content:
```
Hello World
https://example.com
12345
not-a-crypto-address-at-all
```

#### Steps:
1. Copy each non-crypto string above
2. **Expected Console Output:**
   ```
   📋 [DEBUG] Clipboard changed!
   ❌ Length check failed (need 26-95 chars)
   OR
   ❌ No patterns matched
   ❌ Not a crypto address
   ```
3. **Expected UI:**
   - NO floating indicator
   - No animations
   - App continues monitoring

#### Success Criteria:
- [ ] No false positives
- [ ] No indicators for non-crypto content
- [ ] Monitoring continues normally

---

### Test 10: Multi-Copy Sequence 🔄

**Objective:** Verify monitoring switches correctly between different crypto types

#### Steps:
1. Copy Bitcoin: `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`
   - Blue "Bitcoin" indicator
2. Copy Ethereum: `0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC`
   - Blue "Ethereum" indicator
3. Copy Solana: `7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV`
   - Blue "Solana" indicator
4. Paste Solana address (Command+V)
   - Green "Solana Verified ✓" indicator
   - Paste succeeds

#### Success Criteria:
- [ ] Each copy shows correct network type
- [ ] Last copied (Solana) is what gets verified on paste
- [ ] No cross-contamination between addresses
- [ ] All 3 networks work in sequence

---

### Test 11: Statistics Tracking 📈

**Objective:** Verify dashboard statistics update correctly

#### Steps:
1. Note initial dashboard values:
   - `copyCount`: ?
   - `pasteCount`: ?
   - `threatsBlocked`: ?
   - `checksToday`: ?
2. Perform sequence:
   - Copy Bitcoin (×1)
   - Paste Bitcoin (×1)
   - Copy Ethereum (×1)
   - Hijack Ethereum → Bitcoin (×1 threat)
   - Paste Bitcoin (×1)
3. **Expected Final Values:**
   - `copyCount`: +2
   - `pasteCount`: +2
   - `threatsBlocked`: +1
   - `checksToday`: Thousands (5ms polling)

#### Success Criteria:
- [ ] All counters increment correctly
- [ ] No threading issues (main thread updates)
- [ ] Dashboard updates in real-time

---

### Test 12: Accessibility Permission Handling 🔐

**Objective:** Verify graceful degradation without permissions

#### Steps:
1. Revoke Accessibility permissions:
   - System Settings → Privacy & Security → Accessibility
   - Disable `Clipboard.app`
2. Restart app
3. **Expected Console Output:**
   ```
   ⚠️  [PasteBlocker] No Accessibility permissions - paste blocking disabled
   ⚠️  [PasteDetector] No Accessibility permissions - paste detection disabled
   ```
4. Try to copy/paste Bitcoin address
5. **Expected Behavior:**
   - Copy detection STILL WORKS (blue indicator)
   - Paste detection DOES NOT WORK (no green indicator)
   - Paste blocking DOES NOT WORK (hijacked paste allowed)
   - App displays permission request prompt

#### Success Criteria:
- [ ] App doesn't crash without permissions
- [ ] Copy detection continues to work
- [ ] Clear warning messages in console
- [ ] Permission request prompt shows

---

## Regression Tests

Run these after any major code changes:

### Regression 1: Threading Safety 🧵
- [ ] No "Publishing changes from background threads" warnings
- [ ] No NSMenu main thread violations
- [ ] All @Published updates wrapped in `DispatchQueue.main.async`

### Regression 2: Build Success ✅
- [ ] Clean build succeeds: `xcodebuild -project Clipboard.xcodeproj -scheme Clipboard clean build`
- [ ] No compiler warnings (except AppIntents metadata)
- [ ] All files in Xcode project

### Regression 3: Memory Leaks 💧
- [ ] Run Instruments → Leaks
- [ ] No leaks detected after 5 minutes of operation
- [ ] Weak self references in closures

---

## Known Issues / TODO

### Current Limitations:
- ❌ **Paste blocking requires clipboard restoration disabled** (for testing)
- ⚠️ **iOS version not yet implemented** (macOS only)
- ⚠️ **Pattern matching for SegWit Bech32m** (not yet added)

### Future Enhancements:
- [ ] Add more crypto networks (Polygon, BNB, etc.)
- [ ] Implement whitelisting for known safe applications
- [ ] Add sound effects for copy/paste/block events
- [ ] Create Settings panel for polling interval adjustment
- [ ] Add export/import for statistics

---

## Quick Reference: Test Addresses

### Bitcoin
```
1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa  (Legacy P2PKH)
bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq  (SegWit Bech32)
3J98t1WpEZ73CNmYviecrnyiWrnqRhWNLy  (P2SH)
```

### Ethereum
```
0x742d35Cc6634C0532925a3b844Bc9e7595f0bEbC  (42 chars!)
0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
0xdAC17F958D2ee523a2206206994597C13D831ec7  (USDT contract)
```

### Solana
```
7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV
DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK
EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
```

---

## Console Debugging Commands

Enable verbose logging (if needed):
```swift
// In ClipboardMonitor.swift, set:
let debugMode = true  // Shows ALL pattern matching attempts
```

Check running processes:
```bash
ps aux | grep Clipboard
```

Monitor real-time logs:
```bash
log stream --process Clipboard --level debug
```

Check Accessibility permissions programmatically:
```bash
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT * FROM access WHERE service='kTCCServiceAccessibility'"
```

---

## Success Checklist (Full Test Pass)

- [ ] All 12 test cases passed
- [ ] No console errors or crashes
- [ ] CPU usage <3%
- [ ] No threading warnings
- [ ] All animations smooth and instant
- [ ] Statistics update correctly
- [ ] Build succeeds with no warnings

**Test Pass Date:** __________
**Tested By:** __________
**Notes:** __________

---

**End of Testing Guide**
