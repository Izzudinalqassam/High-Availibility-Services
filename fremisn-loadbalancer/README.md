# 🚀 Fremisn Load Balancer & Monitoring Stack

> Solusi load balancing dan monitoring yang powerful untuk aplikasi Fremisn dengan dashboard real-time yang cantik!

## 📖 Deskripsi Proyek

**Fremisn Load Balancer** adalah sistem load balancing dan monitoring yang dirancang khusus untuk aplikasi Fremisn. Proyek ini menyediakan infrastruktur yang robust untuk mendistribusikan traffic ke multiple server Fremisn (Master & Slave) sambil memantau kesehatan dan performa sistem secara real-time.

### 🎯 Tujuan Utama

- **High Availability**: Memastikan aplikasi Fremisn selalu tersedia dengan failover otomatis
- **Load Distribution**: Mendistribusikan beban kerja secara merata antara server Master dan Slave
- **Real-time Monitoring**: Monitoring kesehatan server, response time, dan metrics performa
- **Visual Dashboard**: Interface yang user-friendly untuk monitoring sistem
- **Alerting**: Deteksi dini masalah dengan sistem monitoring yang comprehensive

## 🏗️ Arsitektur Sistem

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Load Balancer │────│  Fremisn Master  │    │  Fremisn Slave  │
│   (Nginx)       │    │  192.168.100.231 │    │  192.168.100.18 │
│   Port: 8081    │    │  Port: 4005      │    │  Port: 4008     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Prometheus    │────│  Blackbox        │    │   Grafana       │
│   Port: 9090    │    │  Exporter        │    │   Port: 3000    │
│                 │    │  Port: 9115      │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🚀 Instalasi & Setup

### Prerequisites

- Docker & Docker Compose
- Server dengan akses ke jaringan Fremisn
- Port 3000, 8080, 8081, 9090, 9115 tersedia

### Langkah-langkah Instalasi

1. **Clone atau copy project ke server**
   ```bash
   # Pastikan Anda berada di direktori /opt
   cd /opt/fremisn-loadbalancer
   ```

2. **Verifikasi konfigurasi**
   ```bash
   # Periksa konfigurasi Nginx
   cat nginx/nginx.conf
   
   # Periksa konfigurasi Prometheus
   cat prometheus/prometheus.yml
   ```

3. **Start semua layanan**
   ```bash
   docker-compose up -d
   ```

4. **Verifikasi deployment**
   ```bash
   # Jalankan script test
   ./test-loadbalancer.sh
   
   # Periksa status container
   docker-compose ps
   ```

### Konfigurasi Server Fremisn

Pastikan server Fremisn Anda berjalan di:
- **Master**: `192.168.100.231:4005`
- **Slave**: `192.168.100.18:4008`

Jika IP atau port berbeda, update file `nginx/nginx.conf` dan `prometheus/prometheus.yml`.

## 🎮 Cara Penggunaan

### Akses Dashboard & Services

| Service | URL | Kredensial |
|---------|-----|------------|
| **Load Balancer** | http://localhost:8081 | - |
| **Grafana Dashboard** | http://localhost:3000 | admin/admin123 |
| **Prometheus** | http://localhost:9090 | - |
| **Nginx Status** | http://localhost:8080/nginx_status | - |

### Monitoring Server Health

1. **Buka Grafana Dashboard**
   - Akses http://localhost:3000
   - Login dengan `admin/admin123`
   - Dashboard akan otomatis terbuka

2. **Panel Monitoring Utama**
   - **Fremisn Master Status**: Menampilkan UP/DOWN status
   - **Fremisn Slave Status**: Menampilkan UP/DOWN status
   - **Response Time**: Waktu respons kedua server
   - **Request Rate**: Jumlah request per detik
   - **HTTP Status Codes**: Distribusi status code response

### Testing Load Balancer

```bash
# Test koneksi ke load balancer
curl http://localhost:8081

# Test dengan multiple requests
./test-request-logging.sh

# Lihat log requests
cat /tmp/fremisn-request.log
```

### Troubleshooting

```bash
# Periksa logs container
docker-compose logs nginx-lb
docker-compose logs prometheus
docker-compose logs grafana

# Restart layanan jika diperlukan
docker-compose restart

# Periksa status target Prometheus
curl 'http://localhost:9090/api/v1/targets'
```

## ✨ Fitur Utama

### 🔄 Load Balancing
- **Round-robin distribution** antara Master dan Slave
- **Health checks** otomatis untuk failover
- **Session persistence** (jika diperlukan)
- **Custom error pages** untuk maintenance

### 📊 Monitoring & Alerting
- **Real-time metrics** dari Nginx dan server Fremisn
- **Custom blackbox probing** yang menerima HTTP 404 sebagai valid
- **Visual dashboard** dengan Grafana
- **Historical data** untuk analisis trend
- **Configurable alerts** (dapat dikembangkan)

### 🛠️ Management Tools
- **Automated testing scripts** untuk validasi sistem
- **Request logging** untuk debugging
- **Easy configuration** melalui file YAML
- **Docker-based deployment** untuk portabilitas

### 🔧 Customization
- **Flexible server configuration** di `nginx.conf`
- **Custom monitoring modules** di `blackbox.yml`
- **Extensible dashboard** di Grafana
- **Configurable scrape intervals** di Prometheus

## 📁 Struktur Project

```
fremisn-loadbalancer/
├── docker-compose.yml          # Orchestrasi semua layanan
├── nginx/
│   ├── nginx.conf              # Konfigurasi load balancer
│   └── conf.d/                 # Konfigurasi tambahan
├── prometheus/
│   └── prometheus.yml          # Konfigurasi monitoring
├── blackbox/
│   └── blackbox.yml            # Konfigurasi health checks
├── grafana/
│   ├── dashboards/
│   │   └── fremisn-monitoring.json  # Dashboard definition
│   └── provisioning/           # Auto-provisioning config
├── test-loadbalancer.sh        # Script testing sistem
├── test-request-logging.sh     # Script testing requests
└── README.md                   # Dokumentasi ini
```

## 🤝 Kontribusi

Kami welcome kontribusi untuk meningkatkan sistem ini! Berikut cara berkontribusi:

### Cara Berkontribusi

1. **Fork repository** ini
2. **Buat branch** untuk fitur baru: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push ke branch**: `git push origin feature/amazing-feature`
5. **Buat Pull Request**

### Guidelines

- Pastikan semua test script berjalan dengan baik
- Update dokumentasi jika menambah fitur baru
- Gunakan commit message yang descriptive
- Test di environment yang mirip dengan production

### Areas yang Bisa Dikembangkan

- 🚨 **Alerting system** dengan Slack/Email notifications
- 📈 **Advanced metrics** dan custom dashboards
- 🔐 **Security enhancements** dengan SSL/TLS
- 🐳 **Kubernetes deployment** manifests
- 📱 **Mobile-responsive** dashboard
- 🔄 **Auto-scaling** berdasarkan load

## 📄 Lisensi

Proyek ini dilisensikan di bawah **MIT License** - lihat file [LICENSE](LICENSE) untuk detail lengkap.

```
MIT License

Copyright (c) 2024 Fremisn Load Balancer Project

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
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

## 📞 Support & Contact

Jika Anda mengalami masalah atau memiliki pertanyaan:

- 📧 **Email**: support@fremisn.com
- 🐛 **Bug Reports**: Buat issue di repository
- 💬 **Discussions**: Gunakan GitHub Discussions
- 📖 **Documentation**: Lihat wiki untuk detail teknis

---

<div align="center">
  <strong>Made with ❤️ for the Fremisn Community</strong>
  <br>
  <em>Happy Load Balancing! 🚀</em>
</div>