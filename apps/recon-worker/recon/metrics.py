"""Metric emission for a short-lived batch job.

Batch jobs can't be scraped, so results are pushed:
  * CloudWatch Embedded Metric Format (EMF): a structured stdout line that CloudWatch Logs turns into
    metrics with no SDK or extra IAM. This is the production path on ECS.
  * Prometheus Pushgateway: optional, used by the local docker-compose stack.
"""

from __future__ import annotations

import json
import sys
import time
from collections import Counter
from typing import TextIO

from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

from recon.reconcile import Result

NAMESPACE = "LedgerOps/Recon"


def emf_record(result: Result, environment: str, book: str, duration_s: float) -> dict:
    by_type = Counter(b.type.value for b in result.breaks)
    return {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": NAMESPACE,
                    "Dimensions": [["Environment", "Book"]],
                    "Metrics": [
                        {"Name": "ReconSuccess", "Unit": "Count"},
                        {"Name": "ReconBreaks", "Unit": "Count"},
                        {"Name": "ReconMatched", "Unit": "Count"},
                        {"Name": "ReconDurationSeconds", "Unit": "Seconds"},
                    ],
                }
            ],
        },
        "Environment": environment,
        "Book": book,
        "ReconSuccess": 1,
        "ReconBreaks": len(result.breaks),
        "ReconMatched": result.matched,
        "ReconDurationSeconds": round(duration_s, 3),
        "BreaksByType": dict(by_type),
    }


def emit_emf(record: dict, out: TextIO = sys.stdout) -> None:
    out.write(json.dumps(record) + "\n")
    out.flush()


def push_prometheus(gateway: str, result: Result, environment: str, book: str, duration_s: float) -> None:
    registry = CollectorRegistry()
    labels = ["environment", "book"]
    Gauge("recon_breaks", "Breaks found in the last run", labels, registry=registry).labels(
        environment, book
    ).set(len(result.breaks))
    Gauge("recon_matched", "Positions matched in the last run", labels, registry=registry).labels(
        environment, book
    ).set(result.matched)
    Gauge("recon_duration_seconds", "Duration of the last run", labels, registry=registry).labels(
        environment, book
    ).set(duration_s)
    # Dead man's switch: alert when this timestamp goes stale, which catches jobs that never ran at all.
    Gauge(
        "recon_last_success_timestamp_seconds", "Unix time of the last successful run", labels, registry=registry
    ).labels(environment, book).set_to_current_time()
    push_to_gateway(gateway, job="recon-worker", grouping_key={"book": book}, registry=registry)
