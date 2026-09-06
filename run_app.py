#!/usr/bin/env python3
"""Desktop application entry point for Madrid Public Libraries Book Finder.

Orchestrates the FastAPI backend server on localhost and launches
the user's default web browser (or pywebview native window if available).
"""

import os
import sys
import time
import socket
import threading
import webbrowser
import uvicorn

# Ensure project root is in sys.path
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from backend.main import app


def find_free_port(default_port: int = 8000) -> int:
    """Checks if default_port is free; if not, selects an available ephemeral port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", default_port))
            return default_port
        except OSError:
            pass

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def run_server(host: str, port: int):
    """Runs the Uvicorn ASGI server in a background thread."""
    config = uvicorn.Config(
        app=app,
        host=host,
        port=port,
        log_level="info",
        access_log=False,
    )
    server = uvicorn.Server(config)
    server.run()


def main():
    host = "127.0.0.1"
    port = find_free_port(8000)
    url = f"http://{host}:{port}"

    print("=" * 70)
    print("  Madrid Public Libraries Book Finder — Desktop Application")
    print(f"  Starting local server at: {url}")
    print("  Press Ctrl+C in this terminal to quit.")
    print("=" * 70)

    # Start FastAPI / Uvicorn server in a daemon thread
    server_thread = threading.Thread(target=run_server, args=(host, port), daemon=True)
    server_thread.start()

    # Wait briefly for server startup
    time.sleep(1.2)

    # Check if pywebview is available for native GUI window
    has_webview = False
    try:
        import webview
        has_webview = True
    except ImportError:
        pass

    if has_webview:
        try:
            print("Opening native desktop window via pywebview...")
            webview.create_window(
                title="Bibliotecas de Madrid — Disponibilidad & Goodreads",
                url=url,
                width=1180,
                height=820,
                min_size=(800, 600),
            )
            webview.start()
            sys.exit(0)
        except Exception as e:
            print(f"Native window launch fallback ({e}); opening in default browser...")

    # Fallback to default browser
    print(f"Opening browser at: {url}")
    webbrowser.open(url)

    # Keep main thread alive
    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        print("\nShutting down Madrid Public Libraries Book Finder. Goodbye!")
        sys.exit(0)


if __name__ == "__main__":
    main()
