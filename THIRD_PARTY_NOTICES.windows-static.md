# Windows static-build notices

`dist/windows-static/pdfgrep.exe` is a Windows 11 x86-64 executable built
from pdfgrep (GPL-2.0-only), Poppler (GPL-2.0-or-later), Gnulib modules,
PCRE2 (BSD-3-Clause), libgcrypt/libgpg-error (LGPL), TRE (BSD), and the
offline Poppler image and font libraries supplied by the UCRT64 SDK.

The exact Poppler source archive and checksum are recorded in
`windows-static-sources.lock`. Exact UCRT64 SDK package versions are recorded
in `windows-static-sdk.lock`; their source packages and build recipes are
published by MSYS2. The complete corresponding source for pdfgrep is this
repository. Distributors must satisfy the applicable GPL and LGPL source and
relinking obligations when redistributing the executable.
