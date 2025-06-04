#!/bin/bash

# === Unified Backup Module ===
# Centralized backup and restore functionality for all components
# Part of the Global Station Search modular architecture

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

# Backup settings (loaded from config)
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
MAX_BACKUPS_PER_TYPE="${MAX_BACKUPS_PER_TYPE:-10}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-false}"

# Backup directories
BACKUP_ROOT_DIR="$BACKUP_DIR"
CONFIG_BACKUP_DIR="$BACKUP_DIR/config_backups"
CACHE_BACKUP_DIR="$BACKUP_DIR/cache_backups"
SCRIPT_BACKUP_DIR="$BACKUP_DIR/script_backups"
EXPORT_BACKUP_DIR="$BACKUP_DIR/export_backups"
DISPATCHARR_BACKUP_DIR="$BACKUP_DIR/dispatcharr_backups"

# Backup log
BACKUP_LOG="$LOGS_DIR/backup_operations.log"

# ============================================================================
# INITIALIZATION
# ============================================================================

init_backup_system() {
    # Create backup directories
    local backup_dirs=(
        "$BACKUP_ROOT_DIR"
        "$CONFIG_BACKUP_DIR"
        "$CACHE_BACKUP_DIR"
        "$SCRIPT_BACKUP_DIR"
        "$EXPORT_BACKUP_DIR"
        "$DISPATCHARR_BACKUP_DIR"
    )
    
    for dir in "${backup_dirs[@]}"; do
        mkdir -p "$dir" || {
            log_backup_operation "ERROR" "Failed to create backup directory: $dir"
            return 1
        }
    done
    
    touch "$BACKUP_LOG"
    load_backup_config
    log_backup_operation "INFO" "Backup system initialized"
}

load_backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        BACKUP_ENABLED=$(grep "^BACKUP_ENABLED=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "true")
        BACKUP_RETENTION_DAYS=$(grep "^BACKUP_RETENTION_DAYS=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "30")
        MAX_BACKUPS_PER_TYPE=$(grep "^MAX_BACKUPS_PER_TYPE=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "10")
        BACKUP_COMPRESSION=$(grep "^BACKUP_COMPRESSION=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "false")
    fi
}

save_backup_config() {
    save_setting "BACKUP_ENABLED" "$BACKUP_ENABLED"
    save_setting "BACKUP_RETENTION_DAYS" "$BACKUP_RETENTION_DAYS"
    save_setting "MAX_BACKUPS_PER_TYPE" "$MAX_BACKUPS_PER_TYPE"
    save_setting "BACKUP_COMPRESSION" "$BACKUP_COMPRESSION"
}

# ============================================================================
# CORE BACKUP FUNCTIONS
# ============================================================================

create_backup() {
    local backup_type="$1"
    local source_path="$2"
    local backup_name="${3:-}"
    local description="${4:-}"
    
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        log_backup_operation "SKIP" "Backup disabled for $backup_type"
        return 1
    fi
    
    if [[ ! -e "$source_path" ]]; then
        log_backup_operation "ERROR" "Source path does not exist: $source_path"
        return 1
    fi
    
    # Determine backup directory based on type
    local backup_dir
    case "$backup_type" in
        "config")     backup_dir="$CONFIG_BACKUP_DIR" ;;
        "cache")      backup_dir="$CACHE_BACKUP_DIR" ;;
        "script")     backup_dir="$SCRIPT_BACKUP_DIR" ;;
        "export")     backup_dir="$EXPORT_BACKUP_DIR" ;;
        "dispatcharr") backup_dir="$DISPATCHARR_BACKUP_DIR" ;;
        *)            backup_dir="$BACKUP_ROOT_DIR" ;;
    esac
    
    # Generate backup filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local source_basename=$(basename "$source_path")
    
    if [[ -n "$backup_name" ]]; then
        local backup_filename="${backup_name}.${timestamp}"
    else
        local backup_filename="${source_basename}.backup.${timestamp}"
    fi
    
    local backup_path="${backup_dir}/${backup_filename}"
    
    # Perform backup based on source type
    local backup_success=false
    
    if [[ -f "$source_path" ]]; then
        # Single file backup
        if cp "$source_path" "$backup_path"; then
            backup_success=true
        fi
    elif [[ -d "$source_path" ]]; then
        # Directory backup
        if [[ "$BACKUP_COMPRESSION" == "true" ]] && command -v tar >/dev/null 2>&1; then
            # Compressed backup
            if tar -czf "${backup_path}.tar.gz" -C "$(dirname "$source_path")" "$(basename "$source_path")" 2>/dev/null; then
                backup_path="${backup_path}.tar.gz"
                backup_success=true
            fi
        else
            # Uncompressed directory copy
            if cp -r "$source_path" "$backup_path"; then
                backup_success=true
            fi
        fi
    fi
    
    if [[ "$backup_success" == "true" ]]; then
        # Create backup metadata
        create_backup_metadata "$backup_path" "$backup_type" "$source_path" "$description"
        
        # Cleanup old backups
        cleanup_old_backups "$backup_type" "$backup_dir"
        
        log_backup_operation "SUCCESS" "Created $backup_type backup: $(basename "$backup_path")"
        echo "$backup_path"
        return 0
    else
        log_backup_operation "ERROR" "Failed to create $backup_type backup from: $source_path"
        return 1
    fi
}

create_backup_metadata() {
    local backup_path="$1"
    local backup_type="$2"
    local source_path="$3"
    local description="$4"
    
    local metadata_file="${backup_path}.meta"
    local backup_size=$(du -h "$backup_path" 2>/dev/null | cut -f1 || echo "unknown")
    
    cat > "$metadata_file" << EOF
{
    "backup_type": "$backup_type",
    "source_path": "$source_path",
    "backup_path": "$backup_path",
    "timestamp": "$(date -Iseconds)",
    "size": "$backup_size",
    "description": "$description",
    "script_version": "$VERSION",
    "created_by": "backup_module"
}
EOF
}

restore_backup() {
    local backup_path="$1"
    local target_path="${2:-}"
    local force="${3:-false}"
    
    if [[ ! -e "$backup_path" ]]; then
        log_backup_operation "ERROR" "Backup file does not exist: $backup_path"
        return 1
    fi
    
    # Read metadata if available
    local metadata_file="${backup_path}.meta"
    local original_source=""
    
    if [[ -f "$metadata_file" ]]; then
        original_source=$(jq -r '.source_path // empty' "$metadata_file" 2>/dev/null)
    fi
    
    # Determine target path
    if [[ -z "$target_path" ]]; then
        if [[ -n "$original_source" ]]; then
            target_path="$original_source"
        else
            log_backup_operation "ERROR" "No target path specified and cannot determine from metadata"
            return 1
        fi
    fi
    
    # Check if target exists and prompt if not forced
    if [[ -e "$target_path" ]] && [[ "$force" != "true" ]]; then
        echo -e "${YELLOW}⚠️  Target exists: $target_path${RESET}"
        if ! confirm_action "Overwrite existing file/directory?"; then
            log_backup_operation "CANCELLED" "Restore cancelled by user: $backup_path"
            return 1
        fi
    fi
    
    # Perform restore
    local restore_success=false
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        # Compressed backup
        local target_dir=$(dirname "$target_path")
        if tar -xzf "$backup_path" -C "$target_dir" 2>/dev/null; then
            restore_success=true
        fi
    elif [[ -f "$backup_path" ]]; then
        # Single file restore
        if cp "$backup_path" "$target_path"; then
            restore_success=true
        fi
    elif [[ -d "$backup_path" ]]; then
        # Directory restore
        if cp -r "$backup_path" "$target_path"; then
            restore_success=true
        fi
    fi
    
    if [[ "$restore_success" == "true" ]]; then
        log_backup_operation "SUCCESS" "Restored backup: $(basename "$backup_path") -> $target_path"
        return 0
    else
        log_backup_operation "ERROR" "Failed to restore backup: $backup_path"
        return 1
    fi
}

# ============================================================================
# SPECIALIZED BACKUP FUNCTIONS
# ============================================================================

backup_configuration() {
    local description="${1:-Configuration backup}"
    local backup_files=()
    
    # Collect config files
    [[ -f "$CONFIG_FILE" ]] && backup_files+=("$CONFIG_FILE")
    [[ -f "$CSV_FILE" ]] && backup_files+=("$CSV_FILE")
    [[ -f "$VALID_CODES_FILE" ]] && backup_files+=("$VALID_CODES_FILE")
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_backup_operation "SKIP" "No configuration files to backup"
        return 1
    fi
    
    # Create temporary directory for config bundle
    local temp_dir="/tmp/config_backup_$$"
    mkdir -p "$temp_dir"
    
    # Copy all config files
    local success=true
    for file in "${backup_files[@]}"; do
        if ! cp "$file" "$temp_dir/"; then
            success=false
            break
        fi
    done
    
    if [[ "$success" == "true" ]]; then
        local backup_path=$(create_backup "config" "$temp_dir" "configuration" "$description")
        rm -rf "$temp_dir"
        echo "$backup_path"
        return 0
    else
        rm -rf "$temp_dir"
        return 1
    fi
}

backup_user_cache() {
    local description="${1:-User cache backup}"
    
    if [[ ! -f "$USER_STATIONS_JSON" ]] || [[ ! -s "$USER_STATIONS_JSON" ]]; then
        log_backup_operation "SKIP" "No user cache to backup"
        return 1
    fi
    
    create_backup "cache" "$USER_STATIONS_JSON" "user_cache" "$description"
}

backup_cache_state() {
    local description="${1:-Cache state backup}"
    
    # Create temporary directory for state bundle
    local temp_dir="/tmp/cache_state_backup_$$"
    mkdir -p "$temp_dir"
    
    local state_files=(
        "$CACHED_MARKETS"
        "$CACHED_LINEUPS"
        "$LINEUP_TO_MARKET"
        "$CACHE_STATE_LOG"
    )
    
    local copied_files=0
    for file in "${state_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$temp_dir/" && ((copied_files++))
        fi
    done
    
    if [[ $copied_files -gt 0 ]]; then
        local backup_path=$(create_backup "cache" "$temp_dir" "cache_state" "$description")
        rm -rf "$temp_dir"
        echo "$backup_path"
        return 0
    else
        rm -rf "$temp_dir"
        log_backup_operation "SKIP" "No cache state files to backup"
        return 1
    fi
}

backup_script_version() {
    local description="${1:-Script version backup}"
    local current_script=$(realpath "$0" 2>/dev/null || echo "$0")
    
    create_backup "script" "$current_script" "globalstationsearch.v${VERSION}" "$description"
}

backup_dispatcharr_data() {
    local description="${1:-Dispatcharr data backup}"
    
    # Create temporary directory for Dispatcharr bundle
    local temp_dir="/tmp/dispatcharr_backup_$$"
    mkdir -p "$temp_dir"
    
    local dispatcharr_files=(
        "$DISPATCHARR_CACHE"
        "$DISPATCHARR_MATCHES"
        "$DISPATCHARR_TOKENS"
        "$DISPATCHARR_LOGOS"
        "$DISPATCHARR_LOG"
    )
    
    local copied_files=0
    for file in "${dispatcharr_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$temp_dir/" && ((copied_files++))
        fi
    done
    
    if [[ $copied_files -gt 0 ]]; then
        local backup_path=$(create_backup "dispatcharr" "$temp_dir" "dispatcharr_data" "$description")
        rm -rf "$temp_dir"
        echo "$backup_path"
        return 0
    else
        rm -rf "$temp_dir"
        log_backup_operation "SKIP" "No Dispatcharr data to backup"
        return 1
    fi
}

# Legacy compatibility function (for existing main script calls)
backup_existing_data() {
    local description="${1:-Legacy backup - config and cache}"
    
    echo -e "${CYAN}📦 Creating comprehensive backup...${RESET}"
    
    local backup_paths=()
    local backup_count=0
    
    # Backup configuration
    if backup_path=$(backup_configuration "$description - Configuration"); then
        backup_paths+=("$backup_path")
        ((backup_count++))
        echo -e "${GREEN}✅ Configuration backed up${RESET}"
    fi
    
    # Backup user cache
    if backup_path=$(backup_user_cache "$description - User Cache"); then
        backup_paths+=("$backup_path")
        ((backup_count++))
        echo -e "${GREEN}✅ User cache backed up${RESET}"
    fi
    
    # Backup cache state
    if backup_path=$(backup_cache_state "$description - Cache State"); then
        backup_paths+=("$backup_path")
        ((backup_count++))
        echo -e "${GREEN}✅ Cache state backed up${RESET}"
    fi
    
    if [[ $backup_count -gt 0 ]]; then
        echo -e "${GREEN}✅ Created $backup_count backup(s)${RESET}"
        log_backup_operation "SUCCESS" "Legacy backup completed: $backup_count files"
        return 0
    else
        echo -e "${YELLOW}⚠️  No data found to backup${RESET}"
        log_backup_operation "SKIP" "Legacy backup: no data to backup"
        return 1
    fi
}

# ============================================================================
# BACKUP MANAGEMENT
# ============================================================================

list_backups() {
    local backup_type="${1:-all}"
    local show_details="${2:-false}"
    
    local backup_dirs=()
    
    case "$backup_type" in
        "config")     backup_dirs=("$CONFIG_BACKUP_DIR") ;;
        "cache")      backup_dirs=("$CACHE_BACKUP_DIR") ;;
        "script")     backup_dirs=("$SCRIPT_BACKUP_DIR") ;;
        "export")     backup_dirs=("$EXPORT_BACKUP_DIR") ;;
        "dispatcharr") backup_dirs=("$DISPATCHARR_BACKUP_DIR") ;;
        "all")        backup_dirs=("$CONFIG_BACKUP_DIR" "$CACHE_BACKUP_DIR" "$SCRIPT_BACKUP_DIR" "$EXPORT_BACKUP_DIR" "$DISPATCHARR_BACKUP_DIR") ;;
        *)            echo -e "${RED}❌ Invalid backup type: $backup_type${RESET}"; return 1 ;;
    esac
    
    local found_backups=false
    
    for backup_dir in "${backup_dirs[@]}"; do
        if [[ ! -d "$backup_dir" ]]; then
            continue
        fi
        
        local backups=($(find "$backup_dir" -maxdepth 1 -type f \( -name "*.backup.*" -o -name "*.tar.gz" \) | sort -r))
        
        if [[ ${#backups[@]} -gt 0 ]]; then
            found_backups=true
            local dir_type=$(basename "$backup_dir" | sed 's/_backup_dir//')
            echo -e "${BOLD}${BLUE}${dir_type^} Backups:${RESET}"
            
            for backup in "${backups[@]}"; do
                local backup_name=$(basename "$backup")
                local backup_date=$(ls -l "$backup" 2>/dev/null | awk '{print $6, $7, $8}')
                local backup_size=$(ls -lh "$backup" 2>/dev/null | awk '{print $5}')
                
                echo -e "${GREEN}• $backup_name${RESET}"
                
                if [[ "$show_details" == "true" ]]; then
                    echo -e "  Date: $backup_date | Size: $backup_size"
                    
                    # Show metadata if available
                    local metadata_file="${backup}.meta"
                    if [[ -f "$metadata_file" ]]; then
                        local description=$(jq -r '.description // empty' "$metadata_file" 2>/dev/null)
                        [[ -n "$description" ]] && echo -e "  Description: $description"
                    fi
                fi
            done
            echo
        fi
    done
    
    if [[ "$found_backups" == "false" ]]; then
        echo -e "${YELLOW}⚠️  No backups found for type: $backup_type${RESET}"
        return 1
    fi
    
    return 0
}

cleanup_old_backups() {
    local backup_type="$1"
    local backup_dir="$2"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi
    
    # Remove backups older than retention period
    if [[ "$BACKUP_RETENTION_DAYS" -gt 0 ]]; then
        find "$backup_dir" -name "*.backup.*" -o -name "*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null
        find "$backup_dir" -name "*.meta" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null
    fi
    
    # Limit number of backups per type
    if [[ "$MAX_BACKUPS_PER_TYPE" -gt 0 ]]; then
        local backups=($(find "$backup_dir" -maxdepth 1 -type f \( -name "*.backup.*" -o -name "*.tar.gz" \) | sort -r))
        
        if [[ ${#backups[@]} -gt $MAX_BACKUPS_PER_TYPE ]]; then
            local excess_count=$((${#backups[@]} - MAX_BACKUPS_PER_TYPE))
            
            for ((i=${#backups[@]}-excess_count; i<${#backups[@]}; i++)); do
                rm -f "${backups[$i]}" "${backups[$i]}.meta" 2>/dev/null
            done
            
            log_backup_operation "CLEANUP" "Removed $excess_count old $backup_type backups"
        fi
    fi
}

get_backup_stats() {
    local stats_json="{"
    
    for backup_type in "config" "cache" "script" "export" "dispatcharr"; do
        local backup_dir_var="${backup_type^^}_BACKUP_DIR"
        local backup_dir="${!backup_dir_var}"
        
        if [[ -d "$backup_dir" ]]; then
            local count=$(find "$backup_dir" -maxdepth 1 -type f \( -name "*.backup.*" -o -name "*.tar.gz" \) | wc -l)
            local size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "0")
            
            stats_json+='"'$backup_type'": {"count": '$count', "size": "'$size'"},'
        fi
    done
    
    # Remove trailing comma and close JSON
    stats_json="${stats_json%,}}"
    
    echo "$stats_json"
}

# ============================================================================
# BACKUP INTERFACE
# ============================================================================

show_backup_management_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== Backup Management ===${RESET}\n"
        
        # Show backup statistics
        show_backup_status
        
        echo -e "${BOLD}${CYAN}Backup Options:${RESET}"
        echo -e "${GREEN}a)${RESET} Create Manual Backup"
        echo -e "${GREEN}b)${RESET} List All Backups"
        echo -e "${GREEN}c)${RESET} Restore from Backup"
        echo -e "${GREEN}d)${RESET} Configure Backup Settings"
        echo -e "${GREEN}e)${RESET} Cleanup Old Backups"
        echo -e "${GREEN}f)${RESET} View Backup Statistics"
        echo -e "${GREEN}q)${RESET} Back to Previous Menu"
        echo
        
        read -p "Select option: " choice
        
        case $choice in
            a|A) create_manual_backup ;;
            b|B) list_backups "all" "true" && pause_for_user ;;
            c|C) restore_from_backup_menu ;;
            d|D) configure_backup_settings ;;
            e|E) cleanup_backups_menu ;;
            f|F) show_detailed_backup_stats && pause_for_user ;;
            q|Q|"") break ;;
            *) echo -e "${RED}❌ Invalid option${RESET}"; sleep 1 ;;
        esac
    done
}

show_backup_status() {
    echo -e "${BOLD}${BLUE}Backup System Status:${RESET}"
    echo -e "${CYAN}Backup Enabled: $([ "$BACKUP_ENABLED" == "true" ] && echo "${GREEN}Yes${RESET}" || echo "${RED}No${RESET}")${RESET}"
    echo -e "${CYAN}Retention Period: ${BOLD}$BACKUP_RETENTION_DAYS days${RESET}"
    echo -e "${CYAN}Max Backups per Type: ${BOLD}$MAX_BACKUPS_PER_TYPE${RESET}"
    echo -e "${CYAN}Compression: $([ "$BACKUP_COMPRESSION" == "true" ] && echo "${GREEN}Enabled${RESET}" || echo "${YELLOW}Disabled${RESET}")${RESET}"
    echo
    
    # Quick backup counts
    local total_backups=0
    for backup_type in "config" "cache" "script" "export" "dispatcharr"; do
        local backup_dir_var="${backup_type^^}_BACKUP_DIR"
        local backup_dir="${!backup_dir_var}"
        
        if [[ -d "$backup_dir" ]]; then
            local count=$(find "$backup_dir" -maxdepth 1 -type f \( -name "*.backup.*" -o -name "*.tar.gz" \) | wc -l)
            if [[ $count -gt 0 ]]; then
                echo -e "${CYAN}$backup_type backups: ${GREEN}$count${RESET}"
                ((total_backups += count))
            fi
        fi
    done
    
    echo -e "${CYAN}Total backups: ${BOLD}$total_backups${RESET}"
    echo
}

# ============================================================================
# LOGGING
# ============================================================================

log_backup_operation() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$BACKUP_LOG"
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize backup system when module is loaded
init_backup_system