#!/usr/bin/env bash
# Seed a few butter-smooth milestones so Grafana Step 3 panels are not empty
# before an iOS smoke. Does NOT store secrets — pass yours on the command line.
#
# Usage:
#   export METRICS_SUMMARY_SECRET='your_render_secret'
#   ./scripts/seed-metrics-sample.sh
#
# Or:
#   METRICS_SUMMARY_SECRET='…' ./scripts/seed-metrics-sample.sh
set -euo pipefail

API="${MATTERYA_API:-https://api.matterya.com}"
SECRET="${METRICS_SUMMARY_SECRET:-${CONTENT_CRON_SECRET:-}}"

if [[ -z "$SECRET" ]]; then
  echo "Set METRICS_SUMMARY_SECRET (same as Render / Grafana Infinity x-cron-secret)." >&2
  exit 1
fi

echo "POST $API/v1/metrics/batch …"
curl -sS -X POST "$API/v1/metrics/batch" \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "grafana-step3-seed",
    "appVersion": "seed",
    "os": "ios",
    "deviceClass": "iphone11_class",
    "events": [
      {"name":"app_start_to_shell","surface":"app","durationMs":420,"ok":true},
      {"name":"app_start_to_feed_visible","surface":"feed","durationMs":180,"ok":true},
      {"name":"sparks_open_first_frame","surface":"sparks","durationMs":95,"ok":true},
      {"name":"sparks_feed_handoff_first_frame","surface":"sparks","durationMs":48,"ok":true},
      {"name":"reel_swipe_first_frame","surface":"sparks","durationMs":72,"ok":true},
      {"name":"hubs_feed_handoff_first_frame","surface":"hubs","durationMs":55,"ok":true},
      {"name":"hubs_first_useful","surface":"hubs","durationMs":110,"ok":true},
      {"name":"message_local_visible","surface":"messages","durationMs":18,"ok":true}
    ]
  }' | head -c 400
echo
echo
echo "GET $API/v1/metrics/summary …"
curl -sS -H "x-cron-secret: $SECRET" "$API/v1/metrics/summary" | head -c 1200
echo
echo
echo "Done. Refresh Grafana dashboard Matterya Butter-Smooth SLOs."
echo
echo "To wipe dirty in-memory samples first:"
echo "  curl -sS -X POST -H \"x-cron-secret: \$METRICS_SUMMARY_SECRET\" \"$API/v1/metrics/reset\""
