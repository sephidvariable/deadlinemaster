# Network checks — 2026-11-08

No system network settings were changed.

- Restricted shell commands could not resolve any test hostname. Repeating outside the sandbox confirmed that this was a sandbox limitation, not global DNS failure.
- Outside the sandbox, DNS resolved. Homebrew's formula API returned HTTP 200. Direct FFmpeg HTTPS timed out during TLS, GNU timed out connecting, and GitHub raw reset the connection.
- macOS had HTTP and HTTPS proxies enabled, but no proxy environment variables were set. curl did not automatically use those system proxy settings.
- Explicitly passing the existing system HTTPS proxy made GNU and GitHub raw return HTTP 200. FFmpeg still timed out. Forcing IPv4/IPv6 did not resolve FFmpeg access.
- Source collection improved from 17/81 to 72/81 verified archives through the proxy. Seven archive downloads remain incomplete (including FFmpeg; LLVM's 179 MB source exceeded the timeout), and aom/x264 need Git source retrieval at their exact formula revisions.

Re-run developer source downloads with:

    python3 scripts/collect-ffmpeg-sources.py --system-proxy

This flag reads the existing system proxy and passes it only to curl. It does not configure the OS or persist credentials. The evidence does not identify whether remaining failures originate at the proxy upstream, routing, or the destination server. App audio conversion itself requires no network.
