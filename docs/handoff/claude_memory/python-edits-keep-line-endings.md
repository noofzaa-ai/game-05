---
name: python-edits-keep-line-endings
description: Editing zorx files with Windows python3 read_text/write_text silently turns LF into CRLF and broke a test literal
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7cbad94-e653-4571-b11f-5919111d855c
  modified: 2026-10-06T15:44:40.683Z
---

On this machine `python3` is Windows Python: `Path.write_text()` writes CRLF. Files in zorx are mixed LF/CRLF; a GDScript multi-line `"""` literal (tests/test_map_data.gd MINIMAL) changed to CRLF and a `.replace("...\n\t...")` test failed (2026-10-06).

**Why:** silent line-ending churn causes confusing test failures and noisy diffs.
**How to apply:** when scripting edits with python, use `read_bytes()/write_bytes()` or `open(..., newline='')` to keep each file's endings; prefer the Edit tool for small changes.
