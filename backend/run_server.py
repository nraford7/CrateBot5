#!/usr/bin/env python3
"""
Launch the CrateBot API server.
"""
import sys
from pathlib import Path

# Add paths - project root for backend.*, python/ for src.*
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "python"))
sys.path.insert(0, str(project_root / "python" / "src"))

import uvicorn


def main():
    """Run the API server."""
    print("Starting CrateBot API server...")
    print("API docs available at: http://127.0.0.1:8742/docs")
    print("Press Ctrl+C to stop\n")

    uvicorn.run(
        "backend.api_server:app",
        host="127.0.0.1",
        port=8742,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
