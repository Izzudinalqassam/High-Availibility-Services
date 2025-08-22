# 🏗️ Architecture Documentation

## High Availability Fremisn Services - System Architecture

Dokumen ini menjelaskan arsitektur sistem High Availability Fremisn Services secara detail, termasuk komponen utama, alur data, dan interaksi antar komponen.

## 📊 Diagram Arsitektur

![Architecture Topology](./architecture-topology.svg)

## 🏛️ Arsitektur Overview

Sistem High Availability Fremisn Services menggunakan arsitektur **multi-tier** yang terdiri dari 4 zona utama:

1. **Client Zone** - Layer akses pengguna
2. **Load Balancer Zone** - Layer distribusi traffic
3. **Application Zone** - Layer aplikasi Fremisn
4. **Monitoring Zone** - Layer observability dan monitoring

## 🔧 Komponen Sistem

### 1. Client Zone

#### External Clients
- **Fungsi**: Entry point untuk semua request dari pengguna
- **Komponen**: Web browsers, mobile applications, API consumers
- **Protokol**: HTTP/HTTPS
- **Karakteristik**:
  - Dapat mengakses sistem dari berbagai platform
  - Mendukung concurrent connections
  - Transparent failover experience

### 2. Load Balancer Zone

#### Nginx Load Balancer
- **Fungsi**: Mendistribusikan traffic ke multiple server Fremisn
- **Port**: 
  - `8081` - Main load balancer endpoint
  - `8080` - Nginx status dan metrics
- **Algoritma**: Round-Robin dengan failover
- **Fitur**:
  - **Enhanced Rate Limiting**: 50 requests/second + 100 burst capacity
  - **Health Checks**: Automatic detection server yang down dengan custom error pages
  - **Session Persistence**: Sticky sessions jika diperlukan
  - **SSL Termination**: HTTPS support
  - **Compression**: Gzip compression untuk response
  - **Proxy Buffering**: Enhanced buffering dan timeout configuration
  - **Keepalive Connections**: Optimized connection pooling

**Konfigurasi Upstream**:
```nginx
upstream fremisn_backend {
    # Load balancing with health checks and failover
    server 192.168.100.231:4005 max_fails=3 fail_timeout=30s weight=1;
    server 192.168.100.18:4008 max_fails=3 fail_timeout=30s weight=1;
    server 192.168.100.17:4009 max_fails=3 fail_timeout=30s weight=1 backup;
    
    # Keep alive connections for better performance
    keepalive 64;
    keepalive_requests 1000;
    keepalive_timeout 60s;
}
```

### 3. Application Zone

#### Fremisn Master Server
- **IP Address**: 192.168.100.231
- **Port**: 4005
- **Role**: Primary application instance
- **Karakteristik**:
  - Handles write operations
  - Primary data source
  - High priority dalam load balancing

#### Fremisn Slave Server 1
- **IP Address**: 192.168.100.18
- **Port**: 4008
- **Role**: Replica instance
- **Karakteristik**:
  - Read-only operations (jika applicable)
  - Backup untuk Master
  - Load distribution

#### Fremisn Slave Server 2
- **IP Address**: 192.168.100.17
- **Port**: 4009
- **Role**: Replica instance
- **Karakteristik**:
  - Additional capacity
  - Enhanced availability
  - Geographic distribution (jika applicable)

### 4. Monitoring Zone

#### Prometheus
- **Port**: 9090
- **Fungsi**: Time-series metrics collection dan storage
- **Data Sources**:
  - Blackbox Exporter metrics
  - Nginx metrics
  - System metrics
- **Retention**: Configurable (default 15 days)
- **Storage**: Persistent volume untuk data retention

#### Blackbox Exporter
- **Port**: 9115
- **Fungsi**: External monitoring dan health checks
- **Probe Types**:
  - HTTP probes untuk server availability
  - TCP probes untuk port connectivity
  - DNS probes untuk name resolution
- **Check Interval**: 15 seconds
- **Timeout**: 10 seconds

#### Grafana
- **Port**: 3000
- **Fungsi**: Visualization dan dashboard
- **Features**:
  - Real-time dashboards
  - Alerting rules
  - User management
  - Dashboard provisioning
- **Data Source**: Prometheus
- **Authentication**: Admin/admin123 (default)

#### Persistent Storage
- **Fungsi**: Data persistence untuk monitoring stack
- **Components**:
  - Prometheus data directory
  - Grafana configuration dan dashboards
  - Log files
- **Technology**: Docker volumes
- **Backup**: Automated backup scripts

#### Docker Engine
- **Fungsi**: Container runtime dan orchestration
- **Technology**: Docker Compose
- **Features**:
  - Service discovery
  - Network isolation
  - Resource management
  - Auto-restart policies

## 🔄 Alur Data dan Interaksi

### 1. Application Traffic Flow

```
Client Request → Nginx Load Balancer → Fremisn Server (Round-Robin) → Response
```

**Detail Flow**:
1. **Client Request**: User mengirim HTTP request ke load balancer (port 8081)
2. **Load Balancing**: Nginx memilih server berdasarkan round-robin algorithm
3. **Health Check**: Nginx memverifikasi server health sebelum forwarding
4. **Request Forwarding**: Request diteruskan ke selected Fremisn server
5. **Response Processing**: Server memproses request dan mengirim response
6. **Response Delivery**: Nginx meneruskan response kembali ke client

### 2. Monitoring Data Flow

```
Blackbox Exporter → Health Checks → Prometheus → Grafana → Dashboard
```

**Detail Flow**:
1. **Health Probes**: Blackbox Exporter melakukan HTTP probes ke semua Fremisn servers
2. **Metrics Collection**: Prometheus scrapes metrics dari Blackbox Exporter
3. **Data Storage**: Metrics disimpan dalam time-series database
4. **Visualization**: Grafana query Prometheus untuk dashboard data
5. **Alerting**: Alert rules trigger notifikasi jika ada issues

### 3. System Monitoring Flow

```
Nginx Status → Prometheus → Grafana → Performance Dashboard
```

**Detail Flow**:
1. **Nginx Metrics**: Nginx expose status metrics di port 8080
2. **Metrics Scraping**: Prometheus collect nginx performance data
3. **Load Balancer Analytics**: Data dianalisis untuk performance insights
4. **Dashboard Update**: Real-time update di Grafana dashboard

## 🚀 Key Performance Indicators (KPIs)

### Availability Metrics
- **Target Uptime**: 99.9% (8.76 hours downtime/year)
- **MTTR (Mean Time To Recovery)**: < 5 minutes
- **MTBF (Mean Time Between Failures)**: > 720 hours

### Performance Metrics
- **Response Time**: < 100ms (95th percentile)
- **Throughput**: 1000 requests/second
- **Concurrent Connections**: 500 simultaneous users
- **Error Rate**: < 0.1%

### Monitoring Metrics
- **Health Check Interval**: 15 seconds
- **Metrics Retention**: 15 days
- **Alert Response Time**: < 30 seconds
- **Dashboard Refresh**: 5 seconds

## 🔒 Security Considerations

### Network Security
- **Firewall Rules**: Restrict access to necessary ports only
- **Internal Communication**: Secure communication between components
- **SSL/TLS**: HTTPS termination at load balancer

### Access Control
- **Grafana Authentication**: Username/password protection
- **Prometheus Security**: Internal network access only
- **Nginx Security**: Rate limiting dan DDoS protection

### Data Protection
- **Metrics Data**: Encrypted storage volumes
- **Log Security**: Secure log rotation dan retention
- **Backup Encryption**: Encrypted backup files

## 📈 Scalability Design

### Horizontal Scaling
- **Add Fremisn Servers**: Easy addition of new backend servers
- **Load Balancer Scaling**: Multiple Nginx instances dengan keepalived
- **Monitoring Scaling**: Prometheus federation untuk large deployments

### Vertical Scaling
- **Resource Allocation**: Configurable CPU dan memory limits
- **Storage Expansion**: Expandable persistent volumes
- **Performance Tuning**: Optimizable configuration parameters

## 🔧 Configuration Management

### Environment Variables
```bash
# Server Configuration
FREMISN_MASTER_HOST=192.168.100.231
FREMISN_MASTER_PORT=4005
FREMISN_SLAVE1_HOST=192.168.100.18
FREMISN_SLAVE1_PORT=4008
FREMISN_SLAVE2_HOST=192.168.100.17
FREMISN_SLAVE2_PORT=4009

# Load Balancer Configuration
LB_PORT=8081
LB_STATUS_PORT=8080
LB_ALGORITHM=round_robin

# Monitoring Configuration
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
BLACKBOX_PORT=9115
```

### Docker Compose Services
```yaml
services:
  nginx-lb:        # Load balancer service
  prometheus:      # Metrics collection
  grafana:         # Visualization
  blackbox:        # Health checking
```

## 🚨 Failure Scenarios dan Recovery

### Single Server Failure
- **Detection**: Blackbox Exporter detects failed health check
- **Action**: Nginx automatically removes server dari pool
- **Recovery**: Automatic re-addition setelah server kembali healthy
- **Impact**: Minimal - traffic redirected ke healthy servers

### Load Balancer Failure
- **Detection**: External monitoring atau manual detection
- **Action**: Failover ke backup load balancer (jika configured)
- **Recovery**: Restart load balancer service
- **Impact**: Brief service interruption

### Monitoring Stack Failure
- **Detection**: Dashboard unavailable atau alerts stop
- **Action**: Restart monitoring services
- **Recovery**: Data recovery dari persistent volumes
- **Impact**: Loss of visibility, tidak affect application traffic

## 📋 Performance Optimization & Error Handling

### Performance Enhancements
- **Enhanced Rate Limiting**: 
  - Primary zone: 50 requests/second
  - Burst zone: 100 requests/second
  - Nodelay processing untuk high traffic
- **Connection Optimization**:
  - Keepalive connections: 64 concurrent
  - Keepalive requests: 1000 per connection
  - Keepalive timeout: 60 seconds
- **Proxy Buffering**:
  - Buffer size: 8k
  - Buffer count: 16 buffers
  - Busy buffers: 16k
  - Temp file write: 64k
- **Compression**: Gzip dengan level 6 untuk multiple content types
- **Timeouts Optimization**:
  - Connect timeout: 10s
  - Send timeout: 120s
  - Read timeout: 120s

### Custom Error Handling
- **502.html**: Bad Gateway error page
  - Modern responsive design dengan gradient background
  - Detailed error information dan troubleshooting steps
  - CSS3 styling dengan shadow effects
- **50x.html**: Service Temporarily Unavailable
  - Professional error page dengan informative content
  - Responsive design untuk mobile dan desktop
  - User-friendly error messaging

### Performance Testing Suite
- **final-stress-test.sh**: Comprehensive load balancer testing
  - 50 concurrent connections
  - 500 requests per connection
  - 30-second duration test
- **simple-stress-test.sh**: Basic load testing
  - 20 concurrent connections
  - 1000 total requests
- **stress-test.sh**: Face enrollment endpoint testing
  - 10 concurrent users
  - 100 requests per user
  - JSON payload testing

## 📋 Maintenance Procedures

### Regular Maintenance
- **Weekly**: Log rotation dan cleanup
- **Monthly**: Performance review dan optimization
- **Quarterly**: Security updates dan patches
- **Annually**: Architecture review dan capacity planning

### Emergency Procedures
- **Incident Response**: Defined escalation procedures
- **Rollback Plans**: Quick rollback untuk configuration changes
- **Communication**: Status page updates dan stakeholder notification
- **Post-Incident**: Root cause analysis dan improvement plans

## 🔍 Monitoring dan Alerting

### Critical Alerts
- Server down (immediate)
- High response time (> 500ms)
- High error rate (> 1%)
- Resource exhaustion (CPU > 80%, Memory > 90%)

### Warning Alerts
- Moderate response time (> 200ms)
- Moderate error rate (> 0.5%)
- Resource usage (CPU > 60%, Memory > 70%)
- Disk space low (< 20%)

### Information Alerts
- Deployment notifications
- Scheduled maintenance
- Performance reports
- Capacity planning alerts

Dokumen ini memberikan pemahaman komprehensif tentang arsitektur sistem High Availability Fremisn Services dan dapat digunakan sebagai referensi untuk deployment, maintenance, dan troubleshooting.