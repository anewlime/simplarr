#!/bin/bash

create_env_file() {
  read -p "Real-Debrid API Key from https://real-debrid.com/apitoken: " REALDEBRID_API_KEY
  read -p "Random 32 digit hex code from https://numbergenerator.org/random-32-digit-hex-codes-generator: " SONARR_RADARR_API_KEY
  tee .env > /dev/null <<EOL
REALDEBRID_API_KEY=$REALDEBRID_API_KEY
SONARR_RADARR_API_KEY=$SONARR_RADARR_API_KEY
EOL
}

create_env_file

mkdir ./media
mkdir ./media/shows
mkdir ./media/movies

tee zurg.yml > /dev/null <<EOL
zurg: v1
token: $REALDEBRID_API_KEY
check_for_changes_every_secs: 10
retain_rd_torrent_name: true
retain_folder_name_extension: true
directories:
  torrents:
    filters:
      - regex: /.*/
EOL

tee rclone.conf > /dev/null <<EOL
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOL

tee docker-compose.yml > /dev/null <<EOL
services:
  zurg:
    container_name: zurg
    image: ghcr.io/debridmediamanager/zurg-testing:latest
    ports:
      - 9999:9999
    volumes:
      - ./zurg.yml:/app/config.yml
      - ./zurg:/app/data
    restart: unless-stopped
  rclone:
    container_name: rclone
    image: rclone/rclone:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - ./rclone.conf:/config/rclone/rclone.conf
      - ./media/zurg:/zurg:rshared
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    depends_on:
      - zurg
    command: "mount zurg: /zurg --allow-other --allow-non-empty --dir-cache-time 10s --vfs-cache-mode full"
    restart: unless-stopped
  prowlarr:
    container_name: prowlarr
    image: lscr.io/linuxserver/prowlarr:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    ports:
      - 9696:9696
    volumes:
      - ./prowlarr:/config
    restart: unless-stopped
  sonarr:
    container_name: sonarr
    image: lscr.io/linuxserver/sonarr:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - SONARR__AUTH__APIKEY=${SONARR_RADARR_API_KEY}
    ports:
      - 8989:8989
    volumes:
      - ./sonarr:/config
      - ./media:/media
    depends_on:
      - rclone
    restart: unless-stopped
  radarr:
    container_name: radarr
    image: lscr.io/linuxserver/radarr:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - RADARR__AUTH__APIKEY=${SONARR_RADARR_API_KEY}
    ports:
      - 7878:7878
    volumes:
      - ./radarr:/config
      - ./media:/media
    depends_on:
      - rclone
    restart: unless-stopped
  blackhole:
    container_name: blackhole
    image: ghcr.io/westsurname/scripts/blackhole:latest
    user: 1000:1000
    environment:
      - SONARR_HOST=http://sonarr:8989
      - SONARR_API_KEY=${SONARR_RADARR_API_KEY}
      - RADARR_HOST=http://radarr:7878
      - RADARR_API_KEY=${SONARR_RADARR_API_KEY}
      - REALDEBRID_ENABLED=true
      - REALDEBRID_HOST=https://api.real-debrid.com/rest/1.0/
      - REALDEBRID_API_KEY=${REAL_DEBRID_API_KEY}
      - REALDEBRID_MOUNT_TORRENTS_PATH=/media/zurg/torrents
      - BLACKHOLE_BASE_WATCH_PATH=/media/blackhole
      - BLACKHOLE_SONARR_PATH=sonarr
      - BLACKHOLE_RADARR_PATH=radarr
      - BLACKHOLE_FAIL_IF_NOT_CACHED=true
      - BLACKHOLE_RD_MOUNT_REFRESH_SECONDS=200
      - BLACKHOLE_WAIT_FOR_TORRENT_TIMEOUT=60
      - BLACKHOLE_HISTORY_PAGE_SIZE=500
      - PYTHONUNBUFFERED=TRUE
      - PLEX_SERVER_MOVIE_LIBRARY_ID=0
      - PLEX_SERVER_TV_SHOW_LIBRARY_ID=0
    volumes:
      - ./media:/media
    depends_on:
      - rclone
    restart: unless-stopped
EOL

docker compose up -d
