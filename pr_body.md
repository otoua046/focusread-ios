## Overview
This PR introduces a suite of new features, UI refinements, and critical stability fixes to the FocusRead app. The primary focus is on enhancing the Library bookshelf experience and resolving core memory and reading engine bugs.

## Features & Improvements
* **Library Controls Menu:** Added a native Apple Books-style `LibraryControlsMenu` providing multi-selection, view modes (Grid and List), and sorting options (Recent, Title, Author, Manual). State is persisted across app launches via `AppStorage`.
* **List View Layout:** Implemented `LibraryListView` and `LibraryListRow`, presenting a clean, flat list aesthetic devoid of heavy shadows and card containers. Rows include thumbnails, titles, authors, and reading progress, separated by subtle alignment-aware dividers.
* **Author Metadata Extraction:** Extended `SavedRead` and `ImportedDocument` to support an optional `author` property. Upgraded `EPUBTextExtractor` and its internal `OPFXMLParser` to seamlessly extract `creator` metadata from EPUB files.
* **Select Mode:** Built a comprehensive multi-select mode with "Select All" / "Deselect All" options and a safe, dynamically worded confirmation dialog for bulk deletions.
* **Menu Action Polish:** Enforced explicit `.red` foreground styling on destructive item-level actions (e.g., the Delete button inside the individual read three-dot menus) and added corresponding SF Symbols for all actions.

## Bug Fixes
* **Paragraph Break Tokenization:** Fixed a critical flaw in `TextTokenizer` where paragraph breaks (`

`) were erroneously applied to the *first word* of the next paragraph. Breaks are now correctly applied retrospectively to the *last word* of the preceding paragraph. This fixes awkward RSVP pause timings and broken sentence rewind behaviors.
* **Memory Leaks & Retain Cycles:** Conducted a deep codebase review and resolved severe memory leaks across `ReaderViewModel`, `GoToViewModel`, and `DocumentImportViewModel`. Fixed infinite execution loops by correctly capturing `[weak self]` inside `Task` blocks, ensuring ViewModels and their underlying `RSVPReadingEngine` tasks deallocate cleanly upon view dismissal.
* **Duplicate Menu Rows:** Fixed a UI bug causing duplicate "Grid" entries and mismatched icons in the library view mode toggle by replacing manual buttons with native `.inline` Swift `Picker` components.

## Verification & Testing
* Added a comprehensive set of unit tests in `TextTokenizerTests` covering paragraph break retroactivity, weak punctuation upgrades, section boundaries, and sentence rewind stability.
* The entire `FocusReadTests` suite ran and passed successfully on the iPhone 17 Simulator (iOS 18).
* Built and validated the application with `xcodebuild`, confirming zero compilation errors or active compiler warnings related to the changes.
* Visual verification of Layout shifts and SF Symbol alignment.