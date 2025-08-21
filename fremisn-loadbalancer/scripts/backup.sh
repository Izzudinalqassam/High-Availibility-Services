#!/bin/bash

# =============================================================================
# High Availability Fremisn Services - Backup Script
# =============================================================================
# This script creates a complete backup of the Fremisn HA system including:
# - Configuration files
# - Prometheus data
# - Grafana data
# - Docker volumes
# - Logs (optional)
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE_DIR="${BACKUP_DIR:-/backup}"
BACKUP_DIR="$BACKUP_BASE_DIR/fremisn-$DATE"
COMPRESS_BACKUP="${COMPRESS_BACKUP:-true}"
INCLUDE_LOGS="${INCLUDE_LOGS:-false}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. This is not recommended for security reasons."
    fi
}

# Check if Docker and Docker Compose are available
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_warning "Backup directory already exists. Removing..."
        rm -rf "$BACKUP_DIR"
    fi
    
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created"
}

# Backup configuration files
backup_configs() {
    log "Backing up configuration files..."
    
    local config_dir="$BACKUP_DIR/configs"
    mkdir -p "$config_dir"
    
    # Copy all configuration directories
    cp -r "$PROJECT_DIR/nginx" "$config_dir/"
    cp -r "$PROJECT_DIR/prometheus" "$config_dir/"
    cp -r "$PROJECT_DIR/blackbox" "$config_dir/"
    cp -r "$PROJECT_DIR/grafana" "$config_dir/"
    
    # Copy main files
    cp "$PROJECT_DIR/docker-compose.yml" "$config_dir/"
    cp "$PROJECT_DIR/README.md" "$config_dir/" 2>/dev/null || true
    cp "$PROJECT_DIR/.env" "$config_dir/" 2>/dev/null || true
    cp "$PROJECT_DIR/.env.example" "$config_dir/" 2>/dev/null || true
    
    log_success "Configuration files backed up"
}

# Backup Docker volumes
backup_volumes() {
    log "Backing up Docker volumes..."
    
    local volumes_dir="$BACKUP_DIR/volumes"
    mkdir -p "$volumes_dir"
    
    cd "$PROJECT_DIR"
    
    # Get volume names
    local prometheus_volume=$(docker-compose config --volumes | grep prometheus || echo "")
    local grafana_volume=$(docker-compose config --volumes | grep grafana || echo "")
    
    # Backup Prometheus data
    if [[ -n "$prometheus_volume" ]] && docker volume inspect "$prometheus_volume" &>/dev/null; then
        log "Backing up Prometheus volume: $prometheus_volume"
        docker run --rm -v "$prometheus_volume":/source -v "$volumes_dir":/backup alpine tar czf /backup/prometheus-data.tar.gz -C /source .
        log_success "Prometheus data backed up"
    else
        log_warning "Prometheus volume not found or not created yet"
    fi
    
    # Backup Grafana data
    if [[ -n "$grafana_volume" ]] && docker volume inspect "$grafana_volume" &>/dev/null; then
        log "Backing up Grafana volume: $grafana_volume"
        docker run --rm -v "$grafana_volume":/source -v "$volumes_dir":/backup alpine tar czf /backup/grafana-data.tar.gz -C /source .
        log_success "Grafana data backed up"
    else
        log_warning "Grafana volume not found or not created yet"
    fi
}

# Backup container data (alternative method)
backup_container_data() {
    log "Backing up container data..."
    
    local data_dir="$BACKUP_DIR/container-data"
    mkdir -p "$data_dir"
    
    cd "$PROJECT_DIR"
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        # Backup Prometheus data from running container
        if docker-compose ps prometheus | grep -q "Up"; then
            log "Backing up Prometheus data from running container..."
            docker-compose exec -T prometheus tar czf - /prometheus > "$data_dir/prometheus-data.tar.gz" 2>/dev/null || {
                log_warning "Failed to backup Prometheus data from running container"
            }
        fi
        
        # Backup Grafana data from running container
        if docker-compose ps grafana | grep -q "Up"; then
            log "Backing up Grafana data from running container..."
            docker-compose exec -T grafana tar czf - /var/lib/grafana > "$data_dir/grafana-data.tar.gz" 2>/dev/null || {
                log_warning "Failed to backup Grafana data from running container"
            }
        fi
    else
        log_warning "Containers are not running. Skipping container data backup."
    fi
}

# Backup logs
backup_logs() {
    if [[ "$INCLUDE_LOGS" == "true" ]]; then
        log "Backing up logs..."
        
        local logs_dir="$BACKUP_DIR/logs"
        mkdir -p "$logs_dir"
        
        # Copy logs directory if it exists
        if [[ -d "$PROJECT_DIR/logs" ]]; then
            cp -r "$PROJECT_DIR/logs"/* "$logs_dir/" 2>/dev/null || true
        fi
        
        # Get Docker logs
        cd "$PROJECT_DIR"
        if docker-compose ps | grep -q "Up"; then
            for service in nginx-lb prometheus grafana blackbox-exporter; do
                if docker-compose ps "$service" | grep -q "Up"; then
                    log "Backing up logs for service: $service"
                    docker-compose logs "$service" > "$logs_dir/${service}.log" 2>/dev/null || true
                fi
            done
        fi
        
        log_success "Logs backed up"
    else
        log "Skipping logs backup (INCLUDE_LOGS=false)"
    fi
}

# Create backup metadata
create_metadata() {
    log "Creating backup metadata..."
    
    local metadata_file="$BACKUP_DIR/backup-metadata.json"
    
    cat > "$metadata_file" << EOF
{
  "backup_date": "$(date -Iseconds)",
  "backup_version": "1.0",
  "project_name": "High Availability Fremisn Services",
  "backup_type": "full",
  "include_logs": $INCLUDE_LOGS,
  "compressed": $COMPRESS_BACKUP,
  "retention_days": $RETENTION_DAYS,
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
    "compose_version": "$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || docker compose version --short 2>/dev/null || echo 'unknown')"
  },
  "services_status": {
EOF

    # Add services status
    cd "$PROJECT_DIR"
    if docker-compose ps --format json &>/dev/null; then
        docker-compose ps --format json >> "$metadata_file" 2>/dev/null || echo '    "error": "Could not get services status"' >> "$metadata_file"
    else
        echo '    "error": "Docker Compose does not support --format json"' >> "$metadata_file"
    fi
    
    echo '  }' >> "$metadata_file"
    echo '}' >> "$metadata_file"
    
    log_success "Backup metadata created"
}

# Compress backup
compress_backup() {
    if [[ "$COMPRESS_BACKUP" == "true" ]]; then
        log "Compressing backup..."
        
        local compressed_file="$BACKUP_BASE_DIR/fremisn-backup-$DATE.tar.gz"
        
        cd "$BACKUP_BASE_DIR"
        tar czf "$compressed_file" "fremisn-$DATE"
        
        # Verify compression
        if [[ -f "$compressed_file" ]]; then
            local original_size=$(du -sh "fremisn-$DATE" | cut -f1)
            local compressed_size=$(du -sh "$compressed_file" | cut -f1)
            
            log_success "Backup compressed successfully"
            log "Original size: $original_size"
            log "Compressed size: $compressed_size"
            log "Compressed file: $compressed_file"
            
            # Remove uncompressed directory
            rm -rf "$BACKUP_DIR"
            log "Uncompressed backup directory removed"
        else
            log_error "Failed to create compressed backup"
            exit 1
        fi
    else
        log "Backup compression disabled"
        log "Backup directory: $BACKUP_DIR"
    fi
}

# Clean old backups
clean_old_backups() {
    log "Cleaning old backups (older than $RETENTION_DAYS days)..."
    
    local deleted_count=0
    
    # Clean compressed backups
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted_count++))
        log "Deleted old backup: $(basename "$file")"
    done < <(find "$BACKUP_BASE_DIR" -name "fremisn-backup-*.tar.gz" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
    
    # Clean uncompressed backups
    while IFS= read -r -d '' dir; do
        rm -rf "$dir"
        ((deleted_count++))
        log "Deleted old backup directory: $(basename "$dir")"
    done < <(find "$BACKUP_BASE_DIR" -name "fremisn-*" -type d -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
    
    if [[ $deleted_count -eq 0 ]]; then
        log "No old backups found to clean"
    else
        log_success "Cleaned $deleted_count old backup(s)"
    fi
}

# Calculate backup size
calculate_size() {
    local target="$1"
    if [[ -f "$target" ]]; then
        du -sh "$target" | cut -f1
    elif [[ -d "$target" ]]; then
        du -sh "$target" | cut -f1
    else
        echo "unknown"
    fi
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    echo "=============================================================================="
    echo "🚀 High Availability Fremisn Services - Backup Script"
    echo "=============================================================================="
    echo "Backup started at: $(date)"
    echo "Backup directory: $BACKUP_DIR"
    echo "Include logs: $INCLUDE_LOGS"
    echo "Compress backup: $COMPRESS_BACKUP"
    echo "Retention days: $RETENTION_DAYS"
    echo "=============================================================================="
    echo
    
    # Run backup steps
    check_permissions
    check_dependencies
    create_backup_dir
    backup_configs
    backup_volumes
    backup_container_data
    backup_logs
    create_metadata
    compress_backup
    clean_old_backups
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "=============================================================================="
    log_success "Backup completed successfully!"
    echo "Duration: ${duration}s"
    
    if [[ "$COMPRESS_BACKUP" == "true" ]]; then
        local backup_file="$BACKUP_BASE_DIR/fremisn-backup-$DATE.tar.gz"
        echo "Backup file: $backup_file"
        echo "Backup size: $(calculate_size "$backup_file")"
    else
        echo "Backup directory: $BACKUP_DIR"
        echo "Backup size: $(calculate_size "$BACKUP_DIR")"
    fi
    
    echo "=============================================================================="
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "High Availability Fremisn Services - Backup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --include-logs      Include logs in backup"
        echo "  --no-compress       Don't compress the backup"
        echo "  --retention DAYS    Set retention period (default: 30 days)"
        echo
        echo "Environment Variables:"
        echo "  BACKUP_DIR          Base backup directory (default: /backup)"
        echo "  INCLUDE_LOGS        Include logs (true/false, default: false)"
        echo "  COMPRESS_BACKUP     Compress backup (true/false, default: true)"
        echo "  BACKUP_RETENTION_DAYS  Retention period in days (default: 30)"
        echo
        echo "Examples:"
        echo "  $0                          # Standard backup"
        echo "  $0 --include-logs           # Backup with logs"
        echo "  $0 --no-compress            # Uncompressed backup"
        echo "  $0 --retention 7            # 7 days retention"
        echo "  BACKUP_DIR=/tmp $0          # Custom backup directory"
        exit 0
        ;;
    --include-logs)
        INCLUDE_LOGS="true"
        ;;
    --no-compress)
        COMPRESS_BACKUP="false"
        ;;
    --retention)
        if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
            RETENTION_DAYS="$2"
            shift
        else
            log_error "Invalid retention days: ${2:-}"
            exit 1
        fi
        ;;
    "")
        # No arguments, proceed with default settings
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"