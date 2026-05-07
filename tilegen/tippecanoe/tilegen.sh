#!/bin/sh
# tilegen.sh
# ─────────────────────────────────────────────────────────────────────────────
# Runs on cron every 5 minutes (see crontab.txt).
# 1. Refreshes the event_log materialized view in PostGIS
# 2. Dumps a GeoJSON of district-level speed stats
# 3. Re-tiles with tippecanoe → /tiles/statistics/
# ─────────────────────────────────────────────────────────────────────────────
set -e

mkdir -p /sources/agg/

# Refresh the materialized view (computes avg speed per district geom)
psql -h ${POSTGRES_HOST} \
    -U ${POSTGRES_USER} \
    -d ${POSTGRES_DB} \
    -c "REFRESH MATERIALIZED VIEW CONCURRENTLY event_log;"

# Export district-level aggregate as GeoJSON
rm -f /sources/agg/statistics.geojson && \
    ogr2ogr -f GeoJSON /sources/agg/statistics.geojson \
    "PG:host=${POSTGRES_HOST} dbname=${POSTGRES_DB} user=${POSTGRES_USER}" \
    -nlt PROMOTE_TO_MULTI \
    -geomfield geom \
    -sql "
        SELECT
            d2.name_2        AS district,
            d2.name_1        AS state,
            d2.wkb_geometry  AS geom,
            stats.spd
        FROM (
            SELECT
                ogc_fid,
                AVG(spd) AS spd
            FROM india_districts d
            LEFT JOIN event_log
                ON ST_Intersects(d.wkb_geometry, event_log.geom)
            GROUP BY ogc_fid
        ) stats
        LEFT JOIN india_districts d2 USING (ogc_fid);
    "

# Only re-tile if file has meaningful content (> 100 bytes)
if [ "$(stat -c %s "/sources/agg/statistics.geojson")" -gt "100" ]; then
    tippecanoe -L statistics:/sources/agg/statistics.geojson \
        --no-tile-compression \
        --force \
        -e /tiles/statistics
fi