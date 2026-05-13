# syntax=docker/dockerfile:1.7
# Fleet Tracker — Dashboard (static HTML served by nginx)
# The new frontend uses OpenLayers via CDN — no npm build needed.
# ── Stage 1: nothing to build (pure HTML/CSS/JS, no bundler) ─────────────────
FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="Fleet Dashboard"
LABEL org.opencontainers.image.description="OpenStreetMap live tracking dashboard."

# Remove default nginx page
RUN rm -rf /usr/share/nginx/html/*

# Copy dashboard
COPY ./index.html /usr/share/nginx/html/index.html

# Minimal nginx config: serve on :8080, proxy /locations/ and /histlocations/
# to the locations_api service
COPY ./nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
CMD ["sh", "-c", "mkdir -p /usr/share/nginx/html/cdn && printf '{\"version\":1,\"mqtt\":{\"host\":\"%s\",\"port\":%s,\"protocol\":\"tcp\"}}\n' \"${PUBLIC_MQTT_HOST:-localhost}\" \"${PUBLIC_MQTT_PORT:-1883}\" > /usr/share/nginx/html/cdn/fleet-config.json && nginx -g 'daemon off;'"]
