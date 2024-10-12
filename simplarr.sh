#!/bin/bash

echo "   _____ _                 _                 ";
echo "  / ____(_)               | |                ";
echo " | (___  _ _ __ ___  _ __ | | __ _ _ __ _ __ ";
echo "  \___ \| | '_ \` _ \| '_ \| |/ _\` | '__| '__|";
echo "  ____) | | | | | | | |_) | | (_| | |  | |   ";
echo " |_____/|_|_| |_| |_| .__/|_|\__,_|_|  |_|   ";
echo "                    | |                      ";
echo "                    |_|                      ";

echo "

A simple script to create a media server stack comprising of:

  Zurg
  Rclone
  Prowlarr
  Flaresolverr
  Sonarr
  Radarr
  Recyclarr
  Blackhole
  Jellyfin
  Jellyseer
  Postgres
  Zilean

"

read -p "RealDebrid API Key from https://real-debrid.com/apitoken: " REALDEBRID_API_KEY

echo ""
echo "Running automated steps..."
echo ""
echo "  Generating random API key for Sonarr"
SONARR_API_KEY=`hexdump -vn16 -e'4/4 "%08X"' /dev/urandom`

echo "  Generating random API key for Radarr"
RADARR_API_KEY=`hexdump -vn16 -e'4/4 "%08X"' /dev/urandom`

echo "  Generating random password for Postgres"
POSTRGRES_PASSWORD=`hexdump -vn16 -e'4/4 "%08X"' /dev/urandom`

echo "  Making prerequisite directories"
mkdir ./media
mkdir ./media/shows
mkdir ./media/movies
mkdir ./recyclarr

echo "  Creating Zurg config file (zurg.yml)"
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

echo "  Creating Rclone config file (rclone.conf)"
tee rclone.conf > /dev/null <<EOL
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOL

echo "  Creating Docker Compose file (docker-compose.yml)"
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
      - PUID=`id -u`
      - PGID=`id -g`
      - TZ=`cat /etc/timezone`
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
      - PUID=`id -u`
      - PGID=`id -g`
      - TZ=`cat /etc/timezone`
    ports:
      - 9696:9696
    volumes:
      - ./prowlarr:/config
    restart: unless-stopped
  flaresolverr:
    container_name: flaresolverr
    image: ghcr.io/flaresolverr/flaresolverr:latest
    environment:
      - TZ=`cat /etc/timezone`
    ports:
      - 8191:8191
    restart: unless-stopped
  sonarr:
    container_name: sonarr
    image: lscr.io/linuxserver/sonarr:latest
    environment:
      - PUID=`id -u`
      - PGID=`id -g`
      - TZ=`cat /etc/timezone`
      - SONARR__AUTH__APIKEY=$SONARR_API_KEY
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
      - PUID=`id -u`
      - PGID=`id -g`
      - TZ=`cat /etc/timezone`
      - RADARR__AUTH__APIKEY=$RADARR_API_KEY
    ports:
      - 7878:7878
    volumes:
      - ./radarr:/config
      - ./media:/media
    depends_on:
      - rclone
    restart: unless-stopped
  recyclarr:
    container_name: recyclarr
    image: ghcr.io/recyclarr/recyclarr:latest
    user: `id -u`:`id -g`
    environment:
      - TZ=`cat /etc/timezone`
    volumes:
      - ./recyclarr:/config
    restart: unless-stopped
  blackhole:
    container_name: blackhole
    image: ghcr.io/westsurname/scripts/blackhole:latest
    user: `id -u`:`id -g`
    environment:
      - SONARR_HOST=http://sonarr:8989
      - SONARR_API_KEY=$SONARR_API_KEY
      - RADARR_HOST=http://radarr:7878
      - RADARR_API_KEY=$RADARR_API_KEY
      - REALDEBRID_ENABLED=true
      - REALDEBRID_HOST=https://api.real-debrid.com/rest/1.0/
      - REALDEBRID_API_KEY=$REALDEBRID_API_KEY
      - REALDEBRID_MOUNT_TORRENTS_PATH=/media/zurg/torrents
      - BLACKHOLE_BASE_WATCH_PATH=/media/blackhole
      - BLACKHOLE_SONARR_PATH=sonarr
      - BLACKHOLE_RADARR_PATH=radarr
      - BLACKHOLE_FAIL_IF_NOT_CACHED=false
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
  jellyfin:
    container_name: jellyfin
    image: lscr.io/linuxserver/jellyfin:latest
    environment:
      - PUID=`id -u`
      - PGID=`id -g`
      - TZ=`cat /etc/timezone`
    volumes:
      - ./jellyfin:/config
      - ./media:/media
    ports:
      - 8096:8096
    depends_on:
      - rclone
    restart: unless-stopped
  jellyseerr:
    container_name: jellyseerr
    image: fallenbagel/jellyseerr:latest
    environment:
      - TZ=`cat /etc/timezone`
    volumes:
      - ./jellyseerr:/app/config
    ports:
      - 5055:5055
    restart: unless-stopped
  postgres:
    container_name: postgres
    image: postgres:latest
    environment:
      - POSTGRES_DB=zilean
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
    volumes:
      - ./postgres:/var/lib/postgresql/data
    restart: unless-stopped
  zilean:
    container_name: zilean
    image: ipromknight/zilean:latest
    environment:
      - ZILEAN__DATABASE__CONNECTIONSTRING=Host=postgres;Port=5432;Database=zilean;Username=postgres;Password=$POSTGRES_PASSWORD
    volumes:
      - ./zilean:/app/data
    ports:
      - 8181:8181
    depends_on:
      - postgres
    restart: unless-stopped
EOL

echo "  Pulling necessary images, creating and starting containers"
docker compose up -d &> /dev/null

echo "  Getting custom Prowlarr indexer definitions"
echo "    Zilean"
wget -q -P prowlarr/Definitions/Custom https://raw.githubusercontent.com/dreulavelle/Prowlarr-Indexers/refs/heads/main/Custom/zilean.yml

echo "    Torrentio"
wget -q -P prowlarr/Definitions/Custom https://raw.githubusercontent.com/dreulavelle/Prowlarr-Indexers/refs/heads/main/Custom/torrentio.yml

echo "  Using Recyclarr to get WEB-2160p TRaSH config file for Sonarr"
docker compose exec recyclarr recyclarr config create -t web-2160p-v4 &> /dev/null

echo "  Customising WEB-2160p config file"
echo "    Setting Sonarr URL"
sed -i -e 's/Put your Sonarr URL here/http:\/\/sonarr:8989/g' ./recyclarr/configs/web-2160p-v4.yml
echo "    Setting Sonarr API Key"
sed -i -e "s/Put your API key here/$SONARR_API_KEY/g" ./recyclarr/configs/web-2160p-v4.yml

echo "    Setting default naming scheme"
tee -a ./recyclarr/configs/web-2160p-v4.yml > /dev/null <<EOL
    media_naming:
      series: default
      season: default
      episodes:
        rename: true
        standard: default
        daily: default
        anime: default
EOL

echo "    Disabling DV (WEBDL) custom format"
sed -i -e "s/- 9b27ab6498ec0f31a3353992e19434ca/# - 9b27ab6498ec0f31a3353992e19434ca/g" ./recyclarr/configs/web-2160p-v4.yml
echo "    Enabling miscellaneous optional custom formats"
echo "      Bad Dual Groups"
sed -i -e "s/# - 32b367365729d530ca1c124a0b180c64/- 32b367365729d530ca1c124a0b180c64/g" ./recyclarr/configs/web-2160p-v4.yml
echo "      No-RlsGroup"
sed -i -e "s/# - 82d40da2bc6923f41e14394075dd4b03/- 82d40da2bc6923f41e14394075dd4b03/g" ./recyclarr/configs/web-2160p-v4.yml
echo "      Obfuscated"
sed -i -e "s/# - e1a997ddb54e3ecbfe06341ad323c458/- e1a997ddb54e3ecbfe06341ad323c458/g" ./recyclarr/configs/web-2160p-v4.yml
echo "      Retags"
sed -i -e "s/# - 06d66ab109d4d2eddb2794d21526d140/- 06d66ab109d4d2eddb2794d21526d140/g" ./recyclarr/configs/web-2160p-v4.yml
echo "      Scene"
sed -i -e "s/# - 1b3994c551cbb92a2c781af061f4ab44/- 1b3994c551cbb92a2c781af061f4ab44/g" ./recyclarr/configs/web-2160p-v4.yml
echo "    Customising miscellaneous UDH optional custom formats"
echo "      Using x265 (no HDR/DV) over x265 (HD)"
sed -i -e "s/# - 47435ece6b99a0b477caf360e79ba0bb/- 47435ece6b99a0b477caf360e79ba0bb/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# assign_scores_to:/assign_scores_to:/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# - name: WEB-2160p/- name: WEB-2160p/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# score: 0/score: 0/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# - trash_ids:/- trash_ids:/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# - 9b64dff695c2115facf1b6ea59c9bd07/- 9b64dff695c2115facf1b6ea59c9bd07/g" ./recyclarr/configs/web-2160p-v4.yml
echo "      Using SDR (no WEBDL) over SDR"
sed -i -e "s/- 2016d1676f5ee13a5b7257ff86ac9a93/# - 2016d1676f5ee13a5b7257ff86ac9a93/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# - 83304f261cf516bb208c18c54c0adf97/- 83304f261cf516bb208c18c54c0adf97/g" ./recyclarr/configs/web-2160p-v4.yml
echo "    Selecting alternative quality profile"
sed -i -e "s/- template: sonarr-v4-quality-profile-web-2160p/# - template: sonarr-v4-quality-profile-web-2160p/g" ./recyclarr/configs/web-2160p-v4.yml
sed -i -e "s/# - template: sonarr-v4-quality-profile-web-2160p-alternative/- template: sonarr-v4-quality-profile-web-2160p-alternative/g" ./recyclarr/configs/web-2160p-v4.yml

echo "  Using Recyclarr to get UHD Remux|IMAX-E (SQP-3) TRaSH config file for Radarr"
docker compose exec recyclarr recyclarr config create -t sqp-3 &> /dev/null

echo "  Customising UHD Remux|IMAX-E (SQP-3) config file"
echo "    Setting Radarr URL"
sed -i -e 's/Put your Radarr URL here/http:\/\/radarr:7878/g' ./recyclarr/configs/sqp-3.yml
echo "    Setting Radarr API Key"
sed -i -e "s/Put your API key here/$RADARR_API_KEY/g" ./recyclarr/configs/sqp-3.yml

echo "    Setting default naming scheme"
tee -a ./recyclarr/configs/sqp-3.yml > /dev/null <<EOL
    media_naming:
      folder: default
      movie:
        rename: true
        standard: default
EOL

echo "    Disabling DV (WEBDL) custom format"
sed -i -e "s/- 923b6abef9b17f937fab56cfcf89e1f1/# - 923b6abef9b17f937fab56cfcf89e1f1/g" ./recyclarr/configs/sqp-3.yml
echo "    Disabling x264 custom format"
sed -i -e "s/# score: 0/score: 0/g" ./recyclarr/configs/sqp-3.yml
echo "    Enabling miscellaneous optional custom formats"
echo "      Bad Dual Groups"
sed -i -e "s/# - b6832f586342ef70d9c128d40c07b872/- b6832f586342ef70d9c128d40c07b872/g" ./recyclarr/configs/sqp-3.yml
echo "      EVO (no WEBDL)"
sed -i -e "s/# - 90cedc1fea7ea5d11298bebd3d1d3223/- 90cedc1fea7ea5d11298bebd3d1d3223/g" ./recyclarr/configs/sqp-3.yml
echo "      No-RlsGroup"
sed -i -e "s/# - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5/- ae9b7c9ebde1f3bd336a8cbd1ec4c5e5/g" ./recyclarr/configs/sqp-3.yml
echo "      Obfuscated"
sed -i -e "s/# - 7357cf5161efbf8c4d5d0c30b4815ee2/- 7357cf5161efbf8c4d5d0c30b4815ee2/g" ./recyclarr/configs/sqp-3.yml
echo "      Retags"
sed -i -e "s/# - 5c44f52a8714fdd79bb4d98e2673be1f/- 5c44f52a8714fdd79bb4d98e2673be1f/g" ./recyclarr/configs/sqp-3.yml
echo "      Scene"
sed -i -e "s/# - f537cf427b64c38c8e36298f657e4828/- f537cf427b64c38c8e36298f657e4828/g" ./recyclarr/configs/sqp-3.yml
echo "      DV (Disk)"
sed -i -e "s/# - f700d29429c023a5734505e77daeaea7/- f700d29429c023a5734505e77daeaea7/g" ./recyclarr/configs/sqp-3.yml
echo "    Customising miscellaneous UDH optional custom formats"
echo "      Using x265 (no HDR/DV) over x265 (HD)"
sed -i -e "s/# - 839bea857ed2c0a8e084f3cbdbd65ecb/- 839bea857ed2c0a8e084f3cbdbd65ecb/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# assign_scores_to:/assign_scores_to:/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# - name: SQP-3/- name: SQP-3/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# score: 0/score: 0/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# - trash_ids:/- trash_ids:/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# - dc98083864ea246d05a42df0d05f81cc/- dc98083864ea246d05a42df0d05f81cc/g" ./recyclarr/configs/sqp-3.yml
echo "      Using SDR (no WEBDL) over SDR"
sed -i -e "s/- 9c38ebb7384dada637be8899efa68e6f/# - 9c38ebb7384dada637be8899efa68e6f/g" ./recyclarr/configs/sqp-3.yml
sed -i -e "s/# - 25c12f78430a3a23413652cbd1d48d77/- 25c12f78430a3a23413652cbd1d48d77/g" ./recyclarr/configs/sqp-3.yml
echo "    Enabling movie versions custom profiles"
echo "      Hybrid"
sed -i -e "s/# - 0f12c086e289cf966fa5948eac571f44/- 0f12c086e289cf966fa5948eac571f44/g" ./recyclarr/configs/sqp-3.yml
echo "      Remaster"
sed -i -e "s/# - 570bc9ebecd92723d2d21500f4be314c/- 570bc9ebecd92723d2d21500f4be314c/g" ./recyclarr/configs/sqp-3.yml
echo "      4K Remaster"
sed -i -e "s/# - eca37840c13c6ef2dd0262b141a5482f/- eca37840c13c6ef2dd0262b141a5482f/g" ./recyclarr/configs/sqp-3.yml
echo "      Criterion Collection"
sed -i -e "s/# - e0c07d59beb37348e975a930d5e50319/- e0c07d59beb37348e975a930d5e50319/g" ./recyclarr/configs/sqp-3.yml
echo "      Masters of Cinema"
sed -i -e "s/# - 9d27d9d2181838f76dee150882bdc58c/- 9d27d9d2181838f76dee150882bdc58c/g" ./recyclarr/configs/sqp-3.yml
echo "      Vinegar Syndrome"
sed -i -e "s/# - db9b4c4b53d312a3ca5f1378f6440fc9/- db9b4c4b53d312a3ca5f1378f6440fc9/g" ./recyclarr/configs/sqp-3.yml
echo "      Special Edition"
sed -i -e "s/# - 957d0f44b592285f26449575e8b1167e/- 957d0f44b592285f26449575e8b1167e/g" ./recyclarr/configs/sqp-3.yml
echo "      IMAX"
sed -i -e "s/# - eecf3a857724171f968a66cb5719e152/- eecf3a857724171f968a66cb5719e152/g" ./recyclarr/configs/sqp-3.yml
echo "      IMAX Enhanced"
sed -i -e "s/# - 9f6cbff8cfe4ebbc1bde14c7b7bec0de/- 9f6cbff8cfe4ebbc1bde14c7b7bec0de/g" ./recyclarr/configs/sqp-3.yml

echo "  Using Recyclarr to sync TRaSH configs to Sonarr and Radarr"
docker compose exec recyclarr recyclarr sync &> /dev/null

echo "

Automated steps completed.

----------------------------------------
        Start of manual steps!
----------------------------------------

Jellyfin - http://localhost:8096
  Add Media Library
    Content type = Shows
    Add Folder '/media/shows/'
  Add Media Library
    Content type = Movies
    Add Folder '/media/movies/'
  Settings --> Dashboard --> API Keys
    Add API Key for Sonarr
    Add API Key for Radarr

Jellyseerr - http://localhost:5055
  Use your Jellyfin account
  Jellyfin URL = http://jellyfin:8096
  Sync Libraries
  Enable Movies
  Enable Shows
  Start Scan
  Add Radaar Server
    Default Server = Enabled
    Server Name = Radarr
    Hostname or IP Address = radarr
    API Key = $RADARR_API_KEY
    Quality Profile = SQP-3
    Root Folder = /media/movies/
    Enable Scan = Enabled
  Add Sonarr Server
    Default Server = Enabled
    Sever Name = Sonarr
    Hostname or IP Address = sonarr
    API Key = $SONARR_API_KEY
    Quality Profile = WEB-2160p
    Root Folder = /media/shows/
    Language Profile = Depricated
    Enable Scan = Enabled

Sonarr - http://localhost:8989
  Settings -->  Show Advanced --> Media Management
    Set Propers and Repacks to 'Do not Prefer'
    Add Root Folder '/media/shows/'
  Settings --> Download Clients
    Add Torrent Blackhole
      Torrent Folder = '/media/blackhole/sonarr/'
      Watch Folder = '/media/blackhole/sonarr/completed/'
      Save Magnet Files = Enabled
      Read Only = Disabled
  Settings --> Connect
    Add Emby / Jellyfin
      Host = 'jellyfin'
      API Key = [Sonarrr key from Jellyfin]

Radarr - http://localhost:7878
  Settings -->  Show Advanced --> Media Management
    Set Propers and Repacks to 'Do not Prefer'
    Add Root Folder '/media/movies/'
  Settings --> Download Clients
    Add Torrent Blackhole
      Torrent Folder = '/media/blackhole/radarr/'
      Watch Folder = '/media/blackhole/radarr/completed/'
      Save Magnet Files = Enabled
      Read Only = Disabled
  Settings --> Connect
    Add Emby / Jellyfin
      Host = 'jellyfin'
      API Key = [Radarr key from Jellyfin]

Prowlarr - http://localhost:9696
  Settings --> Apps
    Add Sonarr
      Prowlarr Server = http://prowlarr:9696
      Sonarr Server = http://sonarr:8989
      API Key = $SONARR_API_KEY
    Add Radarr
      Prowlarr Server = http://prowlarr:9696
      Radarr Server = http://radarr:8989
      API Key = $RADARR_API_KEY
  Settings --> Indexers
    Add FlareSolverr
      Tags = 'flaresolverr'
      Host = 'http://flaresolverr:8191'
  Indexers --> Add Indexer
    Zilean
    1337x
      Tags = 'flaresolverr'
    BitSearch
    EZTV
    The Pirate Bay
    TheRARBG
    Torrentio
      Real-Debrid API Key = $REALDEBRID_API_KEY
    YTS

----------------------------------------
Automated steps completed.
Scroll up to find start of manual steps.
----------------------------------------
"
