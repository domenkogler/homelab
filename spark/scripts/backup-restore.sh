#!/bin/bash
# backup-restore.sh - Backup and restore script for Spark DGX AI Stack
# Usage: ./scripts/backup-restore.sh [backup|restore|list] [options]

set -euo pipefail

# Configuration (override via environment or /etc/spark-ai/backup.conf)
BACKUP_ROOT="${BACKUP_ROOT:-/backup/spark}"
XFS_MOUNT="${XFS_MOUNT:-/mnt/spark_nvme}"
MODELS_DIR="${MODELS_DIR:-/home/ubuntu/models}"
PROJECT_DIR="${PROJECT_DIR:-/home/ubuntu/qwen-spark-stack}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESS="${COMPRESS:-true}"
ENCRYPT="${ENCRYPT:-false}"
GPG_RECIPIENT="${GPG_RECIPIENT:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [backup|restore|list] [options]

Commands:
  backup              Create full backup
  restore <backup>    Restore from backup (specify backup name from list)
  list                List available backups

Environment variables:
  BACKUP_ROOT         Backup destination (default: /backup/spark)
  XFS_MOUNT           XFS mount point (default: /mnt/spark_nvme)
  MODELS_DIR          Models directory (default: /home/ubuntu/models)
  PROJECT_DIR         Project directory (default: /home/ubuntu/qwen-spark-stack)
  RETENTION_DAYS      Days to keep backups (default: 30)
  COMPRESS            Compress backups (default: true)
  ENCRYPT             Encrypt with GPG (default: false)
  GPG_RECIPIENT       GPG key ID for encryption

Examples:
  $0 backup
  $0 list
  $0 restore spark-backup-20250115-120000
  BACKUP_ROOT=/mnt/backup GPG_RECIPIENT=admin@example.com $0 backup
EOF
}

check_dependencies() {
    command -v rsync >/dev/null || error "rsync not found"
    command -v tar >/dev/null || error "tar not found"
    if [[ "$COMPRESS" == "true" ]]; then
        command -v gzip >/dev/null || error "gzip not found"
    fi
    if [[ "$ENCRYPT" == "true" ]]; then
        command -v gpg >/dev/null || error "gpg not found"
        [[ -n "$GPG_RECIPIENT" ]] || error "GPG_RECIPIENT required for encryption"
    fi
}

create_backup_dir() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    BACKUP_NAME="spark-backup-$timestamp"
    BACKUP_DIR="$BACKUP_ROOT/$BACKUP_NAME"
    mkdir -p "$BACKUP_DIR"
    log "Creating backup: $BACKUP_NAME"
}

backup_xfs_data() {
    log "Backing up XFS data (ples_int4, kv_cache)..."
    rsync -aHAX --delete --info=progress2 \
        "$XFS_MOUNT/ples_int4/" "$BACKUP_DIR/ples_int4/" \
        || error "Failed to backup ples_int4"
    rsync -aHAX --delete --info=progress2 \
        "$XFS_MOUNT/kv_cache/" "$BACKUP_DIR/kv_cache/" \
        || error "Failed to backup kv_cache"
    log "XFS data backup complete"
}

backup_models() {
    log "Backing up models..."
    rsync -aHAX --delete --info=progress2 \
        "$MODELS_DIR/" "$BACKUP_DIR/models/" \
        || error "Failed to backup models"
    log "Models backup complete"
}

backup_config() {
    log "Backing up configuration..."
    rsync -aHAX --delete \
        "$PROJECT_DIR/" "$BACKUP_DIR/project/" \
        --exclude='*.log' --exclude='__pycache__' \
        || error "Failed to backup project config"
    
    # Backup systemd service
    if [[ -f /etc/systemd/system/spark-ai.service ]]; then
        cp /etc/systemd/system/spark-ai.service "$BACKUP_DIR/spark-ai.service"
    fi
    
    # Backup kernel params
    if [[ -f /etc/sysctl.d/99-spark-ai.conf ]]; then
        cp /etc/sysctl.d/99-spark-ai.conf "$BACKUP_DIR/99-spark-ai.conf"
    fi
    
    # Backup fstab entry
    grep spark_nvme /etc/fstab > "$BACKUP_DIR/fstab.entry" 2>/dev/null || true
    
    log "Configuration backup complete"
}

create_manifest() {
    log "Creating backup manifest..."
    cat > "$BACKUP_DIR/MANIFEST.txt" <<EOF
Spark DGX AI Stack Backup
=========================
Timestamp: $(date -Iseconds)
Hostname: $(hostname)
Backup Name: $BACKUP_NAME
Backup Root: $BACKUP_ROOT

Contents:
$(find "$BACKUP_DIR" -type f -printf "%s\t%p\n" | sort -k2)

Sizes:
$(du -sh "$BACKUP_DIR"/* 2>/dev/null | sort -h)

Git Commit: $(cd "$PROJECT_DIR" && git rev-parse HEAD 2>/dev/null || echo "N/A")
Git Status: $(cd "$PROJECT_DIR" && git status --short 2>/dev/null || echo "N/A")

Docker Images:
$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep -E "(vllm|llm-d|router)" || echo "None found")

Disk Usage:
$(df -h "$XFS_MOUNT" "$MODELS_DIR" "$PROJECT_DIR")
EOF
    log "Manifest created"
}

compress_backup() {
    if [[ "$COMPRESS" == "true" ]]; then
        log "Compressing backup..."
        tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_ROOT" "$BACKUP_NAME"
        rm -rf "$BACKUP_DIR"
        BACKUP_DIR="$BACKUP_DIR.tar.gz"
        log "Compressed to $BACKUP_DIR"
    fi
}

encrypt_backup() {
    if [[ "$ENCRYPT" == "true" ]]; then
        log "Encrypting backup..."
        gpg --trust-model always --encrypt --recipient "$GPG_RECIPIENT" \
            --output "$BACKUP_DIR.gpg" "$BACKUP_DIR"
        rm -f "$BACKUP_DIR"
        BACKUP_DIR="$BACKUP_DIR.gpg"
        log "Encrypted to $BACKUP_DIR"
    fi
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_ROOT" -maxdepth 1 -name "spark-backup-*" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_ROOT" -maxdepth 1 -name "spark-backup-*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
    log "Cleanup complete"
}

cmd_backup() {
    check_dependencies
    create_backup_dir
    backup_xfs_data
    backup_models
    backup_config
    create_manifest
    compress_backup
    encrypt_backup
    cleanup_old_backups
    log "Backup completed: $BACKUP_DIR"
}

cmd_list() {
    log "Available backups in $BACKUP_ROOT:"
    if [[ -d "$BACKUP_ROOT" ]]; then
        find "$BACKUP_ROOT" -maxdepth 1 -name "spark-backup-*" \( -type f -o -type d \) | sort -r | while read -r backup; do
            name=$(basename "$backup")
            if [[ -f "$backup" ]]; then
                size=$(du -sh "$backup" | cut -f1)
                echo "  $name ($size) [compressed]"
            else
                size=$(du -sh "$backup" | cut -f1)
                echo "  $name ($size) [directory]"
            fi
            if [[ -f "$backup/MANIFEST.txt" ]]; then
                grep "Timestamp:" "$backup/MANIFEST.txt" | sed 's/^/    /'
            elif [[ -f "$backup.tar.gz/MANIFEST.txt" ]]; then
                tar -xzf "$backup.tar.gz" -O "$(basename "$backup")/MANIFEST.txt" 2>/dev/null | grep "Timestamp:" | sed 's/^/    /'
            fi
        done
    else
        warn "Backup directory does not exist: $BACKUP_ROOT"
    fi
}

cmd_restore() {
    local backup_name="${1:-}"
    [[ -n "$backup_name" ]] || error "Backup name required. Use '$0 list' to see available backups."
    
    local backup_path="$BACKUP_ROOT/$backup_name"
    [[ -e "$backup_path" ]] || error "Backup not found: $backup_path"
    
    check_dependencies
    
    # Decrypt if needed
    if [[ "$backup_path" == *.gpg ]]; then
        log "Decrypting backup..."
        gpg --decrypt --output "${backup_path%.gpg}" "$backup_path"
        backup_path="${backup_path%.gpg}"
    fi
    
    # Decompress if needed
    if [[ "$backup_path" == *.tar.gz ]]; then
        log "Decompressing backup..."
        tar -xzf "$backup_path" -C "$BACKUP_ROOT"
        backup_path="${backup_path%.tar.gz}"
    fi
    
    log "Restoring from $backup_path..."
    
    # Stop services first
    log "Stopping services..."
    systemctl stop spark-ai 2>/dev/null || true
    docker compose -p qwen-spark -f "$PROJECT_DIR/docker-compose.yaml" down 2>/dev/null || true
    
    # Restore XFS data
    log "Restoring XFS data..."
    rsync -aHAX --delete "$backup_path/ples_int4/" "$XFS_MOUNT/ples_int4/"
    rsync -aHAX --delete "$backup_path/kv_cache/" "$XFS_MOUNT/kv_cache/"
    
    # Restore models
    log "Restoring models..."
    rsync -aHAX --delete "$backup_path/models/" "$MODELS_DIR/"
    
    # Restore config
    log "Restoring configuration..."
    rsync -aHAX --delete "$backup_path/project/" "$PROJECT_DIR/"
    [[ -f "$backup_path/spark-ai.service" ]] && cp "$backup_path/spark-ai.service" /etc/systemd/system/
    [[ -f "$backup_path/99-spark-ai.conf" ]] && cp "$backup_path/99-spark-ai.conf" /etc/sysctl.d/
    [[ -f "$backup_path/fstab.entry" ]] && grep -v spark_nvme /etc/fstab > /etc/fstab.tmp && cat "$backup_path/fstab.entry" >> /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
    
    # Reload and restart
    log "Reloading systemd and restarting..."
    systemctl daemon-reload
    systemctl enable spark-ai
    systemctl start spark-ai
    
    log "Restore complete! Services restarting..."
    sleep 10
    curl -sf http://localhost:8000/health && log "vLLM healthy" || warn "vLLM health check failed"
    curl -sf http://localhost:8080/ready && log "Router ready" || warn "Router ready check failed"
}

main() {
    case "${1:-}" in
        backup) cmd_backup ;;
        list) cmd_list ;;
        restore) cmd_restore "${2:-}" ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"