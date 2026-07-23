"""Serve the Godot Web build with safe compression and cache negotiation."""

from __future__ import annotations

import argparse
import gzip
import re
import threading
from collections import OrderedDict
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


PROJECT_ROOT = Path(__file__).resolve().parent
PROJECT_VERSION_MATCH = re.search(
    r'^config/version="([^"]+)"',
    (PROJECT_ROOT / "project.godot").read_text(encoding="utf-8"),
    re.MULTILINE,
)
PROJECT_VERSION = PROJECT_VERSION_MATCH.group(1) if PROJECT_VERSION_MATCH else "development"
BUILD_ID = PROJECT_VERSION.split("-", 1)[1] if "-" in PROJECT_VERSION else PROJECT_VERSION


class NoCacheRequestHandler(SimpleHTTPRequestHandler):
    """Latest-safe local handler with immutable caching for versioned binaries."""

    _LEGACY_BUILD_PATH = re.compile(
        r"^/game/riding-dirty-gate8-v\d+(?P<suffix>\..+)$"
    )
    _CONTENT_HASH = re.compile(r"(?:^|[._-])[0-9a-f]{8,}(?=[._-]|$)", re.IGNORECASE)
    _COMPRESSIBLE_SUFFIXES = frozenset({".js", ".pck", ".wasm"})
    _VERSION_QUERY_KEYS = frozenset({"build", "hash", "rev", "sha", "v", "version"})
    _IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable"
    _UPDATE_SAFE_CACHE_CONTROL = "no-store, no-cache, must-revalidate, max-age=0"
    _GZIP_CACHE_MAX_ENTRIES = 8
    _GZIP_CACHE_MAX_BYTES = 64 * 1024 * 1024
    _GZIP_COMPRESSION_LEVEL = 4
    _gzip_cache: OrderedDict[Path, tuple[tuple[int, int, int], bytes]] = OrderedDict()
    _gzip_cache_lock = threading.Lock()

    def _request_path(self) -> str:
        return urlsplit(self.path).path

    def _is_compressible_request(self) -> bool:
        return Path(self._request_path()).suffix.lower() in self._COMPRESSIBLE_SUFFIXES

    def _accepts_gzip(self) -> bool:
        """Honor explicit gzip and wildcard quality values from Accept-Encoding."""
        explicit: bool | None = None
        wildcard: bool | None = None
        for raw_value in self.headers.get_all("Accept-Encoding", []):
            for raw_token in raw_value.split(","):
                parts = [part.strip() for part in raw_token.split(";")]
                coding = parts[0].lower()
                if not coding:
                    continue
                quality = 1.0
                for parameter in parts[1:]:
                    name, separator, value = parameter.partition("=")
                    if separator and name.strip().lower() == "q":
                        try:
                            quality = float(value.strip())
                        except ValueError:
                            quality = 0.0
                        break
                accepted = quality > 0.0
                if coding == "gzip":
                    explicit = accepted
                elif coding == "*":
                    wildcard = accepted
        return explicit if explicit is not None else bool(wildcard)

    @staticmethod
    def _file_signature(stat_result: object) -> tuple[int, int, int]:
        return (
            int(getattr(stat_result, "st_mtime_ns")),
            int(getattr(stat_result, "st_ctime_ns")),
            int(getattr(stat_result, "st_size")),
        )

    @classmethod
    def _cached_gzip_bytes(cls, path: Path) -> tuple[bytes, object]:
        """Return coherent gzip bytes, invalidating entries when a file changes."""
        resolved = path.resolve()
        for _attempt in range(3):
            before = resolved.stat()
            signature = cls._file_signature(before)
            with cls._gzip_cache_lock:
                cached = cls._gzip_cache.get(resolved)
                if cached is not None and cached[0] == signature:
                    cls._gzip_cache.move_to_end(resolved)
                    return cached[1], before

            source = resolved.read_bytes()
            after_read = resolved.stat()
            if cls._file_signature(after_read) != signature or len(source) != signature[2]:
                continue
            compressed = gzip.compress(
                source,
                compresslevel=cls._GZIP_COMPRESSION_LEVEL,
                mtime=0,
            )
            after_compress = resolved.stat()
            if cls._file_signature(after_compress) != signature:
                continue

            with cls._gzip_cache_lock:
                cls._gzip_cache[resolved] = (signature, compressed)
                cls._gzip_cache.move_to_end(resolved)
                while (
                    len(cls._gzip_cache) > cls._GZIP_CACHE_MAX_ENTRIES
                    or sum(len(entry[1]) for entry in cls._gzip_cache.values())
                    > cls._GZIP_CACHE_MAX_BYTES
                ):
                    cls._gzip_cache.popitem(last=False)
            return compressed, after_compress
        raise OSError(f"File changed repeatedly while compressing: {resolved}")

    def _is_immutable_build_asset(self) -> bool:
        split = urlsplit(self.path)
        request_path = split.path
        suffix = Path(request_path).suffix.lower()
        if not request_path.startswith("/game/") or suffix not in self._COMPRESSIBLE_SUFFIXES:
            return False
        if not Path(self.translate_path(request_path)).is_file():
            return False
        query = parse_qs(split.query, keep_blank_values=False)
        has_version_query = any(query.get(key) for key in self._VERSION_QUERY_KEYS)
        has_content_hash = self._CONTENT_HASH.search(Path(request_path).name) is not None
        return has_version_query or has_content_hash

    def _serve_gzip(self, *, head_only: bool) -> bool:
        if (
            not self._is_compressible_request()
            or not self._accepts_gzip()
            or self.headers.get("Range") is not None
        ):
            return False
        path = Path(self.translate_path(self._request_path()))
        if not path.is_file():
            return False
        try:
            payload, stat_result = self._cached_gzip_bytes(path)
        except OSError:
            return False

        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Last-Modified", self.date_time_string(stat_result.st_mtime))
        self.end_headers()
        if not head_only:
            self.wfile.write(payload)
        return True

    def _redirect_legacy_build(self) -> bool:
        """Keep every browser entry point on the canonical current package."""
        match = self._LEGACY_BUILD_PATH.fullmatch(urlsplit(self.path).path)
        if match is None:
            return False
        suffix = match.group("suffix")
        destination = self._canonical_asset_destination(suffix)
        self.send_response(307)
        self.send_header("Location", destination)
        # An old wrapper can already be resident while it lazily requests its
        # versioned PCK/WASM. Redirect every asset, not only the HTML document,
        # and explicitly discard the origin's cached legacy responses.
        self.send_header("Clear-Site-Data", '"cache"')
        self.end_headers()
        return True

    def _canonical_asset_destination(self, suffix: str) -> str:
        """Resolve legacy links to the one current content-addressed payload."""
        if suffix.lower() in {".wasm", ".pck"}:
            game_root = Path(self.translate_path("/game"))
            candidates = sorted(game_root.glob(f"index.*{suffix}"))
            hashed = [candidate for candidate in candidates if self._CONTENT_HASH.search(candidate.name)]
            if hashed:
                return f"/game/{hashed[-1].name}"
        return f"/game/index{suffix}?build={BUILD_ID}"

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if self._redirect_legacy_build():
            return
        if not self._serve_gzip(head_only=False):
            super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib handler API
        if self._redirect_legacy_build():
            return
        if not self._serve_gzip(head_only=True):
            super().do_HEAD()

    def end_headers(self) -> None:
        self.send_header("X-Riding-Dirty-Build", BUILD_ID)
        # Godot's threaded Web export uses SharedArrayBuffer. Keep the wrapper,
        # iframe and every engine asset in one isolated origin so the worker
        # build remains available without weakening the browser boundary.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        if self._is_compressible_request():
            self.send_header("Vary", "Accept-Encoding")
        if self._is_immutable_build_asset():
            self.send_header("Cache-Control", self._IMMUTABLE_CACHE_CONTROL)
        else:
            self.send_header("Cache-Control", self._UPDATE_SAFE_CACHE_CONTROL)
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8777)
    parser.add_argument(
        "--directory",
        type=Path,
        default=Path(__file__).resolve().parent / "web",
    )
    args = parser.parse_args()
    handler = partial(NoCacheRequestHandler, directory=str(args.directory.resolve()))
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    print(
        f"Serving {args.directory.resolve()} at http://{args.bind}:{args.port} "
        "with gzip negotiation and version-aware caching",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
