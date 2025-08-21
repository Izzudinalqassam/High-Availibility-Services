# 🚀 High Availability Fremisn Services

> Solusi load balancing dan monitoring yang powerful untuk aplikasi Fremisn dengan dashboard real-time yang cantik!

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)
[![Nginx](https://img.shields.io/badge/Nginx-Load%20Balancer-green.svg)](https://nginx.org/)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-orange.svg)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-Dashboard-red.svg)](https://grafana.com/)

## 📖 Deskripsi Lengkap Proyek

**High Availability Fremisn Services** adalah sistem load balancing dan monitoring yang dirancang khusus untuk aplikasi Fremisn. Proyek ini menyediakan infrastruktur yang robust untuk mendistribusikan traffic ke multiple server Fremisn (Master & Slave) sambil memantau kesehatan dan performa sistem secara real-time.

### 🎯 Tujuan Utama

- **High Availability**: Memastikan aplikasi Fremisn selalu tersedia dengan failover otomatis
- **Load Distribution**: Mendistribusikan beban kerja secara merata antara server Master dan Slave
- **Real-time Monitoring**: Monitoring kesehatan server, response time, dan metrics performa
- **Visual Dashboard**: Interface yang user-friendly untuk monitoring sistem
- **Alerting**: Deteksi dini masalah dengan sistem monitoring yang comprehensive
- **Scalability**: Mudah untuk menambah server baru ke dalam pool

### 🏗️ Arsitektur Sistem

```
                    ┌──────────────────┐
                    │   Load Balancer  │
                    │   (Nginx)        │
                    │   Port: 8081     │
                    └─────────┬────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │ Fremisn Master  │ │ Fremisn Slave 1 │ │ Fremisn Slave 2 │
    │ 192.168.100.231 │ │ 192.168.100.18  │ │ 192.168.100.17  │
    │ Port: 4005      │ │ Port: 4008      │ │ Port: 4009      │
    └─────────────────┘ └─────────────────┘ └─────────────────┘

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Prometheus    │────│  Blackbox        │    │   Grafana       │
│   Port: 9090    │    │  Exporter        │    │   Port: 3000    │
│                 │    │  Port: 9115      │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### 🔧 Komponen Utama

1. **Nginx Load Balancer**: Mendistribusikan traffic dengan algoritma round-robin
2. **Prometheus**: Mengumpulkan dan menyimpan metrics dari semua komponen
3. **Grafana**: Menyediakan dashboard visual untuk monitoring
4. **Blackbox Exporter**: Melakukan health checks ke server Fremisn
5. **Docker Compose**: Orchestrasi semua layanan dalam container

## ⚙️ Daftar Konfigurasi yang Perlu Diubah

### 1. Konfigurasi Server Fremisn

**File**: `fremisn-loadbalancer/nginx/nginx.conf`

```nginx
# Upstream configuration untuk server Fremisn
upstream fremisn_backend {
    # Ganti IP dan port sesuai dengan server Anda
    server 192.168.100.231:4005 max_conns=1;  # Fremisn Master
    server 192.168.100.18:4008 max_conns=1;   # Fremisn Slave 1
    server 192.168.100.17:4009 max_conns=1;   # Fremisn Slave 2
    
    keepalive 32;
}
```

### Fremisn Servers
- **Master Server**: 192.168.100.231:4005
- **Slave Server 1**: 192.168.100.18:4008
- **Slave Server 2**: 192.168.100.17:4009

### Environment Variables
```
# Fremisn Server Configuration
FREMISN_MASTER_HOST=192.168.100.231
FREMISN_MASTER_PORT=4005
FREMISN_SLAVE1_HOST=192.168.100.18
FREMISN_SLAVE1_PORT=4008
FREMISN_SLAVE2_HOST=192.168.100.17
FREMISN_SLAVE2_PORT=4009
```

**Penjelasan**:
- `192.168.100.231:4005`: IP dan port server Fremisn Master
- `192.168.100.18:4008`: IP dan port server Fremisn Slave 1
- `192.168.100.17:4009`: IP dan port server Fremisn Slave 2
- `max_conns=1`: Maksimal 1 koneksi concurrent per server
- Load balancing menggunakan algoritma **round-robin** untuk mendistribusikan traffic secara merata ke ketiga server
- Tambahkan server baru dengan format yang sama

### 2. Konfigurasi Monitoring Targets

**File**: `fremisn-loadbalancer/prometheus/prometheus.yml`

```yaml
# Blackbox exporter untuk HTTP health checks
- job_name: 'blackbox'
  static_configs:
    - targets:
      - http://192.168.100.231:4005   # Fremisn Master
      - http://192.168.100.18:4008    # Fremisn Slave 1
      - http://192.168.100.17:4009    # Fremisn Slave 2
```

**Penjelasan**:
- Ganti URL sesuai dengan endpoint server Fremisn Anda
- Tambahkan target baru untuk server tambahan
- Sesuaikan `scrape_interval` jika diperlukan (default: 15s)

### 3. Konfigurasi Port Mapping

**File**: `fremisn-loadbalancer/docker-compose.yml`

```yaml
services:
  nginx-lb:
    ports:
      - "8081:80"    # Load Balancer port
      - "8080:8080"  # Nginx status port
  
  grafana:
    ports:
      - "3000:3000"  # Grafana dashboard port
  
  prometheus:
    ports:
      - "9090:9090"  # Prometheus web UI port
```

**Penjelasan**:
- Ubah port eksternal jika terjadi konflik dengan layanan lain
- Port internal (setelah `:`) sebaiknya tidak diubah

### 4. Konfigurasi Kredensial Grafana

**File**: `fremisn-loadbalancer/docker-compose.yml`

```yaml
grafana:
  environment:
    - GF_SECURITY_ADMIN_USER=admin        # Username admin
    - GF_SECURITY_ADMIN_PASSWORD=admin123 # Password admin
```

**Penjelasan**:
- Ganti username dan password default untuk keamanan
- Gunakan password yang kuat untuk environment production

### 5. Konfigurasi Rate Limiting

**File**: `fremisn-loadbalancer/nginx/nginx.conf`

```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
```

**Penjelasan**:
- `rate=10r/s`: Maksimal 10 request per detik per IP
- `zone=api:10m`: Alokasi 10MB memory untuk rate limiting
- Sesuaikan dengan kebutuhan traffic Anda

## 🚀 Petunjuk Instalasi dan Deployment

### Prerequisites

- **Docker Engine**: Version 20.10 atau lebih baru
- **Docker Compose**: Version 2.0 atau lebih baru
- **Server Requirements**: Minimal 2GB RAM, 10GB disk space
- **Network Access**: Akses ke server Fremisn yang akan di-load balance
- **Ports Available**: 3000, 8080, 8081, 9090, 9115

### Langkah-langkah Instalasi

#### 1. Persiapan Environment

```bash
# Clone atau copy project ke server
git clone https://github.com/Izzudinalqassam/High-Availibility-Services.git
cd High-Availibility-Services/fremisn-loadbalancer

# Atau jika menggunakan existing folder
cd /path/to/fremisn-loadbalancer
```

#### 2. Konfigurasi Server

```bash
# Backup konfigurasi original
cp nginx/nginx.conf nginx/nginx.conf.backup
cp prometheus/prometheus.yml prometheus/prometheus.yml.backup

# Edit konfigurasi sesuai environment Anda
nano nginx/nginx.conf
nano prometheus/prometheus.yml
```

#### 3. Verifikasi Konfigurasi

```bash
# Test konfigurasi Nginx
docker run --rm -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf nginx nginx -t

# Verifikasi format YAML Prometheus
docker run --rm -v $(pwd)/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus promtool check config /etc/prometheus/prometheus.yml
```

#### 4. Deploy Services

```bash
# Pull semua images yang diperlukan
docker-compose pull

# Start semua layanan
docker-compose up -d

# Verifikasi semua container berjalan
docker-compose ps
```

#### 5. Verifikasi Deployment

```bash
# Jalankan script test
chmod +x test-loadbalancer.sh
./test-loadbalancer.sh

# Test manual
curl http://localhost:8081/health
curl http://localhost:8080/nginx_status
```

#### 6. Setup Monitoring Dashboard

```bash
# Akses Grafana
echo "Grafana Dashboard: http://localhost:3000"
echo "Username: admin"
echo "Password: admin123"

# Import dashboard (jika belum otomatis)
# Dashboard akan tersedia di: http://localhost:3000/d/fremisn-monitoring
```

### Deployment untuk Production

#### 1. Security Hardening

```bash
# Ganti password default Grafana
export GF_SECURITY_ADMIN_PASSWORD="your-secure-password"

# Setup SSL/TLS (opsional)
# Tambahkan sertifikat SSL ke nginx/ssl/
# Update nginx.conf untuk menggunakan HTTPS
```

#### 2. Persistent Storage

```bash
# Buat direktori untuk persistent data
sudo mkdir -p /opt/fremisn-data/{prometheus,grafana}
sudo chown -R 472:472 /opt/fremisn-data/grafana  # Grafana user ID
sudo chown -R 65534:65534 /opt/fremisn-data/prometheus  # Nobody user ID

# Update docker-compose.yml untuk menggunakan bind mounts
# volumes:
#   - /opt/fremisn-data/grafana:/var/lib/grafana
#   - /opt/fremisn-data/prometheus:/prometheus
```

#### 3. Backup Strategy

```bash
# Script backup otomatis
cat > backup-fremisn.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/fremisn-$DATE"

mkdir -p $BACKUP_DIR
docker-compose exec -T prometheus tar czf - /prometheus > $BACKUP_DIR/prometheus-data.tar.gz
docker-compose exec -T grafana tar czf - /var/lib/grafana > $BACKUP_DIR/grafana-data.tar.gz
cp -r nginx prometheus blackbox grafana $BACKUP_DIR/
EOF

chmod +x backup-fremisn.sh
```

## 💻 Persyaratan Sistem

### Minimum Requirements

| Komponen | Spesifikasi |
|----------|-------------|
| **CPU** | 2 cores |
| **RAM** | 2GB |
| **Storage** | 10GB free space |
| **Network** | 100Mbps |
| **OS** | Linux (Ubuntu 20.04+, CentOS 8+, RHEL 8+) |

### Recommended Requirements

| Komponen | Spesifikasi |
|----------|-------------|
| **CPU** | 4 cores |
| **RAM** | 4GB |
| **Storage** | 50GB SSD |
| **Network** | 1Gbps |
| **OS** | Linux dengan Docker support |

### Software Dependencies

| Software | Version | Purpose |
|----------|---------|----------|
| **Docker Engine** | 20.10+ | Container runtime |
| **Docker Compose** | 2.0+ | Service orchestration |
| **curl** | Any | Testing dan health checks |
| **bash** | 4.0+ | Script execution |

### Network Requirements

- **Inbound Ports**:
  - `3000`: Grafana Dashboard
  - `8080`: Nginx Status
  - `8081`: Load Balancer
  - `9090`: Prometheus Web UI
  - `9115`: Blackbox Exporter (internal)

- **Outbound Access**:
  - Access ke server Fremisn (Master & Slave)
  - Docker Hub untuk pulling images
  - Internet untuk updates (opsional)

### Browser Compatibility

| Browser | Version |
|---------|----------|
| **Chrome** | 90+ |
| **Firefox** | 88+ |
| **Safari** | 14+ |
| **Edge** | 90+ |

## 📚 Dokumentasi

Untuk informasi lebih detail tentang arsitektur sistem:

- **[Architecture Documentation](docs/ARCHITECTURE.md)** - Penjelasan detail komponen dan alur data
- **[Architecture Topology Diagram](docs/architecture-topology.svg)** - Diagram visual arsitektur sistem
- **[Service Topology Manual](docs/service-topology-manual.md)** - Dokumentasi topologi layanan manual
- **[Topology Diagram](docs/topology-diagram.txt)** - Diagram topologi ASCII

### 🔍 Topologi Service

Sistem ini terdiri dari beberapa layer utama:

1. **Load Balancer Layer** - Nginx dengan round-robin load balancing
2. **Application Layer** - 3 Fremisn services (1 master + 2 slaves)
3. **Monitoring Layer** - Prometheus, Grafana, dan Exporters
4. **Network Layer** - Docker network dengan external bridge

Lihat dokumentasi topologi untuk detail lengkap tentang alur data, konfigurasi jaringan, dan interaksi antar komponen.

## 📁 Struktur Direktori Proyek

```
High-Availibility-Services/
├── README.md                           # Dokumentasi utama proyek
├── LICENSE                             # Lisensi MIT
├── .gitignore                          # Git ignore rules
└── fremisn-loadbalancer/               # Main application directory
    ├── docker-compose.yml              # Orchestrasi semua layanan
    ├── .env.example                    # Environment variables template
    ├── nginx/                          # Nginx load balancer configuration
    │   ├── nginx.conf                  # Main nginx configuration
    │   ├── conf.d/                     # Additional nginx configs
    │   │   ├── default.conf            # Default server block
    │   │   └── ssl.conf                # SSL configuration (optional)
    │   └── ssl/                        # SSL certificates directory
    │       ├── cert.pem                # SSL certificate
    │       └── key.pem                 # SSL private key
    ├── prometheus/                     # Prometheus monitoring configuration
    │   ├── prometheus.yml              # Main prometheus config
    │   ├── rules/                      # Alerting rules
    │   │   ├── fremisn.yml             # Fremisn-specific alerts
    │   │   └── infrastructure.yml      # Infrastructure alerts
    │   └── data/                       # Prometheus data directory (auto-created)
    ├── blackbox/                       # Blackbox exporter configuration
    │   └── blackbox.yml                # Health check modules
    ├── grafana/                        # Grafana dashboard configuration
    │   ├── dashboards/                 # Dashboard definitions
    │   │   ├── fremisn-monitoring.json # Main monitoring dashboard
    │   │   ├── nginx-stats.json        # Nginx statistics dashboard
    │   │   └── infrastructure.json     # Infrastructure overview
    │   ├── provisioning/               # Auto-provisioning configs
    │   │   ├── dashboards/             # Dashboard provisioning
    │   │   │   └── dashboard.yml       # Dashboard provider config
    │   │   └── datasources/            # Datasource provisioning
    │   │       └── prometheus.yml      # Prometheus datasource config
    │   └── data/                       # Grafana data directory (auto-created)
    ├── scripts/                        # Utility scripts
    │   ├── test-loadbalancer.sh        # Load balancer testing script
    │   ├── test-request-logging.sh     # Request logging test script
    │   ├── backup.sh                   # Backup script
    │   ├── restore.sh                  # Restore script
    │   └── health-check.sh             # Health check script
    ├── logs/                           # Log files directory (auto-created)
    │   ├── nginx/                      # Nginx logs
    │   ├── prometheus/                 # Prometheus logs
    │   └── grafana/                    # Grafana logs
    └── docs/                           # Additional documentation
        ├── ARCHITECTURE.md             # System architecture documentation
        ├── architecture-topology.svg   # Architecture topology diagram
        ├── DEPLOYMENT.md               # Deployment guide
        ├── CONFIGURATION.md            # Configuration reference
        ├── TROUBLESHOOTING.md          # Troubleshooting guide
        └── API.md                      # API documentation
```

### Penjelasan Direktori

#### `/nginx/`
- **nginx.conf**: Konfigurasi utama load balancer dengan upstream servers
- **conf.d/**: Konfigurasi tambahan untuk virtual hosts atau SSL
- **ssl/**: Sertifikat SSL untuk HTTPS (opsional)

#### `/prometheus/`
- **prometheus.yml**: Konfigurasi scraping targets dan rules
- **rules/**: Alerting rules untuk monitoring proaktif
- **data/**: Persistent storage untuk metrics data

#### `/blackbox/`
- **blackbox.yml**: Konfigurasi health check modules

#### `/grafana/`
- **dashboards/**: JSON definitions untuk dashboard
- **provisioning/**: Auto-setup untuk datasources dan dashboards
- **data/**: Persistent storage untuk Grafana settings

#### `/scripts/`
- **test-*.sh**: Scripts untuk testing dan validasi
- **backup.sh**: Script backup otomatis
- **health-check.sh**: Script monitoring kesehatan sistem

## 🎮 Cara Penggunaan

### Akses Dashboard & Services

| Service | URL | Kredensial | Deskripsi |
|---------|-----|------------|----------|
| **Load Balancer** | http://localhost:8081 | - | Endpoint utama untuk aplikasi Fremisn |
| **Grafana Dashboard** | http://localhost:3000 | admin/admin123 | Monitoring dashboard |
| **Prometheus** | http://localhost:9090 | - | Metrics collection dan query |
| **Nginx Status** | http://localhost:8080/nginx_status | - | Nginx statistics |
| **Blackbox Exporter** | http://localhost:9115 | - | Health check metrics |

### Monitoring Server Health

#### 1. Grafana Dashboard

```bash
# Akses Grafana Dashboard
open http://localhost:3000
# Login: admin/admin123
```

**Panel Monitoring Utama**:
- **Fremisn Master Status**: Real-time UP/DOWN status
- **Fremisn Slave Status**: Real-time UP/DOWN status
- **Response Time**: Latency metrics untuk kedua server
- **Request Rate**: Throughput requests per second
- **HTTP Status Codes**: Distribusi response codes
- **Load Balancer Stats**: Nginx connection dan request metrics

#### 2. Prometheus Queries

```bash
# Akses Prometheus Web UI
open http://localhost:9090

# Contoh queries berguna:
# - Server uptime: up{job="blackbox"}
# - Response time: probe_duration_seconds
# - HTTP status: probe_http_status_code
# - Request rate: rate(nginx_http_requests_total[5m])
```

### Testing Load Balancer

#### 1. Basic Health Check

```bash
# Test koneksi ke load balancer
curl -v http://localhost:8081/health

# Expected response: "healthy"
# Status code: 200
```

#### 2. Load Testing

```bash
# Test dengan multiple requests
./scripts/test-loadbalancer.sh

# Test dengan load tinggi (gunakan ab atau wrk)
ab -n 1000 -c 10 http://localhost:8081/

# Atau menggunakan wrk
wrk -t12 -c400 -d30s http://localhost:8081/
```

#### 3. Request Logging

```bash
# Monitor requests real-time
./scripts/test-request-logging.sh

# Lihat log requests
tail -f logs/nginx/access.log

# Analisis log dengan awk
awk '{print $7}' logs/nginx/access.log | sort | uniq -c | sort -nr
```

### Operasional Harian

#### 1. Monitoring Checklist

```bash
# Daily health check
./scripts/health-check.sh

# Check container status
docker-compose ps

# Check resource usage
docker stats

# Check disk usage
df -h
du -sh logs/
```

#### 2. Log Management

```bash
# Rotate logs (weekly)
find logs/ -name "*.log" -mtime +7 -exec gzip {} \;

# Clean old compressed logs (monthly)
find logs/ -name "*.gz" -mtime +30 -delete

# Monitor log sizes
du -sh logs/*
```

#### 3. Backup Operations

```bash
# Manual backup
./scripts/backup.sh

# Automated backup (add to crontab)
# 0 2 * * * /path/to/fremisn-loadbalancer/scripts/backup.sh

# Restore from backup
./scripts/restore.sh /path/to/backup/fremisn-20240101_020000
```

### Advanced Usage

#### 1. Custom Alerts

```yaml
# Tambahkan ke prometheus/rules/fremisn.yml
groups:
  - name: fremisn.rules
    rules:
      - alert: FremisNServerDown
        expr: up{job="blackbox"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Fremisn server {{ $labels.instance }} is down"
```

#### 2. Custom Dashboard

```bash
# Export existing dashboard
curl -s "http://admin:admin123@localhost:3000/api/dashboards/db/fremisn-monitoring" | jq '.dashboard' > custom-dashboard.json

# Import custom dashboard
curl -X POST \
  http://admin:admin123@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @custom-dashboard.json
```

#### 3. Scaling Servers

```bash
# Tambah server baru ke nginx.conf
# upstream fremisn_backend {
#     server 192.168.100.231:4005 max_conns=1;
#     server 192.168.100.18:4008 max_conns=1;
#     server 192.168.100.50:4009 max_conns=1;  # Server baru
# }

# Reload nginx tanpa downtime
docker-compose exec nginx-lb nginx -s reload

# Update prometheus targets
# Edit prometheus/prometheus.yml dan restart prometheus
docker-compose restart prometheus
```

## 🔧 Troubleshooting Common Issues

### 1. Container Issues

#### Problem: Container tidak bisa start

```bash
# Check logs
docker-compose logs [service-name]

# Check port conflicts
netstat -tulpn | grep -E ':(3000|8080|8081|9090|9115)'

# Check disk space
df -h
docker system df

# Solution: Clean up docker
docker system prune -f
docker volume prune -f
```

#### Problem: Out of memory

```bash
# Check memory usage
free -h
docker stats

# Solution: Increase memory limits
# Edit docker-compose.yml:
# services:
#   prometheus:
#     mem_limit: 1g
#   grafana:
#     mem_limit: 512m
```

### 2. Network Issues

#### Problem: Cannot reach Fremisn servers

```bash
# Test connectivity from container
docker-compose exec nginx-lb ping 192.168.100.231
docker-compose exec nginx-lb telnet 192.168.100.231 4005

# Check nginx upstream status
curl http://localhost:8080/nginx_status

# Solution: Check firewall and network routing
sudo iptables -L
sudo ufw status
route -n
```

#### Problem: Load balancer returns 502/503

```bash
# Check nginx error logs
docker-compose logs nginx-lb

# Test backend servers directly
curl -v http://192.168.100.231:4005/health
curl -v http://192.168.100.18:4008/health

# Check nginx configuration
docker-compose exec nginx-lb nginx -t

# Solution: Fix upstream configuration or server issues
```

### 3. Monitoring Issues

#### Problem: Grafana dashboard tidak menampilkan data

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check Grafana datasource
curl -u admin:admin123 http://localhost:3000/api/datasources

# Test Prometheus query
curl 'http://localhost:9090/api/v1/query?query=up'

# Solution: Restart services dan check configuration
docker-compose restart prometheus grafana
```

#### Problem: Blackbox exporter tidak bisa probe

```bash
# Check blackbox logs
docker-compose logs blackbox-exporter

# Test probe manually
curl 'http://localhost:9115/probe?target=http://192.168.100.231:4005&module=http_2xx'

# Solution: Check blackbox configuration dan network access
```

### 4. Performance Issues

#### Problem: High response time

```bash
# Check server resources
top
iotop
netstat -i

# Check nginx performance
curl http://localhost:8080/nginx_status

# Check backend server performance
time curl http://192.168.100.231:4005/health
time curl http://192.168.100.18:4008/health

# Solution: Optimize configuration atau scale servers
```

#### Problem: High memory usage

```bash
# Check Prometheus retention
# Edit prometheus/prometheus.yml:
# global:
#   storage.tsdb.retention.time: 7d  # Reduce from default 15d

# Check Grafana cache
# Restart Grafana periodically
docker-compose restart grafana
```

### 5. SSL/TLS Issues (jika menggunakan HTTPS)

#### Problem: SSL certificate errors

```bash
# Check certificate validity
openssl x509 -in nginx/ssl/cert.pem -text -noout

# Test SSL connection
openssl s_client -connect localhost:443 -servername yourdomain.com

# Check nginx SSL configuration
docker-compose exec nginx-lb nginx -t

# Solution: Renew certificates atau fix configuration
```

### 6. Data Persistence Issues

#### Problem: Data hilang setelah restart

```bash
# Check volume mounts
docker-compose config
docker volume ls

# Check permissions
ls -la /opt/fremisn-data/

# Solution: Fix volume configuration dan permissions
sudo chown -R 472:472 /opt/fremisn-data/grafana
sudo chown -R 65534:65534 /opt/fremisn-data/prometheus
```

### 7. Emergency Procedures

#### Complete System Reset

```bash
# Stop all services
docker-compose down

# Remove all containers dan volumes
docker-compose down -v
docker system prune -a -f

# Restore from backup
./scripts/restore.sh /path/to/latest/backup

# Start services
docker-compose up -d
```

#### Rollback Configuration

```bash
# Restore configuration from backup
cp nginx/nginx.conf.backup nginx/nginx.conf
cp prometheus/prometheus.yml.backup prometheus/prometheus.yml

# Reload services
docker-compose restart nginx-lb prometheus
```

### 8. Debugging Tools

```bash
# Network debugging
docker-compose exec nginx-lb netstat -tulpn
docker-compose exec nginx-lb ss -tulpn

# Process debugging
docker-compose exec nginx-lb ps aux
docker-compose exec prometheus ps aux

# File system debugging
docker-compose exec nginx-lb ls -la /etc/nginx/
docker-compose exec prometheus ls -la /etc/prometheus/

# Real-time monitoring
watch -n 1 'docker-compose ps'
watch -n 1 'curl -s http://localhost:8081/health'
```

## 🤝 Kontribusi Guidelines

Kami welcome kontribusi untuk meningkatkan sistem ini! Berikut cara berkontribusi:

### Cara Berkontribusi

1. **Fork repository** ini
2. **Buat branch** untuk fitur baru: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push ke branch**: `git push origin feature/amazing-feature`
5. **Buat Pull Request**

### Development Guidelines

#### Code Style

- **Shell Scripts**: Gunakan `shellcheck` untuk validasi
- **YAML Files**: Gunakan 2 spaces untuk indentation
- **Documentation**: Gunakan Markdown dengan format yang konsisten
- **Commit Messages**: Gunakan conventional commits format

```bash
# Contoh commit messages
feat: add SSL support for nginx load balancer
fix: resolve prometheus scraping timeout issue
docs: update installation guide with troubleshooting
refactor: optimize nginx configuration for better performance
```

#### Testing Requirements

```bash
# Pastikan semua test script berjalan
./scripts/test-loadbalancer.sh
./scripts/health-check.sh

# Test konfigurasi
docker run --rm -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf nginx nginx -t
docker run --rm -v $(pwd)/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus promtool check config /etc/prometheus/prometheus.yml

# Test deployment
docker-compose config
docker-compose up -d
docker-compose ps
```

#### Documentation Requirements

- Update README.md jika menambah fitur baru
- Tambahkan komentar untuk konfigurasi kompleks
- Sertakan contoh penggunaan untuk fitur baru
- Update troubleshooting guide jika diperlukan

### Areas yang Bisa Dikembangkan

#### 🚨 High Priority
- **Alerting system** dengan Slack/Email notifications
- **SSL/TLS support** untuk production deployment
- **Authentication** untuk Grafana dan Prometheus
- **Backup automation** dengan retention policy

#### 📈 Medium Priority
- **Advanced metrics** dan custom dashboards
- **Log aggregation** dengan ELK stack
- **Auto-scaling** berdasarkan load metrics
- **Health check improvements** dengan custom endpoints

#### 🔄 Low Priority
- **Kubernetes deployment** manifests
- **Mobile-responsive** dashboard
- **API documentation** dengan Swagger
- **Performance benchmarking** tools

### Pull Request Process

1. **Pastikan branch up-to-date** dengan main
2. **Run semua tests** dan pastikan pass
3. **Update documentation** sesuai perubahan
4. **Tambahkan changelog entry** jika diperlukan
5. **Request review** dari maintainers

### Issue Reporting

#### Bug Reports

```markdown
**Bug Description**
Deskripsi singkat tentang bug

**Steps to Reproduce**
1. Step 1
2. Step 2
3. Step 3

**Expected Behavior**
Apa yang seharusnya terjadi

**Actual Behavior**
Apa yang benar-benar terjadi

**Environment**
- OS: Ubuntu 20.04
- Docker: 20.10.8
- Docker Compose: 2.0.1

**Logs**
```
Paste relevant logs here
```
```

#### Feature Requests

```markdown
**Feature Description**
Deskripsi fitur yang diinginkan

**Use Case**
Kenapa fitur ini diperlukan

**Proposed Solution**
Solusi yang diusulkan (opsional)

**Alternatives**
Alternatif lain yang sudah dipertimbangkan
```

### Code Review Checklist

- [ ] Code mengikuti style guidelines
- [ ] Tests pass dan coverage adequate
- [ ] Documentation updated
- [ ] No breaking changes (atau sudah didokumentasikan)
- [ ] Security considerations addressed
- [ ] Performance impact evaluated

## 📄 Lisensi

Proyek ini dilisensikan di bawah **MIT License** - lihat file [LICENSE](LICENSE) untuk detail lengkap.

```
MIT License

Copyright (c) 2024 High Availability Fremisn Services

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Third-Party Licenses

Proyek ini menggunakan komponen open source berikut:

- **Nginx**: BSD-2-Clause License
- **Prometheus**: Apache License 2.0
- **Grafana**: AGPL-3.0 License
- **Docker**: Apache License 2.0

## 📞 Support & Contact

Jika Anda mengalami masalah atau memiliki pertanyaan:

- 📧 **Email**: izzudin.alqa@gmail.com
- 🐛 **Bug Reports**: [Create an issue](https://github.com/Izzudinalqassam/High-Availibility-Services/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Izzudinalqassam/High-Availibility-Services/discussions)
- 📖 **Documentation**: [Wiki](https://github.com/Izzudinalqassam/High-Availibility-Services/wiki)

### Community

- **Slack**: [Join our Slack workspace](https://join.slack.com/t/fremisn-community/shared_invite/xxx)
- **Discord**: [Join our Discord server](https://discord.gg/xxx)
- **Telegram**: [Join our Telegram group](https://t.me/fremisn_community)

### Professional Support

Untuk enterprise support dan consulting:

- **Enterprise Support**: enterprise@fremisn.com
- **Consulting Services**: consulting@fremisn.com
- **Training**: training@fremisn.com

---

<div align="center">
  <strong>Made with ❤️ for the Fremisn Community</strong>
  <br>
  <em>Happy Load Balancing! 🚀</em>
  <br><br>
  <a href="#-high-availability-fremisn-services">⬆️ Back to Top</a>
</div>