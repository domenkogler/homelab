### tiredofit/db-backup
 - It natively supports MySQL, MariaDB, PostgreSQL, MongoDB, InfluxDB, Redis, and Microsoft SQL Server all within the same image.
 - Runs constantly in the background as a long-lived service. It has an internal Cron scheduler engine. You configure exactly when it runs directly inside your docker-compose.yml file using simple environment variables like DB_DUMP_FREQ=1440 (to trigger exactly every 24 hours)
- Handles the entire file lifecycle. It natively supports multiple compression methods (Gzip, Bzip2, Xz, Zstd), creates MD5/SHA1 verification checksums, and features automatic retention cleanup
- Can write locally, but it also has native upload connectors built-in. It can seamlessly push your database backups directly out to Amazon S3, MinIO, or Azure Blob Storage