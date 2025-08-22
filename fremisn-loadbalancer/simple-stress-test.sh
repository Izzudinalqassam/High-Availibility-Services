#!/bin/bash

# Simple Stress Test for Fremisn Load Balancer
echo "=== Simple Load Balancer Stress Test ==="
echo "Testing health endpoint with high concurrency"
echo

# Configuration
URL="http://localhost:8081/health"
CONCURRENT=20
REQUESTS=1000
TOTAL=$((CONCURRENT * REQUESTS))

echo "Configuration:"
echo "- URL: $URL"
echo "- Concurrent connections: $CONCURRENT"
echo "- Requests per connection: $REQUESTS"
echo "- Total requests: $TOTAL"
echo

# Create temp directory for results
TEMP_DIR="/tmp/stress_$(date +%s)"
mkdir -p "$TEMP_DIR"

echo "Starting stress test..."
start_time=$(date +%s)

# Run concurrent requests
for i in $(seq 1 $CONCURRENT); do
    (
        for j in $(seq 1 $REQUESTS); do
            response=$(curl -s -w "%{http_code}" -o /dev/null "$URL")
            echo "$response" >> "$TEMP_DIR/results_$i.txt"
        done
    ) &
done

# Wait for all processes
wait

end_time=$(date +%s)
duration=$((end_time - start_time))

echo
echo "=== Results ==="
echo "Duration: ${duration} seconds"
echo "Requests/second: $(echo "scale=2; $TOTAL / $duration" | bc)"
echo

# Analyze response codes
echo "Response codes:"
cat "$TEMP_DIR"/results_*.txt | sort | uniq -c | while read count code; do
    case $code in
        200) echo "  ✓ $code (Success): $count" ;;
        429) echo "  ⚠ $code (Rate Limited): $count" ;;
        500) echo "  ✗ $code (Server Error): $count" ;;
        502) echo "  ✗ $code (Bad Gateway): $count" ;;
        503) echo "  ✗ $code (Service Unavailable): $count" ;;
        *) echo "  ? $code (Other): $count" ;;
    esac
done

# Calculate success rate
success=$(cat "$TEMP_DIR"/results_*.txt | grep -c "200" || echo "0")
success_rate=$(echo "scale=1; $success * 100 / $TOTAL" | bc)

echo
echo "Success rate: ${success_rate}%"

if [ "$(echo "$success_rate >= 95" | bc)" -eq 1 ]; then
    echo "✓ PASS: Success rate is acceptable for production"
else
    echo "✗ FAIL: Success rate is too low for production"
fi

# Clean up
rm -rf "$TEMP_DIR"

echo
echo "Test completed!"