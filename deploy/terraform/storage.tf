# =============================================================================
# Storage: a single DynamoDB table for both voter signups and contact submissions
# =============================================================================
# Schema:
#   pk            (string, hash key) — "voter#<email>" or "contact#<uuid>"
#   record_type   ("voter" | "politician" | "media" | "ai")
#   submitted_at  (ISO8601 UTC)
#   pending       (string "1" — present only on contact records that still
#                  need to be emailed; removed after the daily drain emails them)
#   …per-type fields (first_name, email, state, organization, use_case, etc.)
#
# A sparse GSI on `pending` lets the drain Lambda find unprocessed contact
# submissions in O(backlog) rather than scanning the whole table. Items fall
# out of the GSI automatically when the `pending` attribute is removed.
# =============================================================================

resource "aws_dynamodb_table" "submissions" {
  name         = "voxivium-submissions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "pending"
    type = "S"
  }

  attribute {
    name = "submitted_at"
    type = "S"
  }

  # Sparse index: only items with the `pending` attribute appear here.
  # Drain Lambda queries this; emails each item; UpdateItem REMOVE pending.
  global_secondary_index {
    name            = "pending-index"
    hash_key        = "pending"
    range_key       = "submitted_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = true
}
