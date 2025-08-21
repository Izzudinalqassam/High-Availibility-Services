#!/bin/bash

# =============================================================================
# High Availability Fremisn Services - Real-time Monitoring Script
# =============================================================================
# This script provides real-time monitoring capabilities:
# - Live service status monitoring
# - Resource usage tracking
# - Performance metrics
# - Alert notifications
# - Dashboard display
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${LOG_FILE:-/tmp/fremisn-monitoring.log}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-5}"
ALERT_THRESHOLD_CPU="${ALERT_THRESHOLD_CPU:-80}"
ALERT_THRESHOLD_MEMORY="${ALERT_THRESHOLD_MEMORY:-80}"
ALERT_THRESHOLD_DISK="${ALERT_THRESHOLD_DISK:-85}"
ALERT_THRESHOLD_RESPONSE_TIME="${ALERT_THRESHOLD_RESPONSE_TIME:-5000}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_ALERTS="${EMAIL_ALERTS:-}"
VERBOSE="${VERBOSE:-false}"
DASHBOARD_MODE="${DASHBOARD_MODE:-false}"

# Service endpoints
LOAD_BALANCER_URL="http://localhost:8081"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9090"
NGINX_STATUS_URL="http://localhost:8080/nginx_status"
BLACKBOX_URL="http://localhost:9115"

# Fremisn servers
FREMISN_MASTER="${FREMISN_MASTER_HOST:-192.168.100.231}:${FREMISN_MASTER_PORT:-4005}"
FREMISN_SLAVE="${FREMISN_SLAVE_HOST:-192.168.100.18}:${FREMISN_SLAVE_PORT:-4008}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Monitoring state
MONITORING_ACTIVE=false
ALERT_HISTORY=()
LAST_ALERT_TIME=0
ALERT_COOLDOWN=300  # 5 minutes

# Performance metrics
declare -A RESPONSE_TIMES
declare -A SERVICE_STATUS
declare -A RESOURCE_USAGE
declare -A ALERT_COUNTS

# Initialize metrics
init_metrics() {
    RESPONSE_TIMES["load_balancer"]=0
    RESPONSE_TIMES["prometheus"]=0
    RESPONSE_TIMES["grafana"]=0
    RESPONSE_TIMES["nginx_status"]=0
    RESPONSE_TIMES["blackbox"]=0
    RESPONSE_TIMES["fremisn_master"]=0
    RESPONSE_TIMES["fremisn_slave"]=0
    
    SERVICE_STATUS["nginx-lb"]="unknown"
    SERVICE_STATUS["prometheus"]="unknown"
    SERVICE_STATUS["grafana"]="unknown"
    SERVICE_STATUS["blackbox-exporter"]="unknown"
    
    RESOURCE_USAGE["cpu"]=0
    RESOURCE_USAGE["memory"]=0
    RESOURCE_USAGE["disk"]=0
    
    ALERT_COUNTS["cpu"]=0
    ALERT_COUNTS["memory"]=0
    ALERT_COUNTS["disk"]=0
    ALERT_COUNTS["response_time"]=0
    ALERT_COUNTS["service_down"]=0
}

# Logging functions
log() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    if [[ "$DASHBOARD_MODE" != "true" ]]; then
        echo -e "${BLUE}[$timestamp]${NC} $message"
    fi
    [[ "$VERBOSE" == "true" ]] && echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_alert() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "CRITICAL")
            echo -e "${RED}[$timestamp] 🚨 CRITICAL: $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[$timestamp] ⚠️  WARNING: $message${NC}"
            ;;
        "INFO")
            echo -e "${GREEN}[$timestamp] ℹ️  INFO: $message${NC}"
            ;;
    esac
    
    echo "[$timestamp] $level: $message" >> "$LOG_FILE"
    
    # Add to alert history
    ALERT_HISTORY+=("[$timestamp] $level: $message")
    
    # Keep only last 50 alerts
    if [[ ${#ALERT_HISTORY[@]} -gt 50 ]]; then
        ALERT_HISTORY=("${ALERT_HISTORY[@]:1}")
    fi
    
    # Send external alerts
    send_alert "$level" "$message"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Send alert notifications
send_alert() {
    local level="$1"
    local message="$2"
    local current_time=$(date +%s)
    
    # Check cooldown period
    if [[ $((current_time - LAST_ALERT_TIME)) -lt $ALERT_COOLDOWN ]]; then
        return 0
    fi
    
    # Send Slack notification
    if [[ -n "$SLACK_WEBHOOK_URL" ]] && command_exists curl; then
        local color="good"
        case "$level" in
            "CRITICAL") color="danger" ;;
            "WARNING") color="warning" ;;
        esac
        
        local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Fremisn HA Monitoring Alert",
            "text": "$message",
            "fields": [
                {
                    "title": "Level",
                    "value": "$level",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date)",
                    "short": true
                }
            ]
        }
    ]
}
EOF
        )
        
        curl -s -X POST -H 'Content-type: application/json' \
            --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi
    
    # Send email notification
    if [[ -n "$EMAIL_ALERTS" ]] && command_exists mail; then
        echo "$message" | mail -s "Fremisn HA Alert: $level" "$EMAIL_ALERTS" 2>/dev/null || true
    fi
    
    LAST_ALERT_TIME=$current_time
}

# Measure response time
measure_response_time() {
    local url="$1"
    local timeout="${2:-10}"
    
    local start_time=$(date +%s%3N)
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)
    
    local response_time=$((end_time - start_time))
    
    echo "$response_time:$response_code"
}

# Check service endpoints
check_endpoints() {
    # Load Balancer
    local result=$(measure_response_time "$LOAD_BALANCER_URL/health")
    RESPONSE_TIMES["load_balancer"]="${result%%:*}"
    local status_code="${result##*:}"
    
    if [[ "$status_code" == "200" ]]; then
        SERVICE_STATUS["load_balancer"]="healthy"
    else
        SERVICE_STATUS["load_balancer"]="unhealthy"
        log_alert "CRITICAL" "Load Balancer is unhealthy (HTTP $status_code)"
        ((ALERT_COUNTS["service_down"]++))
    fi
    
    # Prometheus
    result=$(measure_response_time "$PROMETHEUS_URL/-/healthy")
    RESPONSE_TIMES["prometheus"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "200" ]] || [[ "$status_code" == "404" ]]; then
        # 404 might be acceptable for older Prometheus versions
        result=$(measure_response_time "$PROMETHEUS_URL")
        status_code="${result##*:}"
    fi
    
    if [[ "$status_code" == "200" ]]; then
        SERVICE_STATUS["prometheus"]="healthy"
    else
        SERVICE_STATUS["prometheus"]="unhealthy"
        log_alert "CRITICAL" "Prometheus is unhealthy (HTTP $status_code)"
        ((ALERT_COUNTS["service_down"]++))
    fi
    
    # Grafana
    result=$(measure_response_time "$GRAFANA_URL/api/health")
    RESPONSE_TIMES["grafana"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "200" ]]; then
        SERVICE_STATUS["grafana"]="healthy"
    else
        SERVICE_STATUS["grafana"]="unhealthy"
        log_alert "WARNING" "Grafana is unhealthy (HTTP $status_code)"
        ((ALERT_COUNTS["service_down"]++))
    fi
    
    # Nginx Status
    result=$(measure_response_time "$NGINX_STATUS_URL")
    RESPONSE_TIMES["nginx_status"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "200" ]]; then
        SERVICE_STATUS["nginx_status"]="healthy"
    else
        SERVICE_STATUS["nginx_status"]="unhealthy"
        log_alert "WARNING" "Nginx Status endpoint is unhealthy (HTTP $status_code)"
    fi
    
    # Blackbox Exporter
    result=$(measure_response_time "$BLACKBOX_URL/metrics")
    RESPONSE_TIMES["blackbox"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "200" ]]; then
        SERVICE_STATUS["blackbox"]="healthy"
    else
        SERVICE_STATUS["blackbox"]="unhealthy"
        log_alert "WARNING" "Blackbox Exporter is unhealthy (HTTP $status_code)"
    fi
    
    # Fremisn Master
    result=$(measure_response_time "http://$FREMISN_MASTER/health")
    RESPONSE_TIMES["fremisn_master"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "000" ]]; then
        # Try root endpoint
        result=$(measure_response_time "http://$FREMISN_MASTER")
        status_code="${result##*:}"
    fi
    
    if [[ "$status_code" != "000" ]]; then
        SERVICE_STATUS["fremisn_master"]="reachable"
    else
        SERVICE_STATUS["fremisn_master"]="unreachable"
        log_alert "CRITICAL" "Fremisn Master is unreachable"
        ((ALERT_COUNTS["service_down"]++))
    fi
    
    # Fremisn Slave
    result=$(measure_response_time "http://$FREMISN_SLAVE/health")
    RESPONSE_TIMES["fremisn_slave"]="${result%%:*}"
    status_code="${result##*:}"
    
    if [[ "$status_code" == "000" ]]; then
        # Try root endpoint
        result=$(measure_response_time "http://$FREMISN_SLAVE")
        status_code="${result##*:}"
    fi
    
    if [[ "$status_code" != "000" ]]; then
        SERVICE_STATUS["fremisn_slave"]="reachable"
    else
        SERVICE_STATUS["fremisn_slave"]="unreachable"
        log_alert "WARNING" "Fremisn Slave is unreachable"
        ((ALERT_COUNTS["service_down"]++))
    fi
    
    # Check response time alerts
    for service in "${!RESPONSE_TIMES[@]}"; do
        local response_time="${RESPONSE_TIMES[$service]}"
        if [[ "$response_time" -gt "$ALERT_THRESHOLD_RESPONSE_TIME" ]]; then
            log_alert "WARNING" "High response time for $service: ${response_time}ms"
            ((ALERT_COUNTS["response_time"]++))
        fi
    done
}

# Check container status
check_containers() {
    cd "$PROJECT_DIR"
    
    local services=("nginx-lb" "prometheus" "grafana" "blackbox-exporter")
    
    for service in "${services[@]}"; do
        local status=$(docker-compose ps -q "$service" 2>/dev/null | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
        
        case "$status" in
            "running")
                SERVICE_STATUS["$service"]="running"
                ;;
            "exited")
                SERVICE_STATUS["$service"]="exited"
                log_alert "CRITICAL" "Container $service has exited"
                ((ALERT_COUNTS["service_down"]++))
                ;;
            "restarting")
                SERVICE_STATUS["$service"]="restarting"
                log_alert "WARNING" "Container $service is restarting"
                ;;
            "not_found")
                SERVICE_STATUS["$service"]="not_found"
                log_alert "CRITICAL" "Container $service not found"
                ((ALERT_COUNTS["service_down"]++))
                ;;
            *)
                SERVICE_STATUS["$service"]="unknown"
                log_alert "WARNING" "Container $service status unknown: $status"
                ;;
        esac
    done
}

# Check system resources
check_system_resources() {
    # CPU usage
    if command_exists top; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1 2>/dev/null || echo "0")
        cpu_usage=${cpu_usage%.*}  # Remove decimal part
        RESOURCE_USAGE["cpu"]="$cpu_usage"
        
        if [[ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]]; then
            log_alert "WARNING" "High CPU usage: ${cpu_usage}%"
            ((ALERT_COUNTS["cpu"]++))
        fi
    fi
    
    # Memory usage
    if command_exists free; then
        local memory_info=$(free | grep Mem)
        local total_mem=$(echo $memory_info | awk '{print $2}')
        local used_mem=$(echo $memory_info | awk '{print $3}')
        local memory_usage=$((used_mem * 100 / total_mem))
        RESOURCE_USAGE["memory"]="$memory_usage"
        
        if [[ "$memory_usage" -gt "$ALERT_THRESHOLD_MEMORY" ]]; then
            log_alert "WARNING" "High memory usage: ${memory_usage}%"
            ((ALERT_COUNTS["memory"]++))
        fi
    fi
    
    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1 2>/dev/null || echo "0")
    RESOURCE_USAGE["disk"]="$disk_usage"
    
    if [[ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]]; then
        log_alert "WARNING" "High disk usage: ${disk_usage}%"
        ((ALERT_COUNTS["disk"]++))
    fi
}

# Get container resource usage
get_container_resources() {
    cd "$PROJECT_DIR"
    
    if docker-compose ps -q >/dev/null 2>&1; then
        docker-compose ps -q | xargs docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | tail -n +2 | while read line; do
            if [[ -n "$line" ]]; then
                local container=$(echo "$line" | awk '{print $1}')
                local cpu_perc=$(echo "$line" | awk '{print $2}' | cut -d'%' -f1)
                local mem_usage=$(echo "$line" | awk '{print $3}')
                local mem_perc=$(echo "$line" | awk '{print $4}' | cut -d'%' -f1)
                
                # Store container metrics (simplified for this example)
                if [[ "$VERBOSE" == "true" ]]; then
                    echo "Container $container: CPU ${cpu_perc}%, Memory ${mem_perc}%" >> "$LOG_FILE"
                fi
            fi
        done
    fi
}

# Display dashboard
display_dashboard() {
    clear
    
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${WHITE}🖥️  High Availability Fremisn Services - Real-time Monitor${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${WHITE}Last Update: $(date)${NC}"
    echo -e "${WHITE}Monitoring Interval: ${MONITOR_INTERVAL}s${NC}"
    echo
    
    # Service Status Section
    echo -e "${BOLD}${BLUE}📦 Container Status:${NC}"
    printf "%-20s %-15s\n" "Service" "Status"
    echo "----------------------------------------"
    
    for service in "nginx-lb" "prometheus" "grafana" "blackbox-exporter"; do
        local status="${SERVICE_STATUS[$service]:-unknown}"
        local color="$RED"
        local icon="❌"
        
        case "$status" in
            "running") color="$GREEN"; icon="✅" ;;
            "restarting") color="$YELLOW"; icon="🔄" ;;
            "exited"|"not_found") color="$RED"; icon="❌" ;;
        esac
        
        printf "%-20s ${color}%-15s${NC}\n" "$service" "$icon $status"
    done
    
    echo
    
    # Endpoint Status Section
    echo -e "${BOLD}${BLUE}🌐 Endpoint Health:${NC}"
    printf "%-20s %-15s %-15s\n" "Endpoint" "Status" "Response Time"
    echo "----------------------------------------------------"
    
    local endpoints=(
        "load_balancer:Load Balancer"
        "prometheus:Prometheus"
        "grafana:Grafana"
        "nginx_status:Nginx Status"
        "blackbox:Blackbox Exp"
        "fremisn_master:Fremisn Master"
        "fremisn_slave:Fremisn Slave"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local key="${endpoint%%:*}"
        local name="${endpoint##*:}"
        local status="${SERVICE_STATUS[$key]:-unknown}"
        local response_time="${RESPONSE_TIMES[$key]:-0}"
        
        local color="$RED"
        local icon="❌"
        
        case "$status" in
            "healthy"|"reachable"|"running") color="$GREEN"; icon="✅" ;;
            "unhealthy"|"unreachable") color="$RED"; icon="❌" ;;
            *) color="$YELLOW"; icon="⚠️" ;;
        esac
        
        printf "%-20s ${color}%-15s${NC} %-15s\n" "$name" "$icon $status" "${response_time}ms"
    done
    
    echo
    
    # System Resources Section
    echo -e "${BOLD}${BLUE}💻 System Resources:${NC}"
    printf "%-15s %-15s %-15s\n" "Resource" "Usage" "Status"
    echo "---------------------------------------------"
    
    local cpu_usage="${RESOURCE_USAGE[cpu]:-0}"
    local mem_usage="${RESOURCE_USAGE[memory]:-0}"
    local disk_usage="${RESOURCE_USAGE[disk]:-0}"
    
    # CPU
    local cpu_color="$GREEN"
    local cpu_icon="✅"
    if [[ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]]; then
        cpu_color="$RED"
        cpu_icon="❌"
    elif [[ "$cpu_usage" -gt $((ALERT_THRESHOLD_CPU - 10)) ]]; then
        cpu_color="$YELLOW"
        cpu_icon="⚠️"
    fi
    
    printf "%-15s %-15s ${cpu_color}%-15s${NC}\n" "CPU" "${cpu_usage}%" "$cpu_icon"
    
    # Memory
    local mem_color="$GREEN"
    local mem_icon="✅"
    if [[ "$mem_usage" -gt "$ALERT_THRESHOLD_MEMORY" ]]; then
        mem_color="$RED"
        mem_icon="❌"
    elif [[ "$mem_usage" -gt $((ALERT_THRESHOLD_MEMORY - 10)) ]]; then
        mem_color="$YELLOW"
        mem_icon="⚠️"
    fi
    
    printf "%-15s %-15s ${mem_color}%-15s${NC}\n" "Memory" "${mem_usage}%" "$mem_icon"
    
    # Disk
    local disk_color="$GREEN"
    local disk_icon="✅"
    if [[ "$disk_usage" -gt "$ALERT_THRESHOLD_DISK" ]]; then
        disk_color="$RED"
        disk_icon="❌"
    elif [[ "$disk_usage" -gt $((ALERT_THRESHOLD_DISK - 10)) ]]; then
        disk_color="$YELLOW"
        disk_icon="⚠️"
    fi
    
    printf "%-15s %-15s ${disk_color}%-15s${NC}\n" "Disk" "${disk_usage}%" "$disk_icon"
    
    echo
    
    # Alert Summary
    echo -e "${BOLD}${BLUE}🚨 Alert Summary:${NC}"
    printf "%-20s %-10s\n" "Alert Type" "Count"
    echo "------------------------------"
    printf "%-20s %-10s\n" "CPU Alerts" "${ALERT_COUNTS[cpu]}"
    printf "%-20s %-10s\n" "Memory Alerts" "${ALERT_COUNTS[memory]}"
    printf "%-20s %-10s\n" "Disk Alerts" "${ALERT_COUNTS[disk]}"
    printf "%-20s %-10s\n" "Response Time" "${ALERT_COUNTS[response_time]}"
    printf "%-20s %-10s\n" "Service Down" "${ALERT_COUNTS[service_down]}"
    
    echo
    
    # Recent Alerts
    if [[ ${#ALERT_HISTORY[@]} -gt 0 ]]; then
        echo -e "${BOLD}${BLUE}📋 Recent Alerts (Last 5):${NC}"
        echo "----------------------------------------"
        local start_idx=$((${#ALERT_HISTORY[@]} - 5))
        if [[ $start_idx -lt 0 ]]; then
            start_idx=0
        fi
        
        for ((i=start_idx; i<${#ALERT_HISTORY[@]}; i++)); do
            echo "${ALERT_HISTORY[$i]}"
        done
        echo
    fi
    
    # Quick Actions
    echo -e "${BOLD}${BLUE}⚡ Quick Actions:${NC}"
    echo "  [Ctrl+C] Stop monitoring"
    echo "  [q] Quit (if interactive)"
    echo "  [r] Restart services"
    echo "  [h] Health check"
    echo "  [l] View logs"
    
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
}

# Interactive mode handler
handle_input() {
    if [[ "$DASHBOARD_MODE" == "true" ]]; then
        # Non-blocking input check
        if read -t 0.1 -n 1 input 2>/dev/null; then
            case "$input" in
                'q'|'Q')
                    log_alert "INFO" "Monitoring stopped by user"
                    exit 0
                    ;;
                'r'|'R')
                    log_alert "INFO" "Restarting services..."
                    cd "$PROJECT_DIR"
                    docker-compose restart
                    ;;
                'h'|'H')
                    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
                        bash "$SCRIPT_DIR/health-check.sh"
                    fi
                    ;;
                'l'|'L')
                    cd "$PROJECT_DIR"
                    docker-compose logs --tail=20
                    ;;
            esac
        fi
    fi
}

# Main monitoring loop
monitor_loop() {
    MONITORING_ACTIVE=true
    
    log_alert "INFO" "Monitoring started with ${MONITOR_INTERVAL}s interval"
    
    while [[ "$MONITORING_ACTIVE" == "true" ]]; do
        # Collect metrics
        check_containers
        check_endpoints
        check_system_resources
        get_container_resources
        
        # Display dashboard if enabled
        if [[ "$DASHBOARD_MODE" == "true" ]]; then
            display_dashboard
            handle_input
        fi
        
        # Wait for next iteration
        sleep "$MONITOR_INTERVAL"
    done
}

# Cleanup function
cleanup() {
    MONITORING_ACTIVE=false
    log_alert "INFO" "Monitoring stopped"
    
    if [[ "$DASHBOARD_MODE" == "true" ]]; then
        echo
        echo "Monitoring session ended."
    fi
    
    exit 0
}

# Set up signal handlers
trap cleanup EXIT
trap 'cleanup' INT TERM

# Main function
main() {
    echo "=============================================================================="
    echo "🖥️  High Availability Fremisn Services - Real-time Monitoring"
    echo "=============================================================================="
    echo "Started at: $(date)"
    echo "Log File: $LOG_FILE"
    echo "Monitor Interval: ${MONITOR_INTERVAL}s"
    echo "Dashboard Mode: $DASHBOARD_MODE"
    echo "=============================================================================="
    echo
    
    # Initialize
    init_metrics
    
    # Initialize log file
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Monitoring started" > "$LOG_FILE"
    
    # Start monitoring
    monitor_loop
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "High Availability Fremisn Services - Real-time Monitoring Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --dashboard, -d         Enable dashboard mode (real-time display)"
        echo "  --verbose, -v           Enable verbose output"
        echo "  --interval N            Monitoring interval in seconds (default: 5)"
        echo "  --log FILE              Specify log file (default: /tmp/fremisn-monitoring.log)"
        echo "  --cpu-threshold N       CPU usage alert threshold (default: 80%)"
        echo "  --mem-threshold N       Memory usage alert threshold (default: 80%)"
        echo "  --disk-threshold N      Disk usage alert threshold (default: 85%)"
        echo "  --response-threshold N  Response time alert threshold in ms (default: 5000)"
        echo "  --slack-webhook URL     Slack webhook URL for alerts"
        echo "  --email EMAIL           Email address for alerts"
        echo
        echo "Environment Variables:"
        echo "  MONITOR_INTERVAL            Monitoring interval in seconds"
        echo "  ALERT_THRESHOLD_CPU         CPU usage alert threshold"
        echo "  ALERT_THRESHOLD_MEMORY      Memory usage alert threshold"
        echo "  ALERT_THRESHOLD_DISK        Disk usage alert threshold"
        echo "  ALERT_THRESHOLD_RESPONSE_TIME Response time threshold in ms"
        echo "  SLACK_WEBHOOK_URL           Slack webhook URL for alerts"
        echo "  EMAIL_ALERTS                Email address for alerts"
        echo "  FREMISN_MASTER_HOST         Fremisn master server IP"
        echo "  FREMISN_MASTER_PORT         Fremisn master server port"
        echo "  FREMISN_SLAVE_HOST          Fremisn slave server IP"
        echo "  FREMISN_SLAVE_PORT          Fremisn slave server port"
        echo "  VERBOSE                     Enable verbose output (true/false)"
        echo "  DASHBOARD_MODE              Enable dashboard mode (true/false)"
        echo
        echo "Interactive Commands (Dashboard Mode):"
        echo "  q    Quit monitoring"
        echo "  r    Restart services"
        echo "  h    Run health check"
        echo "  l    View recent logs"
        echo
        echo "Examples:"
        echo "  $0                          # Standard monitoring"
        echo "  $0 --dashboard              # Dashboard mode"
        echo "  $0 --interval 10            # 10-second intervals"
        echo "  $0 --slack-webhook URL      # Enable Slack alerts"
        exit 0
        ;;
    --dashboard|-d)
        DASHBOARD_MODE="true"
        ;;
    --verbose|-v)
        VERBOSE="true"
        ;;
    --interval)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            MONITOR_INTERVAL="$2"
            shift
        else
            echo "Error: --interval requires a number"
            exit 1
        fi
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
    --response-threshold)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            ALERT_THRESHOLD_RESPONSE_TIME="$2"
            shift
        else
            echo "Error: --response-threshold requires a number"
            exit 1
        fi
        ;;
    --slack-webhook)
        if [[ -n "${2:-}" ]]; then
            SLACK_WEBHOOK_URL="$2"
            shift
        else
            echo "Error: --slack-webhook requires a URL"
            exit 1
        fi
        ;;
    --email)
        if [[ -n "${2:-}" ]]; then
            EMAIL_ALERTS="$2"
            shift
        else
            echo "Error: --email requires an email address"
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

# Parse additional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dashboard|-d)
            DASHBOARD_MODE="true"
            ;;
        --verbose|-v)
            VERBOSE="true"
            ;;
        *)
            # Skip already processed arguments
            ;;
    esac
    shift
donemain