#!/usr/bin/env python3
"""
FleetTrack Truck Simulator
==========================
Simulates trucks driving Visakhapatnam Port → Kakinada Port (NH16, ~185 km).

Pipeline
--------
  This script  →  MQTT broker  →  Go mqtt worker  →  Redis  →  WS  →  Frontend

The simulator also pushes the route geometry once to Redis PubSub
(currentLocationsPS) so the frontend can draw the road without any hardcoding.

Usage
-----
  python3 tools/simulate_trucks.py
  python3 tools/simulate_trucks.py --mqtt-host 10.101.153.123 --mqtt-port 1883 \\
                                   --redis-host 10.101.153.123 --redis-port 6379 \\
                                   --trucks 4 --interval 3
"""

import json
import time
import math
import random
import argparse

import paho.mqtt.client as mqtt

try:
    import redis as redislib
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False
    print("⚠  redis-py not installed — route will not be published to frontend.")
    print("   Install with: pip install redis")

# ── NH16 route waypoints: Vizag Port → Kakinada Port ─────────────────────────
# 16 surveyed points along the highway corridor.
ROUTE = [
    {"lat": 17.6923, "lng": 83.2968, "name": "Visakhapatnam Port"},
    {"lat": 17.7145, "lng": 83.2723, "name": "Gajuwaka"},
    {"lat": 17.7346, "lng": 83.2311, "name": "Kommadi"},
    {"lat": 17.7512, "lng": 83.1854, "name": "Bheemunipatnam Junction"},
    {"lat": 17.7214, "lng": 83.1023, "name": "Sabbavaram"},
    {"lat": 17.6912, "lng": 82.9994, "name": "Anakapalle"},
    {"lat": 17.6134, "lng": 82.8756, "name": "Rambilli"},
    {"lat": 17.5423, "lng": 82.7534, "name": "Atchutapuram"},
    {"lat": 17.4812, "lng": 82.6423, "name": "Hukumpeta"},
    {"lat": 17.3581, "lng": 82.5487, "name": "Tuni"},
    {"lat": 17.2634, "lng": 82.4512, "name": "Prathipadu"},
    {"lat": 17.1523, "lng": 82.3423, "name": "Pithapuram"},
    {"lat": 17.0796, "lng": 82.2434, "name": "Peddapuram"},
    {"lat": 17.0123, "lng": 82.2356, "name": "Samalkota"},
    {"lat": 16.9548, "lng": 82.2378, "name": "Kakinada City"},
    {"lat": 16.9248, "lng": 82.2706, "name": "Kakinada Port"},
]

# ── Truck fleet templates ──────────────────────────────────────────────────────
TRUCK_TEMPLATES = [
    {"vid": "AP39AQ4521", "did": "+919848100001", "tid": "sim-trip-001", "start_seg": 0,  "spd": 55, "bat": 88},
    {"vid": "AP39BX7832", "did": "+919848100002", "tid": "sim-trip-002", "start_seg": 4,  "spd": 48, "bat": 72},
    {"vid": "AP39CK1156", "did": "+919848100003", "tid": "sim-trip-003", "start_seg": 8,  "spd": 62, "bat": 54},
    {"vid": "AP39DM2290", "did": "+919848100004", "tid": "sim-trip-004", "start_seg": 12, "spd": 44, "bat": 91},
    {"vid": "AP39EN3347", "did": "+919848100005", "tid": "sim-trip-005", "start_seg": 2,  "spd": 58, "bat": 65},
    {"vid": "AP39FP5512", "did": "+919848100006", "tid": "sim-trip-006", "start_seg": 10, "spd": 51, "bat": 78},
]


def haversine_km(lat1, lng1, lat2, lng2):
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlng / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def bearing(lat1, lng1, lat2, lng2):
    dlng = math.radians(lng2 - lng1)
    lat1, lat2 = math.radians(lat1), math.radians(lat2)
    x = math.sin(dlng) * math.cos(lat2)
    y = (math.cos(lat1) * math.sin(lat2)
         - math.sin(lat1) * math.cos(lat2) * math.cos(dlng))
    return (math.degrees(math.atan2(x, y)) + 360) % 360


class Truck:
    def __init__(self, tmpl):
        self.vid  = tmpl["vid"]
        self.did  = tmpl["did"]
        self.tid  = tmpl["tid"]
        self.seg  = tmpl["start_seg"] % (len(ROUTE) - 1)
        self.frac = 0.0
        self.spd  = tmpl["spd"]
        self.bat  = float(tmpl["bat"])

    def step(self, interval_sec: float) -> dict:
        p1 = ROUTE[self.seg]
        p2 = ROUTE[self.seg + 1]

        seg_km  = haversine_km(p1["lat"], p1["lng"], p2["lat"], p2["lng"])
        dist_km = (self.spd / 3600) * interval_sec
        advance = dist_km / seg_km if seg_km > 0 else 0

        self.frac += advance
        while self.frac >= 1.0:
            self.frac -= 1.0
            self.seg  += 1
            if self.seg >= len(ROUTE) - 1:
                self.seg  = 0
                self.frac = 0.0
                print(f"  [{self.vid}] ✅ Reached Kakinada — looping back to Vizag")

        p1, p2 = ROUTE[self.seg], ROUTE[self.seg + 1]
        lat = p1["lat"] + (p2["lat"] - p1["lat"]) * self.frac + random.gauss(0, 0.00004)
        lng = p1["lng"] + (p2["lng"] - p1["lng"]) * self.frac + random.gauss(0, 0.00004)

        brg     = bearing(p1["lat"], p1["lng"], p2["lat"], p2["lng"])
        self.bat = max(5.0, self.bat - random.uniform(0, 0.04))

        return {
            "vid": self.vid,
            "did": self.did,
            "tid": self.tid,
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "spd": round(max(0, self.spd + random.gauss(0, 3)), 1),
            "brg": round(brg, 1),
            "acc": round(random.uniform(3, 12), 1),
            "ts":  int(time.time()),
            "bat": int(self.bat),
            "src": "simulator",
        }


def publish_route(redis_client, route_id: str):
    """Push the route geometry to Redis PubSub once at startup."""
    if redis_client is None:
        return
    msg = {
        "type":  "route",
        "id":    route_id,
        "name":  "Visakhapatnam Port → Kakinada Port (NH16)",
        "color": "#f97316",
        "coords": [[wp["lng"], wp["lat"]] for wp in ROUTE],  # [lng, lat] for GeoJSON/OL
    }
    n = redis_client.publish("currentLocationsPS", json.dumps(msg))
    print(f"🗺  Route published to Redis PubSub ({n} subscriber(s) notified)\n")


def main():
    parser = argparse.ArgumentParser(description="FleetTrack Truck Simulator")
    parser.add_argument("--mqtt-host",  default="10.101.153.123")
    parser.add_argument("--mqtt-port",  type=int, default=1883)
    parser.add_argument("--redis-host", default="10.101.153.123")
    parser.add_argument("--redis-port", type=int, default=6379)
    parser.add_argument("--redis-pass", default="", help="REDISCLI_AUTH value")
    parser.add_argument("--trucks",     type=int, default=3,
                        help="Number of simulated trucks (max 6)")
    parser.add_argument("--interval",   type=float, default=3.0,
                        help="Seconds between position updates")
    args = parser.parse_args()

    n_trucks = max(1, min(args.trucks, len(TRUCK_TEMPLATES)))
    trucks   = [Truck(TRUCK_TEMPLATES[i]) for i in range(n_trucks)]

    # ── Redis (for route broadcast) ───────────────────────────────────────────
    redis_client = None
    if REDIS_AVAILABLE:
        try:
            redis_client = redislib.Redis(
                host=args.redis_host,
                port=args.redis_port,
                password=args.redis_pass or None,
                decode_responses=True,
                socket_connect_timeout=3,
            )
            redis_client.ping()
            print(f"✅ Redis connected → {args.redis_host}:{args.redis_port}")
        except Exception as e:
            print(f"⚠  Redis unavailable ({e}) — route will not appear on map")
            redis_client = None

    # ── MQTT ──────────────────────────────────────────────────────────────────
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="fleet_simulator")
    client.connect(args.mqtt_host, args.mqtt_port, keepalive=60)
    client.loop_start()

    print(f"\n🚛 FleetTrack Simulator")
    print(f"   MQTT  → {args.mqtt_host}:{args.mqtt_port}")
    print(f"   Route → Visakhapatnam Port → Kakinada Port (NH16, ~185 km)")
    print(f"   Trucks ({n_trucks}): {', '.join(t.vid for t in trucks)}")
    print(f"   Interval: {args.interval}s\n")

    # Publish route to frontend once at startup
    publish_route(redis_client, "vizag_kakinada_nh16")

    try:
        while True:
            for truck in trucks:
                payload = truck.step(args.interval)
                topic   = f"trucks/{payload['vid']}/location"
                client.publish(topic, json.dumps(payload), qos=1)
                print(f"  [{payload['vid']}] "
                      f"lat={payload['lat']:.5f}  lng={payload['lng']:.5f}  "
                      f"spd={payload['spd']} km/h  bat={payload['bat']}%")
            print()
            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\n⛔ Simulator stopped.")
    finally:
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()
