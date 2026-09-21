#!/usr/bin/env python3
"""Exercise real favicon loading against local HTTP fixtures; no Internet needed."""
from contextlib import ExitStack, contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import time
import zlib


ROOT = Path(__file__).resolve().parents[1]


def png(width=512, height=256):
    def chunk(kind, payload):
        return (struct.pack("!I", len(payload)) + kind + payload
                + struct.pack("!I", zlib.crc32(kind + payload)))
    pixels = (b"\x00" + b"\x55\xaa\xdd\xff" * width) * height
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


@contextmanager
def website(mode):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            requests.append((self.path, self.headers.get("Authorization"), self.headers.get("Cookie")))
            status, mime, body = 200, "text/html", b""
            if mode == "cancel":
                time.sleep(2)
            if self.path == "/":
                if mode == "declared":
                    body = b'''<base href="/assets/">
                    <LINK href='icons/site.png?v=1&amp;theme=light' REL='shortcut icon'>
                    <link rel="apple-touch-icon" href="/touch.png">'''
                elif mode == "oversized":
                    body = b'<link rel="icon" href="/huge.png">'
                else:
                    body = b"<html><head></head></html>"
            elif self.path == "/assets/icons/site.png?v=1&theme=light":
                mime, body = "image/png", png()
            elif self.path == "/favicon.ico":
                mime = "image/x-icon"
                body = b"not an image" if mode == "oversized" else png()
            elif self.path == "/huge.png":
                mime, body = "image/png", bytes(512 * 1024 + 1)
            else:
                status = 404
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Set-Cookie", "fixture=do-not-send")
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_port, requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


HARNESS = r'''
import AppKit
import Foundation

@main
struct WebsiteIconLoaderChecks {
    static func main() async {
        let privatePage = URL(string: "https://user:password@example.test:8443/private/page?token=secret#fragment")!
        assert(WebsiteIconLoader.originURL(for: privatePage)?.absoluteString == "https://example.test:8443/")
        assert(WebsiteIconLoader.originURL(for: URL(string: "file:///tmp/page.html")!) == nil)
        let html = """
        <!-- <link rel='icon' href='comment.png'> -->
        <script>const text = "<link rel='icon' href='script.png'>";</script>
        <base href='../assets/'>
        <link href='ordinary.ico' rel='shortcut icon'>
        <link rel='ICON' type='image/svg+xml' href='vector.svg'>
        <LINK REL='apple-touch-icon' HREF='//cdn.test/touch.png#ignored'>
        <link rel=icon href='brand.png?a=1&amp;b=2'>
        <link rel=icon href='brand.png?a=1&amp;b=2'>
        <link rel=icon href='data:image/png;base64,invalid'>
        <link rel=stylesheet href='styles.css'>
        """
        let candidates = WebsiteIconLoader.iconCandidates(in: html, baseURL: URL(string: "https://example.test/welcome/home")!)
        assert(candidates.map(\.absoluteString) == ["https://cdn.test/touch.png", "https://example.test/assets/brand.png?a=1&b=2", "https://example.test/assets/ordinary.ico"])
        assert(WebsiteIconLoader.pngData(from: Data("not image data".utf8)) == nil)
        assert(WebsiteIconLoader.pngData(from: Data(repeating: 0, count: WebsiteIconLoader.maximumIconBytes + 1)) == nil)

        func page(_ port: String) -> URL {
            URL(string: "http://user:password@127.0.0.1:\(port)/private/page?token=secret#fragment")!
        }
        let declared = await WebsiteIconLoader.fetch(for: page(CommandLine.arguments[1]))
        assert(declared != nil, "declared icon was not loaded")
        let bitmap = NSBitmapImageRep(data: declared!)!
        assert(bitmap.pixelsWide == 128 && bitmap.pixelsHigh == 64, "image was not downsampled proportionally")
        assert(declared!.count <= WebsiteIconLoader.maximumPNGBytes)
        let fallback = await WebsiteIconLoader.fetch(for: page(CommandLine.arguments[2]))
        assert(fallback != nil, "favicon.ico fallback was not loaded")
        let oversized = await WebsiteIconLoader.fetch(for: page(CommandLine.arguments[3]))
        assert(oversized == nil, "invalid/oversized response was accepted")

        let started = ProcessInfo.processInfo.systemUptime
        let pending = Task { await WebsiteIconLoader.fetch(for: page(CommandLine.arguments[4])) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        pending.cancel()
        let cancelled = await pending.value
        assert(cancelled == nil)
        assert(ProcessInfo.processInfo.systemUptime - started < 1.5, "cancellation did not cancel the HTTP request")
        print("Website icon runtime checks passed.")
    }
}
'''


def main():
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    with ExitStack() as stack:
        temporary = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="dok-website-icon-test-", dir=ROOT / "work")))
        source = temporary / "checks.swift"
        source.write_text(HARNESS)
        binary = temporary / "checks"
        subprocess.run([compiler, "-swift-version", "5", str(ROOT / "Sources/dok/WebsiteIconLoader.swift"),
                        str(source), "-o", str(binary)], check=True)
        fixtures = [stack.enter_context(website(mode)) for mode in ["declared", "fallback", "oversized", "cancel"]]
        subprocess.run([str(binary), *(str(port) for port, _ in fixtures)], check=True, timeout=15)
        expected_paths = [["/", "/touch.png", "/assets/icons/site.png?v=1&theme=light"],
                          ["/", "/favicon.ico"], ["/", "/huge.png", "/favicon.ico"]]
        for (_, requests), expected in zip(fixtures, expected_paths):
            assert [path for path, _, _ in requests] == expected, requests
        for _, requests in fixtures:
            assert all(auth is None and cookie is None for _, auth, cookie in requests), requests
    print("Website origin privacy, fallback, bounds and cancellation checks passed.")


if __name__ == "__main__":
    main()
