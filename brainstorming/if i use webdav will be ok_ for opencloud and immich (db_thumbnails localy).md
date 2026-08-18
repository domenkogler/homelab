**Yes, WebDAV will be perfectly fine for both OpenCloud and Immich, provided you maintain local hosting for databases, cache paths, and thumbnails on the netcup NVMe.** \[1\]

Because you are taking the heavy-write operations (the database entries and thumbnail images) off the network storage, WebDAV becomes a highly efficient transport pipeline for your large raw documents and image assets. \[2\]

Here is exactly how to safely configure WebDAV for both applications to avoid performance bottlenecks:

## ---

**📂 Configuration for OpenCloud**

OpenCloud handles this natively. Keep the base application directory on your netcup NVMe, then map your Hetzner Storage Box seamlessly into the application layer: \[3\]

> 1. **Keep App Core Local:** Install OpenCloud normally, keeping /var/www/html/data on the fast local drive.  
> 2. **Add via UI:** Go to the OpenCloud App Market, enable the **External Storage Support** extension, and connect your Hetzner Storage Box using its WebDAV login credentials. \[4\]  
> 3. **The Result:** When browsing via your desktop AppImage client, the file architecture tree is fetched instantly from your local netcup PostgreSQL/MariaDB cache. The actual files are stream-downloaded from the Hetzner Storage Box via WebDAV only when you explicitly open them. \[5\]

## ---

**📸 Configuration for Immich (Crucial)**

Immich handles external media via its **External Libraries** feature, but its Docker configuration requires careful attention to prevent heavy thumbnail rendering cycles from crashing over the network. \[2, 6, 7, 8\]

> 1. **Mount on Host System via rclone:** First, mount your Hetzner Storage Box to your netcup OS using an optimized rclone mount block:  
>    `rclone mount storagebox: /mnt/storagebox \`  
>      `--vfs-cache-mode full \`  
>      `--vfs-cache-max-age 1h \`  
>      `--allow-other \`  
>      `--daemon`

> 2. **Configure your Docker Compose:** In your docker-compose.yml for Immich, separate your standard upload target from your external storage directory:  
>    `services:`  
>      `immich-server:`  
>        `# ... other configurations ...`  
>        `volumes:`  
>          `- /opt/immich/upload:/usr/src/app/upload  # Holds DB, thumbnails, and cache LOCALLY on NVMe`  
>          `- /mnt/storagebox/photos:/mnt/external_photos:ro # Mounted Hetzner storage box mapped as Read-Only`

>      `immich-microservices:`  
>        `volumes:`  
>          `- /opt/immich/upload:/usr/src/app/upload`  
>          `- /mnt/storagebox/photos:/mnt/external_photos:ro # Must match server mount to let ML engines read photos`

> 3. **Scan via Admin UI:** Inside the [Immich Web Interface](https://docs.immich.app/guides/external-library/), navigate to *Administration \-\> External Libraries*, click *Create Library*, and point the scanning path to /mnt/external\_photos. \[6, 9\]

## **Why this hybrid setup succeeds**

When Immich scans your photos, the machine learning models and thumbnail generation engines run tasks natively on the netcup AMD EPYC cores. The newly created tiny thumbnail image files are written right back to your high-speed local NVMe path (/opt/immich/upload). Your main photo collection sits safely and cheaply on the Hetzner Storage Box, but browsing your timeline on the Immich mobile app remains incredibly fast because all your timeline images pull from the local thumbnail folder. \[2, 10, 11\]

Would you like help writing a system startup script (systemd) to ensure your WebDAV mount automatically connects on server reboots before your Docker containers start?

\[1\] [https://github.com](https://github.com/immich-app/immich/discussions/1687)  
\[2\] [https://www.reddit.com](https://www.reddit.com/r/immich/comments/1lv5p16/using_immich_with_nextcloud_storage_on_hetzner/)  
\[3\] [https://docs.opencloud.eu](https://docs.opencloud.eu/docs/admin/features/)  
\[4\] [https://techenclave.com](https://techenclave.com/t/has-anyone-tried-opencloud/407815)  
\[5\] [https://central.owncloud.org](https://central.owncloud.org/t/webdav-general-question-for-oc-newbie/28764)  
\[6\] [https://docs.immich.app](https://docs.immich.app/guides/external-library/)  
\[7\] [https://docs.immich.app](https://docs.immich.app/features/libraries)  
\[8\] [https://www.youtube.com](https://www.youtube.com/watch?v=URJiQb8PwWo)  
\[9\] [https://www.reddit.com](https://www.reddit.com/r/selfhosted/comments/1funfoe/looking_for_alternative_to_immich_that_can_use/)  
\[10\] [https://www.youtube.com](https://www.youtube.com/watch?v=ehX0cl3IfdA)  
\[11\] [https://www.reddit.com](https://www.reddit.com/r/immich/comments/1osrj8f/is_it_possible_to_host_immich_in_one_place_and/)