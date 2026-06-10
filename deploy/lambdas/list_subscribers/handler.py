"""
List Subscribers Lambda — admin tool, invoked manually.

Usage from your terminal:
    aws lambda invoke --function-name voxivium-list-subscribers \\
      --cli-binary-format raw-in-base64-out \\
      output.json
    cat output.json | jq -r '.subscribers[] | "\\(.first_name), \\(.email), \\(.state)"'

Or to get a CSV directly:
    aws lambda invoke --function-name voxivium-list-subscribers \\
      --payload '{"format":"csv"}' \\
      --cli-binary-format raw-in-base64-out \\
      output.json
    cat output.json | jq -r '.csv' > subscribers.csv

Returns voter subscribers sorted by signup time, oldest first.
Contact-form submissions live in the same table but are filtered out here.
"""

import csv
import io
import os

import boto3
from boto3.dynamodb.conditions import Attr

_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(os.environ["SUBMISSIONS_TABLE"])


def _scan_voters():
    """Paginated scan, filtered to voter records only."""
    items = []
    kwargs = {"FilterExpression": Attr("record_type").eq("voter")}
    while True:
        resp = _table.scan(**kwargs)
        items.extend(resp.get("Items", []))
        last_key = resp.get("LastEvaluatedKey")
        if not last_key:
            break
        kwargs["ExclusiveStartKey"] = last_key
    return items


def lambda_handler(event, _context):
    output_format = (event or {}).get("format", "json")

    items = _scan_voters()
    items.sort(key=lambda x: x.get("submitted_at", ""))

    if output_format == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(["first_name", "email", "state", "submitted_at"])
        for item in items:
            writer.writerow(
                [
                    item.get("first_name", ""),
                    item.get("email", ""),
                    item.get("state", ""),
                    item.get("submitted_at", ""),
                ]
            )
        return {"count": len(items), "csv": buf.getvalue()}

    return {
        "count": len(items),
        "subscribers": items,
    }
