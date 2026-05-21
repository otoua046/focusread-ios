# Benchmark Fixtures

The XCTest benchmark suite generates most scale fixtures at runtime:

- seeded Library data for 100, 500, and 1000 saved reads
- large text documents for tokenization and reader-open tests
- native-text PDFs
- image-only scanned PDFs for OCR
- synthetic Discover book and shelf data

Existing checked-in test fixtures are reused for EPUB and PDF realism:

- `FocusReadTests/Fixtures/EPUB/jane-austen_pride-and-prejudice.epub`
- `FocusReadTests/Fixtures/PDF/E001005.pdf`
- `FocusReadTests/Fixtures/PDF/The Psychology of Persuasion.pdf`

Keep generated large artifacts in `benchmarks/results/` or the system temporary directory, not in git.
