#!/bin/bash

# =============================================================================
# High Availability Fremisn Services - Deployment Script
# =============================================================================
# This script automates the deployment process for the Fremisn HA system:
# - Environment validation
# - Configuration verification
# - Service deployment
# - Health checks
# - Rollback capabilities
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${LOG_FILE:-/tmp/fremisn-deploy.log}"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
BACKUP_BEFORE_DEPLOY="${BACKUP_BEFORE_DEPLOY:-true}"
ROLLBACK_ON_FAILURE="${ROLLBACK_ON_FAILURE:-true}"
VERBOSE="${VERBOSE:-false}"

# Service configuration
SERVICES=("nginx-lb" "prometheus" "grafana" "blackbox-exporter")
CRITICAL_SERVICES=("nginx-lb" "prometheus")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Deployment state
DEPLOYMENT_ID="deploy-$(date +%Y%m%d-%H%M%S)"
DEPLOYMENT_STARTED=false
BACKUP_CREATED=false
BACKUP_PATH=""
PREVIOUS_STATE=""

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
}

log_warning() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${YELLOW}[$timestamp] ⚠️  $message${NC}"
    echo "[$timestamp] WARNING: $message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${RED}[$timestamp] ❌ $message${NC}"
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
}

log_critical() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${RED}[$timestamp] 🚨 CRITICAL: $message${NC}"
    echo "[$timestamp] CRITICAL: $message" >> "$LOG_FILE"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    
    if [[ "$exit_code" -ne 0 ]] && [[ "$DEPLOYMENT_STARTED" == "true" ]]; then
        log_error "Deployment failed with exit code $exit_code"
        
        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]] && [[ "$BACKUP_CREATED" == "true" ]]; then
            log "🔄 Initiating automatic rollback..."
            rollback_deployment
        fi
    fi
    
    log "🏁 Deployment process completed with exit code $exit_code"
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'log_error "Deployment interrupted by user"; exit 130' INT TERM

# Validate environment
validate_environment() {
    log "🔍 Validating deployment environment..."
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "curl" "tar" "gzip")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running or not accessible"
        return 1
    fi
    
    # Check Docker Compose version
    local compose_version
    if docker compose version >/dev/null 2>&1; then
        compose_version="$(docker compose version --short 2>/dev/null || echo 'v2.x')"
        log_success "Docker Compose v2 detected: $compose_version"
    elif docker-compose version >/dev/null 2>&1; then
        compose_version="$(docker-compose version --short 2>/dev/null || echo 'v1.x')"
        log_success "Docker Compose v1 detected: $compose_version"
    else
        log_error "Docker Compose is not available"
        return 1
    fi
    
    # Check available disk space (minimum 2GB)
    local available_space=$(df "$PROJECT_DIR" | awk 'NR==2 {print $4}')
    local required_space=2097152  # 2GB in KB
    
    if [[ "$available_space" -lt "$required_space" ]]; then
        log_error "Insufficient disk space. Required: 2GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
    
    # Check network connectivity
    if ! curl -s --connect-timeout 5 http://google.com >/dev/null 2>&1; then
        log_warning "Internet connectivity issues detected. Docker image pulls may fail."
    fi
    
    log_success "Environment validation completed"
}

# Validate configuration files
validate_configuration() {
    log "⚙️  Validating configuration files..."
    
    cd "$PROJECT_DIR"
    
    # Check if required files exist
    local required_files=(
        "docker-compose.yml"
        "nginx/nginx.conf"
        "prometheus/prometheus.yml"
        "blackbox/blackbox.yml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required configuration file not found: $file"
            return 1
        fi
    done
    
    # Validate Docker Compose configuration
    if ! docker-compose config >/dev/null 2>&1; then
        log_error "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Validate Nginx configuration
    if ! docker run --rm -v "$(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf" nginx nginx -t >/dev/null 2>&1; then
        log_error "Nginx configuration is invalid"
        return 1
    fi
    
    # Validate Prometheus configuration
    if ! docker run --rm -v "$(pwd)/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml" prom/prometheus promtool check config /etc/prometheus/prometheus.yml >/dev/null 2>&1; then
        log_error "Prometheus configuration is invalid"
        return 1
    fi
    
    log_success "Configuration validation completed"
}

# Create backup before deployment
create_backup() {
    if [[ "$BACKUP_BEFORE_DEPLOY" != "true" ]]; then
        log "⏭️  Skipping backup (BACKUP_BEFORE_DEPLOY=false)"
        return 0
    fi
    
    log "💾 Creating backup before deployment..."
    
    cd "$PROJECT_DIR"
    
    # Create backup directory
    local backup_dir="backups"
    mkdir -p "$backup_dir"
    
    # Generate backup filename
    local backup_filename="fremisn-backup-${DEPLOYMENT_ID}.tar.gz"
    BACKUP_PATH="$backup_dir/$backup_filename"
    
    # Save current container state
    PREVIOUS_STATE=$(docker-compose ps --format json 2>/dev/null || echo "[]")
    
    # Create backup archive
    local backup_items=(
        "docker-compose.yml"
        "nginx/"
        "prometheus/"
        "blackbox/"
        "grafana/"
        ".env"
    )
    
    # Add existing items to backup
    local existing_items=()
    for item in "${backup_items[@]}"; do
        if [[ -e "$item" ]]; then
            existing_items+=("$item")
        fi
    done
    
    if [[ ${#existing_items[@]} -gt 0 ]]; then
        if tar -czf "$BACKUP_PATH" "${existing_items[@]}" 2>/dev/null; then
            BACKUP_CREATED=true
            log_success "Backup created: $BACKUP_PATH"
        else
            log_error "Failed to create backup"
            return 1
        fi
    else
        log_warning "No configuration files found to backup"
    fi
    
    # Backup Docker volumes if they exist
    local volumes=$(docker volume ls --format "{{.Name}}" | grep "fremisn" || true)
    if [[ -n "$volumes" ]]; then
        log "📦 Backing up Docker volumes..."
        echo "$volumes" > "$backup_dir/volumes-${DEPLOYMENT_ID}.list"
        log_success "Volume list saved for potential restoration"
    fi
}

# Pull latest Docker images
pull_images() {
    log "📥 Pulling latest Docker images..."
    
    cd "$PROJECT_DIR"
    
    # Get list of images from docker-compose
    local images=$(docker-compose config | grep 'image:' | awk '{print $2}' | sort -u)
    
    if [[ -z "$images" ]]; then
        log_warning "No images found in docker-compose.yml"
        return 0
    fi
    
    # Pull each image
    echo "$images" | while read -r image; do
        if [[ -n "$image" ]]; then
            log "Pulling image: $image"
            if docker pull "$image"; then
                log_success "Successfully pulled: $image"
            else
                log_error "Failed to pull: $image"
                return 1
            fi
        fi
    done
    
    log_success "All images pulled successfully"
}

# Deploy services
deploy_services() {
    log "🚀 Deploying services..."
    
    cd "$PROJECT_DIR"
    DEPLOYMENT_STARTED=true
    
    # Stop existing services gracefully
    log "⏹️  Stopping existing services..."
    if docker-compose ps -q | grep -q .; then
        if docker-compose down --timeout 30; then
            log_success "Existing services stopped"
        else
            log_warning "Some services may not have stopped gracefully"
        fi
    else
        log "No existing services to stop"
    fi
    
    # Start services
    log "▶️  Starting services..."
    if docker-compose up -d --remove-orphans; then
        log_success "Services started successfully"
    else
        log_error "Failed to start services"
        return 1
    fi
    
    # Wait for services to be ready
    log "⏳ Waiting for services to be ready..."
    sleep 10
    
    # Check if critical services are running
    for service in "${CRITICAL_SERVICES[@]}"; do
        if docker-compose ps "$service" | grep -q "Up"; then
            log_success "Critical service $service is running"
        else
            log_error "Critical service $service failed to start"
            return 1
        fi
    done
    
    log_success "Service deployment completed"
}

# Perform health checks
perform_health_checks() {
    log "🏥 Performing health checks..."
    
    local retry_count=0
    local max_retries="$HEALTH_CHECK_RETRIES"
    local check_interval="$HEALTH_CHECK_INTERVAL"
    
    while [[ "$retry_count" -lt "$max_retries" ]]; do
        log "Health check attempt $((retry_count + 1))/$max_retries"
        
        # Run health check script if available
        if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
            if bash "$SCRIPT_DIR/health-check.sh" >/dev/null 2>&1; then
                log_success "Health checks passed"
                return 0
            else
                log_warning "Health checks failed on attempt $((retry_count + 1))"
            fi
        else
            # Basic health checks
            local all_healthy=true
            
            # Check service endpoints
            local endpoints=(
                "http://localhost:8081/health"
                "http://localhost:9090/-/healthy"
                "http://localhost:3000/api/health"
            )
            
            for endpoint in "${endpoints[@]}"; do
                if ! curl -s --connect-timeout 5 "$endpoint" >/dev/null 2>&1; then
                    all_healthy=false
                    break
                fi
            done
            
            if [[ "$all_healthy" == "true" ]]; then
                log_success "Basic health checks passed"
                return 0
            else
                log_warning "Basic health checks failed on attempt $((retry_count + 1))"
            fi
        fi
        
        ((retry_count++))
        
        if [[ "$retry_count" -lt "$max_retries" ]]; then
            log "Waiting ${check_interval}s before next health check..."
            sleep "$check_interval"
        fi
    done
    
    log_error "Health checks failed after $max_retries attempts"
    return 1
}

# Rollback deployment
rollback_deployment() {
    log "🔄 Rolling back deployment..."
    
    if [[ "$BACKUP_CREATED" != "true" ]] || [[ ! -f "$BACKUP_PATH" ]]; then
        log_error "No backup available for rollback"
        return 1
    fi
    
    cd "$PROJECT_DIR"
    
    # Stop current services
    log "⏹️  Stopping current services..."
    docker-compose down --timeout 30 || true
    
    # Restore from backup
    log "📦 Restoring from backup: $BACKUP_PATH"
    if tar -xzf "$BACKUP_PATH" -C "$PROJECT_DIR"; then
        log_success "Configuration restored from backup"
    else
        log_error "Failed to restore from backup"
        return 1
    fi
    
    # Restart services with previous configuration
    log "▶️  Restarting services with previous configuration..."
    if docker-compose up -d; then
        log_success "Services restarted with previous configuration"
    else
        log_error "Failed to restart services after rollback"
        return 1
    fi
    
    # Wait and verify rollback
    sleep 10
    
    if perform_health_checks; then
        log_success "Rollback completed successfully"
    else
        log_error "Rollback completed but health checks failed"
        return 1
    fi
}

# Show deployment status
show_status() {
    log "📊 Deployment Status"
    echo "=============================================================================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Project Directory: $PROJECT_DIR"
    echo "Log File: $LOG_FILE"
    echo "Backup Created: $BACKUP_CREATED"
    if [[ "$BACKUP_CREATED" == "true" ]]; then
        echo "Backup Path: $BACKUP_PATH"
    fi
    echo "=============================================================================="
    
    cd "$PROJECT_DIR"
    
    # Show service status
    echo "📦 Service Status:"
    docker-compose ps
    
    echo
    echo "🌐 Service URLs:"
    echo "  Load Balancer:     http://localhost:8081"
    echo "  Nginx Status:      http://localhost:8080/nginx_status"
    echo "  Prometheus:        http://localhost:9090"
    echo "  Grafana:           http://localhost:3000 (admin/admin)"
    echo "  Blackbox Exporter: http://localhost:9115"
    
    echo
    echo "📝 Quick Commands:"
    echo "  View logs:         docker-compose logs -f"
    echo "  Restart service:   docker-compose restart <service>"
    echo "  Stop all:          docker-compose down"
    echo "  Health check:      $SCRIPT_DIR/health-check.sh"
    
    if [[ -f "$SCRIPT_DIR/test-loadbalancer.sh" ]]; then
        echo "  Test load balancer: $SCRIPT_DIR/test-loadbalancer.sh"
    fi
    
    echo "=============================================================================="
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    echo "=============================================================================="
    echo "🚀 High Availability Fremisn Services - Deployment"
    echo "=============================================================================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Started at: $(date)"
    echo "Project Directory: $PROJECT_DIR"
    echo "Log File: $LOG_FILE"
    echo "=============================================================================="
    echo
    
    # Initialize log file
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Deployment $DEPLOYMENT_ID started" > "$LOG_FILE"
    
    # Run deployment steps
    validate_environment
    validate_configuration
    create_backup
    pull_images
    deploy_services
    perform_health_checks
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Deployment completed successfully in ${duration}s"
    
    # Show final status
    echo
    show_status
    
    echo
    log_success "🎉 Deployment $DEPLOYMENT_ID completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "High Availability Fremisn Services - Deployment Script"
        echo
        echo "Usage: $0 [command] [options]"
        echo
        echo "Commands:"
        echo "  deploy              Deploy services (default)"
        echo "  rollback            Rollback to previous deployment"
        echo "  status              Show current deployment status"
        echo "  validate            Validate environment and configuration only"
        echo "  backup              Create backup only"
        echo "  pull                Pull latest images only"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --verbose, -v       Enable verbose output"
        echo "  --log FILE          Specify log file (default: /tmp/fremisn-deploy.log)"
        echo "  --timeout N         Deployment timeout in seconds (default: 300)"
        echo "  --retries N         Health check retries (default: 5)"
        echo "  --interval N        Health check interval in seconds (default: 10)"
        echo "  --no-backup         Skip backup creation"
        echo "  --no-rollback       Disable automatic rollback on failure"
        echo
        echo "Environment Variables:"
        echo "  BACKUP_BEFORE_DEPLOY    Create backup before deployment (true/false)"
        echo "  ROLLBACK_ON_FAILURE     Enable automatic rollback (true/false)"
        echo "  DEPLOY_TIMEOUT          Deployment timeout in seconds"
        echo "  HEALTH_CHECK_RETRIES    Number of health check retries"
        echo "  HEALTH_CHECK_INTERVAL   Health check interval in seconds"
        echo "  VERBOSE                 Enable verbose output (true/false)"
        echo
        echo "Examples:"
        echo "  $0                      # Standard deployment"
        echo "  $0 deploy --verbose     # Verbose deployment"
        echo "  $0 rollback             # Rollback to previous version"
        echo "  $0 status               # Show current status"
        echo "  $0 validate             # Validate configuration only"
        exit 0
        ;;
    deploy|"")
        # Parse additional options
        shift || true
        while [[ $# -gt 0 ]]; do
            case $1 in
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
                --timeout)
                    if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        DEPLOY_TIMEOUT="$2"
                        shift
                    else
                        echo "Error: --timeout requires a number"
                        exit 1
                    fi
                    ;;
                --retries)
                    if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        HEALTH_CHECK_RETRIES="$2"
                        shift
                    else
                        echo "Error: --retries requires a number"
                        exit 1
                    fi
                    ;;
                --interval)
                    if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        HEALTH_CHECK_INTERVAL="$2"
                        shift
                    else
                        echo "Error: --interval requires a number"
                        exit 1
                    fi
                    ;;
                --no-backup)
                    BACKUP_BEFORE_DEPLOY="false"
                    ;;
                --no-rollback)
                    ROLLBACK_ON_FAILURE="false"
                    ;;
                *)
                    echo "Error: Unknown option: $1"
                    echo "Use --help for usage information"
                    exit 1
                    ;;
            esac
            shift
        done
        main
        ;;
    rollback)
        echo "🔄 Initiating manual rollback..."
        if [[ -f "$LOG_FILE" ]]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Manual rollback initiated" >> "$LOG_FILE"
        fi
        rollback_deployment
        ;;
    status)
        show_status
        ;;
    validate)
        echo "🔍 Validating environment and configuration..."
        validate_environment
        validate_configuration
        log_success "Validation completed successfully"
        ;;
    backup)
        echo "💾 Creating backup..."
        create_backup
        log_success "Backup completed"
        ;;
    pull)
        echo "📥 Pulling latest images..."
        pull_images
        log_success "Image pull completed"
        ;;
    *)
        echo "Error: Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac