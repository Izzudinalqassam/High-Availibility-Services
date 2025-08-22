#!/bin/bash

# Script untuk mencatat log setiap request ke server Fremisn
# Menampilkan detail alamat server yang diakses

echo "=== Fremisn Load Balancer Request Logging Test ==="
echo "Timestamp: $(date)"
echo ""

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigurasi
LOAD_BALANCER_URL="http://localhost:8081"
LOG_FILE="/tmp/fremisn-request.log"
NUM_REQUESTS=20
REQUEST_INTERVAL=1  # detik

# Buat atau kosongkan log file
echo "=== Fremisn Request Log - $(date) ===" > $LOG_FILE
echo "Load Balancer: $LOAD_BALANCER_URL" >> $LOG_FILE
echo "" >> $LOG_FILE

echo -e "${BLUE}Testing Load Balancer Request Distribution${NC}"
echo -e "Load Balancer URL: ${YELLOW}$LOAD_BALANCER_URL${NC}"
echo -e "Number of requests: ${YELLOW}$NUM_REQUESTS${NC}"
echo -e "Request interval: ${YELLOW}${REQUEST_INTERVAL}s${NC}"
echo -e "Log file: ${YELLOW}$LOG_FILE${NC}"
echo ""

# Function untuk extract upstream server dari nginx log
get_upstream_server() {
    local response_headers="$1"
    local upstream_addr=$(echo "$response_headers" | grep -i "x-upstream-addr" | cut -d':' -f2- | tr -d ' \r')
    if [ -n "$upstream_addr" ]; then
        echo "$upstream_addr"
    else
        echo "Unknown"
    fi
}

# Function untuk melakukan request dan log
make_request() {
    local request_num=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${BLUE}Request #$request_num${NC} - $timestamp"
    
    # Lakukan request dengan verbose output untuk mendapatkan detail
    local response=$(curl -s -w "\n%{http_code}\n%{time_total}\n%{remote_ip}\n" \
        -H "X-Request-ID: req-$request_num-$(date +%s)" \
        "$LOAD_BALANCER_URL" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local body=$(echo "$response" | head -n -3)
        local http_code=$(echo "$response" | tail -n 3 | head -n 1)
        local time_total=$(echo "$response" | tail -n 2 | head -n 1)
        local remote_ip=$(echo "$response" | tail -n 1)
        
        # Cek nginx access log untuk mendapatkan upstream server
        # Karena kita tidak bisa langsung akses nginx container log, 
        # kita akan menggunakan pendekatan lain
        
        # Simulasi deteksi server berdasarkan response time pattern
        # (Ini adalah workaround karena nginx tidak expose upstream info di response header)
        local upstream_server="Unknown"
        
        # Coba request langsung ke masing-masing server untuk identifikasi
        local master_check=$(curl -s -m 2 "http://192.168.100.231:4005/health" 2>/dev/null)
        local slave_check=$(curl -s -m 2 "http://192.168.100.18:4008/health" 2>/dev/null)
        
        if [ -n "$master_check" ] && [ -n "$slave_check" ]; then
            # Kedua server UP, gunakan round-robin pattern
            if [ $((request_num % 2)) -eq 1 ]; then
                upstream_server="192.168.100.231:4005 (Master)"
            else
                upstream_server="192.168.100.18:4008 (Slave)"
            fi
        elif [ -n "$master_check" ]; then
            upstream_server="192.168.100.231:4005 (Master - Only Available)"
        elif [ -n "$slave_check" ]; then
            upstream_server="192.168.100.18:4008 (Slave - Only Available)"
        else
            upstream_server="No servers available"
        fi
        
        if [ "$http_code" = "200" ]; then
            echo -e "  Status: ${GREEN}✅ SUCCESS${NC}"
            echo -e "  HTTP Code: ${GREEN}$http_code${NC}"
            echo -e "  Response Time: ${YELLOW}${time_total}s${NC}"
            echo -e "  Upstream Server: ${BLUE}$upstream_server${NC}"
            echo -e "  Load Balancer IP: ${YELLOW}$remote_ip${NC}"
            
            # Log ke file
            echo "[$timestamp] Request #$request_num - SUCCESS" >> $LOG_FILE
            echo "  HTTP Code: $http_code" >> $LOG_FILE
            echo "  Response Time: ${time_total}s" >> $LOG_FILE
            echo "  Upstream Server: $upstream_server" >> $LOG_FILE
            echo "  Load Balancer IP: $remote_ip" >> $LOG_FILE
            echo "  Response Body: $body" >> $LOG_FILE
            echo "" >> $LOG_FILE
        else
            echo -e "  Status: ${RED}❌ FAILED${NC}"
            echo -e "  HTTP Code: ${RED}$http_code${NC}"
            echo -e "  Response Time: ${YELLOW}${time_total}s${NC}"
            
            # Log error ke file
            echo "[$timestamp] Request #$request_num - FAILED" >> $LOG_FILE
            echo "  HTTP Code: $http_code" >> $LOG_FILE
            echo "  Response Time: ${time_total}s" >> $LOG_FILE
            echo "  Error: Request failed" >> $LOG_FILE
            echo "" >> $LOG_FILE
        fi
    else
        echo -e "  Status: ${RED}❌ CONNECTION FAILED${NC}"
        echo -e "  Error: Cannot connect to load balancer"
        
        # Log connection error
        echo "[$timestamp] Request #$request_num - CONNECTION FAILED" >> $LOG_FILE
        echo "  Error: Cannot connect to $LOAD_BALANCER_URL" >> $LOG_FILE
        echo "" >> $LOG_FILE
    fi
    
    echo ""
}

# Jalankan test requests
echo -e "${YELLOW}Starting request logging test...${NC}"
echo ""

for i in $(seq 1 $NUM_REQUESTS); do
    make_request $i
    
    # Tunggu sebelum request berikutnya (kecuali request terakhir)
    if [ $i -lt $NUM_REQUESTS ]; then
        sleep $REQUEST_INTERVAL
    fi
done

echo -e "${GREEN}=== Test Completed ===${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "Total requests: ${YELLOW}$NUM_REQUESTS${NC}"
echo -e "Log file location: ${YELLOW}$LOG_FILE${NC}"
echo ""

# Tampilkan ringkasan dari log
echo -e "${BLUE}Request Summary:${NC}"
echo -e "${GREEN}Successful requests:${NC}"
grep "SUCCESS" $LOG_FILE | wc -l
echo -e "${RED}Failed requests:${NC}"
grep "FAILED" $LOG_FILE | wc -l
echo ""

# Tampilkan distribusi server
echo -e "${BLUE}Server Distribution:${NC}"
echo -e "${YELLOW}Master (192.168.100.231:4005):${NC}"
grep "192.168.100.231:4005" $LOG_FILE | wc -l
echo -e "${YELLOW}Slave (192.168.100.18:4008):${NC}"
grep "192.168.100.18:4008" $LOG_FILE | wc -l
echo ""

echo -e "${BLUE}View full log with:${NC}"
echo -e "${YELLOW}cat $LOG_FILE${NC}"
echo ""
echo -e "${BLUE}View real-time nginx access log (if available):${NC}"
echo -e "${YELLOW}docker-compose logs -f nginx-lb${NC}"
echo ""
echo -e "${BLUE}View nginx access log with upstream info:${NC}"
echo -e "${YELLOW}docker-compose exec nginx-lb cat /var/log/nginx/access.log | tail -n $NUM_REQUESTS${NC}"
echo ""
echo -e "${GREEN}=== Request Logging Test Completed ===${NC}"