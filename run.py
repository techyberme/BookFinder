#!/usr/bin/env python3
"""
Entrypoint runner script for Madrid Public Libraries Book Finder.
Starts FastAPI backend server and serves the frontend SPA on http://localhost:8000.
"""

import sys
import uvicorn

def main():
    print("=" * 65)
    print("  Madrid Public Libraries Network — Book Availability Finder")
    print("  Catálogo Red de Bibliotecas de la Comunidad de Madrid (AbsysNet)")
    print("=" * 65)
    print("  Web App URL: http://127.0.0.1:8000")
    print("  API Docs:    http://127.0.0.1:8000/docs")
    print("=" * 65)
    print("Starting server with auto-reload enabled...\n")

    uvicorn.run(
        "backend.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level="info",
    )

if __name__ == "__main__":
    main()
