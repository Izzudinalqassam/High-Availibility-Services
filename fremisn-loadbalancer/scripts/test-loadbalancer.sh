#!/bin/bash

# Script untuk testing load balancer fremisn

echo "=== Testing Fremisn Load Balancer ==="
echo

# Test health endpoint
echo "1. Testing health endpoint:"
curl -s http://localhost:8081/health
echo
echo

# Test fremisn master status
echo "2. Testing Fremisn Master (192.168.100.231:4005):"
if curl -s --connect-timeout 5 --max-time 10 http://192.168.100.231:4005/health > /dev/null 2>&1; then
    echo "✅ Fremisn Master: UP"
    echo "Response: $(curl -s http://192.168.100.231:4005/health)"
else
    echo "❌ Fremisn Master: DOWN"
fi
echo

# Test fremisn slave 1 status
echo "3. Testing Fremisn Slave 1 (192.168.100.18:4008):"
if curl -s --connect-timeout 5 --max-time 10 http://192.168.100.18:4008/health > /dev/null 2>&1; then
    echo "✅ Fremisn Slave 1: UP"
    echo "Response: $(curl -s http://192.168.100.18:4008/health)"
else
    echo "❌ Fremisn Slave 1: DOWN"
fi
echo

# Test fremisn slave 2 status
echo "4. Testing Fremisn Slave 2 (192.168.100.17:4009):"
if curl -s --connect-timeout 5 --max-time 10 http://192.168.100.17:4009/health > /dev/null 2>&1; then
    echo "✅ Fremisn Slave 2: UP"
    echo "Response: $(curl -s http://192.168.100.17:4009/health)"
else
    echo "❌ Fremisn Slave 2: DOWN"
fi
echo

# Test load balancer dengan beberapa request
echo "5. Testing load balancing (10 requests):"
for i in {1..10}; do
    echo "Request $i:"
    curl -s -w "Response Time: %{time_total}s\n" http://localhost:8081/health
    sleep 1
done
echo

# Check nginx status
echo "6. Nginx status:"
curl -s http://localhost:8080/nginx_status
echo
echo

# Check services status
echo "7. Docker containers status:"
docker-compose ps
echo

# Check prometheus targets
echo "8. Prometheus targets (check if accessible):"
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}' 2>/dev/null || echo "jq not available, raw output:"
curl -s http://localhost:9090/api/v1/targets
echo
echo

echo "=== Access URLs ==="
echo "Load Balancer: http://localhost:8081"
echo "Grafana Dashboard: http://localhost:3000 (admin/admin123)"
echo "Prometheus: http://localhost:9090"
echo "Nginx Status: http://localhost:8080/nginx_status"
echo "Fremisn Master: http://192.168.100.231:4005"
echo "Fremisn Slave 1: http://192.168.100.18:4008"
echo "Fremisn Slave 2: http://192.168.100.17:4009"
echo
echo "=== Test completed ==="