#!/bin/bash

# Final Load Balancer Stress Test
# Tests multiple aspects of the optimized Nginx configuration

echo "=== Final Load Balancer Stress Test ==="
echo "Testing optimized Nginx configuration"
echo

# Test configuration
URL="http://localhost:8081/health"
CONCURRENT=50
REQUESTS_PER_CONN=500
TOTAL_REQUESTS=$((CONCURRENT * REQUESTS_PER_CONN))
TEST_DURATION=30

echo "Configuration:"
echo "- URL: $URL"
echo "- Concurrent connections: $CONCURRENT"
echo "- Requests per connection: $REQUESTS_PER_CONN"
echo "- Total requests: $TOTAL_REQUESTS"
echo "- Test duration: ${TEST_DURATION}s"
echo

# Function to run concurrent requests
run_concurrent_test() {
    local url=$1
    local concurrent=$2
    local requests=$3
    local duration=$4
    
    echo "Starting high-load stress test..."
    
    # Create temporary files for results
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    local timing_file="$temp_dir/timing.txt"
    
    # Start time
    local start_time=$(date +%s)
    
    # Run concurrent requests
    for i in $(seq 1 $concurrent); do
        {
            for j in $(seq 1 $requests); do
                local req_start=$(date +%s.%N)
                local response=$(curl -s -w "%{http_code}" -o /dev/null "$url" 2>/dev/null)
                local req_end=$(date +%s.%N)
                local req_time=$(echo "$req_end - $req_start" | bc -l 2>/dev/null || echo "0")
                echo "$response" >> "$results_file"
                echo "$req_time" >> "$timing_file"
            done
        } &
    done
    
    # Wait for all background processes
    wait
    
    # End time
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    echo "=== Results ==="
    echo "Duration: ${total_duration} seconds"
    
    # Calculate requests per second
    if [ $total_duration -gt 0 ]; then
        local rps=$(echo "scale=2; $TOTAL_REQUESTS / $total_duration" | bc -l 2>/dev/null || echo "N/A")
        echo "Requests/second: $rps"
    fi
    
    echo
    echo "Response codes:"
    
    # Count response codes
    if [ -f "$results_file" ]; then
        local total_responses=$(wc -l < "$results_file")
        local success_count=$(grep -c "^200$" "$results_file" 2>/dev/null || echo "0")
        local error_4xx=$(grep -c "^4[0-9][0-9]$" "$results_file" 2>/dev/null || echo "0")
        local error_5xx=$(grep -c "^5[0-9][0-9]$" "$results_file" 2>/dev/null || echo "0")
        
        echo "  ✓ 200 (Success): $success_count"
        [ $error_4xx -gt 0 ] && echo "  ✗ 4xx (Client Error): $error_4xx"
        [ $error_5xx -gt 0 ] && echo "  ✗ 5xx (Server Error): $error_5xx"
        
        # Calculate success rate
        if [ $total_responses -gt 0 ]; then
            local success_rate=$(echo "scale=1; $success_count * 100 / $total_responses" | bc -l 2>/dev/null || echo "0")
            echo
            echo "Success rate: ${success_rate}%"
            
            # Determine if test passed
            local success_threshold=95
            if [ $(echo "$success_rate >= $success_threshold" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
                echo "✓ PASS: Success rate is excellent for production"
            else
                echo "✗ FAIL: Success rate below ${success_threshold}% threshold"
            fi
        fi
    fi
    
    # Response time statistics
    if [ -f "$timing_file" ] && [ -s "$timing_file" ]; then
        echo
        echo "Response time statistics:"
        
        # Calculate average response time
        local avg_time=$(awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print "0"}' "$timing_file" 2>/dev/null || echo "0")
        echo "  Average: ${avg_time}s"
        
        # Find min and max
        local min_time=$(sort -n "$timing_file" | head -1 2>/dev/null || echo "0")
        local max_time=$(sort -n "$timing_file" | tail -1 2>/dev/null || echo "0")
        echo "  Min: ${min_time}s"
        echo "  Max: ${max_time}s"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Test system resources before
echo "System resources before test:"
echo "Memory usage: $(free -h | grep '^Mem:' | awk '{print $3"/"$2}')"
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo

# Run the stress test
run_concurrent_test "$URL" "$CONCURRENT" "$REQUESTS_PER_CONN" "$TEST_DURATION"

echo
echo "System resources after test:"
echo "Memory usage: $(free -h | grep '^Mem:' | awk '{print $3"/"$2}')"
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"

echo
echo "=== Nginx Configuration Validation ==="
echo "Checking if Nginx is running optimally..."

# Check Nginx status
if docker ps | grep -q "fremisn-loadbalancer.*Up"; then
    echo "✓ Nginx container is running"
else
    echo "✗ Nginx container is not running properly"
fi

# Check for any recent errors in logs
echo "Recent Nginx logs (last 10 lines):"
docker logs --tail 10 fremisn-loadbalancer 2>/dev/null || echo "Could not retrieve logs"

echo
echo "Test completed!"
echo "=== Summary ==="
echo "The optimized Nginx configuration has been tested with:"
echo "- High concurrency ($CONCURRENT concurrent connections)"
echo "- Heavy load ($TOTAL_REQUESTS total requests)"
echo "- Performance monitoring"
echo "- Error handling validation"