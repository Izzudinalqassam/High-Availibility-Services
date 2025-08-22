# Topologi Service High Availability Fremisn Services

## Gambaran Umum Arsitektur

Sistem High Availability Fremisn Services terdiri dari beberapa komponen utama yang bekerja sama untuk menyediakan layanan yang handal dan dapat dipantau.

## Komponen Utama

### 1. Load Balancer Layer
```
┌─────────────────────────────────────────────────────────────┐
│                    NGINX Load Balancer                     │
│                  (fremisn-loadbalancer)                    │
│                     Port: 8081                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Upstream Backend                       │   │
│  │           (fremisn_backend)                         │   │
│  │                                                     │   │
│  │  Round Robin Load Balancing:                       │   │
│  │  • 192.168.100.231:4005 (Fremisn Master)          │   │
│  │  • 192.168.100.18:4008  (Fremisn Slave 1)         │   │
│  │  • 192.168.100.17:4009  (Fremisn Slave 2)         │   │
│  │                                                     │   │
│  │  Max Connections: 1 per server                     │   │
│  │  Rate Limiting: 10 req/s with burst 20             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2. Application Layer
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│   Fremisn Master    │  │   Fremisn Slave 1   │  │   Fremisn Slave 2   │
│                     │  │                     │  │                     │
│ 192.168.100.231     │  │ 192.168.100.18      │  │ 192.168.100.17      │
│     Port: 4005      │  │     Port: 4008      │  │     Port: 4009      │
│                     │  │                     │  │                     │
│ [External Service]  │  │ [External Service]  │  │ [External Service]  │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

### 3. Monitoring Layer
```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Monitoring Stack                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   Prometheus    │  │     Grafana     │  │ Nginx Exporter  │         │
│  │                 │  │                 │  │                 │         │
│  │   Port: 9090    │  │   Port: 3000    │  │   Port: 9113    │         │
│  │                 │  │                 │  │                 │         │
│  │ Metrics Storage │  │   Dashboard     │  │ Nginx Metrics   │         │
│  │ & Alerting      │  │   Visualization │  │   Collection    │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                  Blackbox Exporter                             │   │
│  │                    Port: 9115                                  │   │
│  │                                                                 │   │
│  │  Health Check Targets:                                         │   │
│  │  • http://192.168.100.231:4005 (Fremisn Master)               │   │
│  │  • http://192.168.100.18:4008  (Fremisn Slave 1)              │   │
│  │  • http://192.168.100.17:4009  (Fremisn Slave 2)              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Alur Data dan Komunikasi

### 1. Request Flow
```
Client Request
     ↓
┌─────────────────┐
│ Nginx LB        │ ← Rate Limiting (10 req/s)
│ Port: 8081      │
└─────────────────┘
     ↓
┌─────────────────┐
│ Round Robin     │ ← Load Balancing Algorithm
│ Distribution    │
└─────────────────┘
     ↓
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Fremisn Master  │   │ Fremisn Slave 1 │   │ Fremisn Slave 2 │
│ :4005           │   │ :4008           │   │ :4009           │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

### 2. Monitoring Flow
```
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Fremisn Services│   │ Nginx LB        │   │ System Metrics  │
│                 │   │                 │   │                 │
└─────────────────┘   └─────────────────┘   └─────────────────┘
         │                       │                       │
         │ Health Checks         │ Nginx Metrics         │
         ↓                       ↓                       ↓
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Blackbox        │   │ Nginx Exporter  │   │ Prometheus      │
│ Exporter        │   │                 │   │                 │
│ :9115           │   │ :9113           │   │ :9090           │
└─────────────────┘   └─────────────────┘   └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ↓
                    ┌─────────────────┐
                    │ Grafana         │
                    │ Dashboard       │
                    │ :3000           │
                    └─────────────────┘
```

## Konfigurasi Jaringan

### Docker Network
- **Network Name**: `nf-visionaire` (external)
- **Type**: Bridge network
- **Containers**: Semua service berjalan dalam network yang sama

### Port Mapping
| Service | Internal Port | External Port | Deskripsi |
|---------|---------------|---------------|-----------|
| Nginx LB | 80 | 8081 | Load Balancer HTTP |
| Nginx Status | 8080 | 8080 | Nginx Status Page |
| Prometheus | 9090 | 9090 | Metrics Collection |
| Grafana | 3000 | 3000 | Monitoring Dashboard |
| Nginx Exporter | 9113 | 9113 | Nginx Metrics |
| Blackbox Exporter | 9115 | 9115 | Health Checks |

## Fitur High Availability

### 1. Load Balancing
- **Algorithm**: Round Robin
- **Max Connections**: 1 per backend server
- **Keep Alive**: 32 connections
- **Health Checks**: Automatic via Blackbox Exporter

### 2. Rate Limiting
- **Rate**: 10 requests/second
- **Burst**: 20 requests
- **Zone**: 10MB memory allocation

### 3. Monitoring & Alerting
- **Metrics Collection**: Prometheus (15s interval)
- **Health Monitoring**: Blackbox Exporter
- **Visualization**: Grafana Dashboard
- **Nginx Metrics**: Dedicated exporter

### 4. Resilience Features
- **Timeouts**: Connect (5s), Send (60s), Read (60s)
- **Buffering**: Enabled with 8x4k buffers
- **Restart Policy**: unless-stopped
- **Persistent Storage**: Volumes for Prometheus & Grafana

## Scripts Management

Sistem dilengkapi dengan script management di `scripts/`:
- `setup.sh` - Initial setup
- `deploy.sh` - Deployment automation
- `health-check.sh` - Health monitoring
- `monitoring.sh` - System monitoring
- `backup.sh` - Data backup
- `test-loadbalancer.sh` - Load balancer testing
- `test-request-logging.sh` - Request logging test

## Error Handling & Custom Pages

### Custom Error Pages
- **502.html**: Bad Gateway error page dengan desain modern
- **50x.html**: Service Temporarily Unavailable error page
- **Lokasi**: `/etc/nginx/html/` dalam container
- **Fitur**: 
  - Responsive design dengan gradient background
  - Informasi detail error dan troubleshooting
  - Styling modern dengan CSS3

### Error Page Configuration
```nginx
error_page 500 501 502 503 504 /50x.html;
error_page 502 /502.html;
```

## Performance Testing & Load Testing

### Stress Testing Scripts

#### 1. final-stress-test.sh
- **Fungsi**: Comprehensive load balancer stress test untuk konfigurasi Nginx yang dioptimasi
- **Target**: http://localhost:8081/health
- **Konfigurasi**:
  - 50 concurrent connections
  - 500 requests per connection
  - Duration: 30 seconds
- **Tools**: Apache Bench (ab)

#### 2. simple-stress-test.sh
- **Fungsi**: Basic stress test untuk Fremisn Load Balancer
- **Target**: http://localhost:8081/health
- **Konfigurasi**:
  - 20 concurrent connections
  - 1000 requests per connection
- **Tools**: Apache Bench (ab)

#### 3. stress-test.sh
- **Fungsi**: Comprehensive stress test untuk endpoint face enrollment
- **Target**: http://localhost:8081/v1/face/enrollment
- **Konfigurasi**:
  - 10 concurrent users
  - 100 requests per user
  - Duration: 60 seconds
  - JSON payload untuk face enrollment
- **Tools**: Apache Bench (ab) dengan POST requests

## Kesimpulan

Arsitektur ini menyediakan:
1. **High Availability** melalui multiple Fremisn instances
2. **Load Distribution** dengan Nginx round-robin
3. **Comprehensive Monitoring** dengan Prometheus + Grafana
4. **Health Checking** otomatis untuk semua services
5. **Rate Limiting** untuk protection
6. **Easy Management** melalui Docker Compose dan scripts
7. **Custom Error Handling** dengan responsive error pages
8. **Performance Testing** dengan multiple stress testing scripts

Sistem ini dirancang untuk production-ready dengan fokus pada reliability, monitoring, dan ease of management.