#!/bin/bash

# =============================================================================
# High Availability Fremisn Services - Health Check Script
# =============================================================================
# This script performs comprehensive health checks on all components:
# - Docker containers status
# - Service endpoints availability
# - Resource usage monitoring
# - Network connectivity
# - Data integrity checks
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${LOG_FILE:-/tmp/fremisn-health-check.log}"
ALERT_THRESHOLD_CPU="${ALERT_THRESHOLD_CPU:-80}"
ALERT_THRESHOLD_MEMORY="${ALERT_THRESHOLD_MEMORY:-80}"
ALERT_THRESHOLD_DISK="${ALERT_THRESHOLD_DISK:-85}"
CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-10}"
VERBOSE="${VERBOSE:-false}"

# Service endpoints
LOAD_BALANCER_URL="http://localhost:8081"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9090"
NGINX_STATUS_URL="http://localhost:8080/nginx_status"
BLACKBOX_URL="http://localhost:9115"

# Fremisn servers (read from config or environment)
FREMISN_MASTER="${FREMISN_MASTER_HOST:-192.168.100.231}:${FREMISN_MASTER_PORT:-4005}"
FREMISN_SLAVE="${FREMISN_SLAVE_HOST:-192.168.100.18}:${FREMISN_SLAVE_PORT:-4008}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Status counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Arrays to store results
declare -a FAILED_SERVICES=()
declare -a WARNING_SERVICES=()
declare -a CRITICAL_ISSUES=()

# Logging functions
log() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}[$timestamp]${NC} $message"
    [[ "$VERBOSE" == "true" ]] && echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_success() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${GREEN}[$timestamp] ✅ $message${NC}"
    echo "[$timestamp] SUCCESS: $message" >> "$LOG_FILE"
    ((PASSED_CHECKS++))
}

log_warning() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${YELLOW}[$timestamp] ⚠️  $message${NC}"
    echo "[$timestamp] WARNING: $message" >> "$LOG_FILE"
    WARNING_SERVICES+=("$message")
    ((WARNING_CHECKS++))
}

log_error() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${RED}[$timestamp] ❌ $message${NC}"
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
    FAILED_SERVICES+=("$message")
    ((FAILED_CHECKS++))
}

log_critical() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${RED}[$timestamp] 🚨 CRITICAL: $message${NC}"
    echo "[$timestamp] CRITICAL: $message" >> "$LOG_FILE"
    CRITICAL_ISSUES+=("$message")
    FAILED_SERVICES+=("$message")
    ((FAILED_CHECKS++))
}

# Increment total checks counter
check_start() {
    ((TOTAL_CHECKS++))
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check Docker and Docker Compose availability
check_dependencies() {
    log "🔍 Checking dependencies..."
    
    check_start
    if command_exists docker; then
        log_success "Docker is available"
    else
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    check_start
    if command_exists docker-compose || docker compose version &>/dev/null; then
        log_success "Docker Compose is available"
    else
        log_error "Docker Compose is not installed or not in PATH"
        return 1
    fi
    
    check_start
    if command_exists curl; then
        log_success "curl is available"
    else
        log_error "curl is not installed or not in PATH"
        return 1
    fi
}

# Check Docker daemon status
check_docker_daemon() {
    log "🐳 Checking Docker daemon..."
    
    check_start
    if docker info >/dev/null 2>&1; then
        log_success "Docker daemon is running"
    else
        log_critical "Docker daemon is not running or not accessible"
        return 1
    fi
}

# Check container status
check_containers() {
    log "📦 Checking container status..."
    
    cd "$PROJECT_DIR"
    
    local services=("nginx-lb" "prometheus" "grafana" "blackbox-exporter")
    
    for service in "${services[@]}"; do
        check_start
        local status=$(docker-compose ps -q "$service" 2>/dev/null | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
        
        case "$status" in
            "running")
                log_success "Container $service is running"
                ;;
            "exited")
                log_error "Container $service has exited"
                ;;
            "restarting")
                log_warning "Container $service is restarting"
                ;;
            "paused")
                log_warning "Container $service is paused"
                ;;
            "not_found")
                log_error "Container $service not found"
                ;;
            *)
                log_error "Container $service status unknown: $status"
                ;;
        esac
    done
}

# Check service endpoints
check_endpoints() {
    log "🌐 Checking service endpoints..."
    
    local endpoints=(
        "Load Balancer:$LOAD_BALANCER_URL/health"
        "Nginx Status:$NGINX_STATUS_URL"
        "Prometheus:$PROMETHEUS_URL/-/healthy"
        "Grafana:$GRAFANA_URL/api/health"
        "Blackbox Exporter:$BLACKBOX_URL/metrics"
    )
    
    for endpoint in "${endpoints[@]}"; do
        check_start
        local name="${endpoint%%:*}"
        local url="${endpoint#*:}"
        
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECTION_TIMEOUT" "$url" 2>/dev/null || echo "000")
        
        case "$response_code" in
            "200"|"201"|"202")
                log_success "$name endpoint is healthy (HTTP $response_code)"
                ;;
            "404")
                if [[ "$name" == "Prometheus" ]]; then
                    # Prometheus might not have /-/healthy endpoint in older versions
                    local alt_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECTION_TIMEOUT" "$PROMETHEUS_URL" 2>/dev/null || echo "000")
                    if [[ "$alt_response" == "200" ]]; then
                        log_success "$name endpoint is healthy (HTTP $alt_response)"
                    else
                        log_warning "$name endpoint returned HTTP $response_code"
                    fi
                else
                    log_warning "$name endpoint returned HTTP $response_code"
                fi
                ;;
            "000")
                log_error "$name endpoint is unreachable (connection failed)"
                ;;
            *)
                log_error "$name endpoint returned HTTP $response_code"
                ;;
        esac
    done
}

# Check Fremisn backend servers
check_fremisn_servers() {
    log "🎯 Checking Fremisn backend servers..."
    
    local servers=(
        "Fremisn Master:http://$FREMISN_MASTER"
        "Fremisn Slave:http://$FREMISN_SLAVE"
    )
    
    for server in "${servers[@]}"; do
        check_start
        local name="${server%%:*}"
        local url="${server#*:}"
        
        # Try health endpoint first, then root
        local health_url="$url/health"
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECTION_TIMEOUT" "$health_url" 2>/dev/null || echo "000")
        
        if [[ "$response_code" == "000" ]]; then
            # Try root endpoint
            response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECTION_TIMEOUT" "$url" 2>/dev/null || echo "000")
        fi
        
        case "$response_code" in
            "200"|"201"|"202"|"404")
                # 404 might be acceptable for some Fremisn endpoints
                log_success "$name is reachable (HTTP $response_code)"
                ;;
            "000")
                log_error "$name is unreachable (connection failed)"
                ;;
            "500"|"502"|"503"|"504")
                log_error "$name returned server error (HTTP $response_code)"
                ;;
            *)
                log_warning "$name returned HTTP $response_code"
                ;;
        esac
    done
}

# Check system resources
check_system_resources() {
    log "💻 Checking system resources..."
    
    # Check CPU usage
    check_start
    if command_exists top; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1 || echo "0")
        cpu_usage=${cpu_usage%.*}  # Remove decimal part
        
        if [[ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]]; then
            log_warning "High CPU usage: ${cpu_usage}% (threshold: ${ALERT_THRESHOLD_CPU}%)"
        else
            log_success "CPU usage is normal: ${cpu_usage}%"
        fi
    else
        log_warning "Cannot check CPU usage (top command not available)"
    fi
    
    # Check memory usage
    check_start
    if command_exists free; then
        local memory_info=$(free | grep Mem)
        local total_mem=$(echo $memory_info | awk '{print $2}')
        local used_mem=$(echo $memory_info | awk '{print $3}')
        local memory_usage=$((used_mem * 100 / total_mem))
        
        if [[ "$memory_usage" -gt "$ALERT_THRESHOLD_MEMORY" ]]; then
            log_warning "High memory usage: ${memory_usage}% (threshold: ${ALERT_THRESHOLD_MEMORY}%)"
        else
            log_success "Memory usage is normal: ${memory_usage}%"
        fi
    else
        log_warning "Cannot check memory usage (free command not available)"
    fi
    
    # Check disk usage
    check_start
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1 || echo "0")
    
    if [[ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]]; then
        log_warning "High disk usage: ${disk_usage}% (threshold: ${ALERT_THRESHOLD_DISK}%)"
    else
        log_success "Disk usage is normal: ${disk_usage}%"
    fi
}

# Check Docker container resources
check_container_resources() {
    log "📊 Checking container resources..."
    
    cd "$PROJECT_DIR"
    
    check_start
    if docker-compose ps -q | xargs docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | tail -n +2 | while read line; do
        if [[ -n "$line" ]]; then
            local container=$(echo "$line" | awk '{print $1}')
            local cpu_perc=$(echo "$line" | awk '{print $2}' | cut -d'%' -f1)
            local mem_perc=$(echo "$line" | awk '{print $4}' | cut -d'%' -f1)
            
            # Remove decimal part for comparison
            cpu_perc=${cpu_perc%.*}
            mem_perc=${mem_perc%.*}
            
            if [[ "$cpu_perc" -gt 80 ]] || [[ "$mem_perc" -gt 80 ]]; then
                echo "WARNING: Container $container using high resources (CPU: ${cpu_perc}%, Memory: ${mem_perc}%)"
            fi
        fi
    done; then
        log_success "Container resource usage checked"
    else
        log_warning "Could not check container resource usage"
    fi
}

# Check network connectivity
check_network() {
    log "🌍 Checking network connectivity..."
    
    # Check if we can resolve DNS
    check_start
    if nslookup google.com >/dev/null 2>&1; then
        log_success "DNS resolution is working"
    else
        log_warning "DNS resolution issues detected"
    fi
    
    # Check internet connectivity
    check_start
    if curl -s --connect-timeout 5 http://google.com >/dev/null 2>&1; then
        log_success "Internet connectivity is working"
    else
        log_warning "Internet connectivity issues detected"
    fi
}

# Check data persistence
check_data_persistence() {
    log "💾 Checking data persistence..."
    
    cd "$PROJECT_DIR"
    
    # Check Docker volumes
    check_start
    local volumes=$(docker-compose config --volumes 2>/dev/null || echo "")
    if [[ -n "$volumes" ]]; then
        local volume_count=$(echo "$volumes" | wc -l)
        log_success "Docker volumes configured ($volume_count volumes)"
        
        # Check if volumes exist
        echo "$volumes" | while read volume; do
            if [[ -n "$volume" ]] && docker volume inspect "$volume" >/dev/null 2>&1; then
                [[ "$VERBOSE" == "true" ]] && log "Volume $volume exists"
            else
                [[ "$VERBOSE" == "true" ]] && log "Volume $volume does not exist (will be created on startup)"
            fi
        done
    else
        log_warning "No Docker volumes configured"
    fi
    
    # Check if Prometheus data directory exists in container
    check_start
    if docker-compose exec -T prometheus ls /prometheus >/dev/null 2>&1; then
        log_success "Prometheus data directory is accessible"
    else
        log_warning "Prometheus data directory is not accessible"
    fi
    
    # Check if Grafana data directory exists in container
    check_start
    if docker-compose exec -T grafana ls /var/lib/grafana >/dev/null 2>&1; then
        log_success "Grafana data directory is accessible"
    else
        log_warning "Grafana data directory is not accessible"
    fi
}

# Check log files
check_logs() {
    log "📝 Checking log files..."
    
    cd "$PROJECT_DIR"
    
    # Check if logs directory exists
    check_start
    if [[ -d "logs" ]]; then
        local log_count=$(find logs -name "*.log" 2>/dev/null | wc -l)
        log_success "Logs directory exists with $log_count log files"
        
        # Check log file sizes
        find logs -name "*.log" -size +100M 2>/dev/null | while read large_log; do
            log_warning "Large log file detected: $large_log (>100MB)"
        done
    else
        log_warning "Logs directory does not exist"
    fi
    
    # Check container logs for errors
    check_start
    local error_count=0
    for service in nginx-lb prometheus grafana blackbox-exporter; do
        if docker-compose ps "$service" | grep -q "Up"; then
            local errors=$(docker-compose logs --tail=100 "$service" 2>/dev/null | grep -i "error\|fatal\|critical" | wc -l)
            if [[ "$errors" -gt 0 ]]; then
                log_warning "Found $errors error(s) in $service logs"
                ((error_count += errors))
            fi
        fi
    done
    
    if [[ "$error_count" -eq 0 ]]; then
        log_success "No recent errors found in container logs"
    else
        log_warning "Total errors found in logs: $error_count"
    fi
}

# Check configuration files
check_configuration() {
    log "⚙️  Checking configuration files..."
    
    cd "$PROJECT_DIR"
    
    # Check nginx configuration
    check_start
    if docker run --rm -v "$(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf" nginx nginx -t >/dev/null 2>&1; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration is invalid"
    fi
    
    # Check prometheus configuration
    check_start
    if docker run --rm -v "$(pwd)/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml" prom/prometheus promtool check config /etc/prometheus/prometheus.yml >/dev/null 2>&1; then
        log_success "Prometheus configuration is valid"
    else
        log_error "Prometheus configuration is invalid"
    fi
    
    # Check docker-compose configuration
    check_start
    if docker-compose config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration is invalid"
    fi
}

# Generate health report
generate_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "=============================================================================="
    echo "📊 HEALTH CHECK REPORT"
    echo "=============================================================================="
    echo "Timestamp: $(date)"
    echo "Duration: ${duration}s"
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Passed: $PASSED_CHECKS"
    echo "Warnings: $WARNING_CHECKS"
    echo "Failed: $FAILED_CHECKS"
    echo
    
    # Calculate health percentage
    local health_percentage=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    if [[ "$health_percentage" -ge 90 ]]; then
        echo -e "${GREEN}Overall Health: EXCELLENT (${health_percentage}%)${NC}"
    elif [[ "$health_percentage" -ge 75 ]]; then
        echo -e "${YELLOW}Overall Health: GOOD (${health_percentage}%)${NC}"
    elif [[ "$health_percentage" -ge 50 ]]; then
        echo -e "${YELLOW}Overall Health: FAIR (${health_percentage}%)${NC}"
    else
        echo -e "${RED}Overall Health: POOR (${health_percentage}%)${NC}"
    fi
    
    # Show critical issues
    if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}🚨 CRITICAL ISSUES:${NC}"
        for issue in "${CRITICAL_ISSUES[@]}"; do
            echo -e "${RED}  • $issue${NC}"
        done
    fi
    
    # Show failed services
    if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}❌ FAILED CHECKS:${NC}"
        for service in "${FAILED_SERVICES[@]}"; do
            echo -e "${RED}  • $service${NC}"
        done
    fi
    
    # Show warnings
    if [[ ${#WARNING_SERVICES[@]} -gt 0 ]]; then
        echo
        echo -e "${YELLOW}⚠️  WARNINGS:${NC}"
        for service in "${WARNING_SERVICES[@]}"; do
            echo -e "${YELLOW}  • $service${NC}"
        done
    fi
    
    echo
    echo "Log file: $LOG_FILE"
    echo "=============================================================================="
    
    # Return appropriate exit code
    if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
        return 2  # Critical issues
    elif [[ "$FAILED_CHECKS" -gt 0 ]]; then
        return 1  # Some failures
    else
        return 0  # All good
    fi
}

# Main function
main() {
    start_time=$(date +%s)
    
    echo "=============================================================================="
    echo "🏥 High Availability Fremisn Services - Health Check"
    echo "=============================================================================="
    echo "Started at: $(date)"
    echo "Log file: $LOG_FILE"
    echo "Verbose mode: $VERBOSE"
    echo "=============================================================================="
    echo
    
    # Initialize log file
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Health check started" > "$LOG_FILE"
    
    # Run all health checks
    check_dependencies
    check_docker_daemon
    check_containers
    check_endpoints
    check_fremisn_servers
    check_system_resources
    check_container_resources
    check_network
    check_data_persistence
    check_logs
    check_configuration
    
    # Generate and display report
    generate_report
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "High Availability Fremisn Services - Health Check Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --verbose, -v       Enable verbose output"
        echo "  --log FILE          Specify log file (default: /tmp/fremisn-health-check.log)"
        echo "  --cpu-threshold N   CPU usage alert threshold (default: 80%)"
        echo "  --mem-threshold N   Memory usage alert threshold (default: 80%)"
        echo "  --disk-threshold N  Disk usage alert threshold (default: 85%)"
        echo "  --timeout N         Connection timeout in seconds (default: 10)"
        echo
        echo "Environment Variables:"
        echo "  FREMISN_MASTER_HOST     Fremisn master server IP (default: 192.168.100.231)"
        echo "  FREMISN_MASTER_PORT     Fremisn master server port (default: 4005)"
        echo "  FREMISN_SLAVE_HOST      Fremisn slave server IP (default: 192.168.100.18)"
        echo "  FREMISN_SLAVE_PORT      Fremisn slave server port (default: 4008)"
        echo "  VERBOSE                 Enable verbose output (true/false)"
        echo
        echo "Exit Codes:"
        echo "  0    All checks passed"
        echo "  1    Some checks failed"
        echo "  2    Critical issues detected"
        echo
        echo "Examples:"
        echo "  $0                              # Standard health check"
        echo "  $0 --verbose                    # Verbose output"
        echo "  $0 --cpu-threshold 90           # Custom CPU threshold"
        echo "  $0 --log /var/log/health.log    # Custom log file"
        exit 0
        ;;
    --verbose|-v)
        VERBOSE="true"
        ;;
    --log)
        if [[ -n "${2:-}" ]]; then
            LOG_FILE="$2"
            shift
        else
            echo "Error: --log requires a file path"
            exit 1
        fi
        ;;
    --cpu-threshold)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            ALERT_THRESHOLD_CPU="$2"
            shift
        else
            echo "Error: --cpu-threshold requires a number"
            exit 1
        fi
        ;;
    --mem-threshold)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            ALERT_THRESHOLD_MEMORY="$2"
            shift
        else
            echo "Error: --mem-threshold requires a number"
            exit 1
        fi
        ;;
    --disk-threshold)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            ALERT_THRESHOLD_DISK="$2"
            shift
        else
            echo "Error: --disk-threshold requires a number"
            exit 1
        fi
        ;;
    --timeout)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            CONNECTION_TIMEOUT="$2"
            shift
        else
            echo "Error: --timeout requires a number"
            exit 1
        fi
        ;;
    "")
        # No arguments, proceed with default settings
        ;;
    *)
        echo "Error: Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"