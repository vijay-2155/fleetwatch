# 🚛 FleetTrack India — Real-Time Truck & Fleet Tracking

Production-grade GPS tracking platform for Indian logistics fleets.  
**Driver Flutter app → Mosquitto MQTT → Go worker → Redis Stack → PostGIS → OpenStreetMap dashboard**

---

## Architecture

```
[Driver Phone]
  Flutter App (Android Foreground Service)
  GPS → SQLite offline buffer → MQTT QoS 1
             ↓
  [Mosquitto Broker]  port 1883  (our own)
             ↓
  [Go Worker]  (hslservices/cmd/mqtt)
             ↓
  Redis Pipeline: PUBLISH + XADD + TS.ADD
             ↓
  PostGIS  (write-behind via RedisGears / Triggers & Functions)
             ↓
  WebSocket → Live OpenStreetMap Dashboard
```

---

## Quick Start

### Prerequisites
- Docker + Docker Compose v2
- Android phone with network access to the public MQTT endpoint

### 1. Configure Mobile Discovery

Set the public broker address that phones can reach. This can be a VPS IP,
domain, or TCP tunnel host.

```bash
# envs/hslweb.env
PUBLIC_MQTT_HOST=mqtt.example.com
PUBLIC_MQTT_PORT=1883
```

The frontend container writes this into:

```text
http://your-server:8080/cdn/fleet-config.json
```

Build the driver app with `FLEET_CONFIG_URL` pointed at that stable URL. If the
server IP changes later, update `PUBLIC_MQTT_HOST` and restart the frontend
container; the APK does not need to be rebuilt.

### 2. Start backend services

```bash
docker compose up -d
```

| Service | Port | Description |
|---|---|---|
| **Mosquitto** | 1883 | MQTT broker (driver phones connect here) |
| **Redis Stack** | 6379 | TimeSeries, Streams, Pub/Sub |
| **Go Worker** | — | MQTT → Redis bridge |
| **Locations API** | 2152 | WebSocket fan-out + trip history |
| **PostGIS** | 5433 | Write-behind GPS event log |
| **Dashboard** | 8080 | Live OpenStreetMap map |

### 3. Run the Flutter driver app

```bash
cd driver_app
flutter run --release   # or install APK on a real Android device
```

### 4. Open the dashboard

```
http://localhost:8080
```

---

## Payload Format (compact keys → saves bytes on 2G/3G)

```json
{
  "vid": "AP 30 Y 1828",
  "did": "9505683966",
  "tid": "uuid-trip-id",
  "lat": 17.7137197,
  "lng": 83.1691558,
  "spd": 0.30,
  "brg": 0.0,
  "acc": 5.10,
  "ts":  1778132507,
  "bat": 82,
  "src": "mobile"
}
```

---

## Flutter App Features

| Feature | Implementation |
|---|---|
| **Android Foreground Service** | GPS stays alive with screen off |
| **Adaptive GPS rate** | 5 s moving · 60 s parked (saves ~80% battery) |
| **SQLite offline buffer** | Zero data loss during highway signal blackouts |
| **QoS 1 MQTT** | Broker ACKs every delivery |
| **±50 m accuracy filter** | Discards tunnel / bad-fix readings |
| **Auto-boot resume** | Restarts tracking after phone reboot |
| **Buffer flush on reconnect** | Replays offline events when signal returns |

---

## Project Structure

```
.
├── driver_app/          # Flutter Android driver app
│   └── lib/
│       ├── config.dart               # Broker IP · GPS intervals
│       ├── main.dart                 # App entry + dark theme
│       ├── models/truck_event.dart   # Payload struct
│       ├── services/
│       │   ├── tracking_service.dart # Android Foreground Service ⭐
│       │   ├── mqtt_service.dart     # MQTT client (QoS 1, auto-reconnect)
│       │   └── offline_buffer.dart   # SQLite offline queue
│       ├── providers/tracking_provider.dart
│       └── screens/
│           ├── home_screen.dart      # Speedometer · status · SOS
│           └── trip_setup_screen.dart
│
├── hslservices/         # Go backend (renamed package: fleetbridge)
│   ├── event.go         # TruckEvent struct
│   ├── mqttClient.go    # Mosquitto subscriber
│   ├── redisClient.go   # Redis Stack client (v9)
│   ├── errors.go
│   └── cmd/
│       ├── mqtt/        # MQTT → Redis worker
│       ├── locations/   # WebSocket + history API
│       └── tiles/       # Static tile server
│
├── frontend/            # Live map dashboard
│   ├── index.html       # OpenStreetMap (OpenLayers 8, CDN, no API key)
│   ├── nginx.conf       # Proxy WS + tiles to Go services
│   └── Dockerfile       # nginx:1.27-alpine (no npm build needed)
│
├── mosquitto/           # Mosquitto broker config
│   └── mosquitto.conf
│
├── redis/               # Redis Stack 7.4 image + Gears scripts
├── postgis/             # PostGIS init SQL
├── tilegen/             # Tippecanoe tile generator (India districts)
├── envs/                # Environment variable files
└── docker-compose.yml
```

---

## Environment Variables

### `envs/mqtt_connector.env`
```env
MQTT_TOPIC=trucks/#
MQTT_BROKER=mosquitto
MQTT_PORT=1883
MQTT_N_WORKERS=10
```

### `envs/redis.env`
```env
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DB=0
```

## Tech Stack

| Layer | Technology |
|---|---|
| Driver app | Flutter 3, Android Foreground Service, SQLite |
| MQTT broker | Eclipse Mosquitto 2 |
| Go worker | Go 1.22, paho.mqtt v1.5, redis/go-redis v9 |
| Cache & streams | Redis Stack 7.4 (TimeSeries, Pub/Sub, Streams) |
| Write-behind DB | PostGIS 16-3.5 |
| Geofence tiles | tippecanoe + GADM India boundaries |
| Map | OpenLayers 8 + OpenStreetMap (no API key) |
| Dashboard server | nginx 1.27 |

---

## Security Roadmap

- [ ] MQTT username/password per vehicle (`mosquitto.conf` `password_file`)
- [ ] TLS on port 8883 (Let's Encrypt / stunnel)
- [ ] SOS button → `trucks/{vid}/sos` emergency topic
- [ ] JWT auth on WebSocket API
- [ ] Geofence alerts via Redis TimeSeries rules
