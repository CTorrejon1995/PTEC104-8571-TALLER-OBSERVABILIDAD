"""Generate synthetic cloud JSON logs; no external service or credentials."""

import argparse
from datetime import datetime, timezone
import itertools
import json
import logging
from logging.handlers import RotatingFileHandler
import math
import os
from pathlib import Path
import signal
import sys
import threading
import uuid


LEVELS = ("info", "warn", "error")
MESSAGES = {
    "info": "Simulated cloud request completed",
    "warn": "Simulated cloud request approaching latency limit",
    "error": "Simulated cloud upstream request failed",
}


def make_event(level, sequence=0, message=None):
    """Return the log contract consumed by the Promtail JSON pipeline."""
    if level not in LEVELS:
        raise ValueError("level must be info, warn or error")
    return {
        "timestamp": datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
        "level": level,
        "service": "cloud-simulator",
        "message": message if message is not None else MESSAGES[level],
        "request_id": uuid.uuid4().hex,
        "sequence": sequence,
        "simulated": True,
    }


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=os.environ.get("CLOUD_LOG_FILE", "/var/log/cloud/events.jsonl"),
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=os.environ.get("CLOUD_LOG_INTERVAL_SECONDS", "2"),
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=os.environ.get("CLOUD_LOG_MAX_BYTES", "5242880"),
    )
    parser.add_argument(
        "--backup-count",
        type=int,
        default=os.environ.get("CLOUD_LOG_BACKUP_COUNT", "3"),
    )
    parser.add_argument("--once", action="store_true", help="Append one probe log and exit")
    parser.add_argument("--level", choices=LEVELS, default="info")
    parser.add_argument("--message", default=None)
    args = parser.parse_args()
    if not math.isfinite(args.interval) or args.interval <= 0:
        parser.error("--interval must be a positive finite number")
    if args.max_bytes < 1024:
        parser.error("--max-bytes must be at least 1024")
    if args.backup_count < 1:
        parser.error("--backup-count must be at least 1")
    return args


def main():
    args = parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if args.once:
        # A probe appends without rotating the file held by the main writer.
        line = json.dumps(make_event(args.level, message=args.message), ensure_ascii=False)
        with output.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
        print(line, flush=True)
        return

    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda _signum, _frame: stop.set())

    logger = logging.getLogger("cloud-simulator")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    file_handler = RotatingFileHandler(
        output, maxBytes=args.max_bytes, backupCount=args.backup_count, encoding="utf-8"
    )
    file_handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(file_handler)
    try:
        for sequence, level in enumerate(itertools.cycle(LEVELS), 1):
            event = make_event(level, sequence=sequence)
            line = json.dumps(event, ensure_ascii=False)
            logger.info(line)
            print(line, flush=True)
            if stop.wait(args.interval):
                break
    finally:
        file_handler.close()
        logger.removeHandler(file_handler)


if __name__ == "__main__":
    try:
        main()
    except OSError as exc:
        print(f"cloud-simulator: {exc}", file=sys.stderr, flush=True)
        sys.exit(1)
