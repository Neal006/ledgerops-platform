import io
import json

from recon.metrics import NAMESPACE, emf_record, emit_emf
from recon.reconcile import reconcile
from recon.statements import Position


def test_emf_record_is_valid_embedded_metric_format():
    result = reconcile([Position("BROKER:A", "USD", 1)], [Position("BROKER:A", "USD", 2)])
    out = io.StringIO()
    emit_emf(emf_record(result, "staging", "IN", 1.23), out)

    record = json.loads(out.getvalue())
    directive = record["_aws"]["CloudWatchMetrics"][0]
    assert directive["Namespace"] == NAMESPACE
    # Every declared metric and dimension must be present as a top-level member, or CloudWatch drops it.
    for metric in directive["Metrics"]:
        assert metric["Name"] in record
    for dim in directive["Dimensions"][0]:
        assert dim in record
    assert record["ReconBreaks"] == 1
    assert record["BreaksByType"] == {"amount_mismatch": 1}
