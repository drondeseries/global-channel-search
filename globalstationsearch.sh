#!/bin/bash

# === Global Station Search ===
# Description: Television station search tool using Channels DVR API
# dispatcharr integration for direct field population from search results
# Created: 2025/05/26
VERSION="1.3.0"
VERSION_INFO="Last Modified: 2025/06/01
Recent Changes (1.3.0)
• Added flags (-v, -h, --version-info)
• Updated versioning schema and enhanced developer tools
• Addition of USA and GBR streaming channels to base cache
• Cleanup of orphaned code and legacy variables
• Improved channel name parsing for Dispatcharr auto-matching
• Fixed global country search filter
• Enhanced menu consistency and navigation  
• Enhanced Dispatcharr logo integration with API workflow
• Fixed critical function breaks and improved user feedback
• Updated versioning schema and enhanced developer tools

Previous Versions:
• 1.2.0 - Major base cache overhaul, better user cache handling
• 1.1.0 - Added comprehensive local base cache
• 1.0.0 - Initial release with Dispatcharr integration

System Requirements:
• Required: jq, curl, bash 4.0+
• Optional: viu (logo previews), bc (progress calculations)
• Integration: Channels DVR server (optional), Dispatcharr (optional)

Quick Start:
1. Run: ./globalstationsearch.sh
2. Use 'Search Local Database' for immediate access
3. Use 'Dispatcharr Integration' for automated Dispatcharr field population
3. Add custom markets via 'Manage Television Markets' (optional)
4. Configure integrations in 'Settings' (optional)"

check_version_flags() {
  case "${1:-}" in
    --version|-v)
      echo "Global Station Search v$VERSION"
      exit 0
      ;;
    --version-info|--info)
      show_version_info
      exit 0
      ;;
    --help|-h)
      show_usage_help
      exit 0
      ;;
  esac
}

show_version_info() {
  echo -e "${BOLD}${CYAN}=== Global Station Search v$VERSION ===${RESET}"
  echo "$VERSION_INFO"
}

show_usage_help() {
  echo -e "${BOLD}${CYAN}Global Station Search v$VERSION${RESET}"
  echo "Television station search tool with optional Dispatcharr and Channels DVR integration"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  ./globalstationsearch.sh [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  -h, --help         Show this help message"
  echo "  -v, --version      Show version number only"
  echo "      --version-info Show detailed version information"
  echo
  echo -e "${BOLD}Features:${RESET}"
  echo "• Local database search with base cache (ready to use)"
  echo "• User cache expansion via market configuration"
  echo "• Dispatcharr integration with multiple field population"
  echo "  (including station ID, logo, channel name, and callsign [tvg-id])"
  echo "• Direct Channels DVR API search (requires Channels DVR)"
  echo "• Reverse station ID lookup"
  echo
  echo -e "${BOLD}Quick Start:${RESET}"
  echo "1. Run script without options to enter interactive mode"
  echo "2. Try 'Search Local Database' first (works immediately)"
  echo "3. Use 'Dispatcharr Integration' for automated Dispatcharr field population"
  echo "4. Configure additional options in 'Settings' as needed"
  echo
  echo -e "${BOLD}Documentation:${RESET}"
  echo "See README.md for detailed setup and usage instructions"
}

# TERMINAL STYLING
ESC="\033"
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
UNDERLINE="${ESC}[4m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"
BLUE="${ESC}[34m"

# CONFIGURATION
CONFIG_FILE="globalstationsearch.env"

# DIRECTORY STRUCTURE
CACHE_DIR="cache"
BACKUP_DIR="$CACHE_DIR/backups"
LOGO_DIR="$CACHE_DIR/logos"
STATION_CACHE_DIR="$CACHE_DIR/stations"

# INPUT FILES
CSV_FILE="sampled_markets.csv"
VALID_CODES_FILE="$CACHE_DIR/valid_country_codes.txt"

# CACHE FILES
LINEUP_CACHE="$CACHE_DIR/all_lineups.jsonl"

# MODERN TWO-FILE CACHE SYSTEM
BASE_STATIONS_JSON="all_stations_base.json"        # Distributed base cache (script directory)
USER_STATIONS_JSON="$CACHE_DIR/all_stations_user.json"     # User's custom additions
COMBINED_STATIONS_JSON="$CACHE_DIR/all_stations_combined.json"  # Runtime combination

# BASE CACHE MANIFEST SYSTEM
BASE_CACHE_MANIFEST="all_stations_base_manifest.json"      # Manifest for smart market skipping

# CACHE STATE TRACKING FILES
CACHED_MARKETS="$CACHE_DIR/cached_markets.jsonl"
CACHED_LINEUPS="$CACHE_DIR/cached_lineups.jsonl"
LINEUP_TO_MARKET="$CACHE_DIR/lineup_to_market.json"
CACHE_STATE_LOG="$CACHE_DIR/cache_state.log"

# SEARCH RESULT FILES
API_SEARCH_RESULTS="$CACHE_DIR/api_search_results.tsv"
SEARCH_RESULTS="$CACHE_DIR/search_results.tsv"

# DISPATCHARR INTEGRATION FILES
DISPATCHARR_CACHE="$CACHE_DIR/dispatcharr_channels.json"
DISPATCHARR_MATCHES="$CACHE_DIR/dispatcharr_matches.tsv"
DISPATCHARR_LOG="$CACHE_DIR/dispatcharr_operations.log"
DISPATCHARR_TOKENS="$CACHE_DIR/dispatcharr_tokens.json"
DISPATCHARR_LOGOS="$CACHE_DIR/dispatcharr_logos.json"

# TEMPORARY FILES
TEMP_CONFIG="${CONFIG_FILE}.tmp"

# Handle command line arguments before main execution
check_version_flags "$@"

# ============================================================================
# STANDARDIZED NAVIGATION HELPER FUNCTIONS
# ============================================================================

pause_for_user() {
  read -p "Press Enter to continue..."
}

show_invalid_choice() {
  echo -e "${RED}Invalid choice. Please try again.${RESET}"
  sleep 1
}

confirm_action() {
  local message="$1"
  local default="${2:-n}"
  
  read -p "$message (y/n) [default: $default]: " response
  response=${response:-$default}
  [[ "$response" =~ ^[Yy]$ ]]
}

show_system_status() {
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)
  
  # Station Database Status
  if [ "$base_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Base Station Database: $base_count stations${RESET}"
    echo -e "   (Comprehensive USA, CAN, and GBR coverage)"
  else
    echo -e "${YELLOW}⚠️  Base Station Database: Not found${RESET}"
  fi
  
  # User market configuration (moved above user station database)
  local market_count
  if [ -f "$CSV_FILE" ]; then
    market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$market_count" -gt 0 ]; then
      echo -e "📍 User Markets Configured: $market_count"
    else
      echo -e "📍 User Markets Configured: ${YELLOW}0 (no custom markets)${RESET}"
    fi
  else
    echo -e "📍 User Markets Configured: ${YELLOW}0 (no custom markets)${RESET}"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    echo -e "${GREEN}✅ User Station Database: $user_count stations${RESET}"
  else
    echo -e "${YELLOW}⚠️  User Station Database: No custom stations${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total Available Stations: $total_count${RESET}"
  
  # Search capability status
  if [ "$total_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Local Search: Available with full features${RESET}"
  else
    echo -e "${RED}❌ Local Search: No station data available${RESET}"
  fi
  
  # Integration Status
  if [[ -n "${CHANNELS_URL:-}" ]]; then
    if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Channels DVR: Connected ($CHANNELS_URL)${RESET}"
    else
      echo -e "${RED}❌ Channels DVR: Connection Failed ($CHANNELS_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Channels DVR: Not configured (optional)${RESET}"
  fi
  
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    if check_dispatcharr_connection 2>/dev/null; then
      echo -e "${GREEN}✅ Dispatcharr: Connected ($DISPATCHARR_URL)${RESET}"
    else
      echo -e "${RED}❌ Dispatcharr: Connection Failed ($DISPATCHARR_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Dispatcharr: Integration Disabled${RESET}"
  fi
  echo
}

check_database_exists() {
  if ! has_stations_database; then
    clear
    echo -e "${BOLD}${RED}❌ Local Search Not Available${RESET}\n"
    
    echo -e "${YELLOW}Local search requires a station database.${RESET}"
    echo
    
    # Provide detailed status of what's available/missing
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${BOLD}Database Status:${RESET}"
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${RED}❌ Base stations cache: Not found${RESET}"
      echo -e "${CYAN}   Should be: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}   Contact script distributor for base cache file${RESET}"
    else
      echo -e "${GREEN}✅ Base stations cache: $base_count stations${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  User stations cache: Empty${RESET}"
      echo -e "${CYAN}   Create via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    else
      echo -e "${GREEN}✅ User stations cache: $user_count stations${RESET}"
    fi
    
    echo
    
    # Show guidance based on what's available
    if [ "$base_count" -gt 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 You have the base cache - local search should work!${RESET}"
      echo -e "${CYAN}   You can search immediately or add custom markets.${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 No station database found. Base cache may be missing.${RESET}"
      show_workflow_guidance
    fi
    
    echo
    echo -e "${BOLD}${CYAN}What would you like to do?${RESET}"
    echo -e "${GREEN}1.${RESET} Manage Television Markets for User Cache"
    echo -e "${GREEN}2.${RESET} Use Direct API Search instead (requires server)"
    echo -e "${GREEN}3.${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1)
        echo -e "\n${GREEN}Opening market management...${RESET}"
        pause_for_user
        manage_markets
        return 1
        ;;
      2)
        echo -e "\n${CYAN}Opening Direct API Search...${RESET}"
        pause_for_user
        direct_api_search
        return 1
        ;;
      3|"")
        return 1  # Return to main menu
        ;;
      *)
        show_invalid_choice
        return 1
        ;;
    esac
  fi
  
  # We have a stations database available
  return 0
}

show_workflow_guidance() {
  echo -e "${BOLD}${BLUE}=== Getting Started Workflow ===${RESET}"
  echo
  echo -e "${YELLOW}📋 Modern Two-File Cache System:${RESET}"
  echo -e "${GREEN}Base Cache${RESET} - Pre-built stations for major markets (ready to use)"
  echo -e "${GREEN}User Cache${RESET} - Your custom additions from configured markets (optional)"
  echo
  echo -e "${YELLOW}📋 Quick Start Options:${RESET}"
  echo -e "${GREEN}1.${RESET} ${BOLD}Search Local Database${RESET} - Works immediately"
  echo -e "   • Uses base cache for instant access to thousands of stations"
  echo -e "   • Full filtering by resolution (HDTV, SDTV, UHDTV) and country"
  echo -e "   • Browse logos, unlimited results"
  echo
  echo -e "${GREEN}2.${RESET} ${BOLD}Add Custom Markets${RESET} - Optional expansion"
  echo -e "   • Only needed for markets beyond base cache coverage"
  echo -e "   • Configure additional countries/ZIP codes"
  echo -e "   • Run user caching to add to existing stations"
  echo
  echo -e "${GREEN}3.${RESET} ${BOLD}Direct API Search${RESET} - Alternative option"
  echo -e "   • Requires Channels DVR server connection"
  echo -e "   • Limited to 6 results per search, no filtering"
  echo -e "   • Use when base cache is unavailable"
  echo
  echo -e "${CYAN}💡 Most users can start immediately with option 1!${RESET}"
  echo
}

# ============================================================================
# CONFIGURATION SETUP
# ============================================================================

setup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    if source "$CONFIG_FILE" 2>/dev/null; then
      # Set defaults for any missing settings
      CHANNELS_URL=${CHANNELS_URL:-""}
      SHOW_LOGOS=${SHOW_LOGOS:-false}
      FILTER_BY_RESOLUTION=${FILTER_BY_RESOLUTION:-false}
      ENABLED_RESOLUTIONS=${ENABLED_RESOLUTIONS:-"SDTV,HDTV,UHDTV"}
      FILTER_BY_COUNTRY=${FILTER_BY_COUNTRY:-false}
      ENABLED_COUNTRIES=${ENABLED_COUNTRIES:-""}

      # Set defaults for Dispatcharr settings
      DISPATCHARR_URL=${DISPATCHARR_URL:-""}
      DISPATCHARR_USERNAME=${DISPATCHARR_USERNAME:-""}
      DISPATCHARR_PASSWORD=${DISPATCHARR_PASSWORD:-""}
      DISPATCHARR_ENABLED=${DISPATCHARR_ENABLED:-false}
      
      return 0
    else
      echo -e "${RED}Error: Cannot source config file${RESET}"
      rm "$CONFIG_FILE"
      echo -e "${YELLOW}Corrupted config removed. Let's set it up again.${RESET}"
    fi
  fi

  # Config file doesn't exist or was corrupted - create minimal config
  create_minimal_config
}

create_minimal_config() {
  echo -e "${YELLOW}Setting up configuration...${RESET}"
  echo -e "${CYAN}💡 Channels DVR server is optional and only needed for:${RESET}"
  echo -e "${CYAN}   • Direct API Search${RESET}"
  echo -e "${CYAN}   • Dispatcharr Integration${RESET}"
  echo -e "${CYAN}   • Station enhancement during user caching${RESET}"
  echo -e "${GREEN}   • Local search works immediately with base cache!${RESET}"
  echo
  
  if confirm_action "Configure Channels DVR server now? (can be done later in Settings)"; then
    if configure_channels_server; then
      echo -e "${GREEN}Server configured successfully!${RESET}"
    else
      echo -e "${YELLOW}Server configuration skipped${RESET}"
      CHANNELS_URL=""
    fi
  else
    echo -e "${GREEN}Skipping server configuration - you can add it later in Settings${RESET}"
    CHANNELS_URL=""
  fi
  
  # Write minimal config file
  {
    echo "CHANNELS_URL=\"${CHANNELS_URL:-}\""
    echo "SHOW_LOGOS=false"
    echo "FILTER_BY_RESOLUTION=false"
    echo "ENABLED_RESOLUTIONS=\"SDTV,HDTV,UHDTV\""
    echo "FILTER_BY_COUNTRY=false"
    echo "ENABLED_COUNTRIES=\"\""
    echo "# Dispatcharr Settings"
    echo "DISPATCHARR_URL=\"\""
    echo "DISPATCHARR_USERNAME=\"\""
    echo "DISPATCHARR_PASSWORD=\"\""
    echo "DISPATCHARR_ENABLED=false"
  } > "$CONFIG_FILE" || {
    echo -e "${RED}Error: Cannot write to config file${RESET}"
    exit 1
  }
  
  source "$CONFIG_FILE"
  echo -e "${GREEN}Configuration saved successfully!${RESET}"
  echo
  echo -e "${BOLD}${CYAN}Ready to Use:${RESET}"
  echo -e "${GREEN}✅ Search Local Database - Works immediately with base cache${RESET}"
  echo -e "${CYAN}💡 Optional: Add custom markets via 'Manage Television Markets'${RESET}"
}

configure_channels_server() {
  local ip port
  
  echo -e "${BOLD}Channels DVR Server Configuration${RESET}"
  echo
  
  while true; do
    read -p "Enter Channels DVR IP address [default: localhost]: " ip
    ip=${ip:-localhost}
    
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$|^localhost$ ]]; then
      break
    else
      echo -e "${RED}Invalid IP address format. Please enter a valid IP or 'localhost'${RESET}"
    fi
  done
  
  while true; do
    read -p "Enter Channels DVR port [default: 8089]: " port
    port=${port:-8089}
    
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
      break
    else
      echo -e "${RED}Invalid port number. Must be 1-65535${RESET}"
    fi
  done
  
  CHANNELS_URL="http://$ip:$port"
  
  # Test connection
  echo "Testing connection to $ip:$port..."
  if curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Connection successful!${RESET}"
    return 0
  else
    echo -e "${RED}⚠️  Cannot connect to Channels DVR at $ip:$port${RESET}"
    echo -e "${YELLOW}This could be normal if the server is currently offline${RESET}"
    if confirm_action "Save server settings anyway?"; then
      echo -e "${CYAN}Settings saved - connection will be tested when needed${RESET}"
      return 0
    else
      CHANNELS_URL=""
      return 1
    fi
  fi
}

# ============================================================================
# DEPENDENCY CHECKING
# ============================================================================

check_dependency() {
  local cmd="$1"
  local required="$2"
  local install_hint="$3"
  
  if ! command -v "$cmd" &> /dev/null; then
    if [[ "$required" == "true" ]]; then
      echo -e "${RED}❌ Missing required dependency: $cmd${RESET}"
      echo "$install_hint"
      exit 1
    else
      echo -e "${YELLOW}⚠️ Missing optional dependency: $cmd${RESET}"
      echo "$install_hint"
      return 1
    fi
  fi
  return 0
}

check_dependencies() {
  check_dependency "jq" "true" "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
  check_dependency "curl" "true" "Install with: sudo apt-get install curl (Ubuntu/Debian) or brew install curl (macOS)"

  # Check for optional viu dependency for logo previews
  if check_dependency "viu" "false" "viu is not installed, logo previews disabled. Install with: cargo install viu"; then
    echo -e "${CYAN}💡 Logo previews available - enable in Settings if desired${RESET}"
  else
    echo -e "${CYAN}💡 To enable logo previews: install viu with 'cargo install viu'${RESET}"
  fi

  # Note: SHOW_LOGOS setting is managed through Settings menu, not overridden here
}

# ============================================================================
# DIRECTORY AND FILE SETUP
# ============================================================================

setup_directories() {
  # Create main cache directory
  mkdir -p "$CACHE_DIR" || {
    echo -e "${RED}Error: Cannot create cache directory${RESET}"
    exit 1
  }

  # Create cache subdirectories
  mkdir -p "$BACKUP_DIR" "$LOGO_DIR" "$STATION_CACHE_DIR" || {
    echo -e "${RED}Error: Cannot create cache subdirectories${RESET}"
    exit 1
  }

  # Download country codes if needed
  if [ ! -f "$VALID_CODES_FILE" ]; then
    echo "Downloading valid country codes..."
    
    # Try to download with proper error handling
    if curl -s --connect-timeout 10 --max-time 30 \
        "https://raw.githubusercontent.com/lukes/ISO-3166-Countries-with-Regional-Codes/master/all/all.json" \
        | jq -r '.[]."alpha-3"' \
        | sort -u > "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Country codes downloaded successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Failed to download country codes, using fallback list${RESET}"
      echo -e "USA\nCAN\nGBR\nAUS\nDEU\nFRA\nJPN\nITA\nESP\nNLD" > "$VALID_CODES_FILE"
    fi
  fi
}

# ============================================================================
# CACHE MANAGEMENT FUNCTIONS
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

# Get the effective stations database (base + user combined)
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
  
  # Both base and user exist - create combined file
  # User stations take precedence for duplicates
  jq -s '
    .[0] as $base | .[1] as $user |
    ($user | map(.stationId)) as $user_ids |
    ($base | map(select(.stationId | IN($user_ids[]) | not))) + $user |
    sort_by(.name // "")
  ' "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" > "$COMBINED_STATIONS_JSON"
  
  echo "$COMBINED_STATIONS_JSON"
  return 0
}

# Check if we have any stations database available
has_stations_database() {
  local effective_file
  effective_file=$(get_effective_stations_file 2>/dev/null)
  return $?
}

# Get count of total stations across all available files
get_total_stations_count() {
  local effective_file
  effective_file=$(get_effective_stations_file 2>/dev/null)
  if [ $? -eq 0 ]; then
    jq 'length' "$effective_file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Get breakdown of station counts by source
get_stations_breakdown() {
  local base_count=0
  local user_count=0
  
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    base_count=$(jq 'length' "$BASE_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
    user_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  fi
  
  echo "$base_count $user_count"
}

# Initialize base cache if it doesn't exist (for distribution)
init_base_cache() {
  if [ ! -f "$BASE_STATIONS_JSON" ]; then
    echo '[]' > "$BASE_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty base stations cache${RESET}" >&2
  fi

  # Initialize manifest system
  init_base_cache_manifest
}

# Initialize user cache if it doesn't exist
init_user_cache() {
  if [ ! -f "$USER_STATIONS_JSON" ]; then
    echo '[]' > "$USER_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty user stations cache${RESET}" >&2
  fi
}

# Add stations to user cache (for incremental updates)
add_stations_to_user_cache() {
  local new_stations_file="$1"
  
  if [ ! -f "$new_stations_file" ]; then
    echo -e "${RED}Error: New stations file not found: $new_stations_file${RESET}" >&2
    return 1
  fi
  
  # Initialize user cache if needed
  init_user_cache
  
  echo "Merging new stations with user cache..."
  
  # Merge with existing user stations, user cache takes precedence for duplicates
  local temp_file="$USER_STATIONS_JSON.tmp"
  jq -s 'flatten | unique_by(.stationId) | sort_by(.name // "")' \
    "$USER_STATIONS_JSON" "$new_stations_file" > "$temp_file"
  
  if [ $? -eq 0 ]; then
    mv "$temp_file" "$USER_STATIONS_JSON"
    local new_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ User cache updated: $new_count total stations${RESET}"
    return 0
  else
    rm -f "$temp_file"
    echo -e "${RED}❌ Failed to merge stations${RESET}" >&2
    return 1
  fi
}

# Clean up temporary combined files
cleanup_combined_cache() {
  rm -f "$COMBINED_STATIONS_JSON" 2>/dev/null || true
}

# ============================================================================
# BASE CACHE MANIFEST FUNCTIONS
# ============================================================================
# 
# Note: Base cache manifest CREATION is handled by the standalone script:
#       create_base_cache_manifest.sh
# 
# This section contains only manifest READING/CHECKING functions used during
# normal operation to skip markets already covered by the base cache.
# 
# To create a new base cache manifest:
# 1. Run: ./create_base_cache_manifest.sh -v
# 2. Distribute both all_stations_base.json AND all_stations_base_manifest.json
# ============================================================================

# Check if a market is covered by base cache
check_market_in_base_cache() {
  local country="$1"
  local zip="$2"
  
  if [ ! -f "$BASE_CACHE_MANIFEST" ]; then
    return 1  # No manifest = not in base cache
  fi
  
  # Check if this exact market was processed for the base cache
  jq -e --arg country "$country" --arg zip "$zip" \
    '.markets[] | select(.country == $country and .zip == $zip)' \
    "$BASE_CACHE_MANIFEST" >/dev/null 2>&1
}

# Get list of countries covered by base cache
get_base_cache_countries() {
  if [ ! -f "$BASE_CACHE_MANIFEST" ]; then
    echo ""
    return 1
  fi
  
  jq -r '.markets[].country' "$BASE_CACHE_MANIFEST" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Initialize or update base cache manifest
init_base_cache_manifest() {
  if [ -f "$BASE_STATIONS_JSON" ] && [ -s "$BASE_STATIONS_JSON" ]; then
    if [ ! -f "$BASE_CACHE_MANIFEST" ]; then
      echo -e "${CYAN}Initializing base cache manifest...${RESET}"
      echo -e "${YELLOW}⚠️  Base cache manifest missing or outdated${RESET}"
      echo -e "${CYAN}💡 Run: ./create_base_cache_manifest.sh -v${RESET}"
    else
      # Check if manifest is older than base cache
      if [ "$BASE_STATIONS_JSON" -nt "$BASE_CACHE_MANIFEST" ]; then
        echo -e "${CYAN}Base cache updated, refreshing manifest...${RESET}"
        echo -e "${YELLOW}⚠️  Base cache manifest missing or outdated${RESET}"
        echo -e "${CYAN}💡 Run: ./create_base_cache_manifest.sh -v${RESET}"
      fi
    fi
  fi
}

# ============================================================================
# CACHE STATE TRACKING FUNCTIONS
# ============================================================================

# Initialize state tracking files if they don't exist
init_cache_state_tracking() {
  touch "$CACHED_MARKETS" "$CACHED_LINEUPS"
  
  # Initialize lineup-to-market mapping as empty JSON object
  if [ ! -f "$LINEUP_TO_MARKET" ]; then
    echo '{}' > "$LINEUP_TO_MARKET"
  fi
  
  # Create state log if it doesn't exist
  touch "$CACHE_STATE_LOG"
}

# Record that a market has been processed
record_market_processed() {
  local country="$1"
  local zip="$2"
  local lineups_found="$3"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  
  # Create JSONL entry for this market
  local market_record=$(jq -n \
    --arg country "$country" \
    --arg zip "$zip" \
    --arg timestamp "$timestamp" \
    --argjson lineups_found "$lineups_found" \
    '{
      country: $country,
      zip: $zip, 
      timestamp: $timestamp,
      lineups_found: $lineups_found
    }')
  
  # Remove any existing entry for this market (to handle re-processing)
  if [ -f "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" > "$CACHED_MARKETS.tmp" 2>/dev/null || true
    mv "$CACHED_MARKETS.tmp" "$CACHED_MARKETS"
  fi
  
  # Add new entry
  echo "$market_record" >> "$CACHED_MARKETS"
  
  # Log the action
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Recorded market: $country/$zip ($lineups_found lineups)" >> "$CACHE_STATE_LOG"
}

# Record that a lineup has been processed and map it to its source market
record_lineup_processed() {
  local lineup_id="$1"
  local country="$2"
  local zip="$3"
  local stations_found="$4"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  
  # Create JSONL entry for this lineup
  local lineup_record=$(jq -n \
    --arg lineup_id "$lineup_id" \
    --arg timestamp "$timestamp" \
    --argjson stations_found "$stations_found" \
    '{
      lineup_id: $lineup_id,
      timestamp: $timestamp,
      stations_found: $stations_found
    }')
  
  # Remove any existing entry for this lineup
  if [ -f "$CACHED_LINEUPS" ]; then
    grep -v "\"lineup_id\":\"$lineup_id\"" "$CACHED_LINEUPS" > "$CACHED_LINEUPS.tmp" 2>/dev/null || true
    mv "$CACHED_LINEUPS.tmp" "$CACHED_LINEUPS"
  fi
  
  # Add new entry
  echo "$lineup_record" >> "$CACHED_LINEUPS"
  
  # Update lineup-to-market mapping
  local temp_mapping="${LINEUP_TO_MARKET}.tmp"
  jq --arg lineup "$lineup_id" \
     --arg country "$country" \
     --arg zip "$zip" \
     '. + {($lineup): {country: $country, zip: $zip}}' \
     "$LINEUP_TO_MARKET" > "$temp_mapping" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    mv "$temp_mapping" "$LINEUP_TO_MARKET"
  else
    rm -f "$temp_mapping"
  fi
  
  # Log the action
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Recorded lineup: $lineup_id from $country/$zip ($stations_found stations)" >> "$CACHE_STATE_LOG"
}

# Check if a market has already been processed
is_market_cached() {
  local country="$1"
  local zip="$2"
  
  if [ ! -f "$CACHED_MARKETS" ]; then
    return 1  # Not cached (file doesn't exist)
  fi
  
  grep -q "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" 2>/dev/null
}

# Check if a lineup has already been processed  
is_lineup_cached() {
  local lineup_id="$1"
  
  if [ ! -f "$CACHED_LINEUPS" ]; then
    return 1  # Not cached (file doesn't exist)
  fi
  
  grep -q "\"lineup_id\":\"$lineup_id\"" "$CACHED_LINEUPS" 2>/dev/null
}

# Get list of markets that haven't been cached yet
get_unprocessed_markets() {
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    return 1
  fi
  
  # If no cache state exists, all markets are unprocessed
  if [ ! -f "$CACHED_MARKETS" ]; then
    tail -n +2 "$CSV_FILE"  # Skip header
    return 0
  fi
  
  # Compare CSV against cached markets, accounting for base cache coverage
  tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
    # Skip if already processed in user cache
    if is_market_cached "$country" "$zip"; then
      continue
    fi
    
    # Include market for processing (base cache filtering happens elsewhere)
    echo "$country,$zip"
  done
}

show_cache_state_stats() {
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    # Count actual JSON entries, not lines
    local cached_market_count=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
    echo "Cached Markets: $cached_market_count"
    
    # Show breakdown by country
    if command -v jq >/dev/null 2>&1; then
      local countries=$(jq -s '.[] | .country' "$CACHED_MARKETS" 2>/dev/null | sort | uniq -c | sort -rn)
      if [ -n "$countries" ]; then
        echo "  By Country:"
        echo "$countries" | while read -r count country; do
          if [ -n "$country" ] && [ "$country" != "null" ] && [ "$country" != '""' ]; then
            # Remove quotes from country name
            country=$(echo "$country" | tr -d '"')
            echo "    $country: $count markets"
          fi
        done
      fi
    fi
  else
    echo "Cached Markets: 0"
  fi
  
  if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
    # Count actual JSON entries, not lines
    local cached_lineup_count=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
    echo "Cached Lineups: $cached_lineup_count"
    
    # Show total stations across all cached lineups
    if command -v jq >/dev/null 2>&1; then
      local total_stations=$(jq -s '.[] | .stations_found' "$CACHED_LINEUPS" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
      echo "  Total Stations (pre-dedup): $total_stations"
    fi
  else
    echo "Cached Lineups: 0"
  fi
  
  # Show when cache was last updated
  if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
    local last_update=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
    if [ -n "$last_update" ]; then
      echo "Last Cache Update: $last_update"
    fi
  fi
}

# ============================================================================
# DISPATCHARR INTEGRATION FUNCTIONS
# ============================================================================

check_dispatcharr_connection() {
  if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
    return 1
  fi
  
  local test_url="${DISPATCHARR_URL}/api/core/version/"
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  
  # Try with existing JWT token if available
  if [[ -f "$token_file" ]]; then
    local access_token
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      if curl -s --connect-timeout 5 -H "Authorization: Bearer $access_token" "$test_url" >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  
  # If token test fails, the auto-refresh should have handled getting new tokens
  # So just test once more with current token file
  if [[ -f "$token_file" ]]; then
    local access_token
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      curl -s --connect-timeout 5 -H "Authorization: Bearer $access_token" "$test_url" >/dev/null 2>&1
      return $?
    fi
  fi
  
  return 1
}

get_dispatcharr_channels() {
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local response
  
  # Ensure we have a valid connection/token
  if ! check_dispatcharr_connection; then
    return 1
  fi
  
  # Get current access token
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    response=$(curl -s --connect-timeout 15 --max-time 30 \
      -H "Authorization: Bearer $access_token" \
      "${DISPATCHARR_URL}/api/channels/channels/" 2>/dev/null)
  fi
  
  if [[ -n "$response" ]] && echo "$response" | jq empty 2>/dev/null; then
    echo "$response" > "$DISPATCHARR_CACHE"
    echo "$response"
  else
    return 1
  fi
}

find_channels_missing_stationid() {
  local channels_data="$1"
  
  # Extract missing channels and sort by channel number
  echo "$channels_data" | jq -r '
    .[] | 
    select((.tvc_guide_stationid // "") == "" or (.tvc_guide_stationid // "") == null) |
    [.id, .name, .channel_group_id // "Ungrouped", (.channel_number // 0)] | 
    @tsv
  ' 2>/dev/null | sort -t$'\t' -k4 -n
}

search_stations_by_name() {
  local search_term="$1"
  local page="${2:-1}"
  local runtime_country="${3:-}"     # Future: from channel name parsing
  local runtime_resolution="${4:-}"  # Future: from channel name parsing
  
  # Delegate to shared search function
  shared_station_search "$search_term" "$page" "tsv" "$runtime_country" "$runtime_resolution"
}

get_total_search_results() {
  local search_term="$1"
  local runtime_country="${2:-}"     # Future: from channel name parsing
  local runtime_resolution="${3:-}"  # Future: from channel name parsing
  
  # Delegate to shared search function
  shared_station_search "$search_term" 1 "count" "$runtime_country" "$runtime_resolution"
}

update_dispatcharr_channel_epg() {
  local channel_id="$1"
  local station_id="$2"
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local response
  
  # Ensure we have a valid connection/token
  if ! check_dispatcharr_connection; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to connect to Dispatcharr for channel ID $channel_id" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Get current access token
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    response=$(curl -s -X PATCH \
      -H "Authorization: Bearer $access_token" \
      -H "Content-Type: application/json" \
      -d "{\"tvc_guide_stationid\":\"$station_id\"}" \
      "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
  fi
  
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated channel ID $channel_id with station ID $station_id" >> "$DISPATCHARR_LOG"
    return 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to update channel ID $channel_id: $response" >> "$DISPATCHARR_LOG"
    return 1
  fi
}

run_dispatcharr_integration() {
  # Always refresh tokens when entering Dispatcharr integration
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    echo -e "${CYAN}Initializing Dispatcharr integration...${RESET}"
    
    if ! refresh_dispatcharr_tokens; then
      echo -e "${RED}Cannot continue without valid authentication${RESET}"
      echo -e "${CYAN}Please check your Dispatcharr connection settings${RESET}"
      pause_for_user
      return 1
    fi
    echo
  fi
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Integration ===${RESET}\n"
    
    # Check connection status
    if check_dispatcharr_connection; then
      echo -e "${GREEN}✅ Dispatcharr Connection: Active${RESET}"
      echo -e "   Server: $DISPATCHARR_URL"
      
      # Show token freshness
      local token_file="$CACHE_DIR/dispatcharr_tokens.json"
      if [[ -f "$token_file" ]]; then
        local token_time
        token_time=$(stat -c %Y "$token_file" 2>/dev/null || stat -f %m "$token_file" 2>/dev/null)
        if [[ -n "$token_time" ]]; then
          local current_time=$(date +%s)
          local age_seconds=$((current_time - token_time))
          local age_minutes=$((age_seconds / 60))
          echo -e "   Tokens: ${GREEN}Fresh (${age_minutes}m old)${RESET}"
        fi
      fi
    else
      echo -e "${RED}❌ Dispatcharr Connection: Failed${RESET}"
      if [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo -e "${YELLOW}   (Integration disabled in settings)${RESET}"
      fi
    fi
    
    # Show pending matches status
    if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
      local pending_count
      pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
      echo -e "${YELLOW}📋 Pending Station ID Changes: $pending_count matches${RESET}"
    fi
    echo
    
    echo -e "${BOLD}Station ID Management:${RESET}"
    echo "a) Scan Channels for Missing Station IDs"
    echo "b) Interactive Station ID Matching"
    echo "c) Commit Station ID Changes"
    echo
    echo -e "${BOLD}Field Population:${RESET}"
    echo "d) Populate Other Dispatcharr Fields"
    echo
    echo -e "${BOLD}System:${RESET}"
    echo "e) Configure Dispatcharr Connection"
    echo "f) View Integration Logs"
    echo "g) Refresh Authentication Tokens"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) scan_missing_stationids ;;
      b|B) interactive_stationid_matching ;;
      c|C) batch_update_stationids && pause_for_user ;;
      d|D) populate_dispatcharr_fields ;;
      e|E) configure_dispatcharr_connection && pause_for_user ;;
      f|F) view_dispatcharr_logs && pause_for_user ;;
      g|G) refresh_dispatcharr_tokens && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

configure_dispatcharr_connection() {
  echo -e "\n${BOLD}Configure Dispatcharr Connection${RESET}"
  echo
  
  local current_url="${DISPATCHARR_URL:-}"
  local current_enabled="${DISPATCHARR_ENABLED:-false}"
  
  echo "Current settings:"
  echo "  URL: ${current_url:-"Not configured"}"
  echo "  Status: $([ "$current_enabled" = "true" ] && echo "Enabled" || echo "Disabled")"
  echo
  
  # Enable/Disable toggle
  if confirm_action "Enable Dispatcharr integration?"; then
    DISPATCHARR_ENABLED=true
    
    # Get connection details separately
    local ip port username password
    
    echo -e "\n${BOLD}Server Configuration:${RESET}"
    read -p "Dispatcharr IP address [default: localhost]: " ip
    ip=${ip:-localhost}
    
    # Validate IP
    while [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$|^localhost$ ]]; do
      echo -e "${RED}Invalid IP address format${RESET}"
      read -p "Dispatcharr IP address [default: localhost]: " ip
      ip=${ip:-localhost}
    done
    
    read -p "Dispatcharr port [default: 9191]: " port
    port=${port:-9191}
    
    # Validate port
    while [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); do
      echo -e "${RED}Invalid port number. Must be 1-65535${RESET}"
      read -p "Dispatcharr port [default: 9191]: " port
      port=${port:-9191}
    done
    
    local url="http://$ip:$port"
    
    echo -e "\n${BOLD}Authentication:${RESET}"
    read -p "Username: " username
    read -s -p "Password: " password
    echo
    
    # Test connection and generate JWT tokens
    echo -e "\nTesting connection and generating authentication tokens..."
    DISPATCHARR_URL="$url"
    DISPATCHARR_USERNAME="$username"
    DISPATCHARR_PASSWORD="$password"
    
    # Get JWT tokens
    local token_response
    token_response=$(curl -s --connect-timeout 10 \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$username\",\"password\":\"$password\"}" \
      "${url}/api/accounts/token/" 2>/dev/null)
    
    if echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
      # Save tokens to file
      local token_file="$CACHE_DIR/dispatcharr_tokens.json"
      echo "$token_response" > "$token_file"
      
      # Extract tokens for display
      local access_token=$(echo "$token_response" | jq -r '.access')
      local refresh_token=$(echo "$token_response" | jq -r '.refresh')
      
      echo -e "${GREEN}✅ Connection successful!${RESET}"
      echo -e "${GREEN}✅ JWT tokens generated and cached${RESET}"
      echo
      echo -e "${BOLD}${CYAN}Generated API Tokens:${RESET}"
      echo -e "${YELLOW}Access Token (expires in ~30 min):${RESET}"
      echo "  ${access_token:0:50}..."
      echo -e "${YELLOW}Refresh Token (long-lived):${RESET}"
      echo "  ${refresh_token:0:50}..."
      echo
      echo -e "${CYAN}💡 These tokens are automatically managed by the script${RESET}"
      echo -e "${CYAN}💡 Access tokens are refreshed automatically when needed${RESET}"
      echo -e "${CYAN}💡 Tokens are securely cached in: $token_file${RESET}"
      
      # Log token generation
      echo "$(date '+%Y-%m-%d %H:%M:%S') - JWT tokens generated for user: $username" >> "$DISPATCHARR_LOG"
      
      # Test a simple API call to verify everything works
      echo -e "\nTesting API access..."
      if curl -s --connect-timeout 5 -H "Authorization: Bearer $access_token" "${url}/api/channels/channels/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ API access confirmed${RESET}"
      else
        echo -e "${YELLOW}⚠️  API test failed, but tokens were generated${RESET}"
      fi
      
    else
      echo -e "${RED}❌ Authentication failed${RESET}"
      echo "Response: $token_response"
      if ! confirm_action "Save settings anyway?"; then
        return 1
      fi
    fi
  else
    DISPATCHARR_ENABLED=false
    echo -e "${YELLOW}Dispatcharr integration disabled${RESET}"
    
    # Clear any existing tokens
    rm -f "$CACHE_DIR/dispatcharr_tokens.json" 2>/dev/null
  fi
  
  # Update config file
  local temp_config="${CONFIG_FILE}.tmp"
  grep -v -E '^DISPATCHARR_(URL|USERNAME|PASSWORD|ENABLED)=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || true
  {
    echo "DISPATCHARR_URL=\"${DISPATCHARR_URL:-}\""
    echo "DISPATCHARR_USERNAME=\"${DISPATCHARR_USERNAME:-}\""
    echo "DISPATCHARR_PASSWORD=\"${DISPATCHARR_PASSWORD:-}\""
    echo "DISPATCHARR_ENABLED=$DISPATCHARR_ENABLED"
  } >> "$temp_config"
  
  mv "$temp_config" "$CONFIG_FILE"
  echo -e "\n${GREEN}Settings saved${RESET}"
  
  # Show token management info
  if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -f "$CACHE_DIR/dispatcharr_tokens.json" ]]; then
    echo
    echo -e "${BOLD}${BLUE}Token Management:${RESET}"
    echo -e "• Tokens are cached and reused automatically"
    echo -e "• Access tokens refresh automatically when expired"
    echo -e "• View logs: 'View Integration Logs' in the main menu"
    echo -e "• Clear tokens: Disable integration or delete cache files"
  fi
  
  return 0
}

scan_missing_stationids() {
  echo -e "\n${BOLD}Scanning Dispatcharr Channels${RESET}"
  
  if ! check_dispatcharr_connection; then
    echo -e "${RED}Cannot connect to Dispatcharr. Please configure connection first.${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}No station database found${RESET}"
    echo -e "${CYAN}Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}Alternative: Build user cache via 'Manage Television Markets'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo "Fetching channels from Dispatcharr..."
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}Failed to fetch channels from Dispatcharr${RESET}"
    pause_for_user
    return 1
  fi
  
  echo "Analyzing channels for missing station IDs..."
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  # *** THIS IS THE CRITICAL FIX ***
  if [[ -z "$missing_channels" ]]; then
    clear
    echo -e "${BOLD}${GREEN}=== Scan Results ===${RESET}\n"
    echo -e "${GREEN}✅ Excellent! All channels have station IDs assigned!${RESET}"
    echo
    echo -e "${CYAN}📊 Analysis Complete:${RESET}"
    local total_channels=$(echo "$channels_data" | jq 'length' 2>/dev/null || echo "0")
    echo -e "   • Total channels scanned: $total_channels"
    echo -e "   • Channels missing station IDs: 0"
    echo -e "   • Channels with station IDs: $total_channels"
    echo
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Your Dispatcharr channels are fully configured"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance channel data"
    echo -e "• No station ID matching needed at this time"
    echo
    pause_for_user
    return 0
  fi
  
  # Sort by channel number (4th field, tab-separated, numeric sort)
  echo "Sorting channels by channel number..."
  local sorted_missing_channels
  sorted_missing_channels=$(echo "$missing_channels" | sort -t$'\t' -k4 -n)
  
  # Convert to array for pagination
  mapfile -t missing_array <<< "$sorted_missing_channels"
  local total_missing=${#missing_array[@]}
  
  echo -e "${YELLOW}Found $total_missing channels missing station IDs (sorted by channel number)${RESET}"
  echo
  
  # Paginated display with enhanced formatting
  local offset=0
  local results_per_page=10
  
  while (( offset < total_missing )); do
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Channels Missing Station IDs ===${RESET}\n"
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + results_per_page < total_missing ? offset + results_per_page : total_missing))
    local current_page=$(( (offset / results_per_page) + 1 ))
    local total_pages=$(( (total_missing + results_per_page - 1) / results_per_page ))
    
    echo -e "${GREEN}Found $total_missing channels missing station IDs${RESET}"
    echo -e "${BOLD}Showing results $start_num-$end_num of $total_missing (Page $current_page of $total_pages)${RESET}"
    echo -e "${CYAN}Sorted by channel number${RESET}"
    echo
    
    # Enhanced table header with bold formatting - use printf for header
    printf "${BOLD}${YELLOW}%-3s %-8s %-30s %-15s %-8s %s${RESET}\n" "Key" "Ch ID" "Channel Name" "Group" "Number" "Status"
    echo "--------------------------------------------------------------------------------"
    
    # Display results with letter keys and enhanced formatting
    local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
    local result_count=0
    
    for ((i = offset; i < offset + results_per_page && i < total_missing; i++)); do
      IFS=$'\t' read -r id name group number <<< "${missing_array[$i]}"
      
      local key="${key_letters[$result_count]}"
      
      # Simple printf without color codes in format string
      printf "%-3s %-8s %-30s %-15s %-8s " "${key})" "$id" "${name:0:30}" "${group:0:15}" "$number"
      echo -e "${RED}Missing${RESET}"
      
      ((result_count++))
    done
    
    echo
    echo -e "${BOLD}Navigation Options:${RESET}"
    [[ $current_page -lt $total_pages ]] && echo "n) Next page"
    [[ $current_page -gt 1 ]] && echo "p) Previous page"
    echo "m) Go to Interactive Station ID Matching"
    echo "q) Back to Dispatcharr menu"
    echo
    
    read -p "Select option: " choice
    
    case "$choice" in
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          offset=$((offset + results_per_page))
        else
          echo -e "${YELLOW}Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          offset=$((offset - results_per_page))
        else
          echo -e "${YELLOW}Already on first page${RESET}"
          sleep 1
        fi
        ;;
      m|M)
        echo -e "${CYAN}Starting Interactive Station ID Matching...${RESET}"
        sleep 1  # Brief visual feedback
        interactive_stationid_matching "skip_intro"  # Pass flag to skip intro pause
        return 0
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
  
  echo -e "${CYAN}Next: Use 'Interactive Station ID Matching' to resolve these${RESET}"
  return 0
}

interactive_stationid_matching() {
  local skip_intro="${1:-}"  # Optional parameter to skip intro pause
  
  if ! check_dispatcharr_connection; then
    echo -e "${RED}Cannot connect to Dispatcharr. Please configure connection first.${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}No station database found${RESET}"
    echo -e "${CYAN}Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}Alternative: Build user cache via 'Manage Television Markets'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo "Fetching channels..."
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}Failed to fetch channels${RESET}"
    pause_for_user
    return 1
  fi
  
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    echo -e "${GREEN}All channels have station IDs assigned!${RESET}"
    pause_for_user
    return 0
  fi
  
  # Clear previous matches file
  > "$DISPATCHARR_MATCHES"
  
  # Convert to array
  mapfile -t missing_array <<< "$missing_channels"
  local total_missing=${#missing_array[@]}
  
  echo -e "${CYAN}Found $total_missing channels missing station IDs${RESET}"
  
  # USER CHOICE: Immediate or Batch Mode
  echo
  echo -e "${BOLD}${BLUE}=== Station ID Application Mode ===${RESET}"
  echo -e "${YELLOW}How would you like to apply station ID matches?${RESET}"
  echo
  echo -e "${GREEN}1) Immediate Mode${RESET} - Apply each match as you make it"
  echo -e "   ${CYAN}✓ Changes take effect right away${RESET}"
  echo -e "   ${CYAN}✓ No separate commit step needed${RESET}"
  echo -e "   ${CYAN}✓ Can see results immediately${RESET}"
  echo
  echo -e "${GREEN}2) Batch Mode${RESET} - Queue matches for review and batch commit"
  echo -e "   ${CYAN}✓ Review all matches before applying${RESET}"
  echo -e "   ${CYAN}✓ Apply all changes at once${RESET}"
  echo -e "   ${CYAN}✓ Can cancel/modify before commit${RESET}"
  echo
  
  local apply_mode=""
  while [[ -z "$apply_mode" ]]; do
    read -p "Select mode (1=immediate, 2=batch): " mode_choice
    case "$mode_choice" in
      1) apply_mode="immediate" ;;
      2) apply_mode="batch" ;;
      *) echo -e "${RED}Please enter 1 or 2${RESET}" ;;
    esac
  done
  
  echo
  if [[ "$apply_mode" == "immediate" ]]; then
    echo -e "${GREEN}✅ Immediate Mode selected - changes will apply as you make them${RESET}"
  else
    echo -e "${GREEN}✅ Batch Mode selected - changes will be queued for review${RESET}"
  fi
  
  # Only show intro pause if not called from scan function
  if [[ "$skip_intro" != "skip_intro" ]]; then
    echo "Starting interactive matching process..."
    pause_for_user
  else
    echo "Ready to start matching process..."
    sleep 1  # Brief pause for visual feedback
  fi
  
  local immediate_success_count=0
  local immediate_failure_count=0
  
  for ((i = 0; i < total_missing; i++)); do
    IFS=$'\t' read -r channel_id channel_name group number <<< "${missing_array[$i]}"
    
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    # Parse the channel name to extract country, resolution, and clean name
    local parsed_data=$(parse_channel_name "$channel_name")
    IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
    
    # Main matching loop for this channel
    while true; do
      clear
      echo -e "${BOLD}${CYAN}=== Channel Station ID Assignment ===${RESET}\n"
      
      # Show mode indicator
      if [[ "$apply_mode" == "immediate" ]]; then
        echo -e "${GREEN}Mode: Immediate Apply${RESET} | Success: $immediate_success_count | Failed: $immediate_failure_count"
      else
        local queued_count
        queued_count=$(wc -l < "$DISPATCHARR_MATCHES" 2>/dev/null || echo "0")
        echo -e "${BLUE}Mode: Batch Queue${RESET} | Queued: $queued_count matches"
      fi
      echo
      
      echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
      echo -e "Group: $group | Number: $number | ID: $channel_id"
      echo -e "Progress: $((i + 1)) of $total_missing"
      echo
      
      # Show parsing results if anything was detected
      if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
        echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
        echo -e "Original: ${YELLOW}$channel_name${RESET}"
        echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
        [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
        [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
        echo -e "${CYAN}Searching with cleaned name and auto-detected filters...${RESET}"
        echo
      fi
      
      # Use clean name for initial search
      local search_term="$clean_name"
      local current_page=1
      
      # Search and display loop
      while true; do
        echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
        
        # Show active filters
        local filter_status=""
        if [[ -n "$detected_country" ]]; then
          filter_status+="Country: $detected_country (auto) "
        fi
        if [[ -n "$detected_resolution" ]]; then
          filter_status+="Quality: $detected_resolution (auto) "
        fi
        if [[ -n "$filter_status" ]]; then
          echo -e "${BLUE}Active Filters: $filter_status${RESET}"
        fi
        echo
        
        # Get search results with auto-detected filters
        local results
        results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
        
        local total_results
        total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
        
        if [[ -z "$results" ]]; then
          echo -e "${YELLOW}No results found for '$search_term'${RESET}"
          if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
            echo -e "${CYAN}💡 Try 'c' to clear auto-detected filters${RESET}"
          fi
        else
          echo -e "${GREEN}Found $total_results total results${RESET}"
          echo
          
          # Enhanced table header
          printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
          echo "--------------------------------------------------------------------------------"
          
          local station_array=()
          local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
          local result_count=0
          
          # Process TSV results
          while IFS=$'\t' read -r station_id name call_sign country; do
            [[ -z "$station_id" ]] && continue
            
            # Get additional station info for better display
            local quality=$(get_station_quality "$station_id")
            
            local key="${key_letters[$result_count]}"
            
            # Format table row properly
            printf "%-3s " "${key})"
            echo -n -e "${CYAN}${station_id}${RESET}"
            printf "%*s" $((12 - ${#station_id})) ""
            printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
            echo -e "${GREEN}${country}${RESET}"
            
            # Display logo if enabled
            if [[ "$SHOW_LOGOS" == true ]]; then
              display_logo "$station_id"
            else
              echo "[logo previews disabled]"
            fi
            echo
            
            station_array+=("$station_id|$name|$call_sign|$country|$quality")
            ((result_count++))
          done <<< "$results"
        fi
        
        # Calculate pagination info
        local total_pages=$(( (total_results + 9) / 10 ))
        [[ $total_pages -eq 0 ]] && total_pages=1
        
        echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
        echo
        echo -e "${BOLD}Options:${RESET}"
        [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
        [[ $current_page -lt $total_pages ]] && echo "n) Next page"
        [[ $current_page -gt 1 ]] && echo "p) Previous page"
        echo "s) Search with different term"
        echo "m) Enter station ID manually"
        echo "k) Skip this channel"
        echo "q) Quit matching"
        echo
        
        read -p "Your choice: " choice < /dev/tty
        
        case "$choice" in
          a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
            if [[ $result_count -gt 0 ]]; then
              # Convert letter to array index
              local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
              local index=-1
              for ((idx=0; idx<10; idx++)); do
                if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
                  index=$idx
                  break
                fi
              done
              
              if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
                local selected="${station_array[$index]}"
                IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
                
                echo
                echo -e "${BOLD}Selected Station:${RESET}"
                echo "  Station ID: $sel_station_id"
                echo "  Name: $sel_name"
                echo "  Call Sign: $sel_call"
                echo "  Country: $sel_country"
                echo "  Quality: $sel_quality"
                echo
                
                # APPLY MODE LOGIC: Immediate vs Batch
                if [[ "$apply_mode" == "immediate" ]]; then
                  read -p "Apply this station ID immediately? (y/n): " confirm < /dev/tty
                  if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if update_dispatcharr_channel_epg "$channel_id" "$sel_station_id"; then
                      echo -e "${GREEN}✅ Successfully updated channel immediately${RESET}"
                      ((immediate_success_count++))
                      # Also record for logging
                      echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    else
                      echo -e "${RED}❌ Failed to update channel${RESET}"
                      ((immediate_failure_count++))
                    fi
                    pause_for_user
                    break 2  # Exit both loops, move to next channel
                  fi
                else
                  read -p "Queue this match for batch commit? (y/n): " confirm < /dev/tty
                  if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    echo -e "${GREEN}✅ Match queued for batch commit${RESET}"
                    sleep 1
                    break 2  # Exit both loops, move to next channel
                  fi
                fi
              else
                echo -e "${RED}Invalid selection${RESET}"
                sleep 1
              fi
            else
              echo -e "${RED}No results to select from${RESET}"
              sleep 1
            fi
            ;;
          n|N)
            if [[ $current_page -lt $total_pages ]]; then
              ((current_page++))
            else
              echo -e "${YELLOW}Already on last page${RESET}"
              sleep 1
            fi
            ;;
          p|P)
            if [[ $current_page -gt 1 ]]; then
              ((current_page--))
            else
              echo -e "${YELLOW}Already on first page${RESET}"
              sleep 1
            fi
            ;;
          s|S)
            read -p "Enter new search term: " new_search < /dev/tty
            if [[ -n "$new_search" ]]; then
              search_term="$new_search"
              current_page=1
            fi
            ;;
          m|M)
            read -p "Enter station ID manually: " manual_station_id < /dev/tty
            if [[ -n "$manual_station_id" ]]; then
              if [[ "$apply_mode" == "immediate" ]]; then
                if update_dispatcharr_channel_epg "$channel_id" "$manual_station_id"; then
                  echo -e "${GREEN}✅ Manual station ID applied immediately${RESET}"
                  ((immediate_success_count++))
                  echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                else
                  echo -e "${RED}❌ Failed to update channel${RESET}"
                  ((immediate_failure_count++))
                fi
                pause_for_user
              else
                echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                echo -e "${GREEN}✅ Manual station ID queued for batch commit${RESET}"
                sleep 1
              fi
              break 2  # Exit both loops, move to next channel
            fi
            ;;
          k|K)
            echo -e "${YELLOW}Skipped: $channel_name${RESET}"
            break 2  # Exit both loops, move to next channel
            ;;
          q|Q)
            echo -e "${CYAN}Matching session ended${RESET}"
            # Check for pending matches or show immediate results
            if [[ "$apply_mode" == "immediate" ]]; then
              show_immediate_results "$immediate_success_count" "$immediate_failure_count"
            else
              check_and_offer_commit
            fi
            return 0
            ;;
          *)
            echo -e "${RED}Invalid option${RESET}"
            sleep 1
            ;;
        esac
      done
    done
  done
  
  echo -e "\n${GREEN}Matching session complete${RESET}"
  
  # FINAL RESULTS BASED ON MODE
  if [[ "$apply_mode" == "immediate" ]]; then
    show_immediate_results "$immediate_success_count" "$immediate_failure_count"
  else
    # AUTO-FLOW TO COMMIT IF MATCHES EXIST
    check_and_offer_commit
  fi
}

show_immediate_results() {
  local success_count="$1"
  local failure_count="$2"
  
  echo
  echo -e "${BOLD}${GREEN}=== Immediate Mode Results ===${RESET}"
  echo -e "${GREEN}✅ Successfully applied: $success_count station IDs${RESET}"
  [[ $failure_count -gt 0 ]] && echo -e "${RED}❌ Failed to apply: $failure_count station IDs${RESET}"
  echo -e "${CYAN}All changes have been applied immediately to Dispatcharr${RESET}"
  
  if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${CYAN}📋 Session log saved for reference${RESET}"
  fi
}

check_and_offer_commit() {
  if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
    local match_count
    match_count=$(wc -l < "$DISPATCHARR_MATCHES")
    
    echo
    echo -e "${CYAN}📋 Found $match_count queued station ID matches${RESET}"
    
    if confirm_action "Review and commit these station ID changes now?"; then
      echo -e "${GREEN}Opening commit screen...${RESET}"
      sleep 1
      batch_update_stationids
    else
      echo -e "${CYAN}Matches saved. Use 'Commit Station ID Changes' later to apply them.${RESET}"
    fi
  else
    echo -e "${CYAN}No station ID matches were queued${RESET}"
  fi
}

get_station_quality() {
  local station_id="$1"
  
  # Get effective stations file
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    echo "UNK"
    return 1
  fi
  
  # Extract quality for this station
  local quality=$(jq -r --arg id "$station_id" \
    '.[] | select(.stationId == $id) | .videoQuality.videoType // "UNK"' \
    "$stations_file" 2>/dev/null | head -n 1)
  
  echo "${quality:-UNK}"
}

batch_update_stationids() {
  echo -e "\n${BOLD}Batch Update Station IDs${RESET}"
  
  if [[ ! -f "$DISPATCHARR_MATCHES" ]] || [[ ! -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${YELLOW}No pending matches found.${RESET}"
    echo -e "${CYAN}Run 'Interactive Station ID Matching' first to create matches.${RESET}"
    return 1
  fi
  
  local total_matches
  total_matches=$(wc -l < "$DISPATCHARR_MATCHES")
  
  echo "Found $total_matches pending matches:"
  echo
  
  # Show enhanced preview of matches with better formatting
  echo -e "${BOLD}Pending Matches:${RESET}"
  printf "${BOLD}${YELLOW}%-8s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Channel Name" "Station ID" "Match Name" "Quality"
  echo "--------------------------------------------------------------------------------"
  
  local line_count=0
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Get quality info for the station
    local quality=$(get_station_quality "$station_id")
    
    # Simple printf without colors, then add colors with echo
    printf "%-8s %-25s " "$channel_id" "${channel_name:0:25}"
    echo -n -e "${CYAN}${station_id}${RESET}"
    printf "%*s" $((12 - ${#station_id})) ""
    printf "%-20s " "${station_name:0:20}"
    echo -e "${GREEN}${quality}${RESET}"
    
    ((line_count++))
    # Show only first 10 for preview
    [[ $line_count -ge 10 ]] && break
  done < "$DISPATCHARR_MATCHES"
  
  [[ $total_matches -gt 10 ]] && echo "... and $((total_matches - 10)) more"
  echo
  
  if ! confirm_action "Apply all $total_matches matches?"; then
    echo -e "${YELLOW}Batch update cancelled${RESET}"
    return 1
  fi
  
  local success_count=0
  local failure_count=0
  
  echo -e "\n${BOLD}Processing updates...${RESET}"
  
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    echo -n "Updating: ${channel_name:0:25} -> $station_id ... "
    
    if update_dispatcharr_channel_epg "$channel_id" "$station_id"; then
      echo -e "${GREEN}✅ Success${RESET}"
      ((success_count++))
    else
      echo -e "${RED}❌ Failed${RESET}"
      ((failure_count++))
    fi
  done < "$DISPATCHARR_MATCHES"
  
  echo
  echo -e "${BOLD}Batch Update Complete:${RESET}"
  echo -e "${GREEN}✅ Successful: $success_count${RESET}"
  [[ $failure_count -gt 0 ]] && echo -e "${RED}❌ Failed: $failure_count${RESET}"
  
  # Clear processed matches
  > "$DISPATCHARR_MATCHES"
  echo -e "${CYAN}Match queue cleared${RESET}"
  
  return 0
}

populate_dispatcharr_fields() {
  if ! check_dispatcharr_connection; then
    echo -e "${RED}Cannot connect to Dispatcharr. Please configure connection first.${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}No station database found${RESET}"
    echo -e "${CYAN}Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}Alternative: Build user cache via 'Manage Television Markets'${RESET}"
    pause_for_user
    return 1
  fi
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Other Dispatcharr Fields ===${RESET}\n"
  
  echo -e "${YELLOW}This workflow will help you populate additional Dispatcharr channel fields${RESET}"
  echo -e "${YELLOW}using data from your local station database.${RESET}"
  echo
  echo -e "${BOLD}Fields that can be populated:${RESET}"
  echo -e "${GREEN}• Channel Name${RESET} (improve channel identification)"
  echo -e "${GREEN}• TVG-ID${RESET} (set to station call sign)"
  echo -e "${GREEN}• Gracenote ID${RESET} (set to station ID)"
  echo -e "${GREEN}• Logo URL${RESET} (set to station logo)"
  echo
  echo -e "${CYAN}💡 Channels will be processed in order from lowest to highest number${RESET}"
  echo
  
  if ! confirm_action "Continue with field population workflow?"; then
    return 0
  fi
  
  echo "Fetching all channels from Dispatcharr..."
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}Failed to fetch channels from Dispatcharr${RESET}"
    pause_for_user
    return 1
  fi
  
  local total_channels=$(echo "$channels_data" | jq 'length')
  echo -e "${GREEN}Found $total_channels total channels${RESET}"
  echo
  
  # Channel selection mode
  echo -e "${BOLD}Channel Selection:${RESET}"
  echo "1) Process all channels (in channel number order)"
  echo "2) Process channels missing specific fields (in channel number order)"
  echo "3) Process specific channel by number"
  echo "q) Cancel"
  echo
  
  read -p "Select mode: " mode_choice
  
  case "$mode_choice" in
    1) process_all_channels_fields "$channels_data" ;;
    2) process_channels_missing_fields "$channels_data" ;;
    3) process_specific_channel "$channels_data" ;;
    q|Q|"") return 0 ;;
    *) show_invalid_choice && return 1 ;;
  esac
}

process_all_channels_fields() {
  local channels_json="$1"
  
  echo -e "\n${CYAN}Sorting channels by ID (lowest to highest)...${RESET}"
  
  # Sort channels by .id (much more intuitive for users)
  local sorted_channels
  sorted_channels=$(echo "$channels_json" | jq -c '.[] | select(.id != null)' | jq -s 'sort_by(.id)' | jq -c '.[]')
  
  if [[ -z "$sorted_channels" ]]; then
    echo -e "${RED}No channels with valid IDs found${RESET}"
    pause_for_user
    return 1
  fi
  
  mapfile -t channels_array <<< "$sorted_channels"
  local total_channels=${#channels_array[@]}
  
  echo -e "${GREEN}Processing $total_channels channels in ID order...${RESET}"
  echo
  
  for ((i = 0; i < total_channels; i++)); do
    local channel_data="${channels_array[$i]}"
    process_single_channel_fields "$channel_data" $((i + 1)) "$total_channels"
    
    # Ask if user wants to continue after each channel
    if [[ $((i + 1)) -lt $total_channels ]]; then
      echo
      if ! confirm_action "Continue to next channel?"; then
        break
      fi
    fi
  done
  
  echo -e "\n${GREEN}✅ Field population workflow complete${RESET}"
  pause_for_user
}

process_channels_missing_fields() {
  local channels_data="$1"
  
  echo -e "\n${BOLD}Select which missing fields to look for:${RESET}"
  echo "1) Missing channel names (empty or generic names)"
  echo "2) Missing TVG-ID"
  echo "3) Missing TVC Guide Station ID"
  echo "4) Missing any of the above"
  echo
  
  read -p "Select filter: " filter_choice
  
  local filtered_channels
  case "$filter_choice" in
    1)
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.name == "" or .name == null or (.name | test("Channel [0-9]+")))')
      ;;
    2)
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvg_id == "" or .tvg_id == null)')
      ;;
    3)
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid == "" or .tvc_guide_stationid == null)')
      ;;
    4)
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(
        (.name == "" or .name == null or (.name | test("Channel [0-9]+"))) or
        (.tvg_id == "" or .tvg_id == null) or
        (.tvc_guide_stationid == "" or .tvc_guide_stationid == null)
      )')
      ;;
    *)
      show_invalid_choice
      return 1
      ;;
  esac
  
  if [[ -z "$filtered_channels" ]]; then
    echo -e "${GREEN}No channels found matching the selected criteria${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "\n${CYAN}Sorting filtered channels by ID (lowest to highest)...${RESET}"
  
  # Sort filtered channels by .id instead of .channel_number
  local sorted_filtered_channels
  sorted_filtered_channels=$(echo "$filtered_channels" | jq -s 'sort_by(.id)')
  
  mapfile -t filtered_array < <(echo "$sorted_filtered_channels" | jq -c '.[]')
  local filtered_count=${#filtered_array[@]}
  
  echo -e "${GREEN}Found $filtered_count channels matching criteria (sorted by ID)${RESET}"
  echo
  
  for ((i = 0; i < filtered_count; i++)); do
    local channel_data="${filtered_array[$i]}"
    process_single_channel_fields "$channel_data" $((i + 1)) "$filtered_count"
    
    if [[ $((i + 1)) -lt $filtered_count ]]; then
      echo
      if ! confirm_action "Continue to next channel?"; then
        break
      fi
    fi
  done
  
  echo -e "\n${GREEN}✅ Filtered field population complete${RESET}"
  pause_for_user
}

process_specific_channel() {
  local channels_data="$1"
  
  echo -e "\n${BOLD}Available Channels:${RESET}"
  echo "$channels_data" | jq -r '.[] | "\(.channel_number // "N/A") - \(.name // "Unnamed") (ID: \(.id))"' | head -20
  
  local total_shown=$(echo "$channels_data" | jq 'length')
  if [[ $total_shown -gt 20 ]]; then
    echo "... and $((total_shown - 20)) more"
  fi
  echo
  
  read -p "Enter channel number to process: " channel_number
  
  if [[ -z "$channel_number" ]]; then
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
  
  local channel_data
  channel_data=$(echo "$channels_data" | jq -c --arg num "$channel_number" '.[] | select(.channel_number == ($num | tonumber))')
  
  if [[ -z "$channel_data" ]]; then
    echo -e "${RED}Channel number $channel_number not found${RESET}"
    pause_for_user
    return 1
  fi
  
  process_single_channel_fields "$channel_data" 1 1
  pause_for_user
}

process_single_channel_fields() {
  local channel_data="$1"
  local current_num="$2"
  local total_num="$3"
  
  # Extract channel information with CORRECT field names
  local channel_id=$(echo "$channel_data" | jq -r '.id')
  local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
  local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
  local current_tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
  local current_tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')  # CORRECTED
  
  # Parse channel name to get search term
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
  # Main matching loop for this channel (SAME STRUCTURE AS STATION ID WORKFLOW)
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Populate Channel Fields ($current_num of $total_num) ===${RESET}\n"
    
    echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
    echo -e "Number: $channel_number | ID: $channel_id"
    echo -e "Progress: $current_num of $total_num"
    echo
    
    echo -e "${BOLD}Current Field Values:${RESET}"
    echo -e "TVG-ID: ${current_tvg_id:-"${RED}(empty)${RESET}"}"
    echo -e "TVC Station ID: ${current_tvc_stationid:-"${RED}(empty)${RESET}"}"  # CORRECTED
    echo
    
    # Show parsing results if anything was detected
    if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]] || [[ "$clean_name" != "$channel_name" ]]; then
      echo -e "${BOLD}${BLUE}Smart Parsing Results:${RESET}"
      echo -e "Original: ${YELLOW}$channel_name${RESET}"
      echo -e "Cleaned:  ${GREEN}$clean_name${RESET}"
      [[ -n "$detected_country" ]] && echo -e "Country:  ${GREEN}$detected_country${RESET} (auto-detected)"
      [[ -n "$detected_resolution" ]] && echo -e "Quality:  ${GREEN}$detected_resolution${RESET} (auto-detected)"
      echo -e "${CYAN}Searching with cleaned name and auto-detected filters...${RESET}"
      echo
    fi
    
    # Use clean name for initial search
    local search_term="$clean_name"
    local current_page=1
    
    # Search and display loop (IDENTICAL TO STATION ID WORKFLOW)
    while true; do
      echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
      
      # Show active filters
      local filter_status=""
      if [[ -n "$detected_country" ]]; then
        filter_status+="Country: $detected_country (auto) "
      fi
      if [[ -n "$detected_resolution" ]]; then
        filter_status+="Quality: $detected_resolution (auto) "
      fi
      if [[ -n "$filter_status" ]]; then
        echo -e "${BLUE}Active Filters: $filter_status${RESET}"
      fi
      echo
      
      # Get search results using SHARED SEARCH FUNCTION
      local results
      results=$(search_stations_by_name "$search_term" "$current_page" "$detected_country" "$detected_resolution")
      
      local total_results
      total_results=$(get_total_search_results "$search_term" "$detected_country" "$detected_resolution")
      
      if [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found for '$search_term'${RESET}"
        if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
          echo -e "${CYAN}💡 Try 'c' to clear auto-detected filters${RESET}"
        fi
      else
        echo -e "${GREEN}Found $total_results total results${RESET}"
        echo
        
        # IDENTICAL TABLE HEADER TO STATION ID WORKFLOW
        printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
        echo "--------------------------------------------------------------------------------"
        
        local station_array=()
        local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
        local result_count=0
        
        # IDENTICAL RESULT PROCESSING TO STATION ID WORKFLOW
        while IFS=$'\t' read -r station_id name call_sign country; do
          [[ -z "$station_id" ]] && continue
          
          # Get additional station info for better display
          local quality=$(get_station_quality "$station_id")
          
          local key="${key_letters[$result_count]}"
          
          # IDENTICAL TABLE ROW FORMATTING TO STATION ID WORKFLOW
          printf "%-3s " "${key})"
          echo -n -e "${CYAN}${station_id}${RESET}"
          printf "%*s" $((12 - ${#station_id})) ""
          printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
          echo -e "${GREEN}${country}${RESET}"
          
          # IDENTICAL LOGO DISPLAY TO STATION ID WORKFLOW
          if [[ "$SHOW_LOGOS" == true ]]; then
            display_logo "$station_id"
          else
            echo "[logo previews disabled]"
          fi
          echo
          
          # Store for selection (no logo URI needed now)
          station_array+=("$station_id|$name|$call_sign|$country|$quality")
          ((result_count++))
        done <<< "$results"
      fi
      
      # Calculate pagination info
      local total_pages=$(( (total_results + 9) / 10 ))
      [[ $total_pages -eq 0 ]] && total_pages=1
      
      echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
      echo
      
      # IDENTICAL OPTIONS TO STATION ID WORKFLOW
        echo -e "${BOLD}Options:${RESET}"
        [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
        [[ $current_page -lt $total_pages ]] && echo "n) Next page"
        [[ $current_page -gt 1 ]] && echo "p) Previous page"
        echo "s) Search with different term"
        echo "k) Skip this channel"
        echo "q) Quit field population"
      echo
      
      read -p "Your choice: " choice
      
      # IDENTICAL OPTION HANDLING TO STATION ID WORKFLOW
      case "$choice" in
        a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
          if [[ $result_count -gt 0 ]]; then
            # Convert letter to array index
            local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
            local index=-1
            for ((idx=0; idx<10; idx++)); do
              if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
                index=$idx
                break
              fi
            done
            
            if [[ $index -ge 0 ]] && [[ $index -lt $result_count ]]; then
              local selected="${station_array[$index]}"
              IFS='|' read -r sel_station_id sel_name sel_call sel_country sel_quality <<< "$selected"
              
              echo
              echo -e "${BOLD}Selected Station:${RESET}"
              echo "  Station ID: $sel_station_id"
              echo "  Name: $sel_name"
              echo "  Call Sign: $sel_call"
              echo "  Country: $sel_country"
              echo "  Quality: $sel_quality"
              echo
              
              read -p "Use this station for field updates? (y/n): " confirm
              if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # Show field comparison and get user choices (NO LOGO LOGIC)
                if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$sel_station_id" "$sel_name" "$sel_call"; then
                  echo -e "${GREEN}Field updates applied successfully${RESET}"
                else
                  echo -e "${CYAN}No field updates were applied${RESET}"
                fi
                pause_for_user
                return 0  # Exit channel processing, move to next channel
              fi
            else
              echo -e "${RED}Invalid selection${RESET}"
              sleep 1
            fi
          else
            echo -e "${RED}No results to select from${RESET}"
            sleep 1
          fi
          ;;
        n|N)
          if [[ $current_page -lt $total_pages ]]; then
            ((current_page++))
          else
            echo -e "${YELLOW}Already on last page${RESET}"
            sleep 1
          fi
          ;;
        p|P)
          if [[ $current_page -gt 1 ]]; then
            ((current_page--))
          else
            echo -e "${YELLOW}Already on first page${RESET}"
            sleep 1
          fi
          ;;
        s|S)
          read -p "Enter new search term: " new_search
          if [[ -n "$new_search" ]]; then
            search_term="$new_search"
            current_page=1
          fi
          ;;
        k|K)
          echo -e "${YELLOW}Skipped: $channel_name${RESET}"
          return 0  # Skip this channel, move to next
          ;;
        q|Q)
          echo -e "${CYAN}Field population ended${RESET}"
          return 1  # End entire workflow
          ;;
        *)
          echo -e "${RED}Invalid option${RESET}"
          sleep 1
          ;;
      esac
    done
  done
}

show_field_comparison_and_update_simplified() {
  local channel_id="$1"
  local channel_name="$2"
  local current_tvg_id="$3"
  local current_tvc_stationid="$4"
  local station_id="$5"
  local station_name="$6"
  local call_sign="$7"
  
  # Get current channel info to see existing logo
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  local current_logo_id=""
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    local channel_info
    channel_info=$(curl -s -H "Authorization: Bearer $access_token" \
      "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
    
    if echo "$channel_info" | jq empty 2>/dev/null; then
      current_logo_id=$(echo "$channel_info" | jq -r '.logo_id // empty')
    fi
  fi
  
  # Get logo URL from station database
  local logo_url=""
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [[ $? -eq 0 ]]; then
    logo_url=$(jq -r --arg id "$station_id" \
      '.[] | select(.stationId == $id) | .preferredImage.uri // empty' \
      "$stations_file" 2>/dev/null | head -n 1)
  fi
  
  echo
  echo -e "${BOLD}${GREEN}=== Field Comparison & Update Options ===${RESET}\n"
  
  echo -e "${BOLD}Matched Station:${RESET}"
  echo -e "Name: ${GREEN}$station_name${RESET}"
  echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
  echo -e "Station ID: ${GREEN}$station_id${RESET}"
  echo
  
  # LOGO COMPARISON SECTION
  echo -e "${BOLD}${CYAN}=== Logo Comparison ===${RESET}"
  echo
  
  # Show current Dispatcharr logo
  if [[ -n "$current_logo_id" && "$current_logo_id" != "null" ]]; then
    display_dispatcharr_logo "$current_logo_id" "Current Dispatcharr Logo"
  else
    echo "   Current Dispatcharr Logo: ${YELLOW}No logo set${RESET}"
  fi
  echo
  
  # Show potential replacement from station database
  if [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    display_station_logo_preview "$logo_url" "Potential Replacement"
  else
    echo "   Potential Replacement: ${YELLOW}No logo available${RESET}"
  fi
  echo
  
  # Field-by-field comparison
  echo -e "${BOLD}${CYAN}=== Proposed Field Updates ===${RESET}"
  echo
  
  # 1. Channel Name
  echo -e "${BOLD}1. Channel Name:${RESET}"
  echo -e "   Current:  ${YELLOW}$channel_name${RESET}"
  echo -e "   Proposed: ${GREEN}$station_name${RESET}"
  local update_name="n"
  if [[ "$channel_name" != "$station_name" ]]; then
    read -p "   Update channel name? (y/n): " update_name
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 2. TVG-ID
  echo -e "${BOLD}2. TVG-ID:${RESET}"
  echo -e "   Current:  ${YELLOW}${current_tvg_id:-"(empty)"}${RESET}"
  echo -e "   Proposed: ${GREEN}$call_sign${RESET}"
  local update_tvg="n"
  if [[ "$current_tvg_id" != "$call_sign" ]]; then
    read -p "   Update TVG-ID? (y/n): " update_tvg
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 3. TVC Guide Station ID
  echo -e "${BOLD}3. TVC Guide Station ID:${RESET}"
  echo -e "   Current:  ${YELLOW}${current_tvc_stationid:-"(empty)"}${RESET}"
  echo -e "   Proposed: ${GREEN}$station_id${RESET}"
  local update_station_id="n"
  if [[ "$current_tvc_stationid" != "$station_id" ]]; then
    read -p "   Update TVC Guide Station ID? (y/n): " update_station_id
  else
    echo -e "   ${CYAN}(already matches)${RESET}"
  fi
  echo
  
  # 4. Logo (NEW)
  echo -e "${BOLD}4. Channel Logo:${RESET}"
  local update_logo="n"
  local logo_id=""
  if [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    read -p "   Upload and set station logo? (y/n): " update_logo
    
    if [[ "$update_logo" =~ ^[Yy]$ ]]; then
      echo -e "   ${CYAN}Uploading logo to Dispatcharr...${RESET}"
      logo_id=$(upload_station_logo_to_dispatcharr "$station_name" "$logo_url")
      if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
        echo -e "   ${GREEN}✅ Logo uploaded successfully (ID: $logo_id)${RESET}"
      else
        echo -e "   ${RED}❌ Logo upload failed${RESET}"
        update_logo="n"
      fi
    fi
  else
    echo -e "   Station Logo: ${YELLOW}Not available${RESET}"
  fi
  echo
  
  # Apply updates
  local updates_made=0
  if [[ "$update_name" =~ ^[Yy]$ ]] || [[ "$update_tvg" =~ ^[Yy]$ ]] || [[ "$update_station_id" =~ ^[Yy]$ ]] || [[ "$update_logo" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}Applying updates...${RESET}"
    
    if update_dispatcharr_channel_with_logo "$channel_id" "$update_name" "$station_name" "$update_tvg" "$call_sign" "$update_station_id" "$station_id" "$update_logo" "$logo_id"; then
      echo -e "${GREEN}✅ Successfully updated channel fields${RESET}"
      updates_made=1
    else
      echo -e "${RED}❌ Failed to update some channel fields${RESET}"
    fi
  else
    echo -e "${YELLOW}No updates requested${RESET}"
  fi
  
  return $updates_made
}

display_logo_from_url() {
  local logo_url="$1"
  
  if [[ -z "$logo_url" ]]; then
    echo "   [no logo URL]"
    return 1
  fi
  
  # Create temporary file for logo
  local temp_logo="/tmp/temp_logo_$(date +%s).png"
  
  if curl -sL "$logo_url" --output "$temp_logo" 2>/dev/null; then
    local mime_type=$(file --mime-type -b "$temp_logo")
    if [[ "$mime_type" == image/* ]]; then
      viu -h 3 -w 20 "$temp_logo" 2>/dev/null || echo "   [logo preview unavailable]"
    else
      echo "   [invalid image format]"
    fi
    rm -f "$temp_logo"
  else
    echo "   [failed to download logo]"
  fi
}

update_dispatcharr_channel_with_logo() {
  local channel_id="$1"
  local update_name="$2"
  local new_name="$3"
  local update_tvg="$4"
  local new_tvg_id="$5"
  local update_station_id="$6"
  local new_station_id="$7"
  local update_logo="$8"
  local logo_id="$9"
  
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  
  # Ensure we have a valid connection/token
  if ! check_dispatcharr_connection; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to connect to Dispatcharr for channel ID $channel_id" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Get current access token
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No valid access token for channel ID $channel_id" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Build update data JSON with logo support
  local update_data="{}"
  
  if [[ "$update_name" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg name "$new_name" '. + {name: $name}')
  fi
  
  if [[ "$update_tvg" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg tvg_id "$new_tvg_id" '. + {tvg_id: $tvg_id}')
  fi
  
  if [[ "$update_station_id" =~ ^[Yy]$ ]]; then
    update_data=$(echo "$update_data" | jq --arg station_id "$new_station_id" '. + {tvc_guide_stationid: $station_id}')
  fi
  
  # NEW: Add logo ID if provided (field name is "logo_id" not "logo")
  if [[ "$update_logo" =~ ^[Yy]$ ]] && [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --argjson logo_id "$logo_id" '. + {logo_id: $logo_id}')
  fi
  
  # Send PATCH request
  local response
  response=$(curl -s -X PATCH \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "$update_data" \
    "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
  
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local log_msg="Updated channel ID $channel_id:"
    [[ "$update_name" =~ ^[Yy]$ ]] && log_msg+=" name=yes"
    [[ "$update_tvg" =~ ^[Yy]$ ]] && log_msg+=" tvg=yes"
    [[ "$update_station_id" =~ ^[Yy]$ ]] && log_msg+=" station=yes"
    [[ "$update_logo" =~ ^[Yy]$ ]] && log_msg+=" logo=$logo_id"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $log_msg" >> "$DISPATCHARR_LOG"
    return 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to update channel ID $channel_id: $response" >> "$DISPATCHARR_LOG"
    return 1
  fi
}

upload_station_logo_to_dispatcharr() {
  local station_name="$1"
  local logo_url="$2"
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  
  if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
    return 1
  fi
  
  # Ensure we have a valid connection/token
  if ! check_dispatcharr_connection; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to connect to Dispatcharr for logo upload" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Get current access token
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - No valid access token for logo upload" >> "$DISPATCHARR_LOG"
    return 1
  fi
  
  # Create a clean logo name from station name
  local clean_name=$(echo "$station_name" | sed 's/[^a-zA-Z0-9 ]//g' | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
  
  # Check if logo already exists in Dispatcharr cache
  local existing_logo_id=$(check_existing_dispatcharr_logo "$logo_url")
  if [[ -n "$existing_logo_id" && "$existing_logo_id" != "null" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Logo already exists with ID: $existing_logo_id" >> "$DISPATCHARR_LOG"
    echo "$existing_logo_id"
    return 0
  fi
  
  # Upload logo to Dispatcharr using FORM DATA (not JSON)
  local response
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $access_token" \
    -F "name=$clean_name" \
    -F "url=$logo_url" \
    "${DISPATCHARR_URL}/api/channels/logos/" 2>/dev/null)
  
  if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
    local logo_id=$(echo "$response" | jq -r '.id')
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Uploaded logo for '$station_name' with ID: $logo_id" >> "$DISPATCHARR_LOG"
    
    # Cache the logo info locally for future reference
    cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$clean_name"
    
    echo "$logo_id"
    return 0
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to upload logo for '$station_name': $response" >> "$DISPATCHARR_LOG"
    return 1
  fi
}

check_existing_dispatcharr_logo() {
  local logo_url="$1"
  
  # First check our local cache
  if [[ -f "$DISPATCHARR_LOGOS" ]]; then
    local cached_id=$(jq -r --arg url "$logo_url" '.[$url].id // empty' "$DISPATCHARR_LOGOS" 2>/dev/null)
    if [[ -n "$cached_id" && "$cached_id" != "null" ]]; then
      echo "$cached_id"
      return 0
    fi
  fi
  
  # If not in local cache, query Dispatcharr API
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  local access_token
  if [[ -f "$token_file" ]]; then
    access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
  fi
  
  if [[ -n "$access_token" && "$access_token" != "null" ]]; then
    local response
    response=$(curl -s -H "Authorization: Bearer $access_token" \
      "${DISPATCHARR_URL}/api/channels/logos/" 2>/dev/null)
    
    if echo "$response" | jq empty 2>/dev/null; then
      local logo_id=$(echo "$response" | jq -r --arg url "$logo_url" \
        '.[] | select(.url == $url) | .id // empty' 2>/dev/null)
      
      if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
        # Cache this for future use
        local logo_name=$(echo "$response" | jq -r --arg url "$logo_url" \
          '.[] | select(.url == $url) | .name // empty' 2>/dev/null)
        cache_dispatcharr_logo_info "$logo_url" "$logo_id" "$logo_name"
        echo "$logo_id"
        return 0
      fi
    fi
  fi
  
  return 1
}

cache_dispatcharr_logo_info() {
  local logo_url="$1"
  local logo_id="$2"
  local logo_name="$3"
  
  # Initialize cache file if it doesn't exist
  if [[ ! -f "$DISPATCHARR_LOGOS" ]]; then
    echo '{}' > "$DISPATCHARR_LOGOS"
  fi
  
  # Add/update logo info in cache
  local temp_file="${DISPATCHARR_LOGOS}.tmp"
  jq --arg url "$logo_url" \
     --arg id "$logo_id" \
     --arg name "$logo_name" \
     --arg timestamp "$(date -Iseconds)" \
     '. + {($url): {id: $id, name: $name, cached: $timestamp}}' \
     "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
  
  if [[ $? -eq 0 ]]; then
    mv "$temp_file" "$DISPATCHARR_LOGOS"
  else
    rm -f "$temp_file"
  fi
}

display_dispatcharr_logo() {
  local logo_id="$1"
  local label="$2"
  
  if [[ -z "$logo_id" || "$logo_id" == "null" ]]; then
    echo "   $label: ${YELLOW}No logo${RESET}"
    return 1
  fi
  
  if [[ "$SHOW_LOGOS" == "true" ]] && command -v viu >/dev/null 2>&1; then
    echo "   $label:"
    
    # Download logo to temp file
    local temp_logo="/tmp/dispatcharr_logo_${logo_id}_$(date +%s).png"
    
    if curl -s "${DISPATCHARR_URL}/api/channels/logos/${logo_id}/cache/" --output "$temp_logo" 2>/dev/null; then
      local mime_type=$(file --mime-type -b "$temp_logo" 2>/dev/null)
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$temp_logo" 2>/dev/null || echo "   [logo display failed]"
      else
        echo "   [invalid image format]"
      fi
      rm -f "$temp_logo"
    else
      echo "   [failed to download logo]"
    fi
  else
    echo "   $label: ${GREEN}Logo ID $logo_id${RESET} [logo preview unavailable]"
  fi
}

display_station_logo_preview() {
  local logo_url="$1"
  local label="$2"
  
  if [[ -z "$logo_url" || "$logo_url" == "null" ]]; then
    echo "   $label: ${YELLOW}No logo available${RESET}"
    return 1
  fi
  
  if [[ "$SHOW_LOGOS" == "true" ]] && command -v viu >/dev/null 2>&1; then
    echo "   $label:"
    
    # Download logo to temp file
    local temp_logo="/tmp/station_logo_preview_$(date +%s).png"
    
    if curl -s "$logo_url" --output "$temp_logo" 2>/dev/null; then
      local mime_type=$(file --mime-type -b "$temp_logo" 2>/dev/null)
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$temp_logo" 2>/dev/null || echo "   [logo preview failed]"
      else
        echo "   [invalid image format]"
      fi
      rm -f "$temp_logo"
    else
      echo "   [failed to download logo preview]"
    fi
  else
    echo "   $label: ${GREEN}Available${RESET} [logo preview unavailable]"
    echo "   URL: ${CYAN}$logo_url${RESET}"
  fi
}

cleanup_dispatcharr_logo_cache() {
  if [[ -f "$DISPATCHARR_LOGOS" ]]; then
    # Remove entries older than 30 days
    local cutoff_date=$(date -d '30 days ago' -Iseconds 2>/dev/null || date -v-30d -Iseconds 2>/dev/null)
    if [[ -n "$cutoff_date" ]]; then
      local temp_file="${DISPATCHARR_LOGOS}.tmp"
      jq --arg cutoff "$cutoff_date" \
        'to_entries | map(select(.value.cached >= $cutoff)) | from_entries' \
        "$DISPATCHARR_LOGOS" > "$temp_file" 2>/dev/null
      
      if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$DISPATCHARR_LOGOS"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaned up old logo cache entries" >> "$DISPATCHARR_LOG"
      else
        rm -f "$temp_file"
      fi
    fi
  fi
}

view_dispatcharr_logs() {
  echo -e "\n${BOLD}Dispatcharr Integration Logs${RESET}"
  
  if [[ ! -f "$DISPATCHARR_LOG" ]]; then
    echo -e "${YELLOW}No logs found${RESET}"
    return 0
  fi
  
  echo
  echo -e "${BOLD}Recent Operations:${RESET}"
  tail -20 "$DISPATCHARR_LOG" | while IFS= read -r line; do
    if [[ "$line" == *"Updated"* ]]; then
      echo -e "${GREEN}$line${RESET}"
    elif [[ "$line" == *"Failed"* ]]; then
      echo -e "${RED}$line${RESET}"
    elif [[ "$line" == *"JWT tokens generated"* ]]; then
      echo -e "${CYAN}$line${RESET}"
    else
      echo "$line"
    fi
  done
  
  echo
  local total_operations
  total_operations=$(wc -l < "$DISPATCHARR_LOG" 2>/dev/null || echo "0")
  echo "Total operations logged: $total_operations"
  
  # Show token status if available
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  if [[ -f "$token_file" ]]; then
    echo
    echo -e "${BOLD}Current Token Status:${RESET}"
    local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      echo -e "${GREEN}✅ Access token available${RESET}"
      # Try to decode JWT to show expiration (basic parsing)
      local exp_claim=$(echo "$access_token" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
      if [[ -n "$exp_claim" && "$exp_claim" != "null" ]]; then
        local exp_date=$(date -d "@$exp_claim" 2>/dev/null || echo "Unknown")
        echo -e "   Expires: $exp_date"
      fi
    else
      echo -e "${RED}❌ No valid access token${RESET}"
    fi
    
    local refresh_token=$(jq -r '.refresh // empty' "$token_file" 2>/dev/null)
    if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
      echo -e "${GREEN}✅ Refresh token available${RESET}"
    else
      echo -e "${YELLOW}⚠️  No refresh token${RESET}"
    fi
  fi
  
  return 0
}

refresh_dispatcharr_tokens() {
  if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
    echo -e "${RED}Dispatcharr not configured or disabled${RESET}"
    return 1
  fi
  
  if [[ -z "${DISPATCHARR_USERNAME:-}" ]] || [[ -z "${DISPATCHARR_PASSWORD:-}" ]]; then
    echo -e "${RED}Dispatcharr credentials not found in settings${RESET}"
    return 1
  fi
  
  local token_file="$CACHE_DIR/dispatcharr_tokens.json"
  
  echo "🔄 Refreshing Dispatcharr authentication tokens..."
  
  # Get fresh JWT tokens
  local token_response
  token_response=$(curl -s --connect-timeout 10 \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$DISPATCHARR_USERNAME\",\"password\":\"$DISPATCHARR_PASSWORD\"}" \
    "${DISPATCHARR_URL}/api/accounts/token/" 2>/dev/null)
  
  if echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
    # Save tokens to file
    echo "$token_response" > "$token_file"
    
    # Log the refresh
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Tokens refreshed automatically" >> "$DISPATCHARR_LOG"
    
    echo -e "${GREEN}✅ Fresh tokens obtained${RESET}"
    return 0
  else
    echo -e "${RED}❌ Failed to refresh tokens${RESET}"
    echo "Response: $token_response"
    
    # Log the failure
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Token refresh failed: $token_response" >> "$DISPATCHARR_LOG"
    return 1
  fi
}

# ============================================================================
# SEARCH FUNCTIONS
# ============================================================================

shared_station_search() {
  local search_term="$1"
  local page="${2:-1}"
  local output_format="${3:-tsv}"     # "tsv", "count", or "full"
  local runtime_country="${4:-}"      # For future channel name parsing
  local runtime_resolution="${5:-}"   # For future channel name parsing
  local results_per_page=10
  
  local start_index=$(( (page - 1) * results_per_page ))
  
  # Get effective stations file (same source for all searches)
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    if [[ "$output_format" == "count" ]]; then
      echo "0"
    fi
    return 1
  fi
  
  # Escape special regex characters for safety (same as local search)
  local escaped_term=$(echo "$search_term" | sed 's/[[\.*^$()+?{|]/\\&/g')
  
  # Build filters with runtime override capability (for future parsing)
  local resolution_filter=$(build_resolution_filter "$runtime_resolution")
  local country_filter=$(build_country_filter "$runtime_country")
  
  # Core search logic - identical for all callers
  if [[ "$output_format" == "count" ]]; then
    # Return count only
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | length
    ' "$stations_file" 2>/dev/null || echo "0"
  elif [[ "$output_format" == "tsv" ]]; then
    # Return paginated TSV results (for Dispatcharr tables)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      (.stationId // "") + "\t" + 
      (.name // "") + "\t" + 
      (.callSign // "") + "\t" + 
      (.country // "UNK")
    ' "$stations_file" 2>/dev/null
  else
    # Return full JSON results (for local search display)
    jq -r --arg term "$escaped_term" --arg exact_term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
      [.[] | select(
        ((.name // "" | test($term; "i")) or
         (.callSign // "" | test($term; "i")) or
         (.name // "" | . == $exact_term) or
         (.callSign // "" | . == $exact_term))
        '"$resolution_filter"'
        '"$country_filter"'
      )] | .[$start:($start + $limit)][] | 
      [.name, .callSign, (.videoQuality.videoType // ""), .stationId, (.country // "UNK")] | @tsv
    ' "$stations_file" 2>/dev/null
  fi
}

get_available_countries() {
  local countries=""
  
  # Get countries from base cache manifest (if available)
  if [ -f "$BASE_CACHE_MANIFEST" ] && [ -s "$BASE_CACHE_MANIFEST" ]; then
    local base_countries=$(jq -r '.stats.countries_covered[]?' "$BASE_CACHE_MANIFEST" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    if [ -n "$base_countries" ]; then
      countries="$base_countries"
    fi
  fi
  
  # Get countries from user's CSV markets (if available)
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    local csv_countries=$(awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort -u | tr '\n' ',' | sed 's/,$//')
    if [ -n "$csv_countries" ]; then
      if [ -n "$countries" ]; then
        # Combine and deduplicate
        countries=$(echo "$countries,$csv_countries" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
      else
        countries="$csv_countries"
      fi
    fi
  fi
  
  # If no countries found anywhere, try to get from actual station data as fallback
  if [ -z "$countries" ]; then
    local stations_file
    if stations_file=$(get_effective_stations_file 2>/dev/null); then
      countries=$(jq -r '[.[] | .country // empty] | unique | join(",")' "$stations_file" 2>/dev/null)
    fi
  fi
  
  echo "$countries"
}

display_logo() {
  local stid="$1"
  local logo_file="$LOGO_DIR/${stid}.png"
  
  if [[ "$SHOW_LOGOS" == true ]]; then
    if [[ ! -f "$logo_file" ]]; then
      # Get effective stations file for logo lookup
      local stations_file
      stations_file=$(get_effective_stations_file)
      if [ $? -eq 0 ]; then
        local logo_url=$(jq -r --arg id "$stid" '.[] | select(.stationId == $id) | .preferredImage.uri // empty' "$stations_file" | head -n 1)
        if [[ -n "$logo_url" ]]; then
          curl -sL "$logo_url" --output "$logo_file" 2>/dev/null
        fi
      fi
    fi
    
    if [[ -f "$logo_file" ]]; then
      local mime_type=$(file --mime-type -b "$logo_file")
      if [[ "$mime_type" == image/* ]]; then
        viu -h 3 -w 20 "$logo_file" || echo "[no logo available]"
      else
        echo "[no logo available]"
      fi
    else
      echo "[no logo available]"
    fi
  else
    echo "[logo previews disabled]"
  fi
}

run_direct_api_search() {
  # Validate server is configured and accessible
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}No Channels DVR server configured${RESET}"
    echo -e "${CYAN}Configure server in Settings first${RESET}"
    pause_for_user
    return 1
  fi
  
  # Test server connection
  echo "Testing connection to Channels DVR server..."
  if ! curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null; then
    echo -e "${RED}Cannot connect to Channels DVR at $CHANNELS_URL${RESET}"
    echo -e "${CYAN}Check server settings or use Local Database Search instead${RESET}"
    pause_for_user
    return 1
  fi
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct API Search ===${RESET}\n"
    
    echo -e "${YELLOW}⚠️  IMPORTANT LIMITATIONS:${RESET}"
    echo -e "${RED}• Results limited to 6 stations per search${RESET}"
    echo -e "${RED}• No country information available${RESET}"
    echo -e "${RED}• Results filtering (ie resolution, country) not available${RESET}"
    echo -e "${RED}• Less robust than local cache search${RESET}"
    echo
    echo -e "${GREEN}💡 For better results: Use 'Search Local Database'${RESET}"
    echo
    
    read -p "Search API by name or call sign (or 'q' to return to main menu): " SEARCH_TERM
    
    case "$SEARCH_TERM" in
      q|Q|"") break ;;
      *)
        if [[ -z "$SEARCH_TERM" || "$SEARCH_TERM" =~ ^[[:space:]]*$ ]]; then
          echo -e "${RED}Please enter a search term${RESET}"
          pause_for_user
          continue
        fi
        
        perform_direct_api_search "$SEARCH_TERM"
        ;;
    esac
  done
}

perform_direct_api_search() {
  local search_term="$1"
  
  echo -e "\n${YELLOW}Searching API for '$search_term'...${RESET}"
  echo "This may take a moment..."
  
  # Call the TMS API directly
  local api_response
  api_response=$(curl -s --connect-timeout 15 --max-time 30 "$CHANNELS_URL/tms/stations/$search_term" 2>/dev/null)
  
  if [[ -z "$api_response" ]]; then
    echo -e "${RED}No response from API. Check your connection.${RESET}"
    pause_for_user
    return
  fi
  
  # Check if response is valid JSON
  if ! echo "$api_response" | jq empty 2>/dev/null; then
    echo -e "${RED}Invalid response from API${RESET}"
    echo "Response: $(echo "$api_response" | head -c 200)..."
    pause_for_user
    return
  fi
  
  # Process the response and convert to TSV format (fixed column order)
  echo "$api_response" | jq -r '
    .[] | [
      .name // "Unknown", 
      .callSign // "N/A", 
      .videoQuality.videoType // "Unknown", 
      .stationId // "Unknown",
      "API-Direct"
    ] | @tsv
  ' > "$API_SEARCH_RESULTS" 2>/dev/null
  
  display_direct_api_results "$search_term"
}

display_direct_api_results() {
  local search_term="$1"
  
  mapfile -t RESULTS < "$API_SEARCH_RESULTS"
  local count=${#RESULTS[@]}
  
  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No results found for '$search_term' in API${RESET}"
    echo -e "${CYAN}Try: Different spelling, call signs, or partial names${RESET}"
    pause_for_user
    return
  fi
  
  clear
  echo -e "${GREEN}Found $count result(s) for '$search_term' ${YELLOW}(Direct API - Limited to 6)${RESET}"
  echo -e "${YELLOW}Note: No country data available, no filtering applied${RESET}"
  echo
  
  printf "${BOLD}${YELLOW}%-30s %-10s %-8s %-12s${RESET}\n" "Channel Name" "Call Sign" "Quality" "Station ID"
  echo "------------------------------------------------------------------------"
  
  for ((i = 0; i < count; i++)); do
    IFS=$'\t' read -r NAME CALLSIGN RES STID SOURCE <<< "${RESULTS[$i]}" 
    printf "%-30s %-10s %-8s ${CYAN}%-12s${RESET}\n" "$NAME" "$CALLSIGN" "$RES" "$STID"
    
    # Display logo if available
    display_logo "$STID"
    echo
  done
  
  echo -e "${CYAN}💡 Tip: For more results and filtering options, use Local Cache Search${RESET}"
  pause_for_user
}

search_local_database() {
  # Check if any database exists, provide helpful guidance if not
  if ! has_stations_database; then
    clear
    echo -e "${BOLD}${YELLOW}Local Database Search${RESET}\n"
    
    echo -e "${CYAN}No station database available for local search.${RESET}"
    echo
    
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${YELLOW}Base Cache Status: Not found${RESET}"
      echo -e "${CYAN}   Expected location: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}   Contact script distributor for base cache file${RESET}"
    else
      echo -e "${GREEN}Base Cache: $base_count stations available${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}User Cache Status: Empty${RESET}"
      echo -e "${CYAN}   Get base cache: Contact script distributor${RESET}"
      echo -e "${CYAN}   Build user cache: Manage Television Markets → Run User Caching${RESET}"
    else
      echo -e "${GREEN}User Cache: $user_count stations available${RESET}"
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Alternatives:${RESET}"
    echo -e "${GREEN}• Use Direct API Search (requires Channels DVR server)${RESET}"
    echo -e "${GREEN}• Add custom markets and run user caching${RESET}"
    
    pause_for_user
    return
  fi
  
  # Database exists, proceed with search
  run_search_interface
}

direct_api_search() {
  # Check if Channels DVR server is configured
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    clear
    echo -e "${BOLD}${YELLOW}Direct API Search${RESET}\n"
    
    echo -e "${RED}Channels DVR server not configured${RESET}"
    echo -e "${CYAN}Direct API search requires a Channels DVR server connection.${RESET}"
    echo
    echo -e "${BOLD}Would you like to:${RESET}"
    echo -e "${GREEN}1.${RESET} Configure Channels DVR server now"
    echo -e "${GREEN}2.${RESET} Use Local Database Search instead"
    echo -e "${GREEN}3.${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1)
        if configure_channels_server; then
          # Update config file
          sed -i "s|CHANNELS_URL=.*|CHANNELS_URL=\"$CHANNELS_URL\"|" "$CONFIG_FILE"
          echo -e "\n${GREEN}Server configured! Starting Direct API Search...${RESET}"
          pause_for_user
          run_direct_api_search
        else
          echo -e "${YELLOW}Server configuration cancelled${RESET}"
          pause_for_user
        fi
        ;;
      2)
        search_local_database
        ;;
      3|"")
        return
        ;;
      *)
        show_invalid_choice
        ;;
    esac
    return
  fi
  
  # Server is configured, proceed with API search
  run_direct_api_search
}

reverse_station_lookup() {
  local station_id="$1"
  
  if [[ -z "$station_id" ]]; then
    echo -e "${RED}Please provide a station ID${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}Looking up station ID: $station_id${RESET}"
  echo
  
  # Check local database only
  if ! has_stations_database; then
    echo -e "${RED}❌ No local station database available${RESET}"
    echo -e "${CYAN}💡 Build a database using 'Manage Television Markets' → 'Run User Caching'${RESET}"
    echo -e "${CYAN}💡 Or ensure base cache file ($(basename "$BASE_STATIONS_JSON")) is in script directory${RESET}"
    return 1
  fi
  
  local stations_file
  stations_file=$(get_effective_stations_file)
  local local_result=$(jq -r --arg id "$station_id" \
    '.[] | select(.stationId == $id) | 
     "Name: " + (.name // "Unknown") + "\n" +
     "Call Sign: " + (.callSign // "N/A") + "\n" + 
     "Country: " + (.country // "Unknown") + "\n" +
     "Quality: " + (.videoQuality.videoType // "Unknown") + "\n" +
     "Network: " + (.network // "N/A") + "\n" +
     "Source: " + (.source // "Unknown") + "\n" +
     "Logo: " + (.preferredImage.uri // "No logo available")' \
    "$stations_file" 2>/dev/null)
  
  if [[ -n "$local_result" ]]; then
    echo -e "${GREEN}✅ Found in local database:${RESET}"
    echo "$local_result"
    echo
    
    # Show logo if available and enabled
    if [[ "$SHOW_LOGOS" == true ]]; then
      echo -e "${CYAN}Logo preview:${RESET}"
      display_logo "$station_id"
      echo
    fi
    
    # Show additional database info
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${CYAN}📊 Database Info:${RESET}"
    echo "  Total stations in database: $(get_total_stations_count)"
    if [ "$base_count" -gt 0 ]; then
      echo "  Base cache stations: $base_count"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo "  User cache stations: $user_count"
    fi
    
    echo -e "${GREEN}✅ Station found successfully${RESET}"
  else
    echo -e "${RED}❌ Station ID '$station_id' not found in local database${RESET}"
    echo
    echo -e "${CYAN}💡 Suggestions:${RESET}"
    echo -e "  • Check if the station ID is correct"
    echo -e "  • Try searching by name or call sign instead"
    echo -e "  • Add markets containing this station to your cache"
    
    # Show what's available in the database
    local total_count=$(get_total_stations_count)
    echo -e "\n${CYAN}📊 Current database contains $total_count stations${RESET}"
    
    # Suggest similar station IDs if any exist
    local similar_ids=$(jq -r --arg partial "$station_id" \
      '.[] | select(.stationId | contains($partial)) | .stationId' \
      "$stations_file" 2>/dev/null | head -5)
    
    if [[ -n "$similar_ids" ]]; then
      echo -e "\n${YELLOW}💡 Similar station IDs found:${RESET}"
      echo "$similar_ids" | while read -r similar_id; do
        local similar_name=$(jq -r --arg id "$similar_id" \
          '.[] | select(.stationId == $id) | .name // "Unknown"' \
          "$stations_file" 2>/dev/null)
        echo "  • $similar_id ($similar_name)"
      done
    fi
    
    return 1
  fi
  
  return 0
}

parse_channel_name() {
  local channel_name="$1"
  local clean_name="$channel_name"
  local detected_country=""
  local detected_resolution=""
  
  # Country detection patterns (case-insensitive)
  # Look for country codes at word boundaries to avoid false matches
  
  # USA patterns
  if [[ "$clean_name" =~ [[:space:]]+(US|USA)[[:space:]]*$ ]] || \
     [[ "$clean_name" =~ ^(US|USA)[[:space:]]+ ]] || \
     [[ "$clean_name" =~ [[:space:]]+(US|USA)[[:space:]]+ ]]; then
    detected_country="USA"
    clean_name=$(echo "$clean_name" | sed -E 's/[[:space:]]*(US|USA)[[:space:]]*/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
  
  # Canada patterns  
  if [[ "$clean_name" =~ [[:space:]]+(CA|CAN)[[:space:]]*$ ]] || \
     [[ "$clean_name" =~ ^(CA|CAN)[[:space:]]+ ]] || \
     [[ "$clean_name" =~ [[:space:]]+(CA|CAN)[[:space:]]+ ]]; then
    detected_country="CAN"
    clean_name=$(echo "$clean_name" | sed -E 's/[[:space:]]*(CA|CAN)[[:space:]]*/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
  
  # UK/Britain patterns
  if [[ "$clean_name" =~ [[:space:]]+(UK|GBR)[[:space:]]*$ ]] || \
     [[ "$clean_name" =~ ^(UK|GBR)[[:space:]]+ ]] || \
     [[ "$clean_name" =~ [[:space:]]+(UK|GBR)[[:space:]]+ ]]; then
    detected_country="GBR"
    clean_name=$(echo "$clean_name" | sed -E 's/[[:space:]]*(UK|GBR)[[:space:]]*/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
  
  # Germany patterns
  if [[ "$clean_name" =~ [[:space:]]+(DE|DEU)[[:space:]]*$ ]] || \
     [[ "$clean_name" =~ ^(DE|DEU)[[:space:]]+ ]] || \
     [[ "$clean_name" =~ [[:space:]]+(DE|DEU)[[:space:]]+ ]]; then
    detected_country="DEU"
    clean_name=$(echo "$clean_name" | sed -E 's/[[:space:]]*(DE|DEU)[[:space:]]*/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi

  # Clean unwanted characters
  if [[ "$clean_name" =~ [|★◉] ]]; then
     clean_name=$(echo "$clean_name" | sed 's/[|★◉]//g')
  fi
  
  # Resolution detection patterns (order matters - check highest quality first)
  
  # 4K/UHD patterns (UHDTV)
  if [[ "$clean_name" =~ (4K|UHD|UHDTV|Ultra[[:space:]]*HD) ]]; then
    detected_resolution="UHDTV"
    clean_name=$(echo "$clean_name" | sed -E 's/(4K|UHD|UHDTV|Ultra[[:space:]]*HD)//gi' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  # HD patterns (HDTV) - check after 4K to avoid conflicts
  elif [[ "$clean_name" =~ (HD|FHD|1080[ip]?|720[ip]?) ]]; then
    detected_resolution="HDTV"
    clean_name=$(echo "$clean_name" | sed -E 's/(HD|FHD|1080[ip]?|720[ip]?)//gi' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  # SD patterns (SDTV)
  elif [[ "$clean_name" =~ (SD|480[ip]?) ]]; then
    detected_resolution="SDTV"
    clean_name=$(echo "$clean_name" | sed -E 's/(SD|480[ip]?)//gi' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
  
  # Final cleanup: remove extra spaces and common separators
  clean_name=$(echo "$clean_name" | sed 's/[[:space:]]*-[[:space:]]*/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  
  # Output: clean_name|detected_country|detected_resolution
  echo "${clean_name}|${detected_country}|${detected_resolution}"
}

build_resolution_filter() {
  local runtime_resolution="${1:-}"  # Optional runtime override
  
  # Use runtime resolution if provided, otherwise use configured filter
  if [[ -n "$runtime_resolution" ]]; then
    echo "and (.videoQuality.videoType // \"\" | . == \"$runtime_resolution\")"
  elif [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    local filter_conditions=""
    IFS=',' read -ra RESOLUTIONS <<< "$ENABLED_RESOLUTIONS"
    for res in "${RESOLUTIONS[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.videoQuality.videoType // \"\" | . == \"$res\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

build_country_filter() {
  local runtime_country="${1:-}"  # Optional runtime override
  
  # Use runtime country if provided, otherwise use configured filter
  if [[ -n "$runtime_country" ]]; then
    echo "and (.country // \"\" | . == \"$runtime_country\")"
  elif [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
    local filter_conditions=""
    IFS=',' read -ra COUNTRIES <<< "$ENABLED_COUNTRIES"
    for country in "${COUNTRIES[@]}"; do
      if [ -n "$filter_conditions" ]; then
        filter_conditions+=" or "
      fi
      filter_conditions+="(.country // \"\" | . == \"$country\")"
    done
    echo "and ($filter_conditions)"
  else
    echo ""
  fi
}

run_search_interface() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Database Search ===${RESET}\n"
    
    # Show database status
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${GREEN}✅ Database Available: $total_count stations${RESET}"
    if [ "$base_count" -gt 0 ]; then
      echo -e "   Base stations: $base_count"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo -e "   User stations: $user_count"
    fi
    echo
    
    # Show current filter status
    echo -e "${BOLD}Current Filters:${RESET}"
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      echo -e "${GREEN}✅ Resolution: $ENABLED_RESOLUTIONS${RESET}"
    else
      echo -e "${YELLOW}⚠️  Resolution: Disabled${RESET}"
    fi
    
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      echo -e "${GREEN}✅ Country: $ENABLED_COUNTRIES${RESET}"
    else
      echo -e "${YELLOW}⚠️  Country: Disabled${RESET}"
    fi
    echo
    
    read -p "Enter search term (name or call sign) or 'q' to return: " search_term
    
    case "$search_term" in
      q|Q|"") return 0 ;;
      *)
        if [[ -n "$search_term" && ! "$search_term" =~ ^[[:space:]]*$ ]]; then
          perform_search "$search_term"
        else
          echo -e "${RED}Please enter a search term${RESET}"
          pause_for_user
        fi
        ;;
    esac
  done
}

# ============================================================================
# MARKET MANAGEMENT
# ============================================================================

show_current_markets() {
  echo -e "${BOLD}Current Markets:${RESET}"
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    awk -F, 'NR>1 {print $1}' "$CSV_FILE" 2>/dev/null | sort -u | while read -r country; do
      echo -ne "${GREEN}$country${RESET}: "
      grep "^$country," "$CSV_FILE" | cut -d, -f2 | paste -sd ", " -
    done
  else
    echo -e "${YELLOW}No markets configured${RESET}"
  fi
  echo
}

manage_markets() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Market Management ===${RESET}\n"
    
    # Show workflow context
    echo -e "${BLUE}📍 Step 1 of 3: Configure Geographic Markets${RESET}"
    echo -e "${YELLOW}Markets determine which regions' stations will be cached locally.${RESET}"
    echo -e "${YELLOW}Stations from all configured markets will be deduplicated automatically.${RESET}"
    echo
    echo -e "${CYAN}💡 Tips:${RESET}"
    echo -e "• Start with 3-5 markets to test caching speed"
    echo -e "• Add more markets later if needed"
    echo -e "• Larger market lists = longer caching time but more stations"
    echo
    
    show_current_markets
    
    echo -e "${BOLD}Options:${RESET}"
    echo "a) Add Market"
    echo "b) Remove Market"
    echo "c) Import Markets from File"
    echo "d) Export Markets to File"
    echo "e) Clean Up Postal Code Formats"
    echo "f) Force Refresh Market (ignore base cache)"
    echo "r) Ready to Cache - Go to Local Caching"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) add_market && pause_for_user ;;
      b|B) remove_market && pause_for_user ;;
      c|C) import_markets && pause_for_user ;;
      d|D) export_markets && pause_for_user ;;
      e|E) cleanup_existing_postal_codes && pause_for_user ;;
      f|F) force_refresh_market && pause_for_user ;;
      r|R)
        local market_count
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
        if [[ "$market_count" -gt 0 ]]; then
          echo -e "\n${GREEN}Excellent! You have $market_count markets configured.${RESET}"
          echo -e "${CYAN}Proceeding to Local Caching...${RESET}"
          pause_for_user
          run_user_caching
        else
          echo -e "\n${RED}Please add at least one market before caching.${RESET}"
          pause_for_user
        fi
        ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

add_market() {
  echo -e "\n${BOLD}Add New Market${RESET}"
  echo -e "${CYAN}💡 Postal Code Tips:${RESET}"
  echo -e "• UK: Use short format (G1, SW1A, EH1) - not full postcodes"
  echo -e "• USA: Use 5-digit ZIP codes (90210, 10001)"  
  echo -e "• Canada: Use short format (M5V, K1A)"
  echo -e "• If unsure, try the area/district code first"
  echo
  
  local country zip normalized_zip
  
  while true; do
    read -p "Country (3-letter ISO code): " country
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
    
    if [[ -z "$country" ]]; then
      echo -e "${YELLOW}Cancelled${RESET}"
      return 1
    fi
    
    if grep -Fxq "$country" "$VALID_CODES_FILE"; then
      break
    else
      echo -e "${RED}Invalid country code. Must be a valid 3-letter ISO code.${RESET}"
    fi
  done
  
  read -p "ZIP/Postal Code: " zip
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}Cancelled${RESET}"
    return 1
  fi
  
  # Normalize postal code - take only first segment if there's a space
  if [[ "$zip" == *" "* ]]; then
    normalized_zip=$(echo "$zip" | cut -d' ' -f1)
    echo -e "${CYAN}✓ Postal code '$zip' normalized to '$normalized_zip' (first segment only)${RESET}"
    echo -e "${CYAN}  This format works better with TV lineup APIs${RESET}"
  else
    normalized_zip="$zip"
  fi
  
  # Remove any remaining spaces and convert to uppercase for consistency
  normalized_zip=$(echo "$normalized_zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  
  # Create CSV file with header if it doesn't exist
  if [ ! -f "$CSV_FILE" ]; then
    echo "Country,ZIP" > "$CSV_FILE"
  fi
  
  if grep -q "^$country,$normalized_zip$" "$CSV_FILE"; then
    echo -e "${RED}Market $country/$normalized_zip already exists${RESET}"
    return 1
  else
    echo "$country,$normalized_zip" >> "$CSV_FILE"
    echo -e "${GREEN}Added market: $country/$normalized_zip${RESET}"
    return 0
  fi
}

remove_market() {
  echo -e "\n${BOLD}Remove Market${RESET}"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}No markets configured${RESET}"
    return 1
  fi
  
  local country zip
  
  read -p "Country code to remove: " country
  if [[ -z "$country" ]]; then
    echo -e "${YELLOW}Cancelled${RESET}"
    return 1
  fi
  
  read -p "ZIP code to remove: " zip
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}Cancelled${RESET}"
    return 1
  fi
  
  if grep -q "^$country,$zip$" "$CSV_FILE"; then
    sed -i'' "/^$country,$zip$/d" "$CSV_FILE"
    echo -e "${GREEN}Removed market: $country/$zip${RESET}"
    return 0
  else
    echo -e "${RED}Market $country/$zip not found${RESET}"
    return 1
  fi
}

import_markets() {
  echo -e "\n${BOLD}Import Markets from File${RESET}"
  read -p "Enter filename to import from: " filename
  
  if [[ -z "$filename" ]]; then
    echo -e "${YELLOW}Cancelled${RESET}"
    return 1
  fi
  
  if [ ! -f "$filename" ]; then
    echo -e "${RED}File not found: $filename${RESET}"
    return 1
  fi
  
  if confirm_action "Import markets from $filename? This will add to existing markets"; then
    cat "$filename" >> "$CSV_FILE"
    echo -e "${GREEN}Markets imported from $filename${RESET}"
    return 0
  else
    echo -e "${YELLOW}Import cancelled${RESET}"
    return 1
  fi
}

export_markets() {
  echo -e "\n${BOLD}Export Markets to File${RESET}"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}No markets to export${RESET}"
    return 1
  fi
  
  local export_file="markets_export_$(date +%Y%m%d_%H%M%S).csv"
  read -p "Export filename [default: $export_file]: " filename
  filename=${filename:-$export_file}
  
  if cp "$CSV_FILE" "$filename"; then
    echo -e "${GREEN}Markets exported to: $filename${RESET}"
    return 0
  else
    echo -e "${RED}Failed to export markets${RESET}"
    return 1
  fi
}

cleanup_existing_postal_codes() {
  echo -e "\n${BOLD}Clean Up Existing Postal Codes${RESET}"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}No markets file to clean up${RESET}"
    return 1
  fi
  
  local temp_file="${CSV_FILE}.cleanup"
  local changes_made=0
  
  echo "Checking existing postal codes for normalization..."
  
  # Process the CSV file
  {
    # Keep header
    head -1 "$CSV_FILE"
    
    # Process data lines
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      if [[ "$zip" == *" "* ]]; then
        local normalized_zip=$(echo "$zip" | cut -d' ' -f1 | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        echo "$country,$normalized_zip"
        echo -e "${CYAN}Normalized: $country/$zip → $country/$normalized_zip${RESET}" >&2
        changes_made=1
      else
        # Convert to uppercase for consistency
        local clean_zip=$(echo "$zip" | tr '[:lower:]' '[:upper:]')
        echo "$country,$clean_zip"
        if [[ "$zip" != "$clean_zip" ]]; then
          echo -e "${CYAN}Uppercase: $country/$zip → $country/$clean_zip${RESET}" >&2
          changes_made=1
        fi
      fi
    done
  } > "$temp_file"
  
  if [[ $changes_made -eq 1 ]]; then
    mv "$temp_file" "$CSV_FILE"
    echo -e "${GREEN}Postal codes cleaned up successfully${RESET}"
  else
    rm -f "$temp_file"
    echo -e "${GREEN}All postal codes are already in correct format${RESET}"
  fi
  
  return 0
}

force_refresh_market() {
  echo -e "\n${BOLD}Force Refresh Market${RESET}"
  echo -e "${CYAN}This will process a market even if it's in the base cache manifest.${RESET}"
  echo -e "${YELLOW}Use this to add unique stations that may not be in base cache.${RESET}"
  echo
  
  # Show available markets with their status
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    echo -e "${BOLD}Configured Markets:${RESET}"
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      local status=""
      if check_market_in_base_cache "$country" "$zip"; then
        status="${YELLOW}(exact market in base cache)${RESET}"
      elif is_market_cached "$country" "$zip"; then
        status="${GREEN}(processed in user cache)${RESET}"
      else
        status="${CYAN}(unprocessed)${RESET}"
      fi
      echo -e "   • $country / $zip $status"
    done
    echo
  fi
  
  read -p "Enter country code to force refresh: " country
  read -p "Enter ZIP code to force refresh: " zip
  
  if [[ -z "$country" || -z "$zip" ]]; then
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
  
  # Check if market exists in CSV
  if ! grep -q "^$country,$zip$" "$CSV_FILE" 2>/dev/null; then
    echo -e "${RED}Market $country/$zip not found in configured markets${RESET}"
    if confirm_action "Add this market to your configuration?"; then
      echo "$country,$zip" >> "$CSV_FILE"
      echo -e "${GREEN}Market added to configuration${RESET}"
    else
      return 1
    fi
  fi
  
  # Show what will happen
  if check_market_in_base_cache "$country" "$zip"; then
    echo -e "${CYAN}This exact market is in base cache but will be processed anyway${RESET}"
    echo -e "${CYAN}Any unique stations will be added to your user cache${RESET}"
  else
    echo -e "${CYAN}This market is not in base cache and will be fully processed${RESET}"
  fi
  
  if ! confirm_action "Force refresh market $country/$zip?"; then
    echo -e "${YELLOW}Force refresh cancelled${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}Force refreshing market: $country/$zip${RESET}"
  
  # Remove from state tracking to force refresh
  if [ -f "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" > "$CACHED_MARKETS.tmp" 2>/dev/null || true
    mv "$CACHED_MARKETS.tmp" "$CACHED_MARKETS"
  fi
  
  # Create temporary CSV with just this market and set force flag
  local temp_csv="$CACHE_DIR/temp_force_refresh_market.csv"
  {
    echo "Country,ZIP"
    echo "$country,$zip"
  } > "$temp_csv"
  
  # Set force refresh flag and temporarily swap CSV files
  export FORCE_REFRESH_ACTIVE=true
  local original_csv="$CSV_FILE"
  CSV_FILE="$temp_csv"
  
  perform_caching
  
  # Restore original CSV and clear force flag
  CSV_FILE="$original_csv"
  unset FORCE_REFRESH_ACTIVE
  rm -f "$temp_csv"
  
  echo -e "${GREEN}✅ Market $country/$zip force refreshed${RESET}"
}

perform_search() {
  local search_term="$1"
  local page=1
  local results_per_page=10
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Search Results ===${RESET}\n"
    echo -e "${YELLOW}Search term: '$search_term' (Page $page)${RESET}"
    
    # Show active filters
    local filter_status=""
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      filter_status+="Resolution: $ENABLED_RESOLUTIONS "
    fi
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      filter_status+="Country: $ENABLED_COUNTRIES "
    fi
    if [ -n "$filter_status" ]; then
      echo -e "${BLUE}Active Filters: $filter_status${RESET}"
    fi
    echo
    
    # Get search results using shared function
    local results
    results=$(shared_station_search "$search_term" "$page" "full")
    
    local total_results
    total_results=$(shared_station_search "$search_term" 1 "count")
    
    if [[ -z "$results" ]]; then
      echo -e "${YELLOW}No results found for '$search_term'${RESET}"
      if [ "$FILTER_BY_RESOLUTION" = "true" ] || [ "$FILTER_BY_COUNTRY" = "true" ]; then
        echo -e "${CYAN}💡 Try disabling filters in Settings if results seem limited${RESET}"
      fi
    else
      echo -e "${GREEN}Found $total_results total results${RESET}"
      echo
      
      # Enhanced table header
      printf "${BOLD}${YELLOW}%-3s %-30s %-10s %-8s %-12s %s${RESET}\n" "Key" "Channel Name" "Call Sign" "Quality" "Station ID" "Country"
      echo "--------------------------------------------------------------------------------"
      
      local result_count=0
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
      
      # Process search results (TSV format from shared_station_search)
      while IFS=$'\t' read -r name call_sign quality station_id country; do
        [[ -z "$name" ]] && continue
        
        local key="${key_letters[$result_count]}"
        
        # Format table row
        printf "%-3s " "${key})"
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        echo -e "${GREEN}${country}${RESET}"
        
        # Display logo if enabled
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "[logo previews disabled]"
        fi
        echo
        
        ((result_count++))
      done <<< "$results"
    fi
    
    # Calculate pagination info
    local total_pages=$(( (total_results + results_per_page - 1) / results_per_page ))
    [[ $total_pages -eq 0 ]] && total_pages=1
    
    echo -e "${BOLD}Page $page of $total_pages${RESET}"
    echo
    echo -e "${BOLD}Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo "a-j) View detailed info for selected station"
    [[ $page -lt $total_pages ]] && echo "n) Next page"
    [[ $page -gt 1 ]] && echo "p) Previous page"
    echo "s) New search"
    echo "q) Back to search menu"
    echo
    
    read -p "Your choice: " choice
    
    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          show_station_details "$choice" "$results"
        else
          echo -e "${RED}No results to select from${RESET}"
          sleep 1
        fi
        ;;
      n|N)
        if [[ $page -lt $total_pages ]]; then
          ((page++))
        else
          echo -e "${YELLOW}Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $page -gt 1 ]]; then
          ((page--))
        else
          echo -e "${YELLOW}Already on first page${RESET}"
          sleep 1
        fi
        ;;
      s|S)
        return 0  # Return to search interface for new search
        ;;
      q|Q|"")
        return 0  # Return to search interface
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
}

show_station_details() {
  local choice="$1"
  local results="$2"
  
  # Convert letter to array index
  local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
  local index=-1
  local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
  
  for ((idx=0; idx<10; idx++)); do
    if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
      index=$idx
      break
    fi
  done
  
  if [[ $index -ge 0 ]]; then
    # Get the selected result (line number = index + 1)
    local selected_line=$(echo "$results" | sed -n "$((index + 1))p")
    
    if [[ -n "$selected_line" ]]; then
      IFS=$'\t' read -r name call_sign quality station_id country <<< "$selected_line"
      
      clear
      echo -e "${BOLD}${CYAN}=== Station Details ===${RESET}\n"
      
      echo -e "${BOLD}Basic Information:${RESET}"
      echo -e "Name: ${GREEN}$name${RESET}"
      echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
      echo -e "Station ID: ${GREEN}$station_id${RESET}"
      echo -e "Country: ${GREEN}$country${RESET}"
      echo -e "Quality: ${GREEN}$quality${RESET}"
      echo
      
      # Get additional details from database
      local stations_file
      stations_file=$(get_effective_stations_file)
      if [[ $? -eq 0 ]]; then
        local details=$(jq -r --arg id "$station_id" \
          '.[] | select(.stationId == $id) | 
           "Network: " + (.network // "N/A") + "\n" +
           "Language: " + (.language // "N/A") + "\n" +
           "Logo URL: " + (.preferredImage.uri // "N/A") + "\n" +
           "Description: " + (.description // "N/A")' \
          "$stations_file" 2>/dev/null)
        
        if [[ -n "$details" ]]; then
          echo -e "${BOLD}Additional Details:${RESET}"
          echo "$details"
          echo
        fi
      fi
      
      # Show logo if available
      if [[ "$SHOW_LOGOS" == true ]]; then
        echo -e "${BOLD}Logo Preview:${RESET}"
        display_logo "$station_id"
        echo
      fi
      
      pause_for_user
    else
      echo -e "${RED}Could not retrieve station details${RESET}"
      sleep 1
    fi
  else
    echo -e "${RED}Invalid selection${RESET}"
    sleep 1
  fi
}

# ============================================================================
# SETTINGS MANAGEMENT
# ============================================================================

settings_menu() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Settings ===${RESET}\n"
    
    display_current_settings
    
    echo -e "${BOLD}Options:${RESET}"
    echo "a) Change Channels DVR Server"
    echo "b) Toggle Logo Display"
    echo "c) Configure Resolution Filter"
    echo "d) Configure Country Filter"
    echo "e) View Cache Statistics"
    echo "f) Reset All Settings"
    echo "g) Export Settings"
    echo "h) Export Station Database to CSV"
    echo "i) Configure Dispatcharr Integration"
    echo "j) Developer Information"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) change_server_settings && pause_for_user ;;
      b|B) toggle_logo_display && pause_for_user ;;
      c|C) configure_resolution_filter && pause_for_user ;;
      d|D) configure_country_filter && pause_for_user ;;
      e|E) show_detailed_cache_stats && pause_for_user ;;
      f|F) reset_all_settings && pause_for_user ;;
      g|G) export_settings && pause_for_user ;;
      h|H) export_stations_to_csv && pause_for_user ;;
      i|I) configure_dispatcharr_connection && pause_for_user ;;
      j|J) developer_information && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

developer_information() {
  while true; do
    clear
    echo -e "${BOLD}${BLUE}=== Developer Information ===${RESET}\n"
    echo -e "${YELLOW}This section contains technical details for script developers and maintainers.${RESET}"
    echo -e "${CYAN}End users typically don't need this information.${RESET}"
    echo
    
    echo -e "${BOLD}Options:${RESET}"
    echo "a) File System Layout"
    echo "b) Base Cache Manifest Status"
    echo "c) Cache State Tracking Details"
    echo "d) Function Dependencies Map"
    echo "e) Base Cache Manifest Creation Guide"
    echo "f) Debug: Raw Cache Files"
    echo "g) Script Architecture Overview"
    echo "q) Back to Settings"
    echo
    
    read -p "Select option: " dev_choice
    
    case $dev_choice in
      a|A) show_filesystem_layout && pause_for_user ;;
      b|B) show_manifest_status && pause_for_user ;;
      c|C) show_cache_state_details && pause_for_user ;;
      d|D) show_function_dependencies && pause_for_user ;;
      e|E) show_manifest_creation_guide && pause_for_user ;;
      f|F) show_raw_cache_debug && pause_for_user ;;
      g|G) show_script_architecture && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

show_filesystem_layout() {
  echo -e "\n${BOLD}${BLUE}=== File System Layout ===${RESET}"
  echo -e "${CYAN}Critical file paths and their purposes:${RESET}"
  echo
  
  echo -e "${BOLD}Core Files (Script Directory):${RESET}"
  echo "  Script: $(realpath "$0" 2>/dev/null || echo "globalstationsearch.sh")"
  echo "  Version: $VERSION ($(date '+%Y-%m-%d'))"
  echo "  Base Cache: $BASE_STATIONS_JSON"
  echo "  Base Manifest: $BASE_CACHE_MANIFEST"
  echo "  Config: $CONFIG_FILE"
  echo "  Markets CSV: $CSV_FILE"
  echo
  
  echo -e "${BOLD}Cache Directory: $CACHE_DIR${RESET}"
  echo "  User Cache: $USER_STATIONS_JSON"
  echo "  Combined Cache: $COMBINED_STATIONS_JSON (runtime only)"
  echo
  
  echo -e "${BOLD}State Tracking:${RESET}"
  echo "  Markets: $CACHED_MARKETS"
  echo "  Lineups: $CACHED_LINEUPS"
  echo "  Mapping: $LINEUP_TO_MARKET"
  echo "  Log: $CACHE_STATE_LOG"
  echo
  
  echo -e "${BOLD}Search & Integration:${RESET}"
  echo "  Search Results: $SEARCH_RESULTS"
  echo "  API Results: $API_SEARCH_RESULTS"
  echo "  Dispatcharr Cache: $DISPATCHARR_CACHE"
  echo "  Dispatcharr Matches: $DISPATCHARR_MATCHES"
  echo "  Dispatcharr Log: $DISPATCHARR_LOG"
  echo "  Dispatcharr Tokens: $DISPATCHARR_TOKENS"
  echo
  
  echo -e "${BOLD}Temporary/Working:${RESET}"
  echo "  Station Cache Dir: $STATION_CACHE_DIR"
  echo "  Logo Cache: $LOGO_DIR"
  echo "  Lineup Cache: $LINEUP_CACHE"
  echo "  Backup Dir: $BACKUP_DIR"
  echo
  
  echo -e "${BOLD}File Status Check:${RESET}"
  local files_to_check=(
    "$BASE_STATIONS_JSON:Base Cache"
    "$BASE_CACHE_MANIFEST:Base Manifest"
    "$USER_STATIONS_JSON:User Cache"
    "$CONFIG_FILE:Configuration"
    "$CSV_FILE:Markets CSV"
    "$CACHED_MARKETS:Market State"
    "$CACHED_LINEUPS:Lineup State"
  )
  
  for file_info in "${files_to_check[@]}"; do
    IFS=':' read -r file_path file_desc <<< "$file_info"
    if [ -f "$file_path" ]; then
      local size=$(ls -lh "$file_path" 2>/dev/null | awk '{print $5}')
      echo -e "  ${GREEN}✅ $file_desc: $size${RESET}"
    else
      echo -e "  ${RED}❌ $file_desc: Missing${RESET}"
    fi
  done
}

show_manifest_status() {
  echo -e "\n${BOLD}${BLUE}=== Base Cache Manifest Status ===${RESET}"
  
  if [ ! -f "$BASE_CACHE_MANIFEST" ]; then
    echo -e "${RED}❌ Base cache manifest not found${RESET}"
    echo -e "${CYAN}Expected location: $BASE_CACHE_MANIFEST${RESET}"
    echo -e "${YELLOW}Use create_base_cache_manifest.sh to generate${RESET}"
    return 1
  fi
  
  echo -e "${GREEN}✅ Base cache manifest found${RESET}"
  echo
  
  # Show manifest metadata
  echo -e "${BOLD}Manifest Metadata:${RESET}"
  local created=$(jq -r '.created // "Unknown"' "$BASE_CACHE_MANIFEST" 2>/dev/null)
  local version=$(jq -r '.manifest_version // "Unknown"' "$BASE_CACHE_MANIFEST" 2>/dev/null)
  local base_file=$(jq -r '.base_cache_file // "Unknown"' "$BASE_CACHE_MANIFEST" 2>/dev/null)
  echo "  Created: $created"
  echo "  Version: $version"
  echo "  Base File: $base_file"
  echo
  
  # Show statistics
  echo -e "${BOLD}Coverage Statistics:${RESET}"
  if command -v jq >/dev/null 2>&1; then
    local total_stations=$(jq -r '.stats.total_stations // 0' "$BASE_CACHE_MANIFEST" 2>/dev/null)
    local total_markets=$(jq -r '.stats.total_markets // 0' "$BASE_CACHE_MANIFEST" 2>/dev/null)
    local total_lineups=$(jq -r '.stats.total_lineups // 0' "$BASE_CACHE_MANIFEST" 2>/dev/null)
    local countries=$(jq -r '.stats.countries_covered[]? // empty' "$BASE_CACHE_MANIFEST" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    echo "  Total Stations: $total_stations"
    echo "  Total Markets: $total_markets"
    echo "  Total Lineups: $total_lineups"
    echo "  Countries: $countries"
  else
    echo "  jq not available for detailed stats"
  fi
  echo
  
  # Show file info
  local manifest_size=$(ls -lh "$BASE_CACHE_MANIFEST" 2>/dev/null | awk '{print $5}')
  echo -e "${BOLD}File Information:${RESET}"
  echo "  File Size: $manifest_size"
  echo "  Location: $BASE_CACHE_MANIFEST"
  echo
  
  # Show usage info
  echo -e "${BOLD}Integration Status:${RESET}"
  local covered_countries=$(get_base_cache_countries)
  if [ -n "$covered_countries" ]; then
    echo -e "  ${GREEN}✅ Active - Markets from these countries may be skipped: $covered_countries${RESET}"
  else
    echo -e "  ${YELLOW}⚠️  Manifest exists but no country data found${RESET}"
  fi
}

show_cache_state_details() {
  echo -e "\n${BOLD}${BLUE}=== Cache State Tracking Details ===${RESET}"
  echo -e "${CYAN}Technical details about cache state management:${RESET}"
  echo
  
  echo -e "${BOLD}State Files Purpose:${RESET}"
  echo "  $CACHED_MARKETS - JSONL file tracking processed markets"
  echo "  $CACHED_LINEUPS - JSONL file tracking processed lineups"
  echo "  $LINEUP_TO_MARKET - JSON mapping lineups to source markets"
  echo "  $CACHE_STATE_LOG - Human-readable processing log"
  echo
  
  echo -e "${BOLD}Current State:${RESET}"
  
  # Markets state
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    local market_entries=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
    echo "  Cached Markets: $market_entries entries"
    
    # Show last few markets processed
    echo "  Recent Markets:"
    tail -3 "$CACHED_MARKETS" 2>/dev/null | jq -r '"    " + .country + "/" + .zip + " (" + .timestamp + ")"' 2>/dev/null || echo "    (unable to parse recent entries)"
  else
    echo "  Cached Markets: No data"
  fi
  echo
  
  # Lineups state
  if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
    local lineup_entries=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
    echo "  Cached Lineups: $lineup_entries entries"
    
    # Show total stations tracked
    local total_stations=$(jq -s '.[] | .stations_found' "$CACHED_LINEUPS" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    echo "  Total Stations (pre-dedup): $total_stations"
  else
    echo "  Cached Lineups: No data"
  fi
  echo
  
  # Mapping state
  if [ -f "$LINEUP_TO_MARKET" ] && [ -s "$LINEUP_TO_MARKET" ]; then
    local mapping_count=$(jq 'length' "$LINEUP_TO_MARKET" 2>/dev/null || echo "0")
    echo "  Lineup-to-Market Mappings: $mapping_count"
  else
    echo "  Lineup-to-Market Mappings: No data"
  fi
  echo
  
  # Log state
  if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
    local log_lines=$(wc -l < "$CACHE_STATE_LOG" 2>/dev/null || echo "0")
    local last_entry=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
    echo "  State Log: $log_lines entries"
    echo "  Last Activity: $last_entry"
  else
    echo "  State Log: No data"
  fi
  echo
  
  echo -e "${BOLD}Functions Using State:${RESET}"
  echo "  record_market_processed() - Adds market entries"
  echo "  record_lineup_processed() - Adds lineup entries"
  echo "  is_market_cached() - Checks if market already processed"
  echo "  is_lineup_cached() - Checks if lineup already processed"
  echo "  get_unprocessed_markets() - Gets markets needing processing"
}

show_function_dependencies() {
  echo -e "\n${BOLD}${BLUE}=== Function Dependencies Map ===${RESET}"
  echo -e "${CYAN}Key function relationships and call chains:${RESET}"
  echo
  
  echo -e "${BOLD}Cache Management Chain:${RESET}"
  echo "  get_effective_stations_file()"
  echo "    ├── get_stations_breakdown()"
  echo "    ├── has_stations_database()"
  echo "    └── Used by: all search functions"
  echo
  echo "  perform_caching()"
  echo "    ├── init_user_cache()"
  echo "    ├── init_cache_state_tracking()"
  echo "    ├── record_market_processed()"
  echo "    ├── record_lineup_processed()"
  echo "    ├── enhance_stations()"
  echo "    └── add_stations_to_user_cache()"
  echo
  
  echo -e "${BOLD}Search Function Chain:${RESET}"
  echo "  shared_station_search()"
  echo "    ├── build_resolution_filter()"
  echo "    ├── build_country_filter()"
  echo "    └── Used by: search_stations_by_name(), perform_search()"
  echo
  echo "  search_local_database()"
  echo "    ├── check_database_exists()"
  echo "    ├── run_search_interface()"
  echo "    └── perform_search()"
  echo
  
  echo -e "${BOLD}Base Cache Manifest Chain:${RESET}"
  echo "  check_market_in_base_cache()"
  echo "    └── Used by: perform_caching(), run_incremental_update()"
  echo
  echo "  init_base_cache_manifest()"
  echo "    └── Called on startup"
  echo
  
  echo -e "${BOLD}Dispatcharr Integration Chain:${RESET}"
  echo "  run_dispatcharr_integration()"
  echo "    ├── check_dispatcharr_connection()"
  echo "    ├── scan_missing_stationids()"
  echo "    ├── interactive_stationid_matching()"
  echo "    └── batch_update_stationids()"
  echo
  
  echo -e "${BOLD}Critical Initialization Functions:${RESET}"
  echo "  setup_config() - Loads/creates configuration"
  echo "  check_dependencies() - Validates required tools"
  echo "  setup_directories() - Creates cache structure"
  echo "  init_base_cache() - Sets up base cache system"
  echo "  init_user_cache() - Sets up user cache system"
}

show_manifest_creation_guide() {
  echo -e "\n${BOLD}${BLUE}=== Base Cache Manifest Creation Guide ===${RESET}"
  echo -e "${CYAN}Information for maintaining the base cache manifest system:${RESET}"
  echo
  
  echo -e "${BOLD}Purpose:${RESET}"
  echo "The base cache manifest enables efficient user caching by preventing"
  echo "redundant processing of markets already covered by the distributed base cache."
  echo
  
  echo -e "${BOLD}When to Create/Update Manifest:${RESET}"
  echo -e "${GREEN}✅ Required:${RESET}"
  echo "  • After building a fresh base cache from scratch"
  echo "  • When adding new markets/countries to existing base cache"
  echo "  • Before packaging base cache for distribution"
  echo "  • When migrating from legacy cache systems"
  echo
  echo -e "${YELLOW}🔄 Optional:${RESET}"
  echo "  • To verify existing manifest accuracy"
  echo "  • When troubleshooting incorrect skipping behavior"
  echo
  echo -e "${RED}❌ Never Needed:${RESET}"
  echo "  • Regular end-user operations (searching, user caching)"
  echo "  • Configuration changes (settings, markets, filters)"
  echo "  • Script updates that don't affect base cache content"
  echo
  
  echo -e "${BOLD}Prerequisites:${RESET}"
  echo "Files needed in script directory:"
  echo "  • all_stations_base.json (base station cache)"
  echo "  • sampled_markets.csv (markets used to build base cache)"
  echo "  • cache/cached_markets.jsonl (market processing state)"
  echo "  • cache/cached_lineups.jsonl (lineup processing state)"
  echo "  • cache/lineup_to_market.json (lineup-to-market mapping)"
  echo
  
  echo -e "${BOLD}Usage (Separate Tool):${RESET}"
  echo -e "${CYAN}Note: create_base_cache_manifest.sh is NOT bundled with this script${RESET}"
  echo
  echo "Basic usage:"
  echo "  ./create_base_cache_manifest.sh"
  echo
  echo "With options:"
  echo "  ./create_base_cache_manifest.sh -v              # Verbose output"
  echo "  ./create_base_cache_manifest.sh -f              # Force overwrite"
  echo "  ./create_base_cache_manifest.sh --dry-run       # Preview only"
  echo
  echo "Custom files:"
  echo "  ./create_base_cache_manifest.sh \\"
  echo "    --base-cache custom_base.json \\"
  echo "    --manifest custom_manifest.json \\"
  echo "    --csv custom_markets.csv"
  echo
  
  echo -e "${BOLD}Output:${RESET}"
  echo "Creates: all_stations_base_manifest.json"
  echo "Contains: Complete market/lineup coverage data for skipping logic"
  echo
  
  echo -e "${BOLD}Distribution:${RESET}"
  echo "When distributing the script, include BOTH files:"
  echo "  • all_stations_base.json (station data)"
  echo "  • all_stations_base_manifest.json (coverage manifest)"
  echo
  echo "Place both in the same directory as the main script."
  echo
  
  echo -e "${BOLD}Validation:${RESET}"
  echo "After creating manifest:"
  echo "  jq empty all_stations_base_manifest.json        # Check validity"
  echo "  jq '.stats' all_stations_base_manifest.json     # View statistics"
  echo "  jq '.markets | length' all_stations_base_manifest.json  # Market count"
}

show_raw_cache_debug() {
  echo -e "\n${BOLD}${BLUE}=== Debug: Raw Cache Files ===${RESET}"
  echo -e "${YELLOW}⚠️  This shows technical file contents for debugging purposes${RESET}"
  echo
  
  echo -e "${BOLD}Cache Directory Contents:${RESET}"
  if [ -d "$CACHE_DIR" ]; then
    echo "Directory: $CACHE_DIR"
    ls -la "$CACHE_DIR" 2>/dev/null | head -20
    local total_files=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
    echo "Total files: $total_files"
    echo
  else
    echo "Cache directory not found: $CACHE_DIR"
    return 1
  fi
  
  echo -e "${BOLD}State File Samples:${RESET}"
  
  if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
    echo "Recent market entries (last 3):"
    tail -3 "$CACHED_MARKETS" | jq . 2>/dev/null || tail -3 "$CACHED_MARKETS"
    echo
  fi
  
  if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
    echo "Recent lineup entries (last 2):"
    tail -2 "$CACHED_LINEUPS" | jq . 2>/dev/null || tail -2 "$CACHED_LINEUPS"
    echo
  fi
  
  if [ -f "$LINEUP_TO_MARKET" ] && [ -s "$LINEUP_TO_MARKET" ]; then
    echo "Lineup mapping sample (first 3 entries):"
    jq 'to_entries | .[0:3]' "$LINEUP_TO_MARKET" 2>/dev/null || echo "Unable to parse mapping file"
    echo
  fi
  
  echo -e "${BOLD}Temporary Files:${RESET}"
  local temp_count=$(find "$CACHE_DIR" -name "last_raw_*.json" 2>/dev/null | wc -l)
  echo "Temporary API response files: $temp_count"
  if [ "$temp_count" -gt 0 ] && [ "$temp_count" -lt 10 ]; then
    echo "Recent temp files:"
    find "$CACHE_DIR" -name "last_raw_*.json" -exec basename {} \; | head -5
  elif [ "$temp_count" -ge 10 ]; then
    echo "Many temp files found - consider cleanup"
  fi
  echo
  
  echo -e "${BOLD}Cache Integrity Check:${RESET}"
  local issues=0
  
  # Check JSON validity of key files
  for file in "$USER_STATIONS_JSON" "$BASE_CACHE_MANIFEST" "$LINEUP_TO_MARKET"; do
    if [ -f "$file" ]; then
      if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✅ Valid JSON: $(basename "$file")${RESET}"
      else
        echo -e "${RED}❌ Invalid JSON: $(basename "$file")${RESET}"
        ((issues++))
      fi
    fi
  done
  
  if [ "$issues" -eq 0 ]; then
    echo -e "${GREEN}✅ No JSON integrity issues found${RESET}"
  else
    echo -e "${RED}❌ Found $issues JSON integrity issues${RESET}"
  fi
}

show_script_architecture() {
  echo -e "\n${BOLD}${BLUE}=== Script Architecture Overview ===${RESET}"
  echo -e "${CYAN}High-level design and component relationships:${RESET}"
  echo
  
  echo -e "${BOLD}Version Information:${RESET}"
  echo "  Script Version: $VERSION"
  echo "  Last Modified: 2025/06/01"
  echo "  Architecture: Two-file cache system with manifest optimization"
  echo "  Release Stage: Stable"
  echo
  
  echo -e "${BOLD}Core Components:${RESET}"
  echo
  echo -e "${YELLOW}1. Station Database System:${RESET}"
  echo "   • Base Cache: Pre-distributed stations (read-only)"
  echo "   • User Cache: Locally-built stations (user-writable)"
  echo "   • Combined Cache: Runtime merge of base + user (temporary)"
  echo "   • Manifest System: Tracks base cache coverage for optimization"
  echo
  echo -e "${YELLOW}2. Market Management:${RESET}"
  echo "   • CSV Configuration: User-defined markets to cache"
  echo "   • State Tracking: JSONL files track processing progress"
  echo "   • Incremental Updates: Only process new/changed markets"
  echo "   • Force Refresh: Override base cache coverage when needed"
  echo
  echo -e "${YELLOW}3. Search System:${RESET}"
  echo "   • Local Search: Fast queries against cached station data"
  echo "   • API Search: Direct queries to Channels DVR server"
  echo "   • Filtering: Resolution, country, and text-based filters"
  echo "   • Shared Functions: Common search logic for consistency"
  echo
  echo -e "${YELLOW}4. Integration Layer:${RESET}"
  echo "   • Dispatcharr: Channel field population and station ID matching"
  echo "   • Logo Workflow: Station logo upload and channel assignment"
  echo "   • Channels DVR: Station data API and logo retrieval"
  echo "   • Authentication: JWT token management for Dispatcharr"
  echo
  echo -e "${YELLOW}5. User Interface:${RESET}"
  echo "   • Menu System: Hierarchical navigation with consistent patterns"
  echo "   • Status Display: Real-time system status and statistics"
  echo "   • Progress Tracking: Visual feedback during long operations"
  echo "   • Error Handling: Graceful degradation and helpful messages"
  echo
  
  echo -e "${BOLD}Data Flow:${RESET}"
  echo "1. Startup → Load config, check dependencies, init caches"
  echo "2. Market Config → User defines ZIP codes to cache"
  echo "3. User Caching → API calls → Station collection → Deduplication"
  echo "4. Search → Query combined cache → Filter → Display results"
  echo "5. Integration → Match stations → Update external systems"
  echo
  
  echo -e "${BOLD}Key Design Decisions:${RESET}"
  echo "• Two-file cache system: Separates distributed vs user data"
  echo "• JSONL state tracking: Enables incremental processing"
  echo "• Manifest optimization: Prevents redundant API calls"
  echo "• Shared search functions: Consistency across local/API search"
  echo "• Modular integration: Clean separation of Dispatcharr/Channels DVR"
  echo "• Semantic versioning: Professional release management"
  echo
  
  echo -e "${BOLD}Configuration Files:${RESET}"
  echo "• $CONFIG_FILE: Main script settings"
  echo "• $CSV_FILE: User-defined markets"
  echo "• Cache state files: Processing progress tracking"
  echo "• Dispatcharr tokens: Authentication cache"
  echo "• Dispatcharr logos: Logo URL to ID mapping cache"
}

display_current_settings() {
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)
  
  echo -e "${BOLD}Current Configuration:${RESET}"
  
  # Station Database Status (matching main menu format)
  if [ "$base_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Base Station Database: $base_count stations${RESET}"
    echo -e "   (Comprehensive USA, CAN, and GBR coverage)"
  else
    echo -e "${YELLOW}⚠️  Base Station Database: Not found${RESET}"
  fi
  
  # User market configuration
  local market_count
  if [ -f "$CSV_FILE" ]; then
    market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$market_count" -gt 0 ]; then
      echo -e "📍 User Markets Configured: $market_count"
    else
      echo -e "📍 User Markets Configured: ${YELLOW}0 (no custom markets)${RESET}"
    fi
  else
    echo -e "📍 User Markets Configured: ${YELLOW}0 (no custom markets)${RESET}"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    echo -e "${GREEN}✅ User Station Database: $user_count stations${RESET}"
  else
    echo -e "${YELLOW}⚠️  User Station Database: No custom stations${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total Available Stations: $total_count${RESET}"
  
  # Search capability status
  if [ "$total_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Local Search: Available with full features${RESET}"
  else
    echo -e "${RED}❌ Local Search: No station data available${RESET}"
  fi
  
  # Integration Status
  if [[ -n "${CHANNELS_URL:-}" ]]; then
    if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Channels DVR: Connected ($CHANNELS_URL)${RESET}"
    else
      echo -e "${RED}❌ Channels DVR: Connection Failed ($CHANNELS_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Channels DVR: Not configured (optional)${RESET}"
  fi
  
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    if check_dispatcharr_connection 2>/dev/null; then
      echo -e "${GREEN}✅ Dispatcharr: Connected ($DISPATCHARR_URL)${RESET}"
    else
      echo -e "${RED}❌ Dispatcharr: Connection Failed ($DISPATCHARR_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Dispatcharr: Integration Disabled${RESET}"
  fi
  
  # Additional Settings-Specific Information
  echo -e "${GREEN}✅ Logo Display: $([ "$SHOW_LOGOS" = "true" ] && echo "Enabled" || echo "Disabled")${RESET}"
  if command -v viu &> /dev/null; then
    echo -e "   (viu dependency: ${GREEN}Available${RESET})"
  else
    echo -e "   (viu dependency: ${RED}Not installed${RESET})"
  fi
  
  if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    echo -e "${GREEN}✅ Resolution Filter: Enabled${RESET}"
    echo -e "   (Active filters: ${YELLOW}$ENABLED_RESOLUTIONS${RESET})"
  else
    echo -e "${RED}❌ Resolution Filter: Disabled${RESET}"
  fi
  
  if [ "$FILTER_BY_COUNTRY" = "true" ]; then
    echo -e "${GREEN}✅ Country Filter: Enabled${RESET}"
    echo -e "   (Active filters: ${YELLOW}$ENABLED_COUNTRIES${RESET})"
  else
    echo -e "${RED}❌ Country Filter: Disabled${RESET}"
  fi
  echo
}

change_server_settings() {
  echo -e "\n${BOLD}Change Channels DVR Server${RESET}"
  echo "Current: $CHANNELS_URL"
  echo
  
  local current_ip=$(echo "$CHANNELS_URL" | cut -d'/' -f3 | cut -d':' -f1)
  local current_port=$(echo "$CHANNELS_URL" | cut -d':' -f3)
  
  local new_ip new_port
  
  read -p "Enter new IP address [current: $current_ip, Enter to keep]: " new_ip
  new_ip=${new_ip:-$current_ip}
  
  read -p "Enter new port [current: $current_port, Enter to keep]: " new_port
  new_port=${new_port:-$current_port}
  
  # Validate inputs
  if [[ ! "$new_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$|^localhost$ ]]; then
    echo -e "${RED}Invalid IP address format${RESET}"
    return 1
  fi
  
  if [[ ! "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
    echo -e "${RED}Invalid port number${RESET}"
    return 1
  fi
  
  local new_url="http://$new_ip:$new_port"
  
  # Test connection if settings changed
  if [[ "$new_url" != "$CHANNELS_URL" ]]; then
    echo "Testing connection to $new_url..."
    
    if curl -s --connect-timeout 5 "$new_url" >/dev/null; then
      echo -e "${GREEN}Connection successful!${RESET}"
    else
      echo -e "${RED}Connection failed${RESET}"
      if ! confirm_action "Save settings anyway?"; then
        return 1
      fi
    fi
    
    # Update settings
    CHANNELS_URL="$new_url"
    sed -i "s|CHANNELS_URL=.*|CHANNELS_URL=\"$CHANNELS_URL\"|" "$CONFIG_FILE"
    echo -e "${GREEN}Server settings updated${RESET}"
  else
    echo -e "${YELLOW}No changes made${RESET}"
  fi
  
  return 0
}

toggle_logo_display() {
  if ! command -v viu &> /dev/null; then
    echo -e "\n${RED}Cannot enable logo display: viu is not installed${RESET}"
    echo
    echo -e "${BOLD}${CYAN}How to install viu:${RESET}"
    echo -e "${YELLOW}Option 1 (Rust/Cargo):${RESET}"
    echo "  cargo install viu"
    echo
    echo -e "${YELLOW}Option 2 (Package Manager):${RESET}"
    echo "  # Ubuntu/Debian:"
    echo "  sudo apt install viu"
    echo
    echo "  # macOS:"
    echo "  brew install viu"
    echo
    echo "  # Arch Linux:"
    echo "  sudo pacman -S viu"
    echo
    echo -e "${CYAN}After installing viu, you can enable logo display in Settings.${RESET}"
    echo -e "${CYAN}Logo display will show channel logos during search results.${RESET}"
    return 1
  fi
  
  if [ "$SHOW_LOGOS" = "true" ]; then
    SHOW_LOGOS=false
    echo -e "${YELLOW}Logo display disabled${RESET}"
  else
    SHOW_LOGOS=true
    echo -e "${GREEN}Logo display enabled${RESET}"
    echo -e "${CYAN}Channel logos will now be displayed during search results${RESET}"
  fi
  
  # Update config file
  sed -i "s/SHOW_LOGOS=.*/SHOW_LOGOS=$SHOW_LOGOS/" "$CONFIG_FILE"
  return 0
}

configure_resolution_filter() {
  echo -e "\n${BOLD}Resolution Filter Configuration${RESET}"
  echo "Current status: $([ "$FILTER_BY_RESOLUTION" = "true" ] && echo "Enabled" || echo "Disabled")"
  echo "Current filters: $ENABLED_RESOLUTIONS"
  echo
  
  if confirm_action "Enable resolution filtering?"; then
    FILTER_BY_RESOLUTION=true
    
    echo -e "\nSelect resolutions to include (space-separated):"
    echo "Available: SDTV HDTV UHDTV"
    read -p "Enter resolutions: " selected_resolutions
    
    # Validate selections
    local valid_resolutions=""
    for res in $selected_resolutions; do
      case "$res" in
        SDTV|HDTV|UHDTV) valid_resolutions+="$res," ;;
        *) echo -e "${YELLOW}Ignoring invalid resolution: $res${RESET}" ;;
      esac
    done
    
    if [[ -n "$valid_resolutions" ]]; then
      ENABLED_RESOLUTIONS="${valid_resolutions%,}"  # Remove trailing comma
      echo -e "${GREEN}Resolution filter enabled: $ENABLED_RESOLUTIONS${RESET}"
    else
      echo -e "${RED}No valid resolutions selected, filter disabled${RESET}"
      FILTER_BY_RESOLUTION=false
    fi
  else
    FILTER_BY_RESOLUTION=false
    echo -e "${YELLOW}Resolution filter disabled${RESET}"
  fi
  
  # Save to config
  if grep -q "FILTER_BY_RESOLUTION=" "$CONFIG_FILE"; then
    sed -i "s/FILTER_BY_RESOLUTION=.*/FILTER_BY_RESOLUTION=$FILTER_BY_RESOLUTION/" "$CONFIG_FILE"
  else
    echo "FILTER_BY_RESOLUTION=$FILTER_BY_RESOLUTION" >> "$CONFIG_FILE"
  fi
  
  if grep -q "ENABLED_RESOLUTIONS=" "$CONFIG_FILE"; then
    sed -i "s/ENABLED_RESOLUTIONS=.*/ENABLED_RESOLUTIONS=\"$ENABLED_RESOLUTIONS\"/" "$CONFIG_FILE"
  else
    echo "ENABLED_RESOLUTIONS=\"$ENABLED_RESOLUTIONS\"" >> "$CONFIG_FILE"
  fi
  
  return 0
}

configure_country_filter() {
  echo -e "\n${BOLD}Country Filter Configuration${RESET}"
  echo "Current status: $([ "$FILTER_BY_COUNTRY" = "true" ] && echo "Enabled" || echo "Disabled")"
  echo "Current filters: $ENABLED_COUNTRIES"
  
  # Get available countries from markets CSV
  local available_countries=$(get_available_countries)
  if [ -z "$available_countries" ]; then
    echo -e "${RED}No markets configured. Add markets first to enable country filtering.${RESET}"
    return 1
  fi
  
  echo -e "\nAvailable countries from your markets: ${GREEN}$available_countries${RESET}"
  echo
  
  if confirm_action "Enable country filtering?"; then
    FILTER_BY_COUNTRY=true
    
    echo -e "\nSelect countries to include (space-separated):"
    echo "Available: $(echo "$available_countries" | tr ',' ' ')"
    read -p "Enter countries: " selected_countries
    
    # Validate selections against available countries
    local valid_countries=""
    IFS=',' read -ra AVAILABLE <<< "$available_countries"
    for country in $selected_countries; do
      country=$(echo "$country" | tr '[:lower:]' '[:upper:]')  # Normalize to uppercase
      if [[ " ${AVAILABLE[*]} " =~ " ${country} " ]]; then
        valid_countries+="$country,"
      else
        echo -e "${YELLOW}Ignoring invalid country: $country (not in your markets)${RESET}"
      fi
    done
    
    if [[ -n "$valid_countries" ]]; then
      ENABLED_COUNTRIES="${valid_countries%,}"  # Remove trailing comma
      echo -e "${GREEN}Country filter enabled: $ENABLED_COUNTRIES${RESET}"
    else
      echo -e "${RED}No valid countries selected, filter disabled${RESET}"
      FILTER_BY_COUNTRY=false
      ENABLED_COUNTRIES=""
    fi
  else
    FILTER_BY_COUNTRY=false
    ENABLED_COUNTRIES=""
    echo -e "${YELLOW}Country filter disabled${RESET}"
  fi
  
  # Save to config file
  if grep -q "FILTER_BY_COUNTRY=" "$CONFIG_FILE"; then
    sed -i "s/FILTER_BY_COUNTRY=.*/FILTER_BY_COUNTRY=$FILTER_BY_COUNTRY/" "$CONFIG_FILE"
  else
    echo "FILTER_BY_COUNTRY=$FILTER_BY_COUNTRY" >> "$CONFIG_FILE"
  fi
  
  if grep -q "ENABLED_COUNTRIES=" "$CONFIG_FILE"; then
    sed -i "s/ENABLED_COUNTRIES=.*/ENABLED_COUNTRIES=\"$ENABLED_COUNTRIES\"/" "$CONFIG_FILE"
  else
    echo "ENABLED_COUNTRIES=\"$ENABLED_COUNTRIES\"" >> "$CONFIG_FILE"
  fi
  
  return 0
}

display_cache_statistics() {
  echo -e "${BOLD}Cache Statistics:${RESET}"
  
  # Show two-file system breakdown
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)  
  local total_count=$(get_total_stations_count)
  
  if [ "$base_count" -gt 0 ]; then
    echo "Base Stations: $base_count"
  else
    echo "Base Stations: 0 (not found)"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    echo "User Stations: $user_count"
  else
    echo "User Stations: 0 (none added)"
  fi
  
  echo "Total Available: $total_count"
  
  [ -f "$LINEUP_CACHE" ] && echo "Lineups: $(wc -l < "$LINEUP_CACHE" 2>/dev/null || echo "0")"
  [ -d "$LOGO_DIR" ] && echo "Logos cached: $(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)"
  [ -f "$API_SEARCH_RESULTS" ] && echo "API search results: $(wc -l < "$API_SEARCH_RESULTS" 2>/dev/null || echo "0") entries"
  echo "Total cache size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
  echo
  
  # Add state tracking info
  show_cache_state_stats
}

clear_all_cache() {
  if confirm_action "Clear ALL cache data? This will require re-downloading everything"; then
    cleanup_cache
    echo -e "${GREEN}All cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_station_cache() {
  if confirm_action "Clear station cache?"; then
    # Remove station cache files and any legacy master JSON files
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    rm -f "$CACHE_DIR"/all_stations_master.json* 2>/dev/null || true
    rm -f "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
    rm -f "$CACHE_DIR"/temp_stations_*.json 2>/dev/null || true
    echo -e "${GREEN}Station cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_temp_files() {
  if confirm_action "Clear temporary files?"; then
    rm -f "$CACHE_DIR"/*.tmp "$CACHE_DIR"/last_raw_*.json
    echo -e "${GREEN}Temporary files cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

clear_logo_cache() {
  if confirm_action "Clear logo cache?"; then
    rm -f "$LOGO_DIR"/*.png 2>/dev/null || true
    echo -e "${GREEN}Logo cache cleared${RESET}"
    return 0
  else
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
}

show_detailed_cache_stats() {
  echo -e "\n${BOLD}Detailed Cache Statistics:${RESET}"
  
  # Station Database Analysis
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -eq 0 ]; then
    echo -e "\n${BOLD}Station Database:${RESET}"
    echo "  Total stations: $(jq 'length' "$stations_file")"
    echo "  HDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "HDTV")] | length' "$stations_file")"
    echo "  SDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "SDTV")] | length' "$stations_file")"
    echo "  UHDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "UHDTV")] | length' "$stations_file")"
    
    # Show country breakdown if available
    local countries=$(jq -r '[.[] | .country // "UNK"] | unique | .[]' "$stations_file" 2>/dev/null)
    if [ -n "$countries" ]; then
      echo -e "\n  ${BOLD}Countries:${RESET}"
      while read -r country; do
        local count=$(jq --arg c "$country" '[.[] | select((.country // "UNK") == $c)] | length' "$stations_file")
        echo "    $country: $count stations"
      done <<< "$countries"
    fi
  else
    echo -e "\n${BOLD}Station Database:${RESET}"
    echo "  No station database available"
  fi
  
  # Cache File Breakdown (exclude temporary files)
  if [ -d "$CACHE_DIR" ]; then
    echo -e "\n${BOLD}Cache File Breakdown:${RESET}"
    
    # Show important cache files only
    if [ -f "$BASE_STATIONS_JSON" ]; then
      local base_size=$(ls -lh "$BASE_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
      echo "  Base stations cache: $base_size"
    fi
    
    if [ -f "$USER_STATIONS_JSON" ]; then
      local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
      echo "  User stations cache: $user_size"
    fi
    
    if [ -f "$BASE_CACHE_MANIFEST" ]; then
      local manifest_size=$(ls -lh "$BASE_CACHE_MANIFEST" 2>/dev/null | awk '{print $5}')
      echo "  Base cache manifest: $manifest_size"
    fi
    
    if [ -f "$CACHED_MARKETS" ]; then
      local markets_size=$(ls -lh "$CACHED_MARKETS" 2>/dev/null | awk '{print $5}')
      echo "  Market tracking: $markets_size"
    fi
    
    if [ -f "$CACHED_LINEUPS" ]; then
      local lineups_size=$(ls -lh "$CACHED_LINEUPS" 2>/dev/null | awk '{print $5}')
      echo "  Lineup tracking: $lineups_size"
    fi
    
    # Show logo cache size
    if [ -d "$LOGO_DIR" ]; then
      local logo_count=$(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)
      local logo_size=$(du -sh "$LOGO_DIR" 2>/dev/null | cut -f1)
      echo "  Logo cache: $logo_size ($logo_count files)"
    fi
    
    # Show total cache directory size
    local total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    echo "  Total cache size: $total_size"
    
    # Show count of temporary files (but don't list them)
    local temp_count=$(find "$CACHE_DIR" -name "last_raw_*.json" 2>/dev/null | wc -l)
    if [ "$temp_count" -gt 0 ]; then
      echo "  Temporary API files: $temp_count (not shown)"
    fi
  fi
  
  # Market Configuration
  if [ -f "$CSV_FILE" ]; then
    local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
    echo -e "\n${BOLD}Market Configuration:${RESET}"
    echo "  Configured markets: $market_count"
    
    # Show breakdown by country
    if [ "$market_count" -gt 0 ]; then
      echo "  By country:"
      awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort | uniq -c | sort -rn | while read -r count country; do
        echo "    $country: $count markets"
      done
    fi
  fi
  
  # State Tracking Summary
  echo -e "\n${BOLD}Processing State:${RESET}"
  show_cache_state_stats
}

reset_all_settings() {
  echo -e "${RED}This will reset ALL settings to defaults and clear configuration${RESET}"
  if confirm_action "Are you sure?"; then
    rm -f "$CONFIG_FILE"
    SHOW_LOGOS=false
    FILTER_BY_RESOLUTION=false
    ENABLED_RESOLUTIONS="SDTV,HDTV,UHDTV"
    FILTER_BY_COUNTRY=false
    ENABLED_COUNTRIES=""
    echo -e "${GREEN}Settings reset. Restart the script to reconfigure.${RESET}"
    return 0
  else
    echo -e "${YELLOW}Reset cancelled${RESET}"
    return 1
  fi
}

export_settings() {
  local settings_file="globalstationsearch_settings_$(date +%Y%m%d_%H%M%S).txt"
  
  {
    echo "Global Station Search Settings Export"
    echo "Generated: $(date)"
    echo "Script Version: $VERSION"
    echo "Last Modified: 2025/06/01"
    echo
    echo "=== Configuration ==="
    echo "Server: $CHANNELS_URL"
    echo "Logo Display: $SHOW_LOGOS"
    echo "Resolution Filter: $FILTER_BY_RESOLUTION"
    echo "Enabled Resolutions: $ENABLED_RESOLUTIONS"
    echo "Country Filter: $FILTER_BY_COUNTRY"
    echo "Enabled Countries: $ENABLED_COUNTRIES"
    echo "Dispatcharr Enabled: $DISPATCHARR_ENABLED"
    echo "Dispatcharr URL: $DISPATCHARR_URL"
    echo
    echo "=== Markets ==="
    [ -f "$CSV_FILE" ] && cat "$CSV_FILE"
  } > "$settings_file"
  
  echo -e "${GREEN}Settings exported to: $settings_file${RESET}"
  return 0
}

export_stations_to_csv() {
  echo -e "\n${BOLD}Export Station Database to CSV${RESET}"
  
  # Get effective stations file
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    echo -e "${RED}No station database found.${RESET}"
    echo -e "${CYAN}Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}Alternative: Build user cache via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    return 1
  fi
  
  local total_count=$(get_total_stations_count)
  echo "Station database contains: $total_count stations"
  
  # Show source breakdown
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)

  # Show source breakdown
  if [ "$base_count" -gt 0 ]; then
    echo "  Base stations: $base_count"
  fi
  if [ "$user_count" -gt 0 ]; then
    echo "  User stations: $user_count"
  fi
  
  # Generate filename with timestamp
  local csv_file="stations_export_$(date +%Y%m%d_%H%M%S).csv"
  read -p "Export filename [default: $csv_file]: " filename
  filename=${filename:-$csv_file}
  
  echo "Exporting combined station database to CSV..."
  
  # Create CSV with comprehensive station data
  {
    # CSV Header (added Source column)
    echo "Station_ID,Name,Call_Sign,Country,Video_Quality,Network,Genre,Language,Logo_URL,Description,Source"
    
    # Export station data with source indication
    jq -r '
      .[] | [
        .stationId // "",
        .name // "",
        .callSign // "",
        .country // "",
        .videoQuality.videoType // "",
        .network // "",
        (.genre // [] | join("; ")),
        .language // "",
        .preferredImage.uri // "",
        .description // "",
        (.source // "Combined")
      ] | @csv
    ' "$stations_file"
  } > "$filename"
  
  if [ $? -eq 0 ]; then
    local exported_count=$(tail -n +2 "$filename" | wc -l)
    echo -e "${GREEN}✅ Successfully exported $exported_count stations to: $filename${RESET}"
    
    # Show file info
    local file_size
    file_size=$(ls -lh "$filename" 2>/dev/null | awk '{print $5}')
    echo -e "${CYAN}📄 File size: $file_size${RESET}"
    
    # Show sample of exported data
    echo -e "\n${BOLD}Sample of exported data:${RESET}"
    head -3 "$filename" | while IFS= read -r line; do
      echo "  $line"
    done | cut -c1-100  # Truncate long lines
    
    echo -e "\n${CYAN}💡 This CSV includes stations from all available cache sources${RESET}"
    echo -e "${CYAN}💡 Can be opened in Excel, LibreOffice, or imported into databases${RESET}"
  else
    echo -e "${RED}❌ Failed to export stations to CSV${RESET}"
    return 1
  fi
  
  # Clean up any temporary combined files
  cleanup_combined_cache
  
  return 0
}

# ============================================================================
# LOCAL CACHING FUNCTIONS
# ============================================================================

run_user_caching() {
  clear
  echo -e "${BOLD}${CYAN}=== Local Caching ===${RESET}\n"
  
  echo -e "${BLUE}📊 Step 2 of 3: Build Local Station Database${RESET}"
  echo -e "${YELLOW}This process will:${RESET}"
  echo -e "• Query all configured markets for available stations"
  echo -e "• Deduplicate stations that appear in multiple markets"
  echo -e "• Add stations to your personal user cache"
  echo -e "• Enable full-featured local search with filtering"
  echo
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${RED}❌ No markets configured. Please add markets first.${RESET}"
    echo
    echo -e "${CYAN}Would you like to configure markets now?${RESET}"
    if confirm_action "Go to Market Management"; then
      manage_markets
      return 1
    else
      return 1
    fi
  fi
  
  local market_count
  market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  echo -e "${GREEN}✅ Markets configured: $market_count${RESET}"
  
  # Show current cache status
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)
  
  echo
  echo -e "${BOLD}Current Cache Status:${RESET}"
  if [ "$base_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Base stations: $base_count${RESET}"
  else
    echo -e "${YELLOW}⚠️  Base stations: 0 (no distributed cache)${RESET}"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    echo -e "${GREEN}✅ User stations: $user_count${RESET}"
    echo -e "${CYAN}   New stations will be added to your existing collection${RESET}"
  else
    echo -e "${YELLOW}⚠️  User stations: 0 (this will be your first user cache)${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total currently available: $total_count${RESET}"
  
  # Show market preview
  echo -e "\n${BOLD}Markets to be cached:${RESET}"
  head -6 "$CSV_FILE" | tail -5 | while IFS=, read -r country zip; do
    echo -e "   • $country / $zip"
  done
  if [[ "$market_count" -gt 5 ]]; then
    echo -e "   • ... and $((market_count - 5)) more"
  fi
  echo
  
  echo -e "${YELLOW}⏱️  Estimated time: $((market_count * 2))-$((market_count * 5)) minutes${RESET}"
  echo -e "${YELLOW}📡 API calls required: ~$((market_count * 3))${RESET}"
  echo
  
  if ! confirm_action "Continue with user caching?"; then
    echo -e "${YELLOW}User caching cancelled${RESET}"
    return 1
  fi
  
  perform_caching
}

perform_caching() {
  # Check if server is configured for API operations
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${YELLOW}⚠️  No Channels DVR server configured${RESET}"
    echo -e "${CYAN}User caching will work but station enhancement will be skipped${RESET}"
    echo -e "${CYAN}Configure server in Settings to enable full enhancement${RESET}"
    echo
  fi

  echo -e "\n${YELLOW}Building user station cache from configured markets...${RESET}"
  echo -e "${CYAN}This will add stations to your personal cache without affecting the base database.${RESET}"
  
  # Initialize user cache and state tracking
  init_user_cache
  init_cache_state_tracking
  
  # Clean up temporary files (but preserve user and base caches)
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log
  # Remove any legacy master JSON files during cleanup
  rm -f "$CACHE_DIR"/all_stations_master.json* "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR"
  > "$LINEUP_CACHE"

  # Fetch lineups for each market WITH STATE TRACKING AND BASE CACHE CHECKING
  echo -e "\n${BOLD}Phase 1: Fetching lineups from markets${RESET}"
  while IFS=, read -r COUNTRY ZIP; do
    [[ "$COUNTRY" == "Country" ]] && continue
    
    # Skip if force refresh is not active and this exact market is in base cache
    if [[ "$FORCE_REFRESH_ACTIVE" != "true" ]] && check_market_in_base_cache "$COUNTRY" "$ZIP"; then
      echo "Skipping $COUNTRY / $ZIP (exact market found in base cache)"
      # Record as processed with 0 lineups to maintain state tracking
      record_market_processed "$COUNTRY" "$ZIP" 0
      continue
    fi

    if [[ "$FORCE_REFRESH_ACTIVE" == "true" ]]; then
      echo "Force refreshing $COUNTRY / $ZIP (ignoring base cache coverage)"
    fi
    
    echo "Querying lineups for $COUNTRY / $ZIP"
    local response=$(curl -s "$CHANNELS_URL/tms/lineups/$COUNTRY/$ZIP")
    echo "$response" > "cache/last_raw_${COUNTRY}_${ZIP}.json"
    
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      # Count lineups found for this market
      local lineups_found=$(echo "$response" | jq 'length')
      
      # Record that this market was processed
      record_market_processed "$COUNTRY" "$ZIP" "$lineups_found"
      
      # Add lineups to cache
      echo "$response" | jq -c '.[]' >> "$LINEUP_CACHE"
      echo "  Found $lineups_found lineups"
    else
      echo "  Invalid JSON response, skipping"
      # Record market as processed with 0 lineups
      record_market_processed "$COUNTRY" "$ZIP" 0
    fi
  done < "$CSV_FILE"

  # Process lineups WITH STATE TRACKING
  echo -e "\n${BOLD}Phase 2: Processing and deduplicating lineups${RESET}"
  local pre_dedup_lineups=0
  if [ -f "$LINEUP_CACHE" ]; then
    pre_dedup_lineups=$(wc -l < "$LINEUP_CACHE")
  fi

  # Process lineups more safely to avoid jq indexing errors
  sort -u "$LINEUP_CACHE" 2>/dev/null | while IFS= read -r line; do
    echo "$line" | jq -r '.lineupId // empty' 2>/dev/null
  done | grep -v '^$' | sort -u > cache/unique_lineups.txt

  local post_dedup_lineups=$(wc -l < cache/unique_lineups.txt)
  local dup_lineups_removed=$((pre_dedup_lineups - post_dedup_lineups))
  
  echo "  Lineups before dedup: $pre_dedup_lineups"
  echo "  Lineups after dedup: $post_dedup_lineups"
  echo "  Duplicate lineups removed: $dup_lineups_removed"

  # Fetch stations for each lineup WITH STATE TRACKING
  echo -e "\n${BOLD}Phase 3: Fetching stations from lineups${RESET}"
  while read LINEUP; do
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    echo "Fetching stations for $LINEUP"
    curl -s "$CHANNELS_URL/dvr/guide/stations/$LINEUP" -o "$station_file"
    
    # Find which market this lineup belongs to for state tracking
    local country_code=""
    local source_zip=""
    while IFS=, read -r COUNTRY ZIP; do
      [[ "$COUNTRY" == "Country" ]] && continue
      if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
        country_code="$COUNTRY"
        source_zip="$ZIP"
        break
      fi
    done < "$CSV_FILE"
    
    # Count stations and record lineup processing
    local stations_found=0
    if [ -f "$station_file" ]; then
      stations_found=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
      echo "  Found $stations_found stations"
    fi
    
    record_lineup_processed "$LINEUP" "$country_code" "$source_zip" "$stations_found"
    
  done < cache/unique_lineups.txt

  # Process and deduplicate stations with country injection
  # Use temporary working file that will be cleaned up
  echo -e "\n${BOLD}Phase 4: Processing stations and injecting country codes${RESET}"
  local pre_dedup_stations=0
  local temp_stations_file="$CACHE_DIR/temp_stations_$(date +%s).json"
  > "$temp_stations_file.tmp"

  # Process each lineup file individually to track country origin
  while read LINEUP; do
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    if [ -f "$station_file" ]; then
      # Find which country this lineup belongs to by checking our markets
      local country_code=""
      while IFS=, read -r COUNTRY ZIP; do
        [[ "$COUNTRY" == "Country" ]] && continue
        # Check if this lineup matches this market by querying the raw response
        if grep -q "\"lineupId\":\"$LINEUP\"" "cache/last_raw_${COUNTRY}_${ZIP}.json" 2>/dev/null; then
          country_code="$COUNTRY"
          break
        fi
      done < "$CSV_FILE"
      
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
      
      echo "Processing lineup $LINEUP (Country: $country_code)"
      
      # Count stations before processing
      local lineup_count=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
      pre_dedup_stations=$((pre_dedup_stations + lineup_count))
      
      # Inject country code and source into each station
      jq --arg country "$country_code" --arg source "user" \
         'map(. + {country: $country, source: $source})' \
         "$station_file" >> "$temp_stations_file.tmp"
    fi
  done < cache/unique_lineups.txt

  # Now flatten, deduplicate, and sort
  echo -e "\n${BOLD}Phase 5: Final deduplication and processing${RESET}"
  jq -s 'flatten | sort_by((.name // "") | length) | reverse | unique_by(.stationId)' "$temp_stations_file.tmp" \
    | jq 'map(.name = (.name // empty))' > "$temp_stations_file"

  # Clean up intermediate temp file
  rm -f "$temp_stations_file.tmp"

  local post_dedup_stations=$(jq length "$temp_stations_file")
  local dup_stations_removed=$((pre_dedup_stations - post_dedup_stations))
  
  echo "  Stations before dedup: $pre_dedup_stations"
  echo "  Stations after dedup: $post_dedup_stations"
  echo "  Duplicate stations removed: $dup_stations_removed"

  # Enhancement phase with statistics capture
  echo -e "\n${BOLD}Phase 6: Enhancing station data${RESET}"
  local enhancement_stats
  enhancement_stats=$(enhance_stations "$start_time" "$temp_stations_file")
  local enhanced_from_cache=$(echo "$enhancement_stats" | cut -d' ' -f1)
  local enhanced_from_api=$(echo "$enhancement_stats" | cut -d' ' -f2)
  
  # Save to USER cache (merge with existing if present)
  echo -e "\n${BOLD}Phase 7: Saving to user cache${RESET}"
  echo "Adding stations to user cache..."
  
  if add_stations_to_user_cache "$temp_stations_file"; then
    echo -e "${GREEN}✅ User cache updated successfully${RESET}"
  else
    echo -e "${RED}❌ Failed to update user cache${RESET}"
    # Clean up temp file before returning
    rm -f "$temp_stations_file"
    return 1
  fi

  # Calculate duration and show summary
  local end_time=$(date +%s)
  local duration=$((end_time - ${start_time%%.*}))
  local human_duration=$(printf '%02dh %02dm %02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

  show_user_caching_summary "$dup_lineups_removed" "$dup_stations_removed" "$human_duration" "$enhanced_from_cache" "$enhanced_from_api"
  
  # Clean up temporary files including our temp stations file
  cleanup_combined_cache
  rm -f "$temp_stations_file"
}

enhance_stations() {
  local start_time="$1"
  local stations_file="$2"  # The file to enhance (passed as parameter)
  
  echo "Processing final station list..."
  local tmp_json="$CACHE_DIR/enhancement_tmp_$(date +%s).json"
  > "$tmp_json"

  mapfile -t stations < <(jq -c '.[]' "$stations_file")
  local total_stations=${#stations[@]}
  local enhanced_from_api=0

  for ((i = 0; i < total_stations; i++)); do
    local station="${stations[$i]}"
    local current=$((i + 1))
    local percent=$((current * 100 / total_stations))
    
    # Show progress bar BEFORE processing (so it's visible)
    show_progress_bar "$current" "$total_stations" "$percent" "$start_time"

    local callSign=$(echo "$station" | jq -r '.callSign // empty')
    local name=$(echo "$station" | jq -r '.name // empty')
    
    # Only enhance if station has callsign but missing name AND server is configured
    if [[ -n "$callSign" && "$callSign" != "null" && ( -z "$name" || "$name" == "null" ) && -n "${CHANNELS_URL:-}" ]]; then
      local api_response=$(curl -s --connect-timeout 5 "$CHANNELS_URL/tms/stations/$callSign" 2>/dev/null)
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
  
  # Clear the progress line and show completion
  echo
  echo -e "\nProcessing complete."
  mv "$tmp_json" "$stations_file"

  # Return enhancement statistics (0 for cache, actual count for API)
  echo "0 $enhanced_from_api"
}

show_progress_bar() {
  local current="$1"
  local total="$2"
  local percent="$3"
  local start_time="$4"
  
  local bar_width=40
  local filled=$((percent * bar_width / 100))
  local empty=$((bar_width - filled))
  local bar=$(printf '#%.0s' $(seq 1 $filled))
  local spaces=$(printf ' %.0s' $(seq 1 $empty))
  
  # Calculate ETA
  local remaining_fmt="estimating..."
  if (( current > 1 )) && command -v bc &> /dev/null; then
    local now=$(date +%s.%N)
    local elapsed=$(echo "$now - $start_time" | bc)
    local avg_time_per=$(echo "$elapsed / $current" | bc -l)
    local remaining=$(echo "$avg_time_per * ($total - $current)" | bc -l)
    local minutes=$(echo "$remaining / 60" | bc)
    local raw_seconds=$(echo "$remaining - ($minutes * 60)" | bc -l)
    local seconds=$(printf "%.0f" "$raw_seconds")
    (( seconds < 0 )) && seconds=0
    remaining_fmt=$(printf "%02dm %02ds" "$minutes" "$seconds")
  fi

  printf "\rProcessing station %d of %d [%d%%] [%s%s] ETA: %s" \
    "$current" "$total" "$percent" "$bar" "$spaces" "$remaining_fmt"
}

backup_existing_data() {
  # Backup user cache if it exists
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo "Backing up existing user cache..."
    mkdir -p cache/backups
    for ((i=9; i>=1; i--)); do
      if [ -f "cache/backups/all_stations_user.json.bak.$i" ]; then
        local next=$((i + 1))
        mv "cache/backups/all_stations_user.json.bak.$i" "cache/backups/all_stations_user.json.bak.$next"
      fi
    done
    cp "$USER_STATIONS_JSON" "cache/backups/all_stations_user.json.bak.1"
    [ -f "cache/backups/all_stations_user.json.bak.11" ] && rm -f "cache/backups/all_stations_user.json.bak.11"
  fi
  
  # PRESERVE state tracking files - don't back them up, they're cumulative
  # Base cache is never backed up - it's read-only distributed content
}

show_user_caching_summary() {
  local dup_lineups_removed="$1"
  local dup_stations_removed="$2"
  local human_duration="$3"
  local enhanced_from_cache="${4:-0}"
  local enhanced_from_api="${5:-0}"
  
  local num_countries=$(awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort -u | awk 'END {print NR}')
  local num_markets=$(awk 'END {print NR-1}' "$CSV_FILE")
  local num_lineups=$(awk 'END {print NR}' cache/unique_lineups.txt 2>/dev/null || echo "0")
  
  # Get final counts
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)

  echo
  echo -e "${BOLD}${GREEN}=== User Caching Summary ===${RESET}"
  echo "Total Countries:            $num_countries"
  echo "Total Markets:              $num_markets"
  echo "Total Lineups:              $num_lineups"
  echo "Duplicate Lineups Removed:  $dup_lineups_removed"
  echo "Duplicate Stations Removed: $dup_stations_removed"
  
  # Only show API enhancement statistics (no cache enhancement)
  if [[ $enhanced_from_api -gt 0 ]]; then
    echo "Enhanced from API:          $enhanced_from_api"
  fi
  
  echo "Time to Complete:           $human_duration"
  echo
  echo -e "${BOLD}${CYAN}=== Final Database Status ===${RESET}"
  if [ "$base_count" -gt 0 ]; then
    echo "Base Stations:              $base_count"
  fi
  echo "User Stations:              $user_count"
  echo "Total Available:            $total_count"
  echo
  echo -e "${GREEN}✅ User caching completed successfully!${RESET}"
  echo -e "${CYAN}💡 Your stations are now available for local search${RESET}"
  
  # Show state tracking summary
  echo
  show_cache_state_stats
}

# ============================================================================
# MAIN MENU AND APPLICATION ENTRY POINT
# ============================================================================

main_menu() {
  trap cleanup_combined_cache EXIT
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Global Station Search v$VERSION ===${RESET}\n"
    
    show_system_status
    
    # Show workflow guidance for new users or incomplete setups
    local total_count=$(get_total_stations_count)
    if [ "$total_count" -eq 0 ]; then
      show_workflow_guidance
    fi
    
    echo -e "${BOLD}Main Menu:${RESET}"
    echo "1) Search Local Database"
    echo "2) Dispatcharr Integration"
    echo "3) Manage Television Markets for User Cache"
    echo "4) Run User Caching"
    echo "5) Direct API Search"
    echo "6) Reverse Station ID Lookup"
    echo "7) Local Cache Management"
    echo "8) Settings"
    echo "q) Quit"
    
    read -p "Select option: " choice
    
    case $choice in
      1) search_local_database ;;
      2) dispatcharr_integration_check ;;
      3) manage_markets ;;
      4) run_user_caching && pause_for_user ;;
      5) direct_api_search ;;
      6) reverse_station_id_lookup_menu ;;
      7) cache_management_main_menu ;;
      8) settings_menu ;;
      q|Q|"") echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
      *) show_invalid_choice ;;
    esac
  done
}

dispatcharr_integration_check() {
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    run_dispatcharr_integration
  else
    echo -e "${YELLOW}Dispatcharr integration is disabled${RESET}"
    echo -e "${CYAN}Enable it in Settings > Dispatcharr Configuration${RESET}"
    pause_for_user
  fi
}

reverse_station_id_lookup_menu() {
  clear
  echo -e "${BOLD}${CYAN}=== Reverse Station ID Lookup ===${RESET}\n"
  echo -e "${YELLOW}Enter a station ID to get detailed information about that station.${RESET}"
  echo -e "${CYAN}This will search your local database for comprehensive station details.${RESET}"
  echo
  read -p "Enter station ID to lookup: " lookup_id
  if [[ -n "$lookup_id" ]]; then
    echo
    reverse_station_lookup "$lookup_id"
  else
    echo -e "${YELLOW}No station ID provided${RESET}"
  fi
  pause_for_user
}

cache_management_main_menu() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Cache Management ===${RESET}\n"
    
    # Show detailed cache status
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${BOLD}Current Cache Status:${RESET}"
    if [ "$base_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Base Cache: $base_count stations ($(basename "$BASE_STATIONS_JSON"))${RESET}"
    else
      echo -e "${YELLOW}⚠️  Base Cache: Not found (should be $(basename "$BASE_STATIONS_JSON"))${RESET}"
    fi
    
    if [ "$user_count" -gt 0 ]; then
      echo -e "${GREEN}✅ User Cache: $user_count stations (your additions)${RESET}"
    else
      echo -e "${YELLOW}⚠️  User Cache: Empty${RESET}"
    fi
    
    echo -e "${CYAN}📊 Total Available: $total_count stations${RESET}"
    echo
    
    show_cache_state_stats
    echo
    
    echo -e "${BOLD}Cache Management Options:${RESET}"
    echo "a) Incremental Update (add new markets only)"
    echo "b) Full User Cache Refresh"
    echo "c) View Cache Statistics"
    echo "d) Export Combined Database to CSV"
    echo "e) Clear User Cache"
    echo "f) Clear Temporary Files"
    echo "g) Advanced Cache Operations"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) run_incremental_update && pause_for_user ;;
      b|B) run_full_user_refresh && pause_for_user ;;
      c|C) show_detailed_cache_stats && pause_for_user ;;
      d|D) export_stations_to_csv && pause_for_user ;;
      e|E) clear_user_cache && pause_for_user ;;
      f|F) clear_temp_files && pause_for_user ;;
      g|G) advanced_cache_operations ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

run_incremental_update() {
  echo -e "\n${BOLD}Incremental Cache Update${RESET}"
  echo -e "${CYAN}This will only process markets that haven't been cached yet.${RESET}"
  echo -e "${YELLOW}Markets with exact matches in base cache will be automatically skipped.${RESET}"
  echo
  
  # Get unprocessed markets
  local unprocessed_markets
  unprocessed_markets=$(get_unprocessed_markets)
  
  if [ -z "$unprocessed_markets" ]; then
    echo -e "${GREEN}✅ All configured markets have already been processed${RESET}"
    echo -e "${CYAN}💡 To add new markets: Use 'Manage Markets' first${RESET}"
    echo -e "${CYAN}💡 To refresh existing markets: Use 'Full User Cache Refresh'${RESET}"
    echo -e "${CYAN}💡 To force refresh base cache markets: Use 'Force Refresh Market'${RESET}"
    return 0
  fi
  
  local unprocessed_count=$(echo "$unprocessed_markets" | wc -l)
  echo -e "${YELLOW}Found $unprocessed_count unprocessed markets:${RESET}"
  
  # Show markets with base cache status
  echo "$unprocessed_markets" | while IFS=, read -r country zip; do
    if check_market_in_base_cache "$country" "$zip"; then
      echo -e "  • $country / $zip ${YELLOW}(will be skipped - exact market in base cache)${RESET}"
    else
      echo -e "  • $country / $zip ${GREEN}(will be processed)${RESET}"
    fi
  done
  echo
  
  # Filter out exact markets already in base cache
  local markets_to_process=""
  echo "$unprocessed_markets" | while IFS=, read -r country zip; do
    if ! check_market_in_base_cache "$country" "$zip"; then
      if [ -z "$markets_to_process" ]; then
        markets_to_process="$country,$zip"
      else
        markets_to_process="$markets_to_process\n$country,$zip"
      fi
    else
      # Record as processed since exact market is in base cache
      record_market_processed "$country" "$zip" 0
    fi
  done
  
  if [ -z "$markets_to_process" ]; then
    echo -e "${GREEN}✅ All unprocessed markets are exactly matched in base cache${RESET}"
    echo -e "${CYAN}No API calls needed - markets marked as processed${RESET}"
    return 0
  fi
  
  local actual_process_count=$(echo -e "$markets_to_process" | wc -l)
  echo -e "${CYAN}After base cache filtering: $actual_process_count markets will be processed${RESET}"
  
  if confirm_action "Process these $actual_process_count markets?"; then
    # Create temporary CSV with only markets to process
    local temp_csv="$CACHE_DIR/temp_incremental_markets.csv"
    {
      echo "Country,ZIP"
      echo -e "$markets_to_process"
    } > "$temp_csv"
    
    # Temporarily swap CSV files
    local original_csv="$CSV_FILE"
    CSV_FILE="$temp_csv"
    
    echo -e "${CYAN}Processing incremental markets (base cache aware)...${RESET}"
    perform_caching
    
    # Restore original CSV
    CSV_FILE="$original_csv"
    rm -f "$temp_csv"
    
    echo -e "${GREEN}✅ Incremental update complete${RESET}"
  else
    echo -e "${YELLOW}Incremental update cancelled${RESET}"
  fi
}

run_full_user_refresh() {
  echo -e "\n${BOLD}Full User Cache Refresh${RESET}"
  echo -e "${YELLOW}This will rebuild your entire user cache from all configured markets.${RESET}"
  echo -e "${RED}Your existing user cache will be backed up and replaced.${RESET}"
  echo
  
  local user_count=$(echo "$(get_stations_breakdown)" | cut -d' ' -f2)
  if [ "$user_count" -gt 0 ]; then
    echo -e "${YELLOW}Current user cache: $user_count stations${RESET}"
    echo -e "${CYAN}This will be backed up before refresh${RESET}"
    echo
  fi
  
  if confirm_action "Perform full user cache refresh?"; then
    # Clear state tracking to force full refresh
    echo -e "${CYAN}Clearing cache state to force full refresh...${RESET}"
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    
    # Backup current user cache
    if [ -f "$USER_STATIONS_JSON" ] && [ -s "$USER_STATIONS_JSON" ]; then
      backup_existing_data
    fi
    
    # Clear user cache
    echo '[]' > "$USER_STATIONS_JSON"
    
    echo -e "${CYAN}Starting full refresh...${RESET}"
    perform_caching
    
    echo -e "${GREEN}✅ Full user cache refresh complete${RESET}"
  else
    echo -e "${YELLOW}Full refresh cancelled${RESET}"
  fi
}

clear_user_cache() {
  echo -e "\n${BOLD}Clear User Cache${RESET}"
  
  local user_count=$(echo "$(get_stations_breakdown)" | cut -d' ' -f2)
  if [ "$user_count" -eq 0 ]; then
    echo -e "${YELLOW}User cache is already empty${RESET}"
    return 0
  fi
  
  echo -e "${YELLOW}This will remove $user_count stations from your user cache.${RESET}"
  echo -e "${GREEN}Base cache and state tracking will be preserved.${RESET}"
  echo -e "${CYAN}You can rebuild the user cache anytime using 'Run User Caching'.${RESET}"
  echo
  
  if confirm_action "Clear user cache ($user_count stations)?"; then
    # Backup before clearing
    backup_existing_data
    
    # Clear user cache
    echo '[]' > "$USER_STATIONS_JSON"
    
    # Clear state tracking
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    
    echo -e "${GREEN}✅ User cache cleared${RESET}"
    echo -e "${CYAN}💡 State tracking reset - next caching will process all markets${RESET}"
  else
    echo -e "${YELLOW}Clear operation cancelled${RESET}"
  fi
}

advanced_cache_operations() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Advanced Cache Operations ===${RESET}\n"
    
    echo -e "${BOLD}Advanced Options:${RESET}"
    echo "1) Refresh Specific Market (ZIP code)"
    echo "2) Refresh Specific Lineup"
    echo "3) Reset State Tracking"
    echo "4) Rebuild Base Cache from User Cache"
    echo "5) View Raw Cache Files"
    echo "6) Validate Cache Integrity"
    echo "q) Back to Cache Management"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1) refresh_specific_market && pause_for_user ;;
      2) refresh_specific_lineup && pause_for_user ;;
      3) reset_state_tracking && pause_for_user ;;
      4) rebuild_base_from_user && pause_for_user ;;
      5) view_raw_cache_files && pause_for_user ;;
      6) validate_cache_integrity && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

refresh_specific_market() {
  echo -e "\n${BOLD}Refresh Specific Market${RESET}"
  echo -e "${CYAN}This will re-process a single market (country/ZIP combination).${RESET}"
  echo
  
  # Show available markets
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    echo -e "${BOLD}Configured Markets:${RESET}"
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      if check_market_in_base_cache "$country" "$zip"; then
        echo -e "   • $country / $zip ${YELLOW}(exact market in base cache)${RESET}"
      else
        echo -e "   • $country / $zip ${GREEN}(will be processed normally)${RESET}"
      fi
    done
    echo
  fi
  
  read -p "Enter country code (e.g., USA): " country
  read -p "Enter ZIP code (e.g., 10001): " zip
  
  if [[ -z "$country" || -z "$zip" ]]; then
    echo -e "${YELLOW}Operation cancelled${RESET}"
    return 1
  fi
  
  # Check if market exists in CSV
  if ! grep -q "^$country,$zip$" "$CSV_FILE" 2>/dev/null; then
    echo -e "${RED}Market $country/$zip not found in configured markets${RESET}"
    if confirm_action "Add this market to your configuration?"; then
      echo "$country,$zip" >> "$CSV_FILE"
      echo -e "${GREEN}Market added to configuration${RESET}"
    else
      return 1
    fi
  fi
  
  # Check if exact market is in base cache and inform user
  if check_market_in_base_cache "$country" "$zip"; then
    echo -e "${YELLOW}⚠️  Exact market $country/$zip is in base cache${RESET}"
    echo -e "${CYAN}This refresh will process it anyway and add any unique stations${RESET}"
    if ! confirm_action "Continue with refresh anyway?"; then
      echo -e "${YELLOW}Refresh cancelled${RESET}"
      return 1
    fi
    # Set force refresh flag to bypass base cache checking
    export FORCE_REFRESH_ACTIVE=true
  fi
  
  echo -e "${CYAN}Refreshing market: $country/$zip${RESET}"
  
  # Remove from state tracking to force refresh
  if [ -f "$CACHED_MARKETS" ]; then
    grep -v "\"country\":\"$country\",\"zip\":\"$zip\"" "$CACHED_MARKETS" > "$CACHED_MARKETS.tmp" 2>/dev/null || true
    mv "$CACHED_MARKETS.tmp" "$CACHED_MARKETS"
  fi
  
  # Create temporary CSV with just this market
  local temp_csv="$CACHE_DIR/temp_single_market.csv"
  {
    echo "Country,ZIP"
    echo "$country,$zip"
  } > "$temp_csv"
  
  # Temporarily swap CSV files
  local original_csv="$CSV_FILE"
  CSV_FILE="$temp_csv"
  
  perform_caching
  
  # Restore original CSV and clear force flag
  CSV_FILE="$original_csv"
  unset FORCE_REFRESH_ACTIVE
  rm -f "$temp_csv"
  
  echo -e "${GREEN}✅ Market $country/$zip refreshed${RESET}"
}

reset_state_tracking() {
  echo -e "\n${BOLD}Reset State Tracking${RESET}"
  echo -e "${YELLOW}This will clear all state tracking data.${RESET}"
  echo -e "${CYAN}Next caching operation will process all markets as if first time.${RESET}"
  echo -e "${GREEN}User cache and base cache will not be affected.${RESET}"
  echo
  
  if confirm_action "Reset all state tracking?"; then
    > "$CACHED_MARKETS"
    > "$CACHED_LINEUPS"
    echo '{}' > "$LINEUP_TO_MARKET"
    > "$CACHE_STATE_LOG"
    
    echo -e "${GREEN}✅ State tracking reset${RESET}"
    echo -e "${CYAN}💡 Next caching will process all configured markets${RESET}"
  else
    echo -e "${YELLOW}Reset cancelled${RESET}"
  fi
}

refresh_specific_lineup() {
  echo -e "\n${BOLD}Refresh Specific Lineup${RESET}"
  echo -e "${YELLOW}This feature will be implemented in a future update.${RESET}"
  echo -e "${CYAN}For now, use 'Refresh Specific Market' instead.${RESET}"
}

rebuild_base_from_user() {
  echo -e "\n${BOLD}Rebuild Base Cache from User Cache${RESET}"
  echo -e "${YELLOW}This feature is reserved for script distribution management.${RESET}"
  echo -e "${CYAN}Contact the script maintainer if you need this functionality.${RESET}"
}

view_raw_cache_files() {
  echo -e "\n${BOLD}Raw Cache Files${RESET}"
  echo -e "${CYAN}Cache directory: $CACHE_DIR${RESET}"
  echo
  
  if [ -f "$BASE_STATIONS_JSON" ]; then
    echo "Base cache: $(ls -lh "$BASE_STATIONS_JSON" | awk '{print $5}') (script directory)"
  else
    echo "Base cache: Not found (should be $(basename "$BASE_STATIONS_JSON") in script directory)"
  fi
  
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo "User cache: $(ls -lh "$USER_STATIONS_JSON" | awk '{print $5}')"
  fi
  
  if [ -f "$CACHED_MARKETS" ]; then
    echo "Market tracking: $(wc -l < "$CACHED_MARKETS") entries"
  fi
  
  if [ -f "$CACHED_LINEUPS" ]; then
    echo "Lineup tracking: $(wc -l < "$CACHED_LINEUPS") entries"
  fi
  
  echo
  echo -e "${CYAN}💡 Advanced users can inspect these files with: jq . filename${RESET}"
}

validate_cache_integrity() {
  echo -e "\n${BOLD}Cache Integrity Validation${RESET}"
  echo "Checking cache file integrity..."
  
  local errors=0
  
  # Check JSON validity
  for file in "$BASE_STATIONS_JSON" "$USER_STATIONS_JSON" "$LINEUP_TO_MARKET"; do
    if [ -f "$file" ]; then
      if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}❌ Invalid JSON: $file${RESET}"
        ((errors++))
      else
        echo -e "${GREEN}✅ Valid JSON: $(basename "$file")${RESET}"
      fi
    fi
  done
  
  # Check for duplicate station IDs within files
  if [ -f "$USER_STATIONS_JSON" ]; then
    local duplicates=$(jq -r '.[] | .stationId' "$USER_STATIONS_JSON" | sort | uniq -d | wc -l)
    if [ "$duplicates" -gt 0 ]; then
      echo -e "${YELLOW}⚠️  Found $duplicates duplicate station IDs in user cache${RESET}"
    else
      echo -e "${GREEN}✅ No duplicate station IDs in user cache${RESET}"
    fi
  fi
  
  if [ "$errors" -eq 0 ]; then
    echo -e "\n${GREEN}✅ Cache integrity check passed${RESET}"
  else
    echo -e "\n${RED}❌ Found $errors integrity issues${RESET}"
  fi
}


# ============================================================================
# APPLICATION INITIALIZATION AND STARTUP
# ============================================================================

# Initialize application
setup_config
check_dependencies
setup_directories

# Start main application
main_menu