"""Qdrant memory plugin CLI — setup wizard for 'hermes memory setup'."""

from __future__ import annotations

import os
import sys
import argparse
from typing import List


DESCRIPTION = "Qdrant vector database memory provider"


def register_cli(subparsers) -> None:
    """Register the 'qdrant' subcommand under the memory plugin umbrella."""
    parser = subparsers.add_parser(
        "qdrant",
        help="Configure Qdrant memory provider",
        description=(
            "Interactive setup for the Qdrant vector database memory provider.\n\n"
            "Prompts for Qdrant connection details (host, port, optional API key) and\n"
            "writes them to config.yaml under agent.memory.vector_db.*.\n"
            "The embedding service URL is read from config.yaml's embeddings section."
        ),
    )
    parser.set_defaults(func=_handle_qdrant_command)


def _handle_qdrant_command(args: argparse.Namespace) -> None:
    """Run the interactive Qdrant setup wizard."""
    run_setup()


def get_config_schema() -> List[dict]:
    return [
        {
            "key": "vector_db.host",
            "description": "Qdrant server hostname",
            "default": "localhost",
            "required": True,
        },
        {
            "key": "vector_db.port",
            "description": "Qdrant server port (HTTP API)",
            "default": "6333",
            "required": True,
        },
        {
            "key": "vector_db.api_key",
            "description": "Qdrant API key (optional, for production)",
            "secret": True,
            "env_var": "QDRANT_API_KEY",
        },
        {
            "key": "collection",
            "description": "Qdrant collection name for memories",
            "default": "hermes_memory",
            "required": True,
        },
    ]


def run_setup() -> None:
    """Interactive setup wizard for Qdrant memory provider."""
    print("\n=== Qdrant Memory Provider Setup ===\n")
    print("This wizard will configure your Qdrant connection.\n")
    print("Note: The embedding service URL is read from your config.yaml")
    print("      under `embeddings.base_url`. Ensure that section is configured.\n")

    host = _prompt("Qdrant host", default="localhost")
    port = _prompt("Qdrant port", default="6333")
    api_key = _prompt("Qdrant API key (leave empty if none)", default="")
    collection = _prompt("Collection name", default="hermes_memory")

    print("\n--- Summary ---")
    print(f"  Host:       {host}")
    print(f"  Port:       {port}")
    print(f"  API key:    {'***' if api_key else '(none)'}")
    print(f"  Collection: {collection}")

    confirm = input("\nWrite to config.yaml? [Y/n]: ").strip().lower()
    if confirm and confirm not in ("y", "yes", ""):
        print("Aborted.")
        return

    _write_config(host, port, api_key, collection)
    print("\n✓ Qdrant configuration written to config.yaml.")
    print("  Restart Hermes to apply changes.")
    print("\n  Don't forget to also check your docker-compose.yml has the")
    print("  qdrant/qdrant service running on the same network.\n")


def _prompt(label: str, default: str = "") -> str:
    """Prompt user for input with optional default."""
    if default:
        prompt = f"{label} [{default}]: "
    else:
        prompt = f"{label}: "
    value = input(prompt).strip()
    return value if value else default


def _write_config(host: str, port: str, api_key: str, collection: str) -> None:
    """Write Qdrant settings to config.yaml under agent.memory."""
    from hermes_cli.config import load_config, save_config

    config = load_config() or {}
    memory = config.setdefault("agent", {}).setdefault("memory", {})
    memory["enabled"] = True
    memory["provider"] = "qdrant"
    memory["collection"] = collection
    vdb = memory.setdefault("vector_db", {})
    vdb["host"] = host
    vdb["port"] = int(port) if port.isdigit() else 6333
    if api_key:
        vdb["api_key"] = api_key
    elif "api_key" in vdb:
        # User cleared the field — remove old key
        del vdb["api_key"]

    save_config(config)
    logger.debug("Qdrant config written to config.yaml")


# Lazy logger
import logging
logger = logging.getLogger(__name__)
