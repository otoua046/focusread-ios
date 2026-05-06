## Overview
This PR introduces a subtle, warm accent color to the app's visual identity, replacing default system tints (like generic blue) while strictly maintaining the minimal Apple-like design language.

## Changes
*   **New Accent Color:** Introduced `AppTheme.accent` with a custom warm tone. 
    *   **Dark Mode:** Uses a vibrant `#f0e1c8` for excellent contrast against dark backgrounds.
    *   **Light Mode:** Adapts to a darker, slightly muted warm tone (`#bea06e`) to guarantee readability against white backgrounds without losing the brand hue.
*   **Daily Goal Ring:** Updated the progress stroke in `StatsView` (`DailyGoalRingWidget`) to use the new accent.
*   **Select Mode Checkmarks:** Upgraded the multi-select checkmarks in the Library view to utilize the accent color when active.
*   **Reader Controls:** 
    *   The `ReaderView` linear progress bar tint is now updated to the accent color.
    *   The central Play/Pause button inside `ReaderControlsView` now uses the accent color for its background.
*   **Settings Toggles:** All behavior and typography toggles (Italic, Haptics, Reverse WPM Drag, Punctuation Pauses) now glow with the custom tint when enabled.
*   **Tab & Title Renaming:** Personalised the "Stats" tab in the navigation bar and the main header within `StatsView` to read **"My Stats"**.

## Verification
*   Built and verified using `xcodebuild`.
*   Tested the complete UI in both Light and Dark mode on iOS Simulator to confirm color contrast rules apply correctly and automatically.
*   Successfully rebased cleanly onto the latest `main`.