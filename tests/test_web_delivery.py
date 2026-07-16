"""Focused contract tests for the local Web delivery and readiness handshake."""

from __future__ import annotations

import gzip
import hashlib
import http.client
import json
import re
import sys
import tempfile
import threading
import unittest
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from serve_web import BUILD_ID, NoCacheRequestHandler  # noqa: E402


class _QuietHandler(NoCacheRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass


class WebDeliveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._temporary_directory = tempfile.TemporaryDirectory()
        cls.web_root = Path(cls._temporary_directory.name)
        game_root = cls.web_root / "game"
        game_root.mkdir()
        cls.assets = {
            "/app.js": b"console.log('wrapper');\n" * 32,
            "/game/index.js": b"const engine = 'test';\n" * 256,
            "/game/index.pck": b"PCK" + bytes(range(256)) * 64,
            "/game/index.wasm": b"\x00asm" + b"WASM-DATA" * 8192,
            "/game/index.01234567.wasm": b"\x00asm" + b"HASHED" * 1024,
            "/game/index.01234567.audio.worklet.js": b"registerProcessor('test', class {});\n",
        }
        (cls.web_root / "index.html").write_text("wrapper", encoding="utf-8")
        (game_root / "index.html").write_text("game", encoding="utf-8")
        for request_path, payload in cls.assets.items():
            destination = cls.web_root / request_path.removeprefix("/")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)

        with _QuietHandler._gzip_cache_lock:
            _QuietHandler._gzip_cache.clear()
        handler = partial(_QuietHandler, directory=str(cls.web_root))
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = int(cls.server.server_address[1])

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5.0)
        cls._temporary_directory.cleanup()

    def request(
        self,
        method: str,
        target: str,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], bytes]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10.0)
        connection.request(method, target, headers=headers or {})
        response = connection.getresponse()
        body = response.read()
        response_headers = {name.lower(): value for name, value in response.getheaders()}
        status = response.status
        connection.close()
        return status, response_headers, body

    def test_gzip_get_and_head_have_variant_correct_headers(self) -> None:
        for target in ("/app.js", "/game/index.js", "/game/index.pck", "/game/index.wasm"):
            with self.subTest(target=target):
                status, headers, body = self.request(
                    "GET", target, {"Accept-Encoding": "br, gzip;q=1"}
                )
                self.assertEqual(status, 200)
                self.assertEqual(headers.get("content-encoding"), "gzip")
                self.assertIn("accept-encoding", headers.get("vary", "").lower())
                self.assertEqual(int(headers["content-length"]), len(body))
                self.assertEqual(gzip.decompress(body), self.assets[target])

                head_status, head_headers, head_body = self.request(
                    "HEAD", target, {"Accept-Encoding": "gzip"}
                )
                self.assertEqual(head_status, 200)
                self.assertEqual(head_headers.get("content-encoding"), "gzip")
                self.assertEqual(int(head_headers["content-length"]), len(body))
                self.assertEqual(head_body, b"")

    def test_identity_variant_honors_explicit_gzip_rejection(self) -> None:
        target = "/game/index.wasm"
        status, headers, body = self.request(
            "GET", target, {"Accept-Encoding": "gzip;q=0, *;q=1"}
        )
        self.assertEqual(status, 200)
        self.assertNotIn("content-encoding", headers)
        self.assertIn("accept-encoding", headers.get("vary", "").lower())
        self.assertEqual(int(headers["content-length"]), len(self.assets[target]))
        self.assertEqual(body, self.assets[target])

    def test_every_response_enables_cross_origin_isolation(self) -> None:
        for target in (
            "/",
            "/game/index.html",
            "/game/index.js",
            "/game/index.wasm",
            "/game/index.01234567.audio.worklet.js",
        ):
            with self.subTest(target=target):
                status, headers, _body = self.request("HEAD", target)
                self.assertEqual(status, 200)
                self.assertEqual(headers.get("cross-origin-opener-policy"), "same-origin")
                self.assertEqual(headers.get("cross-origin-embedder-policy"), "require-corp")
                self.assertEqual(headers.get("cross-origin-resource-policy"), "same-origin")
                if target.endswith(".audio.worklet.js"):
                    self.assertEqual(headers.get("content-type"), "application/javascript")

    def test_only_versioned_game_assets_are_immutable(self) -> None:
        immutable_targets = (
            f"/game/index.wasm?build={BUILD_ID}",
            "/game/index.js?v=22",
            "/game/index.01234567.wasm",
            "/game/index.01234567.audio.worklet.js",
        )
        for target in immutable_targets:
            with self.subTest(target=target):
                status, headers, _body = self.request("HEAD", target)
                self.assertEqual(status, 200)
                self.assertEqual(
                    headers.get("cache-control"),
                    "public, max-age=31536000, immutable",
                )
                self.assertNotIn("pragma", headers)

        update_safe_targets = (
            "/",
            f"/app.js?build={BUILD_ID}",
            f"/game/index.html?build={BUILD_ID}",
            "/game/index.wasm",
            "/game/index.js?audit=current",
        )
        for target in update_safe_targets:
            with self.subTest(target=target):
                status, headers, _body = self.request("HEAD", target)
                self.assertEqual(status, 200)
                self.assertIn("no-store", headers.get("cache-control", ""))
                self.assertEqual(headers.get("pragma"), "no-cache")

    def test_gzip_cache_invalidates_when_the_file_changes(self) -> None:
        target = "/game/index.js"
        _status, _headers, first_body = self.request(
            "GET", target, {"Accept-Encoding": "gzip"}
        )
        replacement = b"const engine = 'replacement';\n" * 384
        destination = self.web_root / target.removeprefix("/")
        destination.write_bytes(replacement)

        _status, headers, second_body = self.request(
            "GET", target, {"Accept-Encoding": "gzip"}
        )
        self.assertEqual(headers.get("content-encoding"), "gzip")
        self.assertNotEqual(first_body, second_body)
        self.assertEqual(gzip.decompress(second_body), replacement)
        destination.write_bytes(self.assets[target])

    def test_legacy_redirect_contract_is_preserved(self) -> None:
        status, headers, body = self.request(
            "GET", "/game/riding-dirty-gate8-v21.wasm"
        )
        self.assertEqual(status, 307)
        self.assertEqual(
            headers.get("location"),
            "/game/index.01234567.wasm",
        )
        self.assertEqual(headers.get("clear-site-data"), '"cache"')
        self.assertIn("no-store", headers.get("cache-control", ""))
        self.assertEqual(body, b"")


class WebReadinessContractTests(unittest.TestCase):
    def test_wrapper_accessibility_contract_is_present(self) -> None:
        wrapper = (PROJECT_ROOT / "web" / "index.html").read_text(encoding="utf-8")
        styles = (PROJECT_ROOT / "web" / "styles.css").read_text(encoding="utf-8")
        self.assertIn('role="alert"', wrapper)
        self.assertGreaterEqual(wrapper.count('role="status"'), 2)
        self.assertIn('aria-live="polite"', wrapper)
        self.assertIn('aria-label="Enter fullscreen"', wrapper)
        self.assertIn('rel="icon"', wrapper)
        self.assertIn("prefers-reduced-motion: reduce", styles)
        self.assertIn("animation: none", styles)
        self.assertIn(":focus-visible", styles)

    def test_touch_wrapper_has_landscape_and_safe_area_contract(self) -> None:
        wrapper = (PROJECT_ROOT / "web" / "index.html").read_text(encoding="utf-8")
        styles = (PROJECT_ROOT / "web" / "styles.css").read_text(encoding="utf-8")
        self.assertIn("KEYBOARD, GAMEPAD, OR TOUCH", wrapper)
        self.assertIn("orientation-notice", wrapper)
        self.assertIn("ROTATE TO RIDE", wrapper)
        self.assertIn("(pointer: coarse) and (orientation: landscape)", styles)
        self.assertIn("(pointer: coarse) and (orientation: portrait)", styles)
        self.assertIn("env(safe-area-inset-left)", styles)
        self.assertIn("env(safe-area-inset-right)", styles)
        self.assertIn("--playing-chrome: calc(max(4px, env(safe-area-inset-top))", styles)

    def test_static_hosts_boot_through_root_scoped_isolation_worker(self) -> None:
        wrapper = (PROJECT_ROOT / "web" / "index.html").read_text(encoding="utf-8")
        worker = (PROJECT_ROOT / "web" / "coi-serviceworker.js").read_text(
            encoding="utf-8"
        )
        self.assertIn('register("./coi-serviceworker.js"', wrapper)
        self.assertIn('scope: "./"', wrapper)
        self.assertIn("window.crossOriginIsolated", wrapper)
        self.assertIn('allow="autoplay; fullscreen; gamepad; cross-origin-isolated"', wrapper)
        self.assertIn("self.skipWaiting()", worker)
        self.assertIn("self.clients.claim()", worker)
        self.assertIn("'Cross-Origin-Opener-Policy': 'same-origin'", worker)
        self.assertIn("'Cross-Origin-Embedder-Policy': 'require-corp'", worker)
        self.assertIn("'Cross-Origin-Resource-Policy': 'same-origin'", worker)

    def test_wrapper_waits_for_the_inner_engine_message(self) -> None:
        wrapper = (PROJECT_ROOT / "web" / "app.js").read_text(encoding="utf-8")
        load_handler = re.search(
            r"frame\.addEventListener\('load',[\s\S]*?\n  \}\);",
            wrapper,
        )
        self.assertIsNotNone(load_handler)
        self.assertIn("if (!gameRequested || engineSettled) return", load_handler.group(0))
        self.assertIn("STARTING ENGINE", load_handler.group(0))
        self.assertNotIn("ENGINE ONLINE", load_handler.group(0))
        self.assertIn("event.origin !== window.location.origin", wrapper)
        self.assertIn("event.source !== frame.contentWindow", wrapper)
        self.assertIn("event.data.type === 'engine-ready'", wrapper)
        self.assertIn("runtimeStatus.textContent = 'ENGINE ONLINE'", wrapper)
        self.assertIn("startupTimeoutMs", wrapper)
        self.assertIn("RETRY THE TOUR", wrapper)
        self.assertIn("showStartFailure", wrapper)
        self.assertIn("event.data.type === 'engine-progress'", wrapper)
        self.assertNotIn("window.addEventListener('keydown'", wrapper)

    def test_inner_page_posts_ready_only_after_start_game_resolves(self) -> None:
        inner = (PROJECT_ROOT / "web" / "game" / "index.html").read_text(
            encoding="utf-8"
        )
        start_game = inner.index("engine.startGame({")
        ready_message = inner.index("notifyHost('engine-ready')")
        self.assertGreater(ready_message, start_game)
        self.assertIn("window.parent.postMessage", inner)
        self.assertIn("window.location.origin", inner)
        self.assertIn("notifyHost('engine-error')", inner)
        self.assertIn("notifyHost('engine-progress'", inner)

    def test_exported_payloads_are_content_addressed_and_present(self) -> None:
        inner = (PROJECT_ROOT / "web" / "game" / "index.html").read_text(
            encoding="utf-8"
        )
        config_match = re.search(r"const GODOT_CONFIG = (\{.*?\});", inner)
        self.assertIsNotNone(config_match)
        config = json.loads(config_match.group(1))
        assets = (
            f"{config['executable']}.wasm",
            str(config.get("mainPack", "")),
        )
        for asset in assets:
            with self.subTest(asset=asset):
                self.assertRegex(asset, r"^index\.[0-9a-f]{12}\.(?:wasm|pck)$")
                self.assertTrue((PROJECT_ROOT / "web" / "game" / asset).is_file())
                self.assertIn(asset, config.get("fileSizes", {}))

        runtime_companions = (
            ("audio_worklet", f"{config['executable']}.audio.worklet.js"),
            (
                "audio_position_worklet",
                f"{config['executable']}.audio.position.worklet.js",
            ),
        )
        manifest = json.loads(
            (PROJECT_ROOT / "web" / "build-manifest.json").read_text(
                encoding="utf-8"
            )
        )
        asset_records = manifest.get("assets", {})
        runtime_components = {
            key: asset_records.get(key, {}).get("sha256", "")
            for key in ("wasm", "audio_worklet", "audio_position_worklet")
        }
        runtime_sha = hashlib.sha256(
            json.dumps(
                runtime_components,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("ascii")
        ).hexdigest()
        self.assertEqual(config["executable"], f"index.{runtime_sha[:12]}")
        self.assertEqual(
            asset_records.get("wasm", {}).get("runtime_bundle_sha256"),
            runtime_sha,
        )
        for manifest_key, asset in runtime_companions:
            with self.subTest(asset=asset):
                self.assertRegex(
                    asset,
                    r"^index\.[0-9a-f]{12}\.audio(?:\.position)?\.worklet\.js$",
                )
                asset_path = PROJECT_ROOT / "web" / "game" / asset
                self.assertTrue(asset_path.is_file())
                record = asset_records.get(manifest_key, {})
                self.assertEqual(record.get("file"), asset)
                self.assertEqual(record.get("bytes"), asset_path.stat().st_size)
                self.assertEqual(
                    record.get("sha256"),
                    hashlib.sha256(asset_path.read_bytes()).hexdigest(),
                )

        engine = (PROJECT_ROOT / "web" / "game" / "index.js").read_text(
            encoding="utf-8"
        )
        self.assertIn("`${loadPath}.audio.worklet.js`", engine)
        self.assertIn("`${loadPath}.audio.position.worklet.js`", engine)


if __name__ == "__main__":
    unittest.main(verbosity=2)
