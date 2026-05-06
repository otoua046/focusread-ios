## Overview
Added a new "Current Location" preview feature to the Reader. This allows users to quickly see the broader context of their current reading position without losing their place.

## Features
* **Current Location Sheet:** Added a top-right reader button that opens a native SwiftUI sheet.
* **Smart Subtitles:** 
  * TXT/pasted: `Word X of Y`
  * PDF/image: `Page P · Word X of Y`
  * EPUB: `Chapter N: Title · Word X of Y`
* **Context Snippet:** Displays up to 131 words of surrounding text (60 before, current word, 70 after). The current word is highlighted using the app's accent color, previous text is primary colored, and upcoming text is dimmed.

## Technical Details
* Reuses existing in-memory `ReadingSession.tokens` and metadata. No parser, cleanup, AI, or persistence path was touched.
* Uses native SwiftUI `.sheet` with medium/large detents, Dynamic Type-friendly `Text`, and `AttributedString` generated only from the bounded preview slice.

## Verification
* Unit tests successfully added for TXT, PDF, EPUB boundaries, punctuation, and large-book scenarios.
* Tests run and pass cleanly via `xcodebuild` and verified with no whitespace issues.