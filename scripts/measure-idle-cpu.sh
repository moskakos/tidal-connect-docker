#!/bin/bash
# scripts/measure-idle-cpu.sh
# Measure idle CPU usage of a container over a configurable duration

set -euo pipefail

# Default values
DURATION="${1:-60}"
CONTAINER_NAME="${2:-tidal-forwarder}"
SAMPLE_INTERVAL=5

echo "$(date '+%Y-%m-%d %H:%M:%S') Measuring CPU usage for container: $CONTAINER_NAME"
echo "$(date '+%Y-%m-%d %H:%M:%S') Duration: ${DURATION}s, sampling every ${SAMPLE_INTERVAL}s"
echo ""

# Check if container exists and is running
if ! docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "ERROR: Container '$CONTAINER_NAME' is not running or does not exist" >&2
  echo "Available containers:" >&2
  docker ps --format '{{.Names}}' >&2
  exit 1
fi

# Temporary file for samples
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Collect samples
END_TIME=$(($(date +%s) + DURATION))
SAMPLE_COUNT=0

while [ "$(date +%s)" -lt "$END_TIME" ]; do
  # Get CPU percentage (strip the % sign)
  CPU_PERCENT=$(docker stats --no-stream --format '{{.CPUPerc}}' "$CONTAINER_NAME" | sed 's/%//')
  
  if [ -n "$CPU_PERCENT" ]; then
    echo "$CPU_PERCENT" >> "$TEMP_FILE"
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    echo "$(date '+%Y-%m-%d %H:%M:%S') Sample $SAMPLE_COUNT: ${CPU_PERCENT}%"
  fi
  
  sleep "$SAMPLE_INTERVAL"
done

echo ""
echo "============================================"
echo "Summary for $CONTAINER_NAME"
echo "============================================"

if [ "$SAMPLE_COUNT" -eq 0 ]; then
  echo "ERROR: No samples collected" >&2
  exit 1
fi

# Calculate statistics using awk
awk '
BEGIN {
  min = 999999
  max = 0
  sum = 0
  count = 0
}
{
  val = $1 + 0  # Convert to number
  if (val < min) min = val
  if (val > max) max = val
  sum += val
  count++
}
END {
  if (count > 0) {
    printf "Samples collected: %d\n", count
    printf "Min CPU: %.2f%%\n", min
    printf "Mean CPU: %.2f%%\n", sum / count
    printf "Max CPU: %.2f%%\n", max
  }
}' "$TEMP_FILE"

echo "============================================"
