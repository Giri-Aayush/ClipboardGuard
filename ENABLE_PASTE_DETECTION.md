# 🔧 Enable Paste Detection (Required!)

## Why Paste Detection Isn't Working:

Your console shows:
```
⚠️  [PasteDetector] No Accessibility permissions - paste detection disabled
   To enable: System Settings → Privacy & Security → Accessibility → Enable Clipboard
```

This means macOS is blocking the app from detecting keyboard events (⌘V).

## How to Fix:

### Step 1: Open System Settings
- Click the Apple menu () → System Settings

### Step 2: Go to Privacy & Security
- Scroll down and click "Privacy & Security"

### Step 3: Click Accessibility
- In the Privacy section, click "Accessibility"

### Step 4: Add Clipboard App
- Click the **(+)** button at the bottom
- Navigate to: `/Users/aayushgiri/Desktop/Clipboard/DerivedData/Build/Products/Debug/Clipboard.app`
- Or just find "Clipboard" if it's already running
- Select it and click "Open"

### Step 5: Enable the Checkbox
- Make sure the checkbox next to "Clipboard" is **checked** ✅

### Step 6: Restart the App
- Quit Clipboard completely
- Run it again from Xcode (⌘R)

## Verify It's Working:

After restarting, the console should show:
```
✅ [PasteDetector] Accessibility permissions granted
📋 [PasteDetector] Started monitoring for paste events
```

Now when you press ⌘V, you'll see:
```
📋 [PasteDetector] ⌘V detected - USER PASTED!
```

---

## Alternative: If You Can't Find the App

Run this command in Terminal to open System Settings directly:
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Then add the Clipboard app manually!
