#!/bin/bash

# =============================================================================
# High Availability Fremisn Services - Setup Script
# =============================================================================
# This script automates the initial setup and configuration:
# - System requirements validation
# - Docker and Docker Compose installation
# - Environment configuration
# - Initial deployment
# - Security hardening
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${LOG_FILE:-/tmp/fremisn-setup.log}"
AUTO_INSTALL="${AUTO_INSTALL:-false}"
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-false}"
SKIP_SECURITY_HARDENING="${SKIP_SECURITY_HARDENING:-false}"
VERBOSE="${VERBOSE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Default configuration values
DEFAULT_FREMISN_MASTER_HOST="192.168.100.231"
DEFAULT_FREMISN_MASTER_PORT="4005"
DEFAULT_FREMISN_SLAVE_HOST="192.168.100.18"
DEFAULT_FREMISN_SLAVE_PORT="4008"
DEFAULT_GRAFANA_PASSWORD="admin"
DEFAULT_NGINX_RATE_LIMIT="10r/s"

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

# Setup state
SETUP_STARTED=false
DOCKER_INSTALLED=false
CONFIG_CREATED=false
SERVICES_DEPLOYED=false

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

log_info() {
    local message="$1"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}[$timestamp] ℹ️  $message${NC}"
    echo "[$timestamp] INFO: $message" >> "$LOG_FILE"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Get OS information
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID:$VERSION_ID"
    elif command_exists lsb_release; then
        echo "$(lsb_release -si | tr '[:upper:]' '[:lower:]'):$(lsb_release -sr)"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel:$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+')"
    else
        echo "unknown:unknown"
    fi
}

# Prompt for user input
prompt_input() {
    local prompt="$1"
    local default="$2"
    local variable_name="$3"
    local is_password="${4:-false}"
    
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        eval "$variable_name='$default'"
        log_info "Using default value for $variable_name: $default"
        return
    fi
    
    echo -n "$prompt [$default]: "
    
    if [[ "$is_password" == "true" ]]; then
        read -s user_input
        echo
    else
        read user_input
    fi
    
    if [[ -z "$user_input" ]]; then
        eval "$variable_name='$default'"
    else
        eval "$variable_name='$user_input'"
    fi
}

# Validate system requirements
validate_system_requirements() {
    log "🔍 Validating system requirements..."
    
    # Check OS
    local os_info=$(get_os_info)
    local os_id="${os_info%%:*}"
    local os_version="${os_info##*:}"
    
    log_info "Detected OS: $os_id $os_version"
    
    # Check supported OS
    case "$os_id" in
        "ubuntu"|"debian"|"centos"|"rhel"|"fedora"|"amazon")
            log_success "Operating system is supported"
            ;;
        *)
            log_warning "Operating system may not be fully supported: $os_id"
            ;;
    esac
    
    # Check architecture
    local arch=$(uname -m)
    case "$arch" in
        "x86_64"|"amd64")
            log_success "Architecture is supported: $arch"
            ;;
        "aarch64"|"arm64")
            log_success "Architecture is supported: $arch"
            ;;
        *)
            log_warning "Architecture may not be fully supported: $arch"
            ;;
    esac
    
    # Check minimum RAM (2GB)
    local total_ram=$(free -m | awk 'NR==2{print $2}')
    if [[ "$total_ram" -lt 2048 ]]; then
        log_warning "Low RAM detected: ${total_ram}MB (recommended: 2GB+)"
    else
        log_success "RAM is sufficient: ${total_ram}MB"
    fi
    
    # Check available disk space (5GB)
    local available_space=$(df "$PROJECT_DIR" | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ "$available_space" -lt "$required_space" ]]; then
        log_error "Insufficient disk space. Required: 5GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    else
        log_success "Disk space is sufficient: $((available_space / 1024 / 1024))GB available"
    fi
    
    # Check network connectivity
    if ping -c 1 google.com >/dev/null 2>&1; then
        log_success "Internet connectivity is available"
    else
        log_warning "Internet connectivity issues detected"
    fi
    
    # Check required ports
    local required_ports=("80" "443" "3000" "8080" "8081" "9090" "9115")
    local port_conflicts=()
    
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            port_conflicts+=("$port")
        fi
    done
    
    if [[ ${#port_conflicts[@]} -gt 0 ]]; then
        log_warning "Port conflicts detected: ${port_conflicts[*]}"
        log_warning "These ports are required for the services to run properly"
    else
        log_success "All required ports are available"
    fi
}

# Install Docker
install_docker() {
    if [[ "$SKIP_DOCKER_INSTALL" == "true" ]]; then
        log "⏭️  Skipping Docker installation (SKIP_DOCKER_INSTALL=true)"
        return 0
    fi
    
    log "🐳 Installing Docker..."
    
    # Check if Docker is already installed
    if command_exists docker; then
        local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log_success "Docker is already installed: $docker_version"
        DOCKER_INSTALLED=true
        
        # Check if Docker daemon is running
        if docker info >/dev/null 2>&1; then
            log_success "Docker daemon is running"
        else
            log_warning "Docker daemon is not running. Starting Docker..."
            if [[ "$DRY_RUN" != "true" ]]; then
                sudo systemctl start docker || sudo service docker start
                sudo systemctl enable docker || true
            fi
        fi
        
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would install Docker"
        return 0
    fi
    
    # Get OS information for installation
    local os_info=$(get_os_info)
    local os_id="${os_info%%:*}"
    
    case "$os_id" in
        "ubuntu"|"debian")
            # Update package index
            sudo apt-get update
            
            # Install prerequisites
            sudo apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$os_id/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Set up stable repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$os_id $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        "centos"|"rhel"|"fedora")
            # Install prerequisites
            sudo yum install -y yum-utils
            
            # Set up stable repository
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker Engine
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        "amazon")
            # Amazon Linux
            sudo yum update -y
            sudo yum install -y docker
            ;;
        *)
            log_error "Unsupported OS for automatic Docker installation: $os_id"
            log_error "Please install Docker manually: https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warning "Added $USER to docker group. Please log out and log back in for changes to take effect."
    fi
    
    # Verify installation
    if docker --version >/dev/null 2>&1; then
        local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log_success "Docker installed successfully: $docker_version"
        DOCKER_INSTALLED=true
    else
        log_error "Docker installation failed"
        return 1
    fi
}

# Install Docker Compose
install_docker_compose() {
    log "📦 Installing Docker Compose..."
    
    # Check if Docker Compose is already available
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short 2>/dev/null || echo "v2.x")
        log_success "Docker Compose (v2) is already available: $compose_version"
        return 0
    elif command_exists docker-compose; then
        local compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log_success "Docker Compose (v1) is already installed: $compose_version"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would install Docker Compose"
        return 0
    fi
    
    # Try to install Docker Compose v2 (preferred)
    local arch=$(uname -m)
    case "$arch" in
        "x86_64") arch="x86_64" ;;
        "aarch64") arch="aarch64" ;;
        "armv7l") arch="armv7" ;;
        *) arch="x86_64" ;;
    esac
    
    # Get latest version
    local latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    
    if [[ -n "$latest_version" ]]; then
        # Download and install Docker Compose v2
        sudo curl -L "https://github.com/docker/compose/releases/download/$latest_version/docker-compose-$(uname -s)-$arch" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Create symlink for docker compose command
        sudo ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose
        
        # Verify installation
        if docker-compose --version >/dev/null 2>&1; then
            local compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
            log_success "Docker Compose installed successfully: $compose_version"
        else
            log_error "Docker Compose installation failed"
            return 1
        fi
    else
        log_error "Failed to get latest Docker Compose version"
        return 1
    fi
}

# Configure environment
configure_environment() {
    log "⚙️  Configuring environment..."
    
    cd "$PROJECT_DIR"
    
    # Create .env file if it doesn't exist
    if [[ ! -f ".env" ]]; then
        log "📝 Creating environment configuration..."
        
        # Gather configuration from user
        local fremisn_master_host
        local fremisn_master_port
        local fremisn_slave_host
        local fremisn_slave_port
        local grafana_password
        local nginx_rate_limit
        
        echo
        echo -e "${BOLD}${CYAN}=== Fremisn HA Configuration ===${NC}"
        echo
        
        prompt_input "Fremisn Master Host" "$DEFAULT_FREMISN_MASTER_HOST" "fremisn_master_host"
        prompt_input "Fremisn Master Port" "$DEFAULT_FREMISN_MASTER_PORT" "fremisn_master_port"
        prompt_input "Fremisn Slave Host" "$DEFAULT_FREMISN_SLAVE_HOST" "fremisn_slave_host"
        prompt_input "Fremisn Slave Port" "$DEFAULT_FREMISN_SLAVE_PORT" "fremisn_slave_port"
        prompt_input "Grafana Admin Password" "$DEFAULT_GRAFANA_PASSWORD" "grafana_password" "true"
        prompt_input "Nginx Rate Limit" "$DEFAULT_NGINX_RATE_LIMIT" "nginx_rate_limit"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            # Create .env file
            cat > .env << EOF
# =============================================================================
# High Availability Fremisn Services - Environment Configuration
# =============================================================================
# Generated on: $(date)
# =============================================================================

# Fremisn Server Configuration
FREMISN_MASTER_HOST=$fremisn_master_host
FREMISN_MASTER_PORT=$fremisn_master_port
FREMISN_SLAVE_HOST=$fremisn_slave_host
FREMISN_SLAVE_PORT=$fremisn_slave_port

# Load Balancer Configuration
LOAD_BALANCER_PORT=8081
NGINX_STATUS_PORT=8080
NGINX_RATE_LIMIT=$nginx_rate_limit
NGINX_WORKER_PROCESSES=auto
NGINX_WORKER_CONNECTIONS=1024

# Monitoring Configuration
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
GRAFANA_ADMIN_PASSWORD=$grafana_password
BLACKBOX_EXPORTER_PORT=9115

# Logging Configuration
LOG_LEVEL=info
LOG_FORMAT=json
LOG_RETENTION_DAYS=30

# Docker Configuration
COMPOSE_PROJECT_NAME=fremisn-ha
DOCKER_NETWORK_NAME=fremisn-network

# Performance Tuning
NGINX_KEEPALIVE_TIMEOUT=65
NGINX_CLIENT_MAX_BODY_SIZE=10m
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_SCRAPE_INTERVAL=15s

# Security Configuration
SSL_ENABLED=false
SSL_CERT_PATH=/etc/ssl/certs/fremisn.crt
SSL_KEY_PATH=/etc/ssl/private/fremisn.key

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=7
BACKUP_SCHEDULE="0 2 * * *"

# Alert Configuration
ALERT_ENABLED=false
SLACK_WEBHOOK_URL=
EMAIL_ALERTS=
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=80
ALERT_THRESHOLD_DISK=85

# Development/Debug
DEBUG=false
VERBOSE_LOGGING=false
EOF
            
            log_success "Environment configuration created: .env"
            CONFIG_CREATED=true
        else
            log_info "DRY RUN: Would create .env file"
        fi
    else
        log_success "Environment configuration already exists: .env"
        CONFIG_CREATED=true
    fi
    
    # Create necessary directories
    local directories=("logs" "backups" "ssl" "data/prometheus" "data/grafana")
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                mkdir -p "$dir"
                log_success "Created directory: $dir"
            else
                log_info "DRY RUN: Would create directory: $dir"
            fi
        fi
    done
    
    # Set proper permissions
    if [[ "$DRY_RUN" != "true" ]]; then
        chmod 755 scripts/*.sh 2>/dev/null || true
        chmod 600 .env 2>/dev/null || true
        
        # Set ownership for data directories
        if is_root; then
            chown -R 472:472 data/grafana 2>/dev/null || true  # Grafana user
            chown -R 65534:65534 data/prometheus 2>/dev/null || true  # Nobody user
        fi
        
        log_success "Permissions configured"
    else
        log_info "DRY RUN: Would configure permissions"
    fi
}

# Security hardening
security_hardening() {
    if [[ "$SKIP_SECURITY_HARDENING" == "true" ]]; then
        log "⏭️  Skipping security hardening (SKIP_SECURITY_HARDENING=true)"
        return 0
    fi
    
    log "🔒 Applying security hardening..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would apply security hardening"
        return 0
    fi
    
    # Configure firewall (if available)
    if command_exists ufw; then
        log "🔥 Configuring UFW firewall..."
        
        # Enable UFW
        sudo ufw --force enable
        
        # Allow SSH
        sudo ufw allow ssh
        
        # Allow required ports
        sudo ufw allow 80/tcp comment "HTTP"
        sudo ufw allow 443/tcp comment "HTTPS"
        sudo ufw allow 3000/tcp comment "Grafana"
        sudo ufw allow 8080/tcp comment "Nginx Status"
        sudo ufw allow 8081/tcp comment "Load Balancer"
        sudo ufw allow 9090/tcp comment "Prometheus"
        sudo ufw allow 9115/tcp comment "Blackbox Exporter"
        
        log_success "UFW firewall configured"
    elif command_exists firewall-cmd; then
        log "🔥 Configuring firewalld..."
        
        # Enable firewalld
        sudo systemctl enable firewalld
        sudo systemctl start firewalld
        
        # Allow required ports
        sudo firewall-cmd --permanent --add-port=80/tcp
        sudo firewall-cmd --permanent --add-port=443/tcp
        sudo firewall-cmd --permanent --add-port=3000/tcp
        sudo firewall-cmd --permanent --add-port=8080/tcp
        sudo firewall-cmd --permanent --add-port=8081/tcp
        sudo firewall-cmd --permanent --add-port=9090/tcp
        sudo firewall-cmd --permanent --add-port=9115/tcp
        
        sudo firewall-cmd --reload
        
        log_success "Firewalld configured"
    else
        log_warning "No supported firewall found (ufw/firewalld)"
    fi
    
    # Configure Docker daemon security
    local docker_daemon_config="/etc/docker/daemon.json"
    if [[ ! -f "$docker_daemon_config" ]]; then
        log "🐳 Configuring Docker daemon security..."
        
        sudo mkdir -p /etc/docker
        sudo tee "$docker_daemon_config" > /dev/null << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
EOF
        
        # Restart Docker to apply changes
        sudo systemctl restart docker
        
        log_success "Docker daemon security configured"
    fi
    
    # Set up log rotation
    if command_exists logrotate; then
        log "📝 Configuring log rotation..."
        
        sudo tee /etc/logrotate.d/fremisn-ha > /dev/null << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
    postrotate
        docker-compose -f $PROJECT_DIR/docker-compose.yml restart nginx-lb || true
    endscript
}
EOF
        
        log_success "Log rotation configured"
    fi
    
    log_success "Security hardening completed"
}

# Deploy services
deploy_services() {
    log "🚀 Deploying services..."
    
    cd "$PROJECT_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy services"
        return 0
    fi
    
    # Pull latest images
    log "📥 Pulling Docker images..."
    if docker-compose pull; then
        log_success "Docker images pulled successfully"
    else
        log_warning "Some Docker images may not have been pulled"
    fi
    
    # Start services
    log "▶️  Starting services..."
    if docker-compose up -d; then
        log_success "Services started successfully"
        SERVICES_DEPLOYED=true
    else
        log_error "Failed to start services"
        return 1
    fi
    
    # Wait for services to be ready
    log "⏳ Waiting for services to be ready..."
    sleep 15
    
    # Basic health check
    local health_check_passed=true
    local endpoints=(
        "http://localhost:8081/health:Load Balancer"
        "http://localhost:9090:Prometheus"
        "http://localhost:3000:Grafana"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local url="${endpoint%%:*}"
        local name="${endpoint##*:}"
        
        if curl -s --connect-timeout 10 "$url" >/dev/null 2>&1; then
            log_success "$name is responding"
        else
            log_warning "$name is not responding yet"
            health_check_passed=false
        fi
    done
    
    if [[ "$health_check_passed" == "true" ]]; then
        log_success "All services are responding"
    else
        log_warning "Some services may still be starting up"
    fi
}

# Show setup summary
show_setup_summary() {
    echo
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${WHITE}🎉 High Availability Fremisn Services - Setup Complete!${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo
    
    echo -e "${BOLD}📊 Setup Summary:${NC}"
    echo "  Docker Installed: $([[ "$DOCKER_INSTALLED" == "true" ]] && echo "✅ Yes" || echo "❌ No")"
    echo "  Configuration Created: $([[ "$CONFIG_CREATED" == "true" ]] && echo "✅ Yes" || echo "❌ No")"
    echo "  Services Deployed: $([[ "$SERVICES_DEPLOYED" == "true" ]] && echo "✅ Yes" || echo "❌ No")"
    echo
    
    if [[ "$SERVICES_DEPLOYED" == "true" ]]; then
        echo -e "${BOLD}🌐 Service URLs:${NC}"
        echo "  Load Balancer:     http://localhost:8081"
        echo "  Nginx Status:      http://localhost:8080/nginx_status"
        echo "  Prometheus:        http://localhost:9090"
        echo "  Grafana:           http://localhost:3000 (admin/admin)"
        echo "  Blackbox Exporter: http://localhost:9115"
        echo
    fi
    
    echo -e "${BOLD}📁 Project Structure:${NC}"
    echo "  Project Directory: $PROJECT_DIR"
    echo "  Configuration:     $PROJECT_DIR/.env"
    echo "  Scripts:           $PROJECT_DIR/scripts/"
    echo "  Logs:              $PROJECT_DIR/logs/"
    echo "  Backups:           $PROJECT_DIR/backups/"
    echo
    
    echo -e "${BOLD}🛠️  Management Commands:${NC}"
    echo "  Start services:    docker-compose up -d"
    echo "  Stop services:     docker-compose down"
    echo "  View logs:         docker-compose logs -f"
    echo "  Health check:      $SCRIPT_DIR/health-check.sh"
    echo "  Deploy:            $SCRIPT_DIR/deploy.sh"
    echo "  Monitor:           $SCRIPT_DIR/monitoring.sh --dashboard"
    echo "  Backup:            $SCRIPT_DIR/backup.sh"
    echo
    
    echo -e "${BOLD}📚 Next Steps:${NC}"
    echo "  1. Review and customize the configuration in .env file"
    echo "  2. Update Fremisn server endpoints if needed"
    echo "  3. Configure SSL certificates for production use"
    echo "  4. Set up monitoring alerts (Slack/Email)"
    echo "  5. Schedule regular backups"
    echo "  6. Review security settings and firewall rules"
    echo
    
    if [[ ! groups "$USER" | grep -q docker ]]; then
        echo -e "${YELLOW}⚠️  Important: Please log out and log back in for Docker group changes to take effect.${NC}"
        echo
    fi
    
    echo -e "${BOLD}📖 Documentation:${NC}"
    echo "  README:            $PROJECT_DIR/README.md"
    echo "  Environment:       $PROJECT_DIR/.env.example"
    echo "  Setup Log:         $LOG_FILE"
    
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ "$exit_code" -ne 0 ]] && [[ "$SETUP_STARTED" == "true" ]]; then
        log_error "Setup failed with exit code $exit_code"
        
        echo
        echo -e "${RED}Setup failed. Check the log file for details: $LOG_FILE${NC}"
        echo -e "${YELLOW}You can re-run the setup script to continue from where it left off.${NC}"
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'log_error "Setup interrupted by user"; exit 130' INT TERM

# Main setup function
main() {
    local start_time=$(date +%s)
    
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${WHITE}🚀 High Availability Fremisn Services - Setup${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo "Started at: $(date)"
    echo "Project Directory: $PROJECT_DIR"
    echo "Log File: $LOG_FILE"
    echo "Auto Install: $AUTO_INSTALL"
    echo "Dry Run: $DRY_RUN"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo
    
    SETUP_STARTED=true
    
    # Initialize log file
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Setup started" > "$LOG_FILE"
    
    # Run setup steps
    validate_system_requirements
    install_docker
    install_docker_compose
    configure_environment
    security_hardening
    deploy_services
    
    # Calculate setup time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Setup completed successfully in ${duration}s"
    
    # Show summary
    show_setup_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "High Availability Fremisn Services - Setup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --auto, -a              Automatic installation with defaults"
        echo "  --verbose, -v           Enable verbose output"
        echo "  --dry-run               Show what would be done without making changes"
        echo "  --log FILE              Specify log file (default: /tmp/fremisn-setup.log)"
        echo "  --skip-docker           Skip Docker installation"
        echo "  --skip-security         Skip security hardening"
        echo
        echo "Environment Variables:"
        echo "  AUTO_INSTALL            Automatic installation (true/false)"
        echo "  SKIP_DOCKER_INSTALL     Skip Docker installation (true/false)"
        echo "  SKIP_SECURITY_HARDENING Skip security hardening (true/false)"
        echo "  VERBOSE                 Enable verbose output (true/false)"
        echo "  DRY_RUN                 Show what would be done (true/false)"
        echo
        echo "Examples:"
        echo "  $0                      # Interactive setup"
        echo "  $0 --auto              # Automatic setup with defaults"
        echo "  $0 --dry-run            # Preview what would be done"
        echo "  $0 --skip-docker        # Skip Docker installation"
        exit 0
        ;;
    --auto|-a)
        AUTO_INSTALL="true"
        ;;
    --verbose|-v)
        VERBOSE="true"
        ;;
    --dry-run)
        DRY_RUN="true"
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
    --skip-docker)
        SKIP_DOCKER_INSTALL="true"
        ;;
    --skip-security)
        SKIP_SECURITY_HARDENING="true"
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
        --auto|-a)
            AUTO_INSTALL="true"
            ;;
        --verbose|-v)
            VERBOSE="true"
            ;;
        --dry-run)
            DRY_RUN="true"
            ;;
        --skip-docker)
            SKIP_DOCKER_INSTALL="true"
            ;;
        --skip-security)
            SKIP_SECURITY_HARDENING="true"
            ;;
        *)
            # Skip already processed arguments
            ;;
    esac
    shift
done

# Run main function
main