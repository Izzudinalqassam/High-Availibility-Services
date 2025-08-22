#!/bin/bash

# Fremisn Load Balancer Stress Test Script
# This script performs comprehensive stress testing on the load balancer

echo "=== Fremisn Load Balancer Stress Test ==="
echo "Starting stress test at $(date)"
echo

# Configuration
LOAD_BALANCER_URL="http://localhost:8081"
TEST_ENDPOINT="/v1/face/enrollment"
FULL_URL="${LOAD_BALANCER_URL}${TEST_ENDPOINT}"

# Test parameters
CONCURRENT_USERS=10
REQUESTS_PER_USER=100
TOTAL_REQUESTS=$((CONCURRENT_USERS * REQUESTS_PER_USER))
TEST_DURATION=60  # seconds

echo "Test Configuration:"
echo "- Target URL: $FULL_URL"
echo "- Concurrent Users: $CONCURRENT_USERS"
echo "- Requests per User: $REQUESTS_PER_USER"
echo "- Total Requests: $TOTAL_REQUESTS"
echo "- Test Duration: $TEST_DURATION seconds"
echo

# Check if load balancer is accessible
echo "Checking load balancer accessibility..."
if curl -s -o /dev/null -w "%{http_code}" "$LOAD_BALANCER_URL/health" | grep -q "200"; then
    echo "✓ Load balancer is accessible"
else
    echo "✗ Load balancer is not accessible. Please check if it's running."
    exit 1
fi
echo

# Function to perform stress test using curl
perform_curl_test() {
    echo "=== CURL Stress Test ==="
    echo "Performing $TOTAL_REQUESTS requests with $CONCURRENT_USERS concurrent connections..."
    
    # Create temporary directory for results
    TEMP_DIR="/tmp/stress_test_$(date +%s)"
    mkdir -p "$TEMP_DIR"
    
    # Sample JSON payload for face enrollment
    JSON_PAYLOAD='{"image":"base64_encoded_image_data_here","user_id":"test_user_123","metadata":{"test":true}}'
    
    start_time=$(date +%s)
    
    # Run concurrent requests
    for i in $(seq 1 $CONCURRENT_USERS); do
        (
            for j in $(seq 1 $REQUESTS_PER_USER); do
                response_code=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST \
                    -H "Content-Type: application/json" \
                    -d "$JSON_PAYLOAD" \
                    "$FULL_URL")
                echo "$response_code" >> "$TEMP_DIR/responses_$i.txt"
            done
        ) &
    done
    
    # Wait for all background processes to complete
    wait
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Analyze results
    echo
    echo "=== Test Results ==="
    echo "Test Duration: ${duration} seconds"
    echo "Requests per second: $(echo "scale=2; $TOTAL_REQUESTS / $duration" | bc)"
    echo
    
    # Count response codes
    echo "Response Code Distribution:"
    cat "$TEMP_DIR"/responses_*.txt | sort | uniq -c | while read count code; do
        case $code in
            200) echo "  $code (Success): $count requests" ;;
            500) echo "  $code (Internal Server Error): $count requests" ;;
            502) echo "  $code (Bad Gateway): $count requests" ;;
            503) echo "  $code (Service Unavailable): $count requests" ;;
            504) echo "  $code (Gateway Timeout): $count requests" ;;
            *) echo "  $code (Other): $count requests" ;;
        esac
    done
    
    # Calculate success rate
    success_count=$(cat "$TEMP_DIR"/responses_*.txt | grep -c "200" || echo "0")
    success_rate=$(echo "scale=2; $success_count * 100 / $TOTAL_REQUESTS" | bc)
    echo
    echo "Success Rate: ${success_rate}%"
    
    # Clean up
    rm -rf "$TEMP_DIR"
}

# Function to perform stress test using Apache Bench (if available)
perform_ab_test() {
    if command -v ab >/dev/null 2>&1; then
        echo
        echo "=== Apache Bench Stress Test ==="
        echo "Running Apache Bench test..."
        
        # Create temporary file with POST data
        POST_DATA="/tmp/post_data_$(date +%s).json"
        echo '{"image":"base64_encoded_image_data_here","user_id":"test_user_123","metadata":{"test":true}}' > "$POST_DATA"
        
        ab -n $TOTAL_REQUESTS -c $CONCURRENT_USERS \
           -T "application/json" \
           -p "$POST_DATA" \
           "$FULL_URL"
        
        rm -f "$POST_DATA"
    else
        echo
        echo "Apache Bench (ab) not available. Skipping AB test."
        echo "To install: sudo apt-get install apache2-utils"
    fi
}

# Function to monitor system resources during test
monitor_resources() {
    echo
    echo "=== System Resource Monitoring ==="
    echo "Docker container stats during test:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | grep -E "(CONTAINER|fremisn)"
}

# Main execution
echo "Starting stress tests..."
echo

# Monitor resources before test
monitor_resources

# Perform tests
perform_curl_test
perform_ab_test

# Monitor resources after test
echo
monitor_resources

echo
echo "=== Stress Test Completed ==="
echo "Test completed at $(date)"
echo
echo "Recommendations:"
echo "- Monitor the response code distribution"
echo "- Success rate should be > 95% for production readiness"
echo "- Check Docker logs if you see many 5xx errors"
echo "- Consider scaling if success rate is low"
echo
echo "To view detailed logs:"
echo "  docker-compose logs nginx-lb --tail=100"
echo
echo "To view real-time monitoring:"
echo "  docker stats"