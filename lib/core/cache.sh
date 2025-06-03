#!/bin/bash
# lib/core/cache.sh - Cache Management Module
# Extracted from Global Station Search v1.4.0
# Core cache operations, station management, and data processing

# ============================================================================
# CACHE INITIALIZATION AND SETUP
# ============================================================================

init_combined_cache_startup() {
  # Build combined cache if both base and user caches exist
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ] && 
     [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    local base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    
    # Check if we can skip the rebuild using persistent state
    if check_combined_cache_freshness; then
      echo -e "${GREEN}✅ Station database ready (using cached version)${RESET}"
    else
      echo -e "${CYAN}🔄 Building combined station database...${RESET}"
      echo -e "${CYAN}💡 Merging $base_count base stations + $user_count user stations${RESET}"
      echo -e "${CYAN}💡 This may take a moment for large datasets...${RESET}"
      build_combined_cache_with_progress >/dev/null
    fi
  elif [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    # Only base cache exists
    echo -e "${GREEN}✅ Station database ready (base cache only)${RESET}"
  elif [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    # Only user cache exists
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Station database ready ($user_count user stations)${RESET}"
  fi
}

init_user_cache() {
  if [ ! -f "$USER_STATIONS_JSON" ]; then
    echo '[]' > "$USER_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty user stations cache${RESET}" >&2
  fi
}

setup_optimized_cache() {
  # Initialize cache validity checking
  COMBINED_CACHE_VALID=false
  COMBINED_CACHE_TIMESTAMP=0
  
  # Pre-build combined cache if it will be needed and is significant
  init_combined_cache_startup
}

# ============================================================================
# CACHE CLEANUP AND MAINTENANCE
# ============================================================================

cleanup_cache() {
  echo -e "${YELLOW}Cleaning up cached station files...${RESET}"
  
  # IMPORTANT: Create backup before cleanup if user cache exists
  if [[ -f "$USER_STATIONS_JSON" ]] && [[ -s "$USER_STATIONS_JSON" ]]; then
    backup_existing_data
    echo "  ✓ User cache backed up before cleanup"
  fi
  
  # Remove station cache files
  if [ -d "$STATION_CACHE_DIR" ]; then
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    echo "  ✓ Station cache files removed"
  fi
  
  # Remove raw API response files
  rm -f "$CACHE_DIR"/last_raw_*.json 2>/dev/null || true
  echo "  ✓ Raw API response files removed"
  
  # Remove temporary files
  rm -f "$CACHE_DIR"/*.tmp 2>/dev/null || true
  echo "  ✓ Temporary files removed"

  # Remove API search results
  rm -f "$API_SEARCH_RESULTS" 2>/dev/null || true
  echo "  ✓ API search results removed"
  
  # Remove combined cache files
  cleanup_combined_cache
  echo "  ✓ Combined cache files removed"
  
  # Remove legacy master JSON files (all variants)
  rm -f "$CACHE_DIR"/all_stations_master.json* 2>/dev/null || true
  rm -f "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  echo "  ✓ Legacy cache files removed"
  
  # Remove lineup cache (will be rebuilt)
  rm -f "$LINEUP_CACHE" 2>/dev/null || true
  echo "  ✓ Lineup cache removed"
  
  # CRITICAL: PRESERVE these important files:
  # - $BASE_STATIONS_JSON (distributed base cache)
  # - $USER_STATIONS_JSON (user's personal cache) - BACKED UP ABOVE
  # - $BASE_CACHE_MANIFEST (base cache manifest)
  # - $CACHED_MARKETS (state tracking)
  # - $CACHED_LINEUPS (state tracking)
  # - $LINEUP_TO_MARKET (state tracking)
  # - $CACHE_STATE_LOG (state tracking)
  # - $DISPATCHARR_* files (Dispatcharr integration)
  
  echo "  ✓ User cache, base cache, manifest, and state tracking files preserved"
  echo -e "${GREEN}Cache cleanup completed (important files preserved and backed up)${RESET}"
}

invalidate_combined_cache() {
  COMBINED_CACHE_VALID=false
  cleanup_combined_cache
  
  # Remove saved state from config file
  if [ -f "$CONFIG_FILE" ]; then
    local temp_config="${CONFIG_FILE}.tmp"
    grep -v -E '^COMBINED_CACHE_TIMESTAMP=|^COMBINED_CACHE_BASE_TIME=|^COMBINED_CACHE_USER_TIME=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null
    mv "$temp_config" "$CONFIG_FILE"
  fi
}

mark_user_cache_updated() {
  invalidate_combined_cache
  echo -e "${CYAN}💡 Station database will be refreshed on next search${RESET}"
}

# ============================================================================
# COMBINED CACHE MANAGEMENT
# ============================================================================

init_combined_cache_startup() {
  # Build combined cache if both base and user caches exist
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ] && 
     [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    local base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
    
    # Check if we can skip the rebuild using persistent state
    if check_combined_cache_freshness; then
      echo -e "${GREEN}✅ Station database ready (using cached version)${RESET}"
    else
      echo -e "${CYAN}🔄 Building combined station database...${RESET}"
      echo -e "${CYAN}💡 Merging $base_count base stations + $user_count user stations${RESET}"
      echo -e "${CYAN}💡 This may take a moment for large datasets...${RESET}"
      build_combined_cache_with_progress # Show the progress output
    fi
  elif [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    # Only base cache exists
    echo -e "${GREEN}✅ Station database ready (base cache only)${RESET}"
  elif [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    # Only user cache exists
    local user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Station database ready ($user_count user stations)${RESET}"
  fi
}

build_combined_cache_with_progress() {
  echo -e "${CYAN}🔄 Building station database (3 steps)...${RESET}" >&2
  
  # Step 1: Analyze
  echo -e "${CYAN}📊 [1/3] Analyzing source databases...${RESET}" >&2
  local base_count=$([ -f "$BASE_STATIONS_JSON" ] && jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  local user_count=$([ -f "$USER_STATIONS_JSON" ] && jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  echo -e "${CYAN}   Base: $base_count stations, User: $user_count stations${RESET}" >&2
  
  # Step 2: Merge (with spinner)
  echo -e "${CYAN}🔄 [2/3] Merging and deduplicating...${RESET}" >&2
  
  # Do the actual work in background with spinner
  jq -s 'flatten | unique_by(.stationId) | sort_by(.name // "")' \
    "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" > "$COMBINED_STATIONS_JSON" &
  
  local merge_pid=$!
  local spin='-\|/'
  local i=0
  while kill -0 $merge_pid 2>/dev/null; do
    i=$(((i+1)%4))
    printf "\r${CYAN}🔄 [2/3] Merging and deduplicating ${spin:$i:1}${RESET}" >&2
    sleep 0.3
  done
  
  wait $merge_pid
  
  # Step 3: Finalize
  echo -e "\n${CYAN}💾 [3/3] Finalizing database...${RESET}" >&2
  local final_count=$(jq 'length' "$COMBINED_STATIONS_JSON" 2>/dev/null || echo "0")
  
  echo -e "${GREEN}✅ Database ready: $final_count total stations${RESET}" >&2
  
  # Save state and return
  save_combined_cache_state "$(date +%s)" \
    "$(stat -c %Y "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")" \
    "$(stat -c %Y "$USER_STATIONS_JSON" 2>/dev/null || echo "0")"
  
  COMBINED_CACHE_VALID=true
  return 0
}

get_effective_stations_file() {
  # If no user stations exist, check for base stations
  if [ ! -f "$USER_STATIONS_JSON" ] || [ ! -s "$USER_STATIONS_JSON" ]; then
    if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
      echo "$BASE_STATIONS_JSON"
      return 0
    else
      return 1  # No stations available
    fi
  fi
  
  # If no base stations, use user only
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    echo "$USER_STATIONS_JSON"
    return 0
  fi
  
  # Both base and user exist - need combined file
  # Check if combined cache is fresh
  if check_combined_cache_freshness; then
    # Cache is valid, use it
    echo "$COMBINED_STATIONS_JSON"
    return 0
  else
    # Cache needs rebuilding
    if build_combined_cache_with_progress; then
      echo "$COMBINED_STATIONS_JSON"
      return 0
    else
      # Fallback to user cache if merge fails
      echo -e "${YELLOW}⚠️  Using user cache only due to merge failure${RESET}" >&2
      echo "$USER_STATIONS_JSON"
      return 0
    fi
  fi
}

# ============================================================================
# USER CACHE MANAGEMENT
# ============================================================================

add_stations_to_user_cache() {
  local new_stations_file="$1"
  
  echo -e "${CYAN}🔄 Starting user cache integration process...${RESET}"
  
  # File validation with detailed feedback
  if [ ! -f "$new_stations_file" ]; then
    echo -e "${RED}❌ File Validation: New stations file not found${RESET}"
    echo -e "${CYAN}💡 Expected file: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 Check if caching process completed successfully${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔍 Validating new stations file format...${RESET}"
  if ! jq empty "$new_stations_file" 2>/dev/null; then
    echo -e "${RED}❌ File Validation: New stations file contains invalid JSON${RESET}"
    echo -e "${CYAN}💡 File: $new_stations_file${RESET}"
    echo -e "${CYAN}💡 File may be corrupted or incomplete${RESET}"
    echo -e "${CYAN}💡 Try running User Cache Expansion again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ New stations file validation passed${RESET}"
  
  # Initialize user cache with feedback
  echo -e "${CYAN}🔄 Initializing user cache environment...${RESET}"
  init_user_cache
  
  # Validate user cache file with comprehensive error handling
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}🔍 Validating existing user cache...${RESET}"
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ User Cache Validation: Existing cache file is corrupted${RESET}"
      echo -e "${CYAN}💡 File: $USER_STATIONS_JSON${RESET}"
      echo -e "${CYAN}💡 Backing up corrupted file and creating fresh cache${RESET}"
      
      # Backup corrupted file with feedback
      local backup_file="${USER_STATIONS_JSON}.corrupted.$(date +%Y%m%d_%H%M%S)"
      echo -e "${CYAN}💾 Creating backup of corrupted cache...${RESET}"
      if mv "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}✅ Corrupted file backed up to: $(basename "$backup_file")${RESET}"
      else
        echo -e "${RED}❌ Backup Operation: Cannot backup corrupted cache file${RESET}"
        echo -e "${CYAN}💡 Check file permissions in cache directory${RESET}"
        return 1
      fi
      
      # Initialize fresh cache with feedback
      echo -e "${CYAN}🔄 Creating fresh user cache...${RESET}"
      echo '[]' > "$USER_STATIONS_JSON" || {
        echo -e "${RED}❌ Cache Creation: Cannot create new user cache file${RESET}"
        echo -e "${CYAN}💡 Check disk space and file permissions${RESET}"
        echo -e "${CYAN}💡 Directory: $(dirname "$USER_STATIONS_JSON")${RESET}"
        return 1
      }
      echo -e "${GREEN}✅ Fresh user cache created successfully${RESET}"
    else
      echo -e "${GREEN}✅ Existing user cache validation passed${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  No existing user cache found - will create new one${RESET}"
  fi
  
  echo -e "${CYAN}📊 Preparing to merge new stations with user cache...${RESET}"
  
  # Create temporary file with feedback
  local temp_file="$USER_STATIONS_JSON.tmp.$(date +%s)"
  
  # Check disk space with detailed feedback
  echo -e "${CYAN}🔍 Checking available disk space...${RESET}"
  local new_stations_size=$(stat -c%s "$new_stations_file" 2>/dev/null || stat -f%z "$new_stations_file" 2>/dev/null || echo "0")
  local user_cache_size=$(stat -c%s "$USER_STATIONS_JSON" 2>/dev/null || stat -f%z "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  local estimated_size=$((new_stations_size + user_cache_size + 1048576))  # Add 1MB buffer
  
  # Check available disk space (rough estimate)
  local available_space=$(df "$(dirname "$USER_STATIONS_JSON")" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo "999999999999")
  
  # Convert scientific notation to integer if needed
  if [[ "$available_space" == *"e+"* ]] || [[ "$available_space" == *"E+"* ]]; then
    # Use printf to convert scientific notation to integer
    available_space=$(printf "%.0f" "$available_space" 2>/dev/null || echo "999999999999")
  fi
  
  # Ensure we have a valid integer
  if ! [[ "$available_space" =~ ^[0-9]+$ ]]; then
    available_space="999999999999"  # Default to large number if parsing fails
  fi
  
  if [[ $estimated_size -gt $available_space ]]; then
    echo -e "${RED}❌ Disk Space Check: Insufficient disk space for merge operation${RESET}"
    echo -e "${CYAN}💡 Estimated space needed: $(( estimated_size / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Available space: $(( available_space / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Free up disk space and try again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ Sufficient disk space available for merge${RESET}"
  
  # Perform merge with detailed progress
  echo -e "${CYAN}🔄 Merging station data (deduplication and sorting)...${RESET}"
  echo -e "${CYAN}💡 This may take a moment for large datasets${RESET}"
  
  if ! jq -s 'flatten | unique_by(.stationId) | sort_by(.name // "")' \
    "$USER_STATIONS_JSON" "$new_stations_file" > "$temp_file" 2>/dev/null; then
    
    echo -e "${RED}❌ Merge Operation: Failed to merge station data${RESET}"
    echo -e "${CYAN}💡 This could be due to:${RESET}"
    echo -e "${CYAN}  • Insufficient memory for large datasets${RESET}"
    echo -e "${CYAN}  • Disk I/O errors or corruption${RESET}"
    echo -e "${CYAN}  • Invalid JSON data in source files${RESET}"
    echo -e "${CYAN}💡 Try running User Cache Expansion with fewer markets${RESET}"
    
    # Clean up temp file
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  echo -e "${GREEN}✅ Station data merge completed successfully${RESET}"
  
  # Validate merged result with feedback
  echo -e "${CYAN}🔍 Validating merged station data...${RESET}"
  if ! jq empty "$temp_file" 2>/dev/null; then
    echo -e "${RED}❌ Merge Validation: Merge produced invalid JSON${RESET}"
    echo -e "${CYAN}💡 Merge operation failed - keeping original cache${RESET}"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  echo -e "${GREEN}✅ Merged data validation passed${RESET}"
  
  # Backup original cache with feedback
  if [ -s "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}💾 Creating backup of current user cache...${RESET}"
    local backup_file="${USER_STATIONS_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  Backup Warning: Could not create safety backup${RESET}"
      echo -e "${CYAN}💡 Continuing without backup (original cache will be overwritten)${RESET}"
      
      if ! confirm_action "Continue without backup?"; then
        echo -e "${YELLOW}⚠️  User cache merge cancelled by user${RESET}"
        rm -f "$temp_file" 2>/dev/null
        return 1
      fi
    else
      echo -e "${GREEN}✅ Safety backup created: $(basename "$backup_file")${RESET}"
    fi
  fi
  
  # Replace original with merged data
  echo -e "${CYAN}💾 Finalizing user cache update...${RESET}"
  if ! mv "$temp_file" "$USER_STATIONS_JSON" 2>/dev/null; then
    echo -e "${RED}❌ Cache Update: Cannot finalize user cache file${RESET}"
    echo -e "${CYAN}💡 Check file permissions: $USER_STATIONS_JSON${RESET}"
    echo -e "${CYAN}💡 Check disk space and try again${RESET}"
    
    # Try to restore from backup if it exists
    local latest_backup=$(ls -t "${USER_STATIONS_JSON}.backup."* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
      echo -e "${CYAN}🔄 Attempting to restore from backup...${RESET}"
      if cp "$latest_backup" "$USER_STATIONS_JSON" 2>/dev/null; then
        echo -e "${GREEN}✅ User cache restored from backup${RESET}"
      fi
    fi
    
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  
  # Success validation and reporting
  echo -e "${CYAN}🔍 Validating final user cache...${RESET}"
  local new_count
  if new_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null); then
    echo -e "${GREEN}✅ User cache integration completed successfully${RESET}"
    echo -e "${CYAN}📊 Total stations in user cache: $new_count${RESET}"
    
    # Cleanup old backups with feedback
    echo -e "${CYAN}🧹 Cleaning up old backup files...${RESET}"
    local backup_pattern="${USER_STATIONS_JSON}.backup.*"
    local backup_count=$(ls -1 $backup_pattern 2>/dev/null | wc -l)
    if [[ $backup_count -gt 5 ]]; then
      ls -t $backup_pattern 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
      echo -e "${GREEN}✅ Cleaned up old backup files (kept 5 most recent)${RESET}"
    else
      echo -e "${CYAN}💡 Backup file count within limits ($backup_count kept)${RESET}"
    fi
    
    mark_user_cache_updated

    # Immediately rebuild combined cache
    echo -e "${CYAN}🔄 Rebuilding combined cache with new stations...${RESET}"
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt and ready${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache will rebuild on next access${RESET}"
    fi
      
    return 0
  fi
}

# ============================================================================
# DATA BACKUP AND RECOVERY
# ============================================================================

backup_existing_data() {
  echo -e "${CYAN}🔄 Creating comprehensive backup of existing user data...${RESET}"
  
  # Ensure backup directory exists
  if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    echo -e "${RED}❌ Backup System: Cannot create backup directory${RESET}"
    echo -e "${CYAN}💡 Directory: $BACKUP_DIR${RESET}"
    echo -e "${CYAN}💡 Check file permissions and disk space${RESET}"
    return 1
  fi
  
  local backup_created=false
  local backup_errors=0
  local files_processed=0
  
  # Critical files to backup
  local critical_files=(
    "$USER_STATIONS_JSON:user_stations_cache:User Station Database"
    "$BASE_STATIONS_JSON:base_stations_cache:Base Station Database" 
    "$BASE_CACHE_MANIFEST:base_cache_manifest:Base Cache Manifest"
    "$CACHED_MARKETS:cached_markets:Market Processing State"
    "$CACHED_LINEUPS:cached_lineups:Lineup Processing State"
    "$LINEUP_TO_MARKET:lineup_to_market:Lineup-to-Market Mapping"
    "$CSV_FILE:sampled_markets:Market Configuration"
    "$CACHE_STATE_LOG:cache_state_log:Cache Processing Log"
  )
  
  local total_files=${#critical_files[@]}
  echo -e "${CYAN}📊 Preparing to backup $total_files critical files...${RESET}"
  
  for file_info in "${critical_files[@]}"; do
    IFS=':' read -r file_path file_desc file_name <<< "$file_info"
    ((files_processed++))
    
    if [ -f "$file_path" ] && [ -s "$file_path" ]; then
      echo -e "${CYAN}📁 [$files_processed/$total_files] Backing up $file_name...${RESET}"
      
      # Create timestamped backup
      local timestamp=$(date +%Y%m%d_%H%M%S)
      local backup_name="${file_desc}.backup.$timestamp"
      local backup_path="$BACKUP_DIR/$backup_name"
      
      # Check file size before backup
      local source_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null || echo "0")
      local available_space=$(df "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo "999999999999")
      
      if [[ $source_size -gt $available_space ]]; then
        echo -e "${RED}❌ Backup System: Insufficient disk space for $file_name${RESET}"
        echo -e "${CYAN}💡 File size: $(( source_size / 1048576 )) MB, Available: $(( available_space / 1048576 )) MB${RESET}"
        ((backup_errors++))
        continue
      fi
      
      # Validate JSON files before backup (skip CSV and log files)
      if [[ "$file_path" == *.json* ]]; then
        if ! jq empty "$file_path" 2>/dev/null; then
          echo -e "${YELLOW}⚠️  Data Validation: $file_name contains invalid JSON${RESET}"
          echo -e "${CYAN}💡 Backing up anyway for recovery purposes${RESET}"
        fi
      fi
      
      # Perform backup with progress feedback
      if cp "$file_path" "$backup_path" 2>/dev/null; then
        # Validate backup was created successfully
        if [ -f "$backup_path" ] && [ -s "$backup_path" ]; then
          local backup_size=$(stat -c%s "$backup_path" 2>/dev/null || stat -f%z "$backup_path" 2>/dev/null || echo "0")
          
          if [[ $backup_size -eq $source_size ]]; then
            # Additional validation for JSON files
            if [[ "$file_path" == *.json* ]]; then
              if jq empty "$backup_path" 2>/dev/null; then
                echo -e "${GREEN}✅ $file_name backed up successfully ($(( backup_size / 1024 )) KB)${RESET}"
                backup_created=true
              else
                echo -e "${YELLOW}⚠️  $file_name backup created but contains invalid JSON${RESET}"
                backup_created=true  # Still counts as backup attempt
              fi
            else
              # Non-JSON files (CSV, log files)
              echo -e "${GREEN}✅ $file_name backed up successfully ($(( backup_size / 1024 )) KB)${RESET}"
              backup_created=true
            fi
          else
            echo -e "${RED}❌ Backup System: $file_name backup size mismatch${RESET}"
            echo -e "${CYAN}💡 Source: $(( source_size / 1024 )) KB, Backup: $(( backup_size / 1024 )) KB${RESET}"
            ((backup_errors++))
          fi
        else
          echo -e "${RED}❌ Backup System: $file_name backup file not created or empty${RESET}"
          ((backup_errors++))
        fi
      else
        echo -e "${RED}❌ Backup System: Cannot backup $file_name${RESET}"
        echo -e "${CYAN}💡 Source: $file_path${RESET}"
        echo -e "${CYAN}💡 Target: $backup_path${RESET}"
        echo -e "${CYAN}💡 Check file permissions and disk space${RESET}"
        ((backup_errors++))
      fi
    else
      echo -e "${CYAN}💡 [$files_processed/$total_files] $file_name not found or empty - skipping${RESET}"
    fi
  done
  
  # Clean up old backups for each file type (keep last 5 of each)
  echo -e "${CYAN}🧹 Cleaning up old backup files...${RESET}"
  local backup_patterns=(
    "user_stations_cache.backup.*"
    "base_stations_cache.backup.*"
    "base_cache_manifest.backup.*"
    "cached_markets.backup.*"
    "cached_lineups.backup.*"
    "lineup_to_market.backup.*"
    "sampled_markets.backup.*"
    "cache_state_log.backup.*"
  )
  
  local total_cleaned=0
  for pattern in "${backup_patterns[@]}"; do
    local old_backups=($(ls -t "$BACKUP_DIR"/$pattern 2>/dev/null | tail -n +6))
    if [[ ${#old_backups[@]} -gt 0 ]]; then
      echo -e "${CYAN}🧹 Cleaning ${#old_backups[@]} old backups for $(echo "$pattern" | cut -d'.' -f1)${RESET}"
      rm -f "${old_backups[@]}" 2>/dev/null || true
      total_cleaned=$((total_cleaned + ${#old_backups[@]}))
    fi
  done
  
  if [[ $total_cleaned -gt 0 ]]; then
    echo -e "${GREEN}✅ Cleaned up $total_cleaned old backup files${RESET}"
  fi
  
  # Report backup summary with clear status
  echo
  if [[ $backup_created == true && $backup_errors -eq 0 ]]; then
    echo -e "${GREEN}✅ Data backup completed successfully${RESET}"
    echo -e "${CYAN}💡 Backup location: $BACKUP_DIR${RESET}"
    echo -e "${CYAN}💡 All critical files have been safely backed up${RESET}"
    return 0
  elif [[ $backup_created == true && $backup_errors -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Data backup completed with $backup_errors errors${RESET}"
    echo -e "${CYAN}💡 Some files backed up successfully, others failed${RESET}"
    echo -e "${CYAN}💡 Check disk space and file permissions for failed backups${RESET}"
    echo -e "${CYAN}💡 Backup location: $BACKUP_DIR${RESET}"
    return 1
  else
    echo -e "${RED}❌ Data backup failed${RESET}"
    echo -e "${CYAN}💡 No backups were created successfully${RESET}"
    echo -e "${CYAN}💡 Check backup directory permissions and available disk space${RESET}"
    echo -e "${CYAN}💡 Directory: $BACKUP_DIR${RESET}"
    return 1
  fi
}

# ============================================================================
# STATION DATA PROCESSING
# ============================================================================

enhance_stations() {
  local start_time="$1"
  local stations_file="$2"  # The file to enhance (passed as parameter)
  
  echo -e "${CYAN}🔄 Starting station data enhancement process...${RESET}" >&2
  local tmp_json="$CACHE_DIR/enhancement_tmp_$(date +%s).json"
  > "$tmp_json"

  # Check if stations file exists and has content
  if [ ! -f "$stations_file" ]; then
    echo -e "${RED}❌ Stations file not found: $stations_file${RESET}" >&2
    echo "0"  # Return 0 enhanced stations
    return 1
  fi

  local total_stations
  total_stations=$(jq 'length' "$stations_file" 2>/dev/null)
  if [ -z "$total_stations" ] || [ "$total_stations" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No stations found in file: $stations_file${RESET}" >&2
    echo -e "${CYAN}💡 This suggests the station collection process didn't work properly${RESET}" >&2
    echo "0"  # Return 0 enhanced stations
    return 0
  fi

  mapfile -t stations < <(jq -c '.[]' "$stations_file")
  local actual_stations=${#stations[@]}
  local enhanced_from_api=0

  echo -e "${CYAN}📊 Processing $actual_stations stations for enhancement...${RESET}" >&2
  
  for ((i = 0; i < actual_stations; i++)); do
    local station="${stations[$i]}"
    local current=$((i + 1))
    local percent=$((current * 100 / actual_stations))
    
    # Show progress bar BEFORE processing (only if more than 10 stations)
    if [ "$actual_stations" -gt 10 ]; then
      show_progress_bar "$current" "$actual_stations" "$percent" "$start_time"
    fi

    local callSign=$(echo "$station" | jq -r '.callSign // empty')
    local name=$(echo "$station" | jq -r '.name // empty')
    
    # Only enhance if station has callsign but missing name AND server is configured
    if [[ -n "$callSign" && "$callSign" != "null" && ( -z "$name" || "$name" == "null" ) && -n "${CHANNELS_URL:-}" ]]; then
      local api_response=$(curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL/tms/stations/$callSign" 2>/dev/null)
      local current_station_id=$(echo "$station" | jq -r '.stationId')
      local station_info=$(echo "$api_response" | jq -c --arg id "$current_station_id" '.[] | select(.stationId == $id) // empty' 2>/dev/null)
      
      if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
        if echo "$station_info" | jq empty 2>/dev/null; then
          station=$(echo "$station" "$station_info" | jq -s '.[0] * .[1]' 2>/dev/null)
          ((enhanced_from_api++))
        fi
      fi
    fi

    echo "$station" >> "$tmp_json"
  done
  
  # Clear progress line only if it was shown
  if [ "$actual_stations" -gt 10 ]; then
    echo >&2
  fi
  
  echo -e "${GREEN}✅ Station enhancement completed successfully${RESET}" >&2
  echo -e "${CYAN}📊 Enhanced $enhanced_from_api stations via API lookup${RESET}" >&2
  
  # File operation feedback
  echo -e "${CYAN}💾 Finalizing enhanced station data...${RESET}" >&2
  mv "$tmp_json" "$stations_file"
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Enhanced station data saved successfully${RESET}" >&2
  else
    echo -e "${RED}❌ Station Enhancement: Failed to save enhanced data${RESET}" >&2
    echo -e "${CYAN}💡 Check disk space and file permissions${RESET}" >&2
  fi

  # Return only the API enhancement count (clean number only)
  echo "$enhanced_from_api"
}

# ============================================================================
# INCREMENTAL USER CACHING (MAIN FUNCTION)
# ============================================================================

perform_incremental_user_caching() {
  local force_refresh="${1:-false}"  # Optional parameter to force refresh all markets
  
  # Check if server is configured for API operations - REQUIRED for user caching
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: Server not configured${RESET}"
    echo -e "${CYAN}💡 User Cache Expansion requires a Channels DVR server to function${RESET}"
    return 1
  fi

  echo -e "${GREEN}✅ Channels DVR server configured: $CHANNELS_URL${RESET}"
  echo -e "${CYAN}🔗 Testing server connection...${RESET}"
  
  # Test server connection before starting caching process
  if ! curl -s --connect-timeout $QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${RED}❌ Channels DVR Integration: Cannot connect to server${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    if ! confirm_action "Continue anyway? (caching will likely fail)"; then
      echo -e "${YELLOW}⚠️  User Cache Expansion cancelled${RESET}"
      return 1
    fi
  else
    echo -e "${GREEN}✅ Server connection confirmed${RESET}"
  fi

  # Initialize user cache and state tracking
  init_user_cache
  init_cache_state_tracking
  
  # Determine which markets need processing
  echo -e "\n${CYAN}🔍 Analyzing markets for processing...${RESET}"
  local markets_to_process=()
  local total_configured=0
  local already_cached=0
  local base_cache_skipped=0
  local will_process=0
  
  # Read through CSV and categorize each market
  while IFS=, read -r country zip; do
    [[ "$country" == "Country" ]] && continue
    ((total_configured++))
    
    # Check various conditions to determine if we should process this market
    if [[ "$force_refresh" == "true" ]]; then
      # Force refresh mode - process everything
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${CYAN}🔄 Will force refresh: $country/$zip${RESET}"
    elif is_market_cached "$country" "$zip"; then
      # Market already processed in user cache
      ((already_cached++))
      echo -e "${GREEN}✅ Already cached: $country/$zip${RESET}"
    elif [[ "$FORCE_REFRESH_ACTIVE" != "true" ]] && check_market_in_base_cache "$country" "$zip"; then
      # Market exactly covered by base cache
      ((base_cache_skipped++))
      echo -e "${YELLOW}⏭️  Skipping (in base cache): $country/$zip${RESET}"
      # Record as processed since it's covered by base cache
      record_market_processed "$country" "$zip" 0
    else
      # Market needs processing
      markets_to_process+=("$country,$zip")
      ((will_process++))
      echo -e "${BLUE}📋 Will process: $country/$zip${RESET}"
    fi
  done < "$CSV_FILE"
  
  # Show processing summary
  echo -e "\n${BOLD}${BLUE}=== Market Analysis Results ===${RESET}"
  echo -e "${CYAN}📊 Total configured markets: $total_configured${RESET}"
  echo -e "${GREEN}📊 Already cached: $already_cached${RESET}"
  echo -e "${YELLOW}📊 Skipped (base cache): $base_cache_skipped${RESET}"
  echo -e "${BLUE}📊 Will process: $will_process${RESET}"
  
  # Early exit if nothing to process
  if [ "$will_process" -eq 0 ]; then
    echo -e "\n${GREEN}✅ All markets are already processed!${RESET}"
    echo -e "${CYAN}💡 No new stations to add to user cache${RESET}"
    echo -e "${CYAN}💡 Add new markets or use force refresh to reprocess existing ones${RESET}"
    return 0
  fi
  
  echo -e "\n${CYAN}🔄 Starting incremental caching for $will_process markets...${RESET}"
  
  # Clean up temporary files (but preserve user and base caches)
  echo -e "${CYAN}🧹 Preparing cache environment...${RESET}"
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log
  rm -f "$CACHE_DIR"/all_stations_master.json* "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR"
  > "$LINEUP_CACHE"

  # Process only the markets that need processing
  echo -e "\n${BOLD}${BLUE}Phase 1: Market Lineup Discovery${RESET}"
  echo -e "${CYAN}📊 Fetching TV lineups from unprocessed markets...${RESET}"
  local markets_processed=0
  local markets_failed=0
  
  for market in "${markets_to_process[@]}"; do
    IFS=, read -r COUNTRY ZIP <<< "$market"
    ((markets_processed++))
    
    echo -e "${CYAN}📡 [$markets_processed/$will_process] Querying lineups for $COUNTRY/$ZIP${RESET}"
    
    # API call with enhanced error handling
    local api_url="$CHANNELS_URL/tms/lineups/$COUNTRY/$ZIP"
    
    local response
    response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$api_url" 2>/dev/null)
    local curl_exit_code=$?
    
    # Handle API errors during caching
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for $COUNTRY/$ZIP: Curl failed with code $curl_exit_code${RESET}"
      ((markets_failed++))
      record_market_processed "$COUNTRY" "$ZIP" 0
      continue
    fi
    
    echo "$response" > "cache/last_raw_${COUNTRY}_${ZIP}.json"
    
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      # Count lineups found for this market
      local lineups_found=$(echo "$response" | jq 'length')
      
      # Record that this market was processed
      record_market_processed "$COUNTRY" "$ZIP" "$lineups_found"
      
      # Add lineups to cache
      echo "$response" | jq -c '.[]' >> "$LINEUP_CACHE"
      echo -e "${GREEN}✅ Found $lineups_found lineups for $COUNTRY/$ZIP${RESET}"
    else
      echo -e "${RED}❌ Invalid JSON response for $COUNTRY/$ZIP${RESET}"
      ((markets_failed++))
      record_market_processed "$COUNTRY" "$ZIP" 0
    fi
  done
  
  # Show market processing summary
  echo -e "\n${BOLD}${GREEN}✅ Market Processing Summary:${RESET}"
  echo -e "${GREEN}Markets processed: $markets_processed${RESET}"
  if [[ $markets_failed -gt 0 ]]; then
    echo -e "${RED}Markets failed: $markets_failed${RESET}"
  fi

  # Early exit if no lineups were collected
  if [ ! -f "$LINEUP_CACHE" ] || [ ! -s "$LINEUP_CACHE" ]; then
    echo -e "\n${YELLOW}⚠️  No lineups collected from processed markets${RESET}"
    echo -e "${CYAN}💡 This may be normal if markets failed or returned no lineups${RESET}"
    return 0
  fi

  # Process lineups WITH STATE TRACKING
  echo -e "\n${BOLD}${BLUE}Phase 2: Lineup Processing & Deduplication${RESET}"
  echo -e "${CYAN}📊 Processing and deduplicating TV lineups...${RESET}"
  local pre_dedup_lineups=$(wc -l < "$LINEUP_CACHE")

  # Process lineups more safely to avoid jq indexing errors
  sort -u "$LINEUP_CACHE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | jq -r '.lineupId // empty' 2>/dev/null
  done | grep -v '^$' | sort -u > cache/unique_lineups.txt

  local post_dedup_lineups=$(wc -l < cache/unique_lineups.txt)
  local dup_lineups_removed=$((pre_dedup_lineups - post_dedup_lineups))
  
  echo -e "${CYAN}📋 Lineups before dedup: $pre_dedup_lineups${RESET}"
  echo -e "${CYAN}📋 Lineups after dedup: $post_dedup_lineups${RESET}"
  echo -e "${GREEN}✅ Duplicate lineups removed: $dup_lineups_removed${RESET}"

  # Fetch stations for each lineup WITH STATE TRACKING AND SMART SKIPPING
  echo -e "\n${BOLD}${BLUE}Phase 3: Smart Lineup Processing${RESET}"
  echo -e "${CYAN}📡 Processing lineups with base cache and user cache awareness...${RESET}"
  local lineups_processed=0
  local lineups_failed=0
  local lineups_skipped_base=0
  local lineups_skipped_user=0
  local total_lineups=$(wc -l < cache/unique_lineups.txt)

  while read LINEUP; do
    # Skip empty lines
    [[ -z "$LINEUP" ]] && continue
    
    ((total_lineups_checked++))
    
    # SMART SKIPPING LOGIC
    local skip_reason=""
    local should_skip=false
    
    # Check 1: Is this lineup covered by base cache manifest?
    if [[ "$force_refresh" != "true" ]] && check_lineup_in_base_cache "$LINEUP"; then
      skip_reason="base cache"
      should_skip=true
      ((lineups_skipped_base++))
    # Check 2: Have we already cached this lineup in user cache?
    elif [[ "$force_refresh" != "true" ]] && is_lineup_cached "$LINEUP"; then
      skip_reason="user cache"
      should_skip=true
      ((lineups_skipped_user++))
    fi
    
    if [ "$should_skip" = true ]; then
      echo -e "${YELLOW}⏭️  Skipping lineup $LINEUP (covered by $skip_reason)${RESET}"
      continue
    fi
    
    # Process this lineup (existing logic)
    ((lineups_processed++))
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    
    echo -e "${CYAN}📡 [$lineups_processed/$total_lineups] Processing lineup $LINEUP${RESET}"
    
    # API call with enhanced error handling (existing code)
    local station_api_url="$CHANNELS_URL/dvr/guide/stations/$LINEUP"
    
    local curl_response
    curl_response=$(curl -s --connect-timeout $STANDARD_TIMEOUT --max-time $MAX_OPERATION_TIME "$station_api_url" 2>/dev/null)
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for lineup $LINEUP: Curl failed with code $curl_exit_code${RESET}"
      ((lineups_failed++))
      record_lineup_processed "$LINEUP" "UNK" "UNK" 0
      continue
    fi
    
    echo "$curl_response" > "$station_file"
    
    # Find which market this lineup belongs to for state tracking
    local country_code=""
    local source_zip=""
    for market in "${markets_to_process[@]}"; do
      IFS=, read -r COUNTRY ZIP <<< "$market"
      if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
        country_code="$COUNTRY"
        source_zip="$ZIP"
        break
      fi
    done
    
    # Count stations and record lineup processing
    local stations_found=0
    if [ -f "$station_file" ] && echo "$curl_response" | jq empty 2>/dev/null; then
      stations_found=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
      echo -e "${GREEN}✅ Found $stations_found stations${RESET}"
    else
      echo -e "${RED}❌ Invalid JSON response for lineup $LINEUP${RESET}"
      ((lineups_failed++))
    fi
    
    record_lineup_processed "$LINEUP" "$country_code" "$source_zip" "$stations_found"
    
  done < cache/unique_lineups.txt

  # Show enhanced lineup processing summary
  echo -e "\n${BOLD}${GREEN}✅ Smart Lineup Processing Summary:${RESET}"
  echo -e "${GREEN}Lineups processed: $lineups_processed${RESET}"
  echo -e "${YELLOW}Lineups skipped (base cache): $lineups_skipped_base${RESET}"
  echo -e "${YELLOW}Lineups skipped (user cache): $lineups_skipped_user${RESET}"
  if [[ $lineups_failed -gt 0 ]]; then
    echo -e "${RED}Lineups failed: $lineups_failed${RESET}"
  fi
  echo -e "${CYAN}Total efficiency gain: $((lineups_skipped_base + lineups_skipped_user)) fewer API calls${RESET}"

  # Early exit if no stations were collected
  if [ "$lineups_processed" -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️  No new lineups processed${RESET}"
    echo -e "${CYAN}💡 All lineups may have been previously cached${RESET}"
    return 0
  fi

  # Process and deduplicate stations with country injection
  echo -e "\n${BOLD}${BLUE}Phase 4: Station Processing & Country Assignment${RESET}"
  echo -e "${CYAN}🔄 Processing stations and injecting country codes...${RESET}"
  local pre_dedup_stations=0
  local temp_stations_file="$CACHE_DIR/temp_incremental_stations_$(date +%s).json"
  > "$temp_stations_file.tmp"

  # Process each lineup file individually to track country origin
  while read LINEUP; do
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    if [ -f "$station_file" ]; then
      # Find which country this lineup belongs to by checking our processed markets
      local country_code=""
      for market in "${markets_to_process[@]}"; do
        IFS=, read -r COUNTRY ZIP <<< "$market"
        if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
          country_code="$COUNTRY"
          break
        fi
      done
      
      # If we couldn't find country, try to extract from lineup ID pattern
      if [[ -z "$country_code" ]]; then
        case "$LINEUP" in
          *USA*|*US-*) country_code="USA" ;;
          *CAN*|*CA-*) country_code="CAN" ;;
          *GBR*|*GB-*|*UK-*) country_code="GBR" ;;
          *DEU*|*DE-*) country_code="DEU" ;;
          *FRA*|*FR-*) country_code="FRA" ;;
          *) country_code="UNK" ;;  # Unknown
        esac
      fi
      
      echo -e "${CYAN}📋 Processing lineup $LINEUP (Country: $country_code)${RESET}"
      
      # Count stations before processing
      if jq empty "$station_file" 2>/dev/null; then
        local lineup_count=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
        pre_dedup_stations=$((pre_dedup_stations + lineup_count))
        
        # Inject country code and source into each station
        jq --arg country "$country_code" --arg source "user" \
           'map(. + {country: $country, source: $source})' \
           "$station_file" >> "$temp_stations_file.tmp"
      fi
    fi
  done < cache/unique_lineups.txt

  # Now flatten, deduplicate, and sort the NEW stations only
  echo -e "\n${BOLD}${BLUE}Phase 5: Final Deduplication & Organization${RESET}"
  echo -e "${CYAN}🔄 Combining and deduplicating new station data...${RESET}"
  
  if [ -s "$temp_stations_file.tmp" ]; then
    jq -s 'flatten | sort_by((.name // "") | length) | reverse | unique_by(.stationId)' "$temp_stations_file.tmp" \
      | jq 'map(.name = (.name // empty))' > "$temp_stations_file"
    
    local post_dedup_stations=$(jq 'length' "$temp_stations_file")
  else
    echo '[]' > "$temp_stations_file"
    local post_dedup_stations=0
  fi

  # Clean up intermediate temp file
  rm -f "$temp_stations_file.tmp"

  local dup_stations_removed=$((pre_dedup_stations - post_dedup_stations))
  
  echo -e "${CYAN}📋 New stations before dedup: $pre_dedup_stations${RESET}"
  echo -e "${CYAN}📋 New stations after dedup: $post_dedup_stations${RESET}"
  echo -e "${GREEN}✅ Duplicate stations removed: $dup_stations_removed${RESET}"

  # Early exit if no new stations to add
  if [ "$post_dedup_stations" -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️  No new stations to add to cache${RESET}"
    echo -e "${CYAN}💡 Processed markets may have contained duplicate stations${RESET}"
    rm -f "$temp_stations_file"
    return 0
  fi

  # Enhancement phase with statistics capture
  echo -e "\n${BOLD}${BLUE}Phase 6: Station Data Enhancement${RESET}"
  echo -e "${CYAN}🔄 Enhancing station information...${RESET}"
  local enhanced_count
  enhanced_count=$(enhance_stations "$start_time" "$temp_stations_file")
  
  # APPEND to existing USER cache (this is the key difference)
  echo -e "\n${BOLD}${BLUE}Phase 7: Incremental User Cache Integration${RESET}"
  echo -e "${CYAN}💾 Appending new stations to existing user cache...${RESET}"
  
  if add_stations_to_user_cache "$temp_stations_file"; then
    echo -e "${GREEN}✅ User cache updated successfully${RESET}"
    echo -e "${CYAN}📊 Added $post_dedup_stations new stations to user cache${RESET}"
  else
    echo -e "${RED}❌ Failed to update user cache${RESET}"
    rm -f "$temp_stations_file"
    return 1
  fi

  # Calculate duration and show summary
  local end_time=$(date +%s)
  local duration=$((end_time - ${start_time%%.*}))
  local human_duration=$(printf '%02dh %02dm %02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

  # Show incremental summary
  show_incremental_caching_summary "$will_process" "$already_cached" "$base_cache_skipped" "$post_dedup_stations" "$dup_stations_removed" "$human_duration" "$enhanced_count" "$lineups_skipped_base" "$lineups_skipped_user"
  
  # Rebuild combined cache as final step
  if [ "$post_dedup_stations" -gt 0 ]; then
    echo -e "\n${BOLD}${BLUE}Final Step: Rebuilding Combined Cache${RESET}"
    echo -e "${CYAN}🔄 Updating combined cache with new stations...${RESET}"
    
    # Force invalidate and rebuild
    invalidate_combined_cache
    
    if build_combined_cache_with_progress >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Combined cache rebuilt successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Combined cache rebuild failed - will rebuild on next search${RESET}"
    fi
  else
    echo -e "\n${CYAN}💡 No new stations added - combined cache unchanged${RESET}"
  fi

  # Clean up temporary files
  rm -f "$temp_stations_file"
}