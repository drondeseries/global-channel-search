#!/bin/bash

# === Global Station Search ===
# Description: Television station search tool using Channels DVR API
# dispatcharr integration for direct field population from search results
# Created: 2025/05/26
VERSION="1.3.1"
VERSION_INFO="Last Modified: 2025/06/01
Patch (1.3.2)
• Fixed broken automatic token refresh during workflow
• Add save and resume state handling to dispatcharr all channels workflow
• Add ability to start at any channel in the dispatcharr all channels workflow
Patch (1.3.1)
• Update to regex logic for channel name parsing, including helper functions
• Updated instructions and guidance to be more accurate in multiple functions
• Fixed dispatcharr integration workflows to be significantly more efficient
• Improved backup handling
• Removed broken 'station information' option in direct API search
• More consistent appearance across the script
• Code cleanup and reorganization

Recent Major Version Changes (1.3.0)
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
  echo -e "${BOLD}Key Features:${RESET}"
  echo "• ${GREEN}Local Database Search${RESET} - Search thousands of stations instantly"
  echo "• ${GREEN}User Cache Expansion${RESET} - Add custom markets to your database (requires Channels DVR server)"
  echo "• ${GREEN}Dispatcharr Integration${RESET} - Automated channel field population in Dispatcharr"
  echo "  - Station ID assignment with smart matching"
  echo "  - Logo upload and channel name updates"
  echo "  - TVG-ID (call sign) population"
  echo "• ${GREEN}Channels DVR Integration${RESET} - Direct API search"
  echo "• ${GREEN}Reverse Station Lookup${RESET} - Get detailed info from station IDs"
  echo
  echo -e "${BOLD}Quick Start Guide:${RESET}"
  echo "1. ${CYAN}First Run${RESET}: Script will guide you through initial setup"
  echo "2. ${CYAN}Immediate Use${RESET}: Try 'Search Local Database' (works out of the box)"
  echo "3. ${CYAN}Integration${RESET}: Use 'Dispatcharr Integration' for channel management"
  echo "4. ${CYAN}Customization${RESET}: Configure servers and filters in 'Settings'"
  echo "5. ${CYAN}Expansion${RESET}: Add custom markets via 'Manage Television Markets' (requires CHannels DVR server)"
  echo
  echo -e "${BOLD}Getting Help:${RESET}"
  echo "• Run without options for interactive menus with built-in guidance"
  echo "• Check 'Developer Information' in Settings for technical details"
  echo "• All operations include help text and examples"
}

if [[ -z "${TERM:-}" ]]; then
    export TERM="xterm"
fi

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
# UTILITY & HELPER FUNCTIONS
# ============================================================================

pause_for_user() {
  read -p "Press Enter to continue..."
}

show_invalid_choice() {
  echo -e "${RED}❌ Invalid Option: Please select a valid option from the menu${RESET}"
  echo -e "${CYAN}💡 Check the available choices and try again${RESET}"
  sleep 2
}

confirm_action() {
  local message="$1"
  local default="${2:-n}"
  
  echo -e "${BOLD}${YELLOW}Confirmation Required:${RESET}"
  read -p "$message (y/n) [default: $default]: " response < /dev/tty
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
    echo -e "${GREEN}✅ Local Database Search: Available with full features${RESET}"
  else
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
  fi
  
  # Integration Status
  if [[ -n "${CHANNELS_URL:-}" ]]; then
    if curl -s --connect-timeout 2 "$CHANNELS_URL" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Channels DVR Integration: Connected ($CHANNELS_URL)${RESET}"
    else
      echo -e "${RED}❌ Channels DVR Integration: Connection Failed ($CHANNELS_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Channels DVR Integration: Not configured (optional)${RESET}"
  fi
  
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    if check_dispatcharr_connection 2>/dev/null; then
      echo -e "${GREEN}✅ Dispatcharr Integration: Connected ($DISPATCHARR_URL)${RESET}"
    else
      echo -e "${RED}❌ Dispatcharr Integration: Connection Failed ($DISPATCHARR_URL)${RESET}"
    fi
  else
    echo -e "${YELLOW}⚠️  Dispatcharr Integration: Disabled${RESET}"
  fi
  echo
}

check_database_exists() {
  if ! has_stations_database; then
    clear
    echo -e "${BOLD}${YELLOW}Local Database Search${RESET}\n"
    
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo
    
    # Provide detailed status of what's available/missing
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${BOLD}${BLUE}Database Status Analysis:${RESET}"
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${RED}❌ Base Station Database: Not found${RESET}"
      echo -e "${CYAN}💡 Expected location: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}💡 Contact script distributor for base database file${RESET}"
    else
      echo -e "${GREEN}✅ Base Station Database: $base_count stations available${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  User Station Database: Empty${RESET}"
      echo -e "${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    else
      echo -e "${GREEN}✅ User Station Database: $user_count stations available${RESET}"
    fi
    
    echo
    
    # Show guidance based on what's available
    if [ "$base_count" -gt 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 You have the base database - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 You can search immediately or add custom markets for expansion${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -gt 0 ]; then
      echo -e "${CYAN}💡 You have user stations - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 Consider getting base database for broader coverage${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 No station database found - need to build or obtain one${RESET}"
      show_workflow_guidance
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Available Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Manage Television Markets → Build User Station Database"
    echo -e "${GREEN}2)${RESET} Use Direct Channels DVR API Search (requires Channels DVR server)"
    echo -e "${GREEN}3)${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "\n${CYAN}🔄 Opening Television Markets management...${RESET}"
        pause_for_user
        manage_markets
        return 1
        ;;
      2)
        echo -e "\n${CYAN}🔄 Opening Direct Channels DVR API Search...${RESET}"
        pause_for_user
        direct_api_search
        return 1
        ;;
      3|"")
        return 1  # Return to main menu
        ;;
      *)
        echo -e "${RED}❌ Invalid Option: Please select 1, 2, or 3${RESET}"
        sleep 1
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
  echo -e "${YELLOW}📋 Two-File Database System:${RESET}"
  echo -e "${GREEN}Base Station Database${RESET} - Pre-built stations for major markets (works out of the box)"
  echo -e "${GREEN}User Station Database${RESET} - Your custom additions from configured markets (optional)"
  echo
  echo -e "${YELLOW}📋 Quick Start Options:${RESET}"
  echo -e "${GREEN}1.${RESET} ${BOLD}Local Database Search${RESET} - Works immediately"
  echo -e "   • Search thousands of stations instantly"
  echo -e "   • Full filtering by resolution (HDTV, SDTV, UHDTV) and country"
  echo -e "   • Browse logos and detailed station information"
  echo
  echo -e "${GREEN}2.${RESET} ${BOLD}User Cache Expansion${RESET} - Optional expansion"
  echo -e "   • Add custom markets to your database (requires Channels DVR server)"
  echo -e "   • Configure additional countries/ZIP codes via 'Manage Television Markets'"
  echo -e "   • Run user caching to expand your available stations"
  echo
  echo -e "${GREEN}3.${RESET} ${BOLD}Channels DVR Integration${RESET} - Alternative search method"
  echo -e "   • Direct API search (requires Channels DVR server)"
  echo -e "   • Limited to 6 results per search, no filtering"
  echo -e "   • Use when base database is unavailable"
  echo
  echo -e "${CYAN}💡 Most users can start immediately with Local Database Search!${RESET}"
  echo
}

# ============================================================================
# CONFIGURATION & SETUP FUNCTIONS
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
      DISPATCHARR_REFRESH_INTERVAL=${DISPATCHARR_REFRESH_INTERVAL:-25}
      
      # Add resume state variables
      LAST_PROCESSED_CHANNEL_NUMBER=${LAST_PROCESSED_CHANNEL_NUMBER:-""}
      LAST_PROCESSED_CHANNEL_INDEX=${LAST_PROCESSED_CHANNEL_INDEX:-""}
      
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
  echo -e "${CYAN}   • Direct API search${RESET}"
  echo -e "${CYAN}   • User Cache Expansion${RESET}"
  echo -e "${GREEN}   • Local Database Search works out of the box with base database!${RESET}"
  echo
  
  if confirm_action "Configure Channels DVR server now? (can be done later in Settings)"; then
    if configure_channels_server; then
      echo -e "${GREEN}✅ Server configured successfully!${RESET}"
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
    echo "DISPATCHARR_REFRESH_INTERVAL=25"
    echo "# Resume State for Field Population"
    echo "LAST_PROCESSED_CHANNEL_NUMBER=\"\""
    echo "LAST_PROCESSED_CHANNEL_INDEX=\"\""
  } > "$CONFIG_FILE" || {
    echo -e "${RED}Error: Cannot write to config file${RESET}"
    exit 1
  }
  
  source "$CONFIG_FILE"
  echo -e "${GREEN}✅ Configuration saved successfully!${RESET}"
  echo
  echo -e "${BOLD}${CYAN}Ready to Use:${RESET}"
  echo -e "${GREEN}✅ Local Database Search - Works out of the box with base database${RESET}"
  echo -e "${CYAN}💡 Optional: Add custom markets via 'Manage Television Markets'${RESET}"
}

configure_channels_server() {
  local ip port
  
  clear
  echo -e "${BOLD}${CYAN}=== Channels DVR Server Configuration ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Connection to Channels DVR Server${RESET}"
  echo -e "${YELLOW}This server provides TV lineup data and station information for searches and caching.${RESET}"
  echo
  
  echo -e "${BOLD}${BLUE}Server Connection Guidelines:${RESET}"
  echo -e "${GREEN}• Local installation:${RESET} Use 'localhost' or '127.0.0.1'"
  echo -e "${GREEN}• Remote server:${RESET} Use the server's IP address on your network"
  echo -e "${GREEN}• Default port:${RESET} Usually 8089 unless you changed it"
  echo -e "${CYAN}💡 The server must be running and accessible from this machine${RESET}"
  echo
  
  while true; do
    echo -e "${BOLD}Step 1: Server IP Address${RESET}"
    read -p "Enter Channels DVR IP address [default: localhost]: " ip < /dev/tty
    ip=${ip:-localhost}
    
    # Validate IP format
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ "$ip" == "localhost" ]]; then
      echo -e "${GREEN}✅ IP address accepted: $ip${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid IP address format${RESET}"
      echo -e "${CYAN}💡 Use format like: 192.168.1.100 or 'localhost'${RESET}"
      echo
    fi
  done
  
  echo
  
  while true; do
    echo -e "${BOLD}Step 2: Server Port${RESET}"
    read -p "Enter Channels DVR port [default: 8089]: " port < /dev/tty
    port=${port:-8089}
    
    # Validate port number
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
      echo -e "${GREEN}✅ Port accepted: $port${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid port number${RESET}"
      echo -e "${CYAN}💡 Port must be a number between 1 and 65535${RESET}"
      echo
    fi
  done
  
  CHANNELS_URL="http://$ip:$port"
  
  echo
  echo -e "${BOLD}Step 3: Connection Test${RESET}"
  echo -e "${CYAN}🔗 Testing connection to $CHANNELS_URL...${RESET}"
  
  if curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Connection successful!${RESET}"
    echo -e "${CYAN}💡 Server is responding and ready for use${RESET}"
    return 0
  else
    echo -e "${RED}❌ Connection test failed${RESET}"
    echo -e "${CYAN}💡 This could be normal if the server is currently offline${RESET}"
    echo -e "${CYAN}💡 Common issues: Server not running, wrong IP/port, firewall blocking${RESET}"
    echo
    
    echo -e "${BOLD}${YELLOW}Connection Failed - What would you like to do?${RESET}"
    echo -e "${GREEN}1)${RESET} Save settings anyway (connection will be tested when needed)"
    echo -e "${GREEN}2)${RESET} Try different IP/port settings"
    echo -e "${GREEN}3)${RESET} Cancel configuration"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "${YELLOW}⚠️  Settings saved with failed connection test${RESET}"
        echo -e "${CYAN}💡 Connection will be tested again when features are used${RESET}"
        return 0
        ;;
      2)
        echo -e "${CYAN}🔄 Restarting server configuration...${RESET}"
        echo
        configure_channels_server  # Recursive call to restart
        return $?
        ;;
      3|"")
        echo -e "${YELLOW}⚠️  Server configuration cancelled${RESET}"
        CHANNELS_URL=""
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option${RESET}"
        sleep 1
        # Default to cancelling
        CHANNELS_URL=""
        return 1
        ;;
    esac
  fi
}

# ============================================================================
# CACHE MANAGEMENT CORE FUNCTIONS
# ============================================================================

init_base_cache() {
  if [ ! -f "$BASE_STATIONS_JSON" ]; then
    echo '[]' > "$BASE_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty base stations cache${RESET}" >&2
  fi

  # Initialize manifest system
  init_base_cache_manifest
}

init_user_cache() {
  if [ ! -f "$USER_STATIONS_JSON" ]; then
    echo '[]' > "$USER_STATIONS_JSON"
    echo -e "${YELLOW}Initialized empty user stations cache${RESET}" >&2
  fi
}

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

has_stations_database() {
  local effective_file
  effective_file=$(get_effective_stations_file 2>/dev/null)
  return $?
}

get_total_stations_count() {
  local effective_file
  effective_file=$(get_effective_stations_file 2>/dev/null)
  if [ $? -eq 0 ]; then
    jq 'length' "$effective_file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

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

add_stations_to_user_cache() {
  local new_stations_file="$1"
  
  echo -e "${CYAN}🔄 Starting user cache integration process...${RESET}"
  
  # STANDARDIZED: File validation with detailed feedback
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
  
  # STANDARDIZED: Initialize user cache with feedback
  echo -e "${CYAN}🔄 Initializing user cache environment...${RESET}"
  init_user_cache
  
  # STANDARDIZED: Validate user cache file with comprehensive error handling
  if [ -f "$USER_STATIONS_JSON" ]; then
    echo -e "${CYAN}🔍 Validating existing user cache...${RESET}"
    if ! jq empty "$USER_STATIONS_JSON" 2>/dev/null; then
      echo -e "${RED}❌ User Cache Validation: Existing cache file is corrupted${RESET}"
      echo -e "${CYAN}💡 File: $USER_STATIONS_JSON${RESET}"
      echo -e "${CYAN}💡 Backing up corrupted file and creating fresh cache${RESET}"
      
      # STANDARDIZED: Backup corrupted file with feedback
      local backup_file="${USER_STATIONS_JSON}.corrupted.$(date +%Y%m%d_%H%M%S)"
      echo -e "${CYAN}💾 Creating backup of corrupted cache...${RESET}"
      if mv "$USER_STATIONS_JSON" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}✅ Corrupted file backed up to: $(basename "$backup_file")${RESET}"
      else
        echo -e "${RED}❌ Backup Operation: Cannot backup corrupted cache file${RESET}"
        echo -e "${CYAN}💡 Check file permissions in cache directory${RESET}"
        return 1
      fi
      
      # STANDARDIZED: Initialize fresh cache with feedback
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
  
  # STANDARDIZED: Create temporary file with feedback
  local temp_file="$USER_STATIONS_JSON.tmp.$(date +%s)"
  
  # STANDARDIZED: Check disk space with detailed feedback
  echo -e "${CYAN}🔍 Checking available disk space...${RESET}"
  local new_stations_size=$(stat -c%s "$new_stations_file" 2>/dev/null || stat -f%z "$new_stations_file" 2>/dev/null || echo "0")
  local user_cache_size=$(stat -c%s "$USER_STATIONS_JSON" 2>/dev/null || stat -f%z "$USER_STATIONS_JSON" 2>/dev/null || echo "0")
  local estimated_size=$((new_stations_size + user_cache_size + 1048576))  # Add 1MB buffer
  
  # Check available disk space (rough estimate)
  local available_space=$(df "$(dirname "$USER_STATIONS_JSON")" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' || echo "999999999999")
  
  if [[ $estimated_size -gt $available_space ]]; then
    echo -e "${RED}❌ Disk Space Check: Insufficient disk space for merge operation${RESET}"
    echo -e "${CYAN}💡 Estimated space needed: $(( estimated_size / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Available space: $(( available_space / 1048576 )) MB${RESET}"
    echo -e "${CYAN}💡 Free up disk space and try again${RESET}"
    return 1
  fi
  echo -e "${GREEN}✅ Sufficient disk space available for merge${RESET}"
  
  # STANDARDIZED: Perform merge with detailed progress
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
  
  # STANDARDIZED: Validate merged result with feedback
  echo -e "${CYAN}🔍 Validating merged station data...${RESET}"
  if ! jq empty "$temp_file" 2>/dev/null; then
    echo -e "${RED}❌ Merge Validation: Merge produced invalid JSON${RESET}"
    echo -e "${CYAN}💡 Merge operation failed - keeping original cache${RESET}"
    rm -f "$temp_file" 2>/dev/null
    return 1
  fi
  echo -e "${GREEN}✅ Merged data validation passed${RESET}"
  
  # STANDARDIZED: Backup original cache with feedback
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
  
  # STANDARDIZED: Replace original with merged data
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
  
  # STANDARDIZED: Success validation and reporting
  echo -e "${CYAN}🔍 Validating final user cache...${RESET}"
  local new_count
  if new_count=$(jq 'length' "$USER_STATIONS_JSON" 2>/dev/null); then
    echo -e "${GREEN}✅ User cache integration completed successfully${RESET}"
    echo -e "${CYAN}📊 Total stations in user cache: $new_count${RESET}"
    
    # STANDARDIZED: Cleanup old backups with feedback
    echo -e "${CYAN}🧹 Cleaning up old backup files...${RESET}"
    local backup_pattern="${USER_STATIONS_JSON}.backup.*"
    local backup_count=$(ls -1 $backup_pattern 2>/dev/null | wc -l)
    if [[ $backup_count -gt 5 ]]; then
      ls -t $backup_pattern 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
      echo -e "${GREEN}✅ Cleaned up old backup files (kept 5 most recent)${RESET}"
    else
      echo -e "${CYAN}💡 Backup file count within limits ($backup_count kept)${RESET}"
    fi
    
    return 0
  else
    echo -e "${RED}❌ Final Validation: User cache update succeeded but validation failed${RESET}"
    echo -e "${CYAN}💡 Cache file may be corrupted after update${RESET}"
    return 1
  fi
}

cleanup_combined_cache() {
  rm -f "$COMBINED_STATIONS_JSON" 2>/dev/null || true
}

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
# BASE CACHE MANIFEST FUNCTIONS
# ============================================================================
# 
# Note: Base cache manifest CREATION is handled by the standalone script:
#       create_base_cache_manifest.sh
# 
# This section contains only manifest READING/CHECKING functions used during
# normal operation to skip markets already covered by the base cache.
# 
# Distribute both all_stations_base.json AND all_stations_base_manifest.json
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
# CHANNEL NAME PARSING & FILTERS
# ============================================================================

parse_channel_name() {
  local channel_name="$1"
  local clean_name="$channel_name"
  local detected_country=""
  local detected_resolution=""
  
  # FIRST: Clean unwanted characters that can interfere with parsing
  # Replace with spaces (not delete) to maintain word boundaries
  # This fixes cases like "US:ESPN" or "Sports:CA" where separators prevent proper detection
  if [[ "$clean_name" =~ [\|★◉:] ]]; then
     clean_name=$(echo "$clean_name" | sed 's/[|★◉:]/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
  
  # Helper function to check if a word exists as a separate word (not part of another word)
  word_exists() {
    local text="$1"
    local word="$2"
    # Check if word exists with word boundaries (start/end of string or surrounded by spaces)
    [[ " $text " =~ [[:space:]]$word[[:space:]] ]] || [[ "$text" =~ ^$word[[:space:]] ]] || [[ "$text" =~ [[:space:]]$word$ ]] || [[ "$text" == "$word" ]]
  }
  
  # Helper function to remove a word safely (only if it's a separate word)
  remove_word() {
    local text="$1"
    local word="$2"
    # Remove the word and clean up extra spaces
    echo "$text" | sed -E "s/(^|[[:space:]])$word([[:space:]]|$)/ /g" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
  }
  
  # Country detection - check for separate words only
  if word_exists "$clean_name" "US" || word_exists "$clean_name" "USA"; then
    detected_country="USA"
    clean_name=$(remove_word "$clean_name" "US")
    clean_name=$(remove_word "$clean_name" "USA")
  elif word_exists "$clean_name" "CA" || word_exists "$clean_name" "CAN"; then
    detected_country="CAN" 
    clean_name=$(remove_word "$clean_name" "CA")
    clean_name=$(remove_word "$clean_name" "CAN")
  elif word_exists "$clean_name" "UK" || word_exists "$clean_name" "GBR"; then
    detected_country="GBR"
    clean_name=$(remove_word "$clean_name" "UK")
    clean_name=$(remove_word "$clean_name" "GBR")
  elif word_exists "$clean_name" "DE" || word_exists "$clean_name" "DEU"; then
    detected_country="DEU"
    clean_name=$(remove_word "$clean_name" "DE")
    clean_name=$(remove_word "$clean_name" "DEU")
  fi

  # Resolution detection patterns (order matters - check highest quality first)
  if word_exists "$clean_name" "4K" || word_exists "$clean_name" "UHD" || word_exists "$clean_name" "UHDTV" || [[ "$clean_name" =~ Ultra[[:space:]]*HD ]]; then
    detected_resolution="UHDTV"
    clean_name=$(remove_word "$clean_name" "4K")
    clean_name=$(remove_word "$clean_name" "UHD") 
    clean_name=$(remove_word "$clean_name" "UHDTV")
    clean_name=$(echo "$clean_name" | sed -E 's/Ultra[[:space:]]*HD/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  elif word_exists "$clean_name" "HD" || word_exists "$clean_name" "FHD" || [[ "$clean_name" =~ (^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$) ]]; then
    detected_resolution="HDTV"
    clean_name=$(remove_word "$clean_name" "HD")
    clean_name=$(remove_word "$clean_name" "FHD")
    clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  elif word_exists "$clean_name" "SD" || [[ "$clean_name" =~ (^|[[:space:]])480[ip]?([[:space:]]|$) ]]; then
    detected_resolution="SDTV"
    clean_name=$(remove_word "$clean_name" "SD")
    clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])480[ip]?([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
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

search_local_database() {
  # Check if any database exists, provide helpful guidance if not
  if ! has_stations_database; then
    clear
    echo -e "${BOLD}${YELLOW}Local Database Search${RESET}\n"
    
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo
    
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${BOLD}Database Status Analysis:${RESET}"
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${RED}❌ Base Station Database: Not found${RESET}"
      echo -e "${CYAN}💡 Expected location: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}💡 Contact script distributor for base database file${RESET}"
    else
      echo -e "${GREEN}✅ Base Station Database: $base_count stations available${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  User Station Database: Empty${RESET}"
      echo -e "${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    else
      echo -e "${GREEN}✅ User Station Database: $user_count stations available${RESET}"
    fi
    
    echo
    
    # Show guidance based on what's available
    if [ "$base_count" -gt 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 You have the base database - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 You can search immediately or add custom markets for expansion${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -gt 0 ]; then
      echo -e "${CYAN}💡 You have user stations - Local Database Search should work!${RESET}"
      echo -e "${CYAN}💡 Consider getting base database for broader coverage${RESET}"
    elif [ "$base_count" -eq 0 ] && [ "$user_count" -eq 0 ]; then
      echo -e "${CYAN}💡 No station database found - need to build or obtain one${RESET}"
      show_workflow_guidance
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Available Options:${RESET}"
    echo -e "${GREEN}1.${RESET} Manage Television Markets → Build User Station Database"
    echo -e "${GREEN}2.${RESET} Use Direct Channels DVR API Search (requires Channels DVR server)"
    echo -e "${GREEN}3.${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "\n${CYAN}🔄 Opening Television Markets management...${RESET}"
        pause_for_user
        manage_markets
        return
        ;;
      2)
        echo -e "\n${CYAN}🔄 Opening Direct Channels DVR API Search...${RESET}"
        pause_for_user
        direct_api_search
        return
        ;;
      3|"")
        return
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        return
        ;;
    esac
  fi
  
  # Database exists, proceed with search
  run_search_interface
}

run_search_interface() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Database Search ===${RESET}\n"
    
    # Show database status with standardized patterns
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${GREEN}✅ Database Available: $total_count stations${RESET}"
    if [ "$base_count" -gt 0 ]; then
      echo -e "   Base Station Database: $base_count stations"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo -e "   User Station Database: $user_count stations"
    fi
    echo
    
    # STANDARDIZED: Current Search Filters with consistent patterns
    echo -e "${BOLD}${BLUE}Current Search Filters:${RESET}"
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      echo -e "${GREEN}✅ Resolution Filter: Active (${YELLOW}$ENABLED_RESOLUTIONS${RESET})"
      echo -e "${CYAN}💡 Showing only: $ENABLED_RESOLUTIONS quality stations${RESET}"
    else
      echo -e "${YELLOW}⚠️  Resolution Filter: Disabled${RESET}"
      echo -e "${CYAN}💡 Showing all quality levels (SDTV, HDTV, UHDTV)${RESET}"
    fi
    
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      echo -e "${GREEN}✅ Country Filter: Active (${YELLOW}$ENABLED_COUNTRIES${RESET})"
      echo -e "${CYAN}💡 Showing only: $ENABLED_COUNTRIES stations${RESET}"
    else
      echo -e "${YELLOW}⚠️  Country Filter: Disabled${RESET}"
      echo -e "${CYAN}💡 Showing stations from all available countries${RESET}"
    fi
    
    echo -e "${CYAN}💡 Configure filters in Settings → Search Filters to narrow results${RESET}"
    echo
    
    read -p "Enter search term (station name or call sign) or 'q' to return: " search_term < /dev/tty
    
    case "$search_term" in
      q|Q|"") return 0 ;;
      *)
        if [[ -n "$search_term" && ! "$search_term" =~ ^[[:space:]]*$ ]]; then
          perform_search "$search_term"
        else
          echo -e "${RED}❌ Please enter a search term${RESET}"
          echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'WABC'${RESET}"
          pause_for_user
        fi
        ;;
    esac
  done
}

perform_search() {
  local search_term="$1"
  local page=1
  local results_per_page=10
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Database Search Results ===${RESET}\n"
    echo -e "${YELLOW}Search: '$search_term' (Page $page)${RESET}"
    
    # STANDARDIZED: Show active filters with consistent formatting
    local filter_status=""
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      filter_status+="Resolution: ${GREEN}$ENABLED_RESOLUTIONS${RESET} "
    fi
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      filter_status+="Country: ${GREEN}$ENABLED_COUNTRIES${RESET} "
    fi
    if [ -n "$filter_status" ]; then
      echo -e "${BLUE}🔍 Active Filters: $filter_status${RESET}"
    else
      echo -e "${CYAN}🔍 No filters active - showing all available stations${RESET}"
    fi
    echo

    # STANDARDIZED: Progress indicator for search
    echo -e "${CYAN}🔄 Searching database...${RESET}"
    
    # Get search results using shared function
    local results
    results=$(shared_station_search "$search_term" "$page" "full")
    
    local total_results
    total_results=$(shared_station_search "$search_term" 1 "count")

    # STANDARDIZED: Result display with consistent error handling
    if [[ -z "$results" ]]; then
      echo -e "\n${YELLOW}⚠️  No results found for '$search_term'${RESET}"
      echo
      echo -e "${BOLD}${CYAN}Suggestions to improve your search:${RESET}"
      if [ "$FILTER_BY_RESOLUTION" = "true" ] || [ "$FILTER_BY_COUNTRY" = "true" ]; then
        echo -e "${CYAN}💡 Try disabling filters in Settings → Search Filters${RESET}"
      fi
      echo -e "${CYAN}💡 Try partial names: 'ESPN' instead of 'ESPN Sports Center'${RESET}"
      echo -e "${CYAN}💡 Try call signs: 'CNN' for CNN stations${RESET}"
      echo -e "${CYAN}💡 Check spelling and try alternative names${RESET}"
      echo
    else
      echo -e "\n${GREEN}✅ Found $total_results total results${RESET}"
      echo -e "${CYAN}💡 Showing page $page with up to $results_per_page results${RESET}"
      echo

      # FIXED: Enhanced table header with selection column
      printf "${BOLD}${YELLOW}%-3s %-30s %-10s %-8s %-12s %s${RESET}\n" "Key" "Channel Name" "Call Sign" "Quality" "Station ID" "Country"
      echo "---------------------------------------------------------------------------------"

      local result_count=0
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")

      # FIXED: Process search results with GREEN selection highlighting
      while IFS=$'\t' read -r name call_sign quality station_id country; do
        [[ -z "$name" ]] && continue

        local key="${key_letters[$result_count]}"

        # FIXED: Format table row with GREEN selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        echo -e "${GREEN}${country}${RESET}"

        # STANDARDIZED: Logo display with consistent messaging
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "   [logo previews disabled - enable in Settings]"
        fi
        echo

        ((result_count++))
      done <<< "$results"
    fi

    # STANDARDIZED: Calculate pagination info with error handling
    local total_pages=$(( (total_results + results_per_page - 1) / results_per_page ))
    [[ $total_pages -eq 0 ]] && total_pages=1

    echo -e "${BOLD}${BLUE}Page $page of $total_pages${RESET}"
    echo

    # STANDARDIZED: Navigation options with consistent formatting
    echo -e "${BOLD}${CYAN}Navigation Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo -e "${GREEN}a-j)${RESET} View detailed info for selected station"
    [[ $page -lt $total_pages ]] && echo -e "${GREEN}n)${RESET} Next page"
    [[ $page -gt 1 ]] && echo -e "${GREEN}p)${RESET} Previous page"
    echo -e "${GREEN}s)${RESET} New search"
    echo -e "${GREEN}q)${RESET} Back to search menu"
    echo

    read -p "Your choice: " choice < /dev/tty

    case "$choice" in
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        if [[ $result_count -gt 0 ]]; then
          show_station_details "$choice" "$results"
        else
          echo -e "${RED}❌ No results to select from${RESET}"
          echo -e "${CYAN}💡 Try a different search term${RESET}"
          sleep 2
        fi
        ;;
      n|N)
        if [[ $page -lt $total_pages ]]; then
          ((page++))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $page -gt 1 ]]; then
          ((page--))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
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
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
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
      
      # STANDARDIZED: Basic Information with enhanced formatting
      echo -e "${BOLD}${BLUE}Basic Information:${RESET}"
      echo -e "${CYAN}Station Name:${RESET} ${GREEN}$name${RESET}"
      echo -e "${CYAN}Call Sign:${RESET} ${GREEN}$call_sign${RESET}"
      echo -e "${CYAN}Station ID:${RESET} ${GREEN}$station_id${RESET}"
      echo -e "${CYAN}Country:${RESET} ${GREEN}$country${RESET}"
      echo -e "${CYAN}Video Quality:${RESET} ${GREEN}$quality${RESET}"
      echo
      
      # STANDARDIZED: Progress indicator for additional data lookup
      echo -e "${CYAN}🔄 Retrieving additional station information...${RESET}"
      
      # Get additional details from database with error handling
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
          echo -e "${BOLD}${BLUE}Extended Information:${RESET}"
          echo "$details"
          echo
        else
          echo -e "${YELLOW}⚠️  Extended information not available for this station${RESET}"
          echo -e "${CYAN}💡 This may occur with manually-added or API-sourced stations${RESET}"
          echo
        fi
      else
        echo -e "${RED}❌ Station Database: Unable to access extended information${RESET}"
        echo -e "${CYAN}💡 Database may be temporarily unavailable${RESET}"
        echo
      fi
      
      # STANDARDIZED: Logo display with enhanced messaging
      echo -e "${BOLD}${BLUE}Station Logo:${RESET}"
      if [[ "$SHOW_LOGOS" == true ]]; then
        echo -e "${CYAN}🖼️  Logo preview:${RESET}"
        display_logo "$station_id"
        echo
      else
        echo -e "${YELLOW}⚠️  Logo previews disabled${RESET}"
        echo -e "${CYAN}💡 Enable in Settings → Logo Display for visual previews${RESET}"
        echo -e "${CYAN}💡 Requires 'viu' tool for terminal image display${RESET}"
        echo
      fi
      
      # STANDARDIZED: Usage guidance
      echo -e "${BOLD}${BLUE}Usage Information:${RESET}"
      echo -e "${CYAN}💡 This station can be used for:${RESET}"
      echo -e "${GREEN}• Search results and filtering${RESET}"
      echo -e "${GREEN}• Dispatcharr integration and channel matching${RESET}"
      echo -e "${GREEN}• Station ID lookups and reverse searches${RESET}"
      echo -e "${GREEN}• Export to CSV for external use${RESET}"
      echo
      
      # STANDARDIZED: Data source information
      local data_source="Unknown"
      local stations_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id) | .source // "Unknown"' "$stations_file" 2>/dev/null)
      if [[ -n "$stations_data" && "$stations_data" != "null" ]]; then
        data_source="$stations_data"
      fi
      
      echo -e "${BOLD}${BLUE}Data Source:${RESET}"
      case "$data_source" in
        "user")
          echo -e "${GREEN}✅ User Station Database${RESET} (from your configured markets)"
          ;;
        "base"|"combined")
          echo -e "${GREEN}✅ Base Station Database${RESET} (distributed with script)"
          ;;
        *)
          echo -e "${CYAN}💡 Combined Database${RESET} (merged from available sources)"
          ;;
      esac
      echo
      
      pause_for_user
    else
      echo -e "${RED}❌ Station Details: Could not retrieve information${RESET}"
      echo -e "${CYAN}💡 The selected station may no longer be available${RESET}"
      echo -e "${CYAN}💡 Try refreshing your search results${RESET}"
      sleep 2
    fi
  else
    echo -e "${RED}❌ Invalid Selection: '$choice' is not a valid option${RESET}"
    echo -e "${CYAN}💡 Use letters a-j to select from the displayed results${RESET}"
    sleep 2
  fi
}

run_direct_api_search() {
  # Validate server is configured and accessible
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: No server configured${RESET}"
    echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server first${RESET}"
    pause_for_user
    return 1
  fi
  
  # Test server connection
  echo -e "${CYAN}🔗 Testing connection to Channels DVR server...${RESET}"
  if ! curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null; then
    echo -e "${RED}❌ Channels DVR Integration: Connection failed${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    echo -e "${CYAN}💡 Verify server is running and accessible${RESET}"
    echo -e "${CYAN}💡 Check IP address and port in Settings${RESET}"
    echo -e "${CYAN}💡 Alternative: Use Local Database Search instead${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${GREEN}✅ Connection to Channels DVR server confirmed${RESET}"
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}\n"
    
    echo -e "${GREEN}✅ Connected to: $CHANNELS_URL${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}⚠️  IMPORTANT API LIMITATIONS:${RESET}"
    echo -e "${RED}• Results limited to 6 stations per search${RESET}"
    echo -e "${RED}• No country information available${RESET}"
    echo -e "${RED}• Search filters (resolution, country) not available${RESET}"
    echo -e "${RED}• Station details and comprehensive information not available${RESET}"
    echo -e "${RED}• Less comprehensive than Local Database Search${RESET}"
    echo
    echo -e "${GREEN}💡 For full features and station details: Use 'Local Database Search' instead${RESET}"
    echo
    
    read -p "Search API by station name or call sign (or 'q' to return): " SEARCH_TERM < /dev/tty
    
    case "$SEARCH_TERM" in
      q|Q|"") break ;;
      *)
        if [[ -z "$SEARCH_TERM" || "$SEARCH_TERM" =~ ^[[:space:]]*$ ]]; then
          echo -e "${RED}❌ Please enter a search term${RESET}"
          echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'ESPN'${RESET}"
          pause_for_user
          continue
        fi
        
        perform_direct_api_search "$SEARCH_TERM"
        ;;
    esac
  done
}

run_direct_api_search() {
  # Validate server is configured and accessible
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    echo -e "${RED}❌ Channels DVR Integration: No server configured${RESET}"
    echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server first${RESET}"
    pause_for_user
    return 1
  fi
  
  # Test server connection
  echo -e "${CYAN}🔗 Testing connection to Channels DVR server...${RESET}"
  if ! curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null; then
    echo -e "${RED}❌ Channels DVR Integration: Connection failed${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    echo -e "${CYAN}💡 Verify server is running and accessible${RESET}"
    echo -e "${CYAN}💡 Check IP address and port in Settings${RESET}"
    echo -e "${CYAN}💡 Alternative: Use Local Database Search instead${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${GREEN}✅ Connection to Channels DVR server confirmed${RESET}"
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}\n"
    
    echo -e "${GREEN}✅ Connected to: $CHANNELS_URL${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}⚠️  IMPORTANT API LIMITATIONS:${RESET}"
    echo -e "${RED}• Results limited to 6 stations per search${RESET}"
    echo -e "${RED}• No country information available${RESET}"
    echo -e "${RED}• Search filters (resolution, country) not available${RESET}"
    echo -e "${RED}• Less comprehensive than Local Database Search${RESET}"
    echo
    echo -e "${GREEN}💡 For better results: Use 'Local Database Search' instead${RESET}"
    echo
    
    read -p "Search API by station name or call sign (or 'q' to return): " SEARCH_TERM < /dev/tty
    
    case "$SEARCH_TERM" in
      q|Q|"") break ;;
      *)
        if [[ -z "$SEARCH_TERM" || "$SEARCH_TERM" =~ ^[[:space:]]*$ ]]; then
          echo -e "${RED}❌ Please enter a search term${RESET}"
          echo -e "${CYAN}💡 Try station names like 'CNN' or call signs like 'ESPN'${RESET}"
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
  
  echo -e "\n${CYAN}🔍 Searching Channels DVR API for '$search_term'...${RESET}"
  echo -e "${CYAN}💡 This may take a moment to query the server${RESET}"
  
  # Call the TMS API directly with better error handling
  local api_response
  echo -e "${CYAN}📡 Querying: $CHANNELS_URL/tms/stations/$search_term${RESET}"
  
  api_response=$(curl -s --connect-timeout 15 --max-time 30 "$CHANNELS_URL/tms/stations/$search_term" 2>/dev/null)
  local curl_exit_code=$?
  
  # Handle connection/timeout errors
  if [[ $curl_exit_code -ne 0 ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    
    case $curl_exit_code in
      6)
        echo -e "${RED}❌ Channels DVR API: Could not resolve hostname${RESET}"
        echo -e "${CYAN}💡 Check server IP address in Settings${RESET}"
        echo -e "${CYAN}💡 Verify server is accessible on your network${RESET}"
        ;;
      7)
        echo -e "${RED}❌ Channels DVR API: Connection refused${RESET}"
        echo -e "${CYAN}💡 Verify Channels DVR server is running${RESET}"
        echo -e "${CYAN}💡 Check port number in Settings (usually 8089)${RESET}"
        ;;
      28)
        echo -e "${RED}❌ Channels DVR API: Connection timeout${RESET}"
        echo -e "${CYAN}💡 Server may be slow or unresponsive${RESET}"
        echo -e "${CYAN}💡 Try again or check server status${RESET}"
        ;;
      *)
        echo -e "${RED}❌ Channels DVR API: Connection failed (error $curl_exit_code)${RESET}"
        echo -e "${CYAN}💡 Check server connection and try again${RESET}"
        ;;
    esac
    echo -e "${CYAN}💡 Alternative: Use Local Database Search for reliable results${RESET}"
    pause_for_user
    return
  fi
  
  # Handle empty response
  if [[ -z "$api_response" ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    echo -e "${RED}❌ Channels DVR API: No response from server${RESET}"
    echo -e "${CYAN}💡 Server responded but returned no data${RESET}"
    echo -e "${CYAN}💡 Check server status and try again${RESET}"
    echo -e "${CYAN}💡 Alternative: Use Local Database Search instead${RESET}"
    pause_for_user
    return
  fi
  
  # Check if response is valid JSON
  if ! echo "$api_response" | jq empty 2>/dev/null; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    echo -e "${RED}❌ Channels DVR API: Invalid response format${RESET}"
    echo -e "${CYAN}💡 Server returned non-JSON data${RESET}"
    echo -e "${CYAN}Response preview: $(echo "$api_response" | head -c 100)...${RESET}"
    echo -e "${CYAN}💡 Check API endpoint or server configuration${RESET}"
    pause_for_user
    return
  fi
  
  # Check if response is an empty array
  local response_length=$(echo "$api_response" | jq 'length' 2>/dev/null || echo "0")
  if [[ "$response_length" -eq 0 ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    echo -e "${YELLOW}⚠️  No stations found for '$search_term'${RESET}"
    echo -e "${CYAN}💡 Try different spelling or search terms${RESET}"
    echo -e "${CYAN}💡 Use call signs (like CNN, ESPN) for better results${RESET}"
    echo -e "${CYAN}💡 Try partial names instead of full names${RESET}"
    echo -e "${GREEN}💡 Local Database Search may have more comprehensive results${RESET}"
    pause_for_user
    return
  fi
  
  # Process the response and convert to TSV format
  echo "$api_response" | jq -r '
    .[] | [
      .name // "Unknown", 
      .callSign // "N/A", 
      .videoQuality.videoType // "Unknown", 
      .stationId // "Unknown",
      "API-Direct"
    ] | @tsv
  ' > "$API_SEARCH_RESULTS" 2>/dev/null
  
  if [[ $? -ne 0 ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
    echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
    echo
    echo -e "${RED}❌ API Response Processing: Failed to parse station data${RESET}"
    echo -e "${CYAN}💡 API response format may have changed${RESET}"
    echo -e "${CYAN}💡 Try Local Database Search as alternative${RESET}"
    pause_for_user
    return
  fi
  
  # Success case - pass search context to display function
  display_direct_api_results "$search_term"
}

display_direct_api_results() {
  local search_term="$1"
  
  mapfile -t RESULTS < "$API_SEARCH_RESULTS"
  local count=${#RESULTS[@]}
  
  clear
  echo -e "${BOLD}${CYAN}=== Direct Channels DVR API Search ===${RESET}"
  echo -e "${CYAN}Searched for: '$search_term' on $CHANNELS_URL${RESET}"
  echo -e "${GREEN}✅ API search completed successfully${RESET}"
  echo
  
  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No results found for '$search_term' in API${RESET}"
    echo -e "${CYAN}💡 Try: Different spelling, call signs, or partial names${RESET}"
    echo -e "${GREEN}💡 Local Database Search may have more comprehensive results${RESET}"
  else
    echo -e "${GREEN}✅ Found $count result(s) for '$search_term'${RESET}"
    echo -e "${YELLOW}⚠️  Direct API results (limited to 6 maximum)${RESET}"
    echo -e "${CYAN}💡 No country data available, no filtering applied${RESET}"
    echo -e "${RED}⚠️  Station details not available for API results${RESET}"
    echo

    # Table header WITHOUT selection column (no Key column)
    printf "${BOLD}${YELLOW}%-30s %-10s %-8s %-12s${RESET}\n" "Channel Name" "Call Sign" "Quality" "Station ID"
    echo "----------------------------------------------------------------"

    for ((i = 0; i < count; i++)); do
      IFS=$'\t' read -r NAME CALLSIGN RES STID SOURCE <<< "${RESULTS[$i]}" 
      printf "%-30s %-10s %-8s ${CYAN}%-12s${RESET}\n" "$NAME" "$CALLSIGN" "$RES" "$STID"

      # Display logo if available
      display_logo "$STID"
      echo
    done

    echo -e "${CYAN}💡 Tip: For detailed station information and filtering, use Local Database Search${RESET}"
    echo -e "${CYAN}💡 Local Database Search provides comprehensive station details and advanced features${RESET}"
  fi
  
  pause_for_user
}

reverse_station_lookup() {
  local station_id="$1"
  
  if [[ -z "$station_id" ]]; then
    echo -e "${RED}❌ Station ID required for lookup${RESET}"
    echo -e "${CYAN}💡 Please provide a station ID to search for${RESET}"
    return 1
  fi
  
  echo -e "${CYAN}🔍 Looking up station ID: $station_id${RESET}"
  echo
  
  # Check local database only
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo
    
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    echo -e "${BOLD}Database Status Analysis:${RESET}"
    
    if [ "$base_count" -eq 0 ]; then
      echo -e "${RED}❌ Base Station Database: Not found${RESET}"
      echo -e "${CYAN}💡 Expected location: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "${CYAN}💡 Contact script distributor for base database file${RESET}"
    else
      echo -e "${GREEN}✅ Base Station Database: $base_count stations available${RESET}"
    fi
    
    if [ "$user_count" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  User Station Database: Empty${RESET}"
      echo -e "${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    else
      echo -e "${GREEN}✅ User Station Database: $user_count stations available${RESET}"
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "${CYAN}💡 Build a station database using 'Manage Television Markets' → 'Run User Caching'${RESET}"
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
    echo -e "${GREEN}✅ Station found in Local Database Search:${RESET}"
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
    
    echo -e "${CYAN}📊 Database Information:${RESET}"
    echo "  Total stations in database: $(get_total_stations_count)"
    if [ "$base_count" -gt 0 ]; then
      echo "  Base cache stations: $base_count"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo "  User cache stations: $user_count"
    fi
    
    echo -e "\n${GREEN}✅ Station lookup completed successfully${RESET}"
  else
    echo -e "${RED}❌ Station ID '$station_id' not found in Local Database Search${RESET}"
    echo
    echo -e "${BOLD}${CYAN}Troubleshooting Suggestions:${RESET}"
    echo -e "${CYAN}💡 Verify the station ID is correct${RESET}"
    echo -e "${CYAN}💡 Try searching by name or call sign instead${RESET}"
    echo -e "${CYAN}💡 Add markets containing this station to your cache${RESET}"
    
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
    
    echo
    echo -e "${BOLD}${CYAN}Alternative Options:${RESET}"
    echo -e "${CYAN}💡 Use 'Local Database Search' to browse available stations${RESET}"
    echo -e "${CYAN}💡 Add more markets via 'Manage Television Markets' for broader coverage${RESET}"
    
    return 1
  fi
  
  return 0
}

reverse_station_id_lookup_menu() {
  clear
  echo -e "${BOLD}${CYAN}=== Reverse Station ID Lookup ===${RESET}\n"
  echo -e "${BLUE}📍 Station Information Retrieval${RESET}"
  echo -e "${YELLOW}Enter a station ID to get comprehensive information about that station.${RESET}"
  echo -e "${CYAN}This searches your local database for detailed station information.${RESET}"
  echo
  
  # STANDARDIZED: Show usage examples with detailed guidance
  echo -e "${BOLD}${BLUE}Station ID Format Guide:${RESET}"
  echo -e "${CYAN}💡 Station IDs are typically 4-6 digit numbers${RESET}"
  echo -e "${CYAN}💡 Common examples: 10142, 16331, 18279, 24821${RESET}"
  echo -e "${CYAN}💡 Range: Usually between 1000-99999${RESET}"
  echo -e "${CYAN}💡 You can find station IDs in:${RESET}"
  echo -e "${CYAN}  • Search results from Local Database Search${RESET}"
  echo -e "${CYAN}  • Dispatcharr channel configuration${RESET}"
  echo -e "${CYAN}  • Direct API search results${RESET}"
  echo -e "${CYAN}  • CSV exports from this tool${RESET}"
  echo
  
  # STANDARDIZED: Show database status with helpful context
  local total_count=$(get_total_stations_count)
  if [ "$total_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Database Available: $total_count stations ready for lookup${RESET}"
    
    # Show breakdown for user context
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    
    if [ "$base_count" -gt 0 ]; then
      echo -e "   Base Station Database: $base_count stations"
    fi
    if [ "$user_count" -gt 0 ]; then
      echo -e "   User Station Database: $user_count stations"
    fi
    
    # Show sample station IDs for guidance
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ]; then
      echo
      echo -e "${BOLD}${BLUE}Sample Station IDs from your database:${RESET}"
      local sample_ids=$(jq -r '.[] | .stationId' "$stations_file" 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
      if [ -n "$sample_ids" ]; then
        echo -e "${CYAN}Examples you can try: $sample_ids${RESET}"
      fi
    fi
  else
    echo -e "${RED}❌ No station database available for lookup${RESET}"
    echo -e "${CYAN}💡 To build a station database:${RESET}"
    echo -e "${CYAN}  • Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    echo -e "${CYAN}  • Or ensure base cache file ($(basename "$BASE_STATIONS_JSON")) is in script directory${RESET}"
    echo
    echo -e "${YELLOW}⚠️  Cannot perform station ID lookup without database${RESET}"
    pause_for_user
    return 1
  fi
  echo
  
  # STANDARDIZED: Station ID input with comprehensive validation
  echo -e "${BOLD}Step 1: Station ID Entry${RESET}"
  echo -e "${CYAN}💡 Enter a numeric station ID to look up${RESET}"
  echo -e "${CYAN}💡 Press Enter without input to return to main menu${RESET}"
  echo
  
  local lookup_id
  while true; do
    read -p "Enter station ID to lookup (or press Enter to return): " lookup_id < /dev/tty
    
    # Handle empty input (user wants to exit)
    if [[ -z "$lookup_id" ]]; then
      echo -e "${YELLOW}⚠️  Station ID lookup cancelled${RESET}"
      return 0
    fi
    
    # Remove any whitespace
    lookup_id=$(echo "$lookup_id" | tr -d '[:space:]')
    
    # STANDARDIZED: Comprehensive station ID validation
    if [[ "$lookup_id" =~ ^[0-9]+$ ]]; then
      # Check reasonable range for station IDs
      if (( lookup_id >= 1 && lookup_id <= 999999 )); then
        # Additional check for typical range
        if (( lookup_id < 1000 )); then
          echo -e "${YELLOW}⚠️  Station ID $lookup_id is unusually low${RESET}"
          echo -e "${CYAN}💡 Most station IDs are 4+ digits (e.g., 10142, 16331)${RESET}"
          if confirm_action "Continue with station ID $lookup_id anyway?"; then
            echo -e "${GREEN}✅ Station ID accepted: $lookup_id${RESET}"
            break
          else
            echo -e "${CYAN}💡 Try a different station ID${RESET}"
            continue
          fi
        elif (( lookup_id > 99999 )); then
          echo -e "${YELLOW}⚠️  Station ID $lookup_id is unusually high${RESET}"
          echo -e "${CYAN}💡 Most station IDs are 4-5 digits (e.g., 10142, 16331)${RESET}"
          if confirm_action "Continue with station ID $lookup_id anyway?"; then
            echo -e "${GREEN}✅ Station ID accepted: $lookup_id${RESET}"
            break
          else
            echo -e "${CYAN}💡 Try a different station ID${RESET}"
            continue
          fi
        else
          # Station ID is in typical range
          echo -e "${GREEN}✅ Station ID accepted: $lookup_id${RESET}"
          break
        fi
      else
        echo -e "${RED}❌ Station ID out of valid range${RESET}"
        echo -e "${CYAN}💡 Station IDs must be between 1 and 999999${RESET}"
        echo -e "${CYAN}💡 Check that you entered the number correctly${RESET}"
      fi
    else
      echo -e "${RED}❌ Invalid Station ID format${RESET}"
      echo -e "${CYAN}💡 Station IDs must be numeric only (e.g., 10142, 16331)${RESET}"
      echo -e "${CYAN}💡 Do not include letters, spaces, or special characters${RESET}"
      
      # Helpful guidance for common mistakes
      if [[ "$lookup_id" =~ [a-zA-Z] ]]; then
        echo -e "${CYAN}💡 Tip: Remove any letters from your input${RESET}"
      fi
      if [[ "$lookup_id" =~ [^0-9a-zA-Z] ]]; then
        echo -e "${CYAN}💡 Tip: Remove any special characters or spaces${RESET}"
      fi
    fi
    echo
  done
  
  # STANDARDIZED: Perform lookup with detailed feedback
  echo
  echo -e "${CYAN}🔍 Looking up station ID: $lookup_id${RESET}"
  echo -e "${CYAN}💡 Searching local database for matching station...${RESET}"
  
  # Call the actual lookup function and provide enhanced feedback
  if reverse_station_lookup "$lookup_id"; then
    echo
    echo -e "${BOLD}${CYAN}=== Lookup Complete ===${RESET}"
    echo -e "${GREEN}✅ Station information retrieved successfully${RESET}"
    echo -e "${CYAN}💡 Station ID $lookup_id found in your local database${RESET}"
  else
    echo
    echo -e "${BOLD}${CYAN}=== Lookup Complete ===${RESET}"
    echo -e "${YELLOW}⚠️  Station ID $lookup_id not found in database${RESET}"
    echo
    echo -e "${BOLD}${CYAN}Troubleshooting Suggestions:${RESET}"
    echo -e "${CYAN}💡 Verify the station ID is correct (check source where you found it)${RESET}"
    echo -e "${CYAN}💡 Try searching by station name instead using 'Search Local Database'${RESET}"
    echo -e "${CYAN}💡 Station may not be in your current database coverage${RESET}"
    
    # Show what's available in the database for context
    echo -e "${CYAN}💡 Your database contains $total_count stations total${RESET}"
    
    # Suggest similar station IDs if database is available
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -eq 0 ]; then
      local similar_ids=$(jq -r --arg partial "$lookup_id" \
        '.[] | select(.stationId | tostring | contains($partial)) | .stationId' \
        "$stations_file" 2>/dev/null | head -5)
      
      if [[ -n "$similar_ids" ]]; then
        echo
        echo -e "${YELLOW}💡 Similar station IDs found in your database:${RESET}"
        while read -r similar_id; do
          if [[ -n "$similar_id" ]]; then
            local similar_name=$(jq -r --arg id "$similar_id" \
              '.[] | select(.stationId == $id) | .name // "Unknown"' \
              "$stations_file" 2>/dev/null)
            echo -e "${CYAN}  • $similar_id${RESET} - $similar_name"
          fi
        done <<< "$similar_ids"
      fi
    fi
    
    echo
    echo -e "${BOLD}${CYAN}Alternative Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Try a different station ID"
    echo -e "${GREEN}2)${RESET} Use 'Search Local Database' to browse available stations"
    echo -e "${GREEN}3)${RESET} Add more markets via 'Manage Television Markets' for broader coverage"
    echo -e "${GREEN}4)${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "${CYAN}🔄 Starting new station ID lookup...${RESET}"
        echo
        reverse_station_id_lookup_menu  # Recursive call for new lookup
        return $?
        ;;
      2)
        echo -e "${CYAN}🔄 Opening Local Database Search...${RESET}"
        pause_for_user
        search_local_database
        return 0
        ;;
      3)
        echo -e "${CYAN}🔄 Opening Television Markets management...${RESET}"
        pause_for_user
        manage_markets
        return 0
        ;;
      4|"")
        echo -e "${CYAN}🔄 Returning to main menu${RESET}"
        return 0
        ;;
      *)
        echo -e "${RED}❌ Invalid option${RESET}"
        echo -e "${CYAN}💡 Returning to main menu${RESET}"
        return 0
        ;;
    esac
  fi
  
  # STANDARDIZED: Show next steps after successful lookup
  echo
  echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
  echo -e "${GREEN}• Search for more stations using 'Search Local Database'${RESET}"
  echo -e "${GREEN}• Look up additional station IDs${RESET}"
  echo -e "${GREEN}• Use this station information in Dispatcharr integration${RESET}"
  echo -e "${GREEN}• Export station data via Settings → Export Station Database${RESET}"
  
  pause_for_user
}

# ============================================================================
# DISPATCHARR INTEGRATION FUNCTIONS
# ============================================================================

DISPATCHARR_INTERACTION_COUNT=0

init_dispatcharr_interaction_counter() {
  DISPATCHARR_INTERACTION_COUNT=0
  echo -e "${CYAN}💡 Token refresh: Every $DISPATCHARR_REFRESH_INTERVAL channel interactions${RESET}"
}

increment_dispatcharr_interaction() {
  local operation_description="${1:-channel interaction}"
  
  ((DISPATCHARR_INTERACTION_COUNT++))
  
  # Check if we need to refresh tokens
  if (( DISPATCHARR_INTERACTION_COUNT % DISPATCHARR_REFRESH_INTERVAL == 0 )); then
    echo -e "${CYAN}🔄 Refreshing authentication tokens ($DISPATCHARR_INTERACTION_COUNT $operation_description processed)...${RESET}"
    
    if refresh_dispatcharr_tokens >/dev/null 2>&1; then
      echo -e "${GREEN}✅ Tokens refreshed successfully${RESET}"
    else
      echo -e "${YELLOW}⚠️  Token refresh failed - continuing with existing tokens${RESET}"
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Automatic token refresh failed after $DISPATCHARR_INTERACTION_COUNT interactions" >> "$DISPATCHARR_LOG"
    fi
  fi
}

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
  
  # Increment interaction counter BEFORE the API call
  increment_dispatcharr_interaction "station ID updates"
  
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

configure_dispatcharr_connection() {
  clear
  echo -e "${BOLD}${CYAN}=== Configure Dispatcharr Integration ===${RESET}\n"
  echo -e "${BLUE}📍 Setup Dispatcharr Connection and Authentication${RESET}"
  echo -e "${YELLOW}This configures the connection to your Dispatcharr server for channel management.${RESET}"
  echo
  
  local current_url="${DISPATCHARR_URL:-}"
  local current_enabled="${DISPATCHARR_ENABLED:-false}"
  
  echo -e "${BOLD}${BLUE}Current Configuration:${RESET}"
  echo "  URL: ${current_url:-"Not configured"}"
  echo "  Status: $([ "$current_enabled" = "true" ] && echo -e "${GREEN}Enabled${RESET}" || echo -e "${YELLOW}Disabled${RESET}")"
  echo
  
  # STANDARDIZED: Enable/Disable toggle with clear guidance
  echo -e "${BOLD}Step 1: Integration Mode${RESET}"
  echo -e "${CYAN}💡 Enable to use Dispatcharr features like station ID matching and field population${RESET}"
  echo -e "${CYAN}💡 Disable to skip Dispatcharr integration entirely${RESET}"
  echo
  
  if confirm_action "Enable Dispatcharr Integration?"; then
    DISPATCHARR_ENABLED=true
    echo -e "${GREEN}✅ Dispatcharr Integration enabled${RESET}"
  else
    DISPATCHARR_ENABLED=false
    echo -e "${YELLOW}⚠️  Dispatcharr Integration disabled${RESET}"
    echo -e "${CYAN}💡 You can re-enable this anytime in Settings${RESET}"
    
    # Clear any existing tokens and update config
    rm -f "$CACHE_DIR/dispatcharr_tokens.json" 2>/dev/null
    
    # Update config file
    local temp_config="${CONFIG_FILE}.tmp"
    grep -v -E '^DISPATCHARR_(URL|USERNAME|PASSWORD|ENABLED)=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || true
    {
      echo "DISPATCHARR_URL=\"\""
      echo "DISPATCHARR_USERNAME=\"\""
      echo "DISPATCHARR_PASSWORD=\"\""
      echo "DISPATCHARR_ENABLED=false"
    } >> "$temp_config"
    
    mv "$temp_config" "$CONFIG_FILE"
    echo -e "${GREEN}✅ Configuration saved${RESET}"
    return 0
  fi
  
  # Continue with server configuration
  echo
  echo -e "${BOLD}${BLUE}=== Server Connection Configuration ===${RESET}"
  echo -e "${CYAN}💡 Dispatcharr typically runs on port 9191${RESET}"
  echo -e "${CYAN}💡 Use 'localhost' if Dispatcharr is on the same machine${RESET}"
  echo -e "${CYAN}💡 Use the server's IP address if Dispatcharr is remote${RESET}"
  echo
  
  local ip port
  
  # STANDARDIZED: IP Address validation with comprehensive guidance
  echo -e "${BOLD}Step 2: Server IP Address${RESET}"
  echo -e "${CYAN}💡 Format examples: localhost, 192.168.1.100, 10.0.0.50${RESET}"
  echo -e "${CYAN}💡 For local Dispatcharr: use 'localhost' or '127.0.0.1'${RESET}"
  echo -e "${CYAN}💡 For remote Dispatcharr: use the server's network IP${RESET}"
  echo
  
  while true; do
    read -p "Enter Dispatcharr IP address [default: localhost]: " ip < /dev/tty
    ip=${ip:-localhost}
    
    # STANDARDIZED: Comprehensive IP validation
    if [[ "$ip" == "localhost" ]] || [[ "$ip" == "127.0.0.1" ]]; then
      echo -e "${GREEN}✅ Local server address accepted: $ip${RESET}"
      break
    elif [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      # Additional validation for valid IP ranges
      IFS='.' read -ra IP_PARTS <<< "$ip"
      local valid_ip=true
      for part in "${IP_PARTS[@]}"; do
        if (( part < 0 || part > 255 )); then
          valid_ip=false
          break
        fi
      done
      
      if [[ "$valid_ip" == "true" ]]; then
        echo -e "${GREEN}✅ Network IP address accepted: $ip${RESET}"
        break
      else
        echo -e "${RED}❌ Invalid IP address: Each number must be 0-255${RESET}"
        echo -e "${CYAN}💡 Example valid IPs: 192.168.1.100, 10.0.0.50, 172.16.0.10${RESET}"
      fi
    else
      echo -e "${RED}❌ Invalid IP address format${RESET}"
      echo -e "${CYAN}💡 Use 'localhost' for local server${RESET}"
      echo -e "${CYAN}💡 Use format like: 192.168.1.100 for network server${RESET}"
      echo -e "${CYAN}💡 Check that you entered the IP correctly${RESET}"
    fi
    echo
  done
  
  echo
  
  # STANDARDIZED: Port validation with guidance
  echo -e "${BOLD}Step 3: Server Port${RESET}"
  echo -e "${CYAN}💡 Dispatcharr default port: 9191${RESET}"
  echo -e "${CYAN}💡 Valid range: 1-65535${RESET}"
  echo -e "${CYAN}💡 Check your Dispatcharr configuration if unsure${RESET}"
  echo
  
  while true; do
    read -p "Enter Dispatcharr port [default: 9191]: " port < /dev/tty
    port=${port:-9191}
    
    # STANDARDIZED: Comprehensive port validation
    if [[ "$port" =~ ^[0-9]+$ ]]; then
      if (( port >= 1 && port <= 65535 )); then
        if (( port < 1024 )); then
          echo -e "${YELLOW}⚠️  Port $port is in reserved range (1-1023)${RESET}"
          echo -e "${CYAN}💡 This may require administrator privileges${RESET}"
          if confirm_action "Continue with port $port?"; then
            echo -e "${GREEN}✅ Port accepted: $port${RESET}"
            break
          fi
        else
          echo -e "${GREEN}✅ Port accepted: $port${RESET}"
          break
        fi
      else
        echo -e "${RED}❌ Port out of valid range${RESET}"
        echo -e "${CYAN}💡 Port must be between 1 and 65535${RESET}"
        echo -e "${CYAN}💡 Dispatcharr typically uses 9191${RESET}"
      fi
    else
      echo -e "${RED}❌ Port must be a number${RESET}"
      echo -e "${CYAN}💡 Enter only numeric values (e.g., 9191, 8080, 3000)${RESET}"
    fi
    echo
  done
  
  local url="http://$ip:$port"
  echo
  echo -e "${GREEN}✅ Server configuration: $url${RESET}"
  
  # STANDARDIZED: Credential collection with validation
  echo
  echo -e "${BOLD}${BLUE}=== Authentication Configuration ===${RESET}"
  echo -e "${CYAN}💡 Use your Dispatcharr login credentials${RESET}"
  echo -e "${CYAN}💡 These will be used to generate secure API tokens${RESET}"
  echo -e "${CYAN}💡 Credentials are stored locally and used only for token generation${RESET}"
  echo
  
  local username password
  
  echo -e "${BOLD}Step 4: Username${RESET}"
  echo -e "${CYAN}💡 Enter your Dispatcharr username (case-sensitive)${RESET}"
  
  while true; do
    read -p "Username: " username < /dev/tty
    
    if [[ -n "$username" ]] && [[ ! "$username" =~ ^[[:space:]]*$ ]]; then
      # Basic username validation
      if [[ ${#username} -lt 50 ]] && [[ ! "$username" =~ [[:cntrl:]] ]]; then
        echo -e "${GREEN}✅ Username accepted${RESET}"
        break
      else
        echo -e "${RED}❌ Invalid username format${RESET}"
        echo -e "${CYAN}💡 Username should be under 50 characters with no control characters${RESET}"
      fi
    else
      echo -e "${RED}❌ Username cannot be empty${RESET}"
      echo -e "${CYAN}💡 Enter your Dispatcharr login username${RESET}"
    fi
  done
  
  echo
  echo -e "${BOLD}Step 5: Password${RESET}"
  echo -e "${CYAN}💡 Enter your Dispatcharr password (input will be hidden)${RESET}"
  echo -e "${CYAN}💡 Password is used only for initial token generation${RESET}"
  
  while true; do
    read -s -p "Password: " password < /dev/tty
    echo  # Add newline after hidden input
    
    if [[ -n "$password" ]] && [[ ! "$password" =~ ^[[:space:]]*$ ]]; then
      if [[ ${#password} -ge 1 && ${#password} -le 128 ]]; then
        echo -e "${GREEN}✅ Password accepted${RESET}"
        break
      else
        echo -e "${RED}❌ Password length invalid${RESET}"
        echo -e "${CYAN}💡 Password should be 1-128 characters${RESET}"
      fi
    else
      echo -e "${RED}❌ Password cannot be empty${RESET}"
      echo -e "${CYAN}💡 Enter your Dispatcharr login password${RESET}"
    fi
  done
  
  # STANDARDIZED: Connection testing with detailed feedback
  echo
  echo -e "${BOLD}${BLUE}=== Connection and Authentication Testing ===${RESET}"
  echo -e "${CYAN}🔗 Testing connection to Dispatcharr server...${RESET}"
  
  # Test basic connectivity first
  if ! curl -s --connect-timeout 10 --max-time 15 "$url" >/dev/null 2>&1; then
    echo -e "${RED}❌ Connection Test: Cannot reach Dispatcharr server${RESET}"
    echo -e "${CYAN}💡 Server: $url${RESET}"
    echo -e "${CYAN}💡 Common issues:${RESET}"
    echo -e "${CYAN}  • Dispatcharr server is not running${RESET}"
    echo -e "${CYAN}  • Wrong IP address or port${RESET}"
    echo -e "${CYAN}  • Firewall blocking connection${RESET}"
    echo -e "${CYAN}  • Network connectivity issues${RESET}"
    echo
    
    echo -e "${BOLD}${YELLOW}Connection Failed - What would you like to do?${RESET}"
    echo -e "${GREEN}1)${RESET} Save settings anyway (test connection later)"
    echo -e "${GREEN}2)${RESET} Try different server settings"
    echo -e "${GREEN}3)${RESET} Cancel Dispatcharr configuration"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "${YELLOW}⚠️  Saving settings with failed connection test${RESET}"
        echo -e "${CYAN}💡 Connection will be tested again when Dispatcharr features are used${RESET}"
        ;;
      2)
        echo -e "${CYAN}🔄 Restarting server configuration...${RESET}"
        pause_for_user
        configure_dispatcharr_connection  # Recursive call to restart
        return $?
        ;;
      3|"")
        echo -e "${YELLOW}⚠️  Dispatcharr configuration cancelled${RESET}"
        DISPATCHARR_ENABLED=false
        DISPATCHARR_URL=""
        DISPATCHARR_USERNAME=""
        DISPATCHARR_PASSWORD=""
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option${RESET}"
        echo -e "${YELLOW}⚠️  Defaulting to cancel configuration${RESET}"
        DISPATCHARR_ENABLED=false
        return 1
        ;;
    esac
  else
    echo -e "${GREEN}✅ Server connection successful${RESET}"
  fi
  
  # STANDARDIZED: JWT token generation with comprehensive error handling
  echo -e "${CYAN}🔑 Generating authentication tokens...${RESET}"
  
  DISPATCHARR_URL="$url"
  DISPATCHARR_USERNAME="$username"
  DISPATCHARR_PASSWORD="$password"
  
  # Get JWT tokens with detailed error handling
  local token_response
  token_response=$(curl -s --connect-timeout 10 --max-time 20 \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$username\",\"password\":\"$password\"}" \
    "${url}/api/accounts/token/" 2>/dev/null)
  local curl_exit_code=$?
  
  if [[ $curl_exit_code -ne 0 ]]; then
    echo -e "${RED}❌ Token Generation: Connection failed during authentication${RESET}"
    echo -e "${CYAN}💡 Server may be slow or experiencing issues${RESET}"
    echo -e "${CYAN}💡 Check server status and try again${RESET}"
    
    if ! confirm_action "Save configuration anyway?"; then
      echo -e "${YELLOW}⚠️  Dispatcharr configuration cancelled${RESET}"
      return 1
    fi
  elif echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
    # STANDARDIZED: Successful token generation
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    echo "$token_response" > "$token_file"
    
    # Extract tokens for display
    local access_token=$(echo "$token_response" | jq -r '.access')
    local refresh_token=$(echo "$token_response" | jq -r '.refresh')
    
    echo -e "${GREEN}✅ Authentication successful!${RESET}"
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
    
    # STANDARDIZED: Test API access
    echo -e "${CYAN}🔍 Testing API access with new tokens...${RESET}"
    if curl -s --connect-timeout 5 \
      -H "Authorization: Bearer $access_token" \
      "${url}/api/channels/channels/" >/dev/null 2>&1; then
      echo -e "${GREEN}✅ API access confirmed - Dispatcharr integration ready${RESET}"
    else
      echo -e "${YELLOW}⚠️  API test inconclusive, but tokens were generated${RESET}"
      echo -e "${CYAN}💡 Integration should work - test with actual Dispatcharr features${RESET}"
    fi
    
  else
    # STANDARDIZED: Authentication failure handling
    echo -e "${RED}❌ Authentication Failed: Invalid credentials${RESET}"
    echo
    
    # Analyze the response for better error messaging
    if echo "$token_response" | grep -q "non_field_errors"; then
      echo -e "${CYAN}💡 Username or password is incorrect${RESET}"
    elif echo "$token_response" | grep -q "username"; then
      echo -e "${CYAN}💡 Username format issue${RESET}"
    elif echo "$token_response" | grep -q "password"; then
      echo -e "${CYAN}💡 Password format issue${RESET}"
    else
      echo -e "${CYAN}💡 Dispatcharr rejected the login attempt${RESET}"
    fi
    
    echo -e "${CYAN}💡 Verify your Dispatcharr login credentials${RESET}"
    echo -e "${CYAN}💡 Make sure you can log into Dispatcharr web interface${RESET}"
    echo
    echo "Server response: $token_response"
    echo
    
    echo -e "${BOLD}${YELLOW}Authentication Failed - What would you like to do?${RESET}"
    echo -e "${GREEN}1)${RESET} Try different credentials"
    echo -e "${GREEN}2)${RESET} Save configuration anyway (fix credentials later)"
    echo -e "${GREEN}3)${RESET} Cancel Dispatcharr configuration"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      1)
        echo -e "${CYAN}🔄 Restarting credential setup...${RESET}"
        echo
        # Restart from authentication step (recursive)
        configure_dispatcharr_connection
        return $?
        ;;
      2)
        echo -e "${YELLOW}⚠️  Saving configuration with failed authentication${RESET}"
        echo -e "${CYAN}💡 Fix credentials later in Settings → Dispatcharr Integration${RESET}"
        ;;
      3|"")
        echo -e "${YELLOW}⚠️  Dispatcharr configuration cancelled${RESET}"
        DISPATCHARR_ENABLED=false
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option${RESET}"
        echo -e "${YELLOW}⚠️  Defaulting to save anyway${RESET}"
        ;;
    esac
  fi

  # Token Refresh Setting
  echo
  echo -e "${BOLD}${BLUE}=== Token Refresh Configuration ===${RESET}"
  echo -e "${CYAN}💡 Configure automatic token refresh during long operations${RESET}"
  echo -e "${CYAN}💡 Tokens automatically refresh every N channel interactions${RESET}"
  echo -e "${CYAN}💡 This prevents timeout during long channel processing sessions${RESET}"
  echo

  echo -e "${BOLD}Step 6: Token Refresh Interval${RESET}"
  echo -e "${CYAN}💡 Current setting: Every $DISPATCHARR_REFRESH_INTERVAL channel interactions${RESET}"
  echo -e "${CYAN}💡 Recommended: 20-30 interactions (keeps tokens fresh without being intrusive)${RESET}"
  echo -e "${CYAN}💡 Lower numbers = more frequent refresh, higher numbers = less frequent${RESET}"
  echo

  local refresh_interval
  while true; do
    read -p "Enter refresh interval [current: $DISPATCHARR_REFRESH_INTERVAL]: " refresh_interval < /dev/tty
    refresh_interval=${refresh_interval:-$DISPATCHARR_REFRESH_INTERVAL}
    
    if [[ "$refresh_interval" =~ ^[0-9]+$ ]]; then
      if (( refresh_interval >= 5 && refresh_interval <= 100 )); then
        DISPATCHARR_REFRESH_INTERVAL="$refresh_interval"
        echo -e "${GREEN}✅ Refresh interval set: Every $refresh_interval channel interactions${RESET}"
        break
      else
        echo -e "${RED}❌ Interval out of range${RESET}"
        echo -e "${CYAN}💡 Please enter a number between 5 and 100${RESET}"
      fi
    else
      echo -e "${RED}❌ Invalid number format${RESET}"
      echo -e "${CYAN}💡 Enter a whole number (e.g., 25, 30, 20)${RESET}"
    fi
  done
  
  # STANDARDIZED: Save configuration with feedback
  echo
  echo -e "${CYAN}💾 Saving Dispatcharr configuration...${RESET}"
  
  local temp_config="${CONFIG_FILE}.tmp"
  grep -v -E '^DISPATCHARR_(URL|USERNAME|PASSWORD|ENABLED)=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || true
  {
    echo "DISPATCHARR_URL=\"${DISPATCHARR_URL:-}\""
    echo "DISPATCHARR_USERNAME=\"${DISPATCHARR_USERNAME:-}\""
    echo "DISPATCHARR_PASSWORD=\"${DISPATCHARR_PASSWORD:-}\""
    echo "DISPATCHARR_ENABLED=$DISPATCHARR_ENABLED"
  } >> "$temp_config"
  
  if mv "$temp_config" "$CONFIG_FILE"; then
    echo -e "${GREEN}✅ Configuration saved successfully${RESET}"
  else
    echo -e "${RED}❌ Configuration Save: Failed to save settings${RESET}"
    echo -e "${CYAN}💡 Check file permissions for: $CONFIG_FILE${RESET}"
    rm -f "$temp_config" 2>/dev/null
  fi
  
  # STANDARDIZED: Show final status and next steps
  echo
  echo -e "${BOLD}${GREEN}=== Dispatcharr Integration Summary ===${RESET}"
  echo -e "Status: $([ "$DISPATCHARR_ENABLED" = "true" ] && echo -e "${GREEN}Enabled${RESET}" || echo -e "${YELLOW}Disabled${RESET}")"
  echo -e "Server: ${DISPATCHARR_URL:-"Not configured"}"
  
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    echo
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "${GREEN}• Use 'Dispatcharr Integration' from main menu${RESET}"
    echo -e "${GREEN}• Try 'Scan Channels for Missing Station IDs'${RESET}"
    echo -e "${GREEN}• Use 'Interactive Station ID Matching' for channel setup${RESET}"
    echo -e "${GREEN}• Use 'Populate Other Dispatcharr Fields' for channel enhancement${RESET}"
    
    # Show token management info
    if [[ -f "$CACHE_DIR/dispatcharr_tokens.json" ]]; then
      echo
      echo -e "${BOLD}${BLUE}Token Management:${RESET}"
      echo -e "• Tokens are cached and reused automatically"
      echo -e "• Access tokens refresh automatically when expired"
      echo -e "• View logs: 'View Integration Logs' in Dispatcharr Integration menu"
      echo -e "• Clear tokens: Disable integration or delete cache files"
    fi
  fi
  
  return 0
}

scan_missing_stationids() {
  echo -e "\n${BOLD}Scanning Dispatcharr Channels${RESET}"
  echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
  echo -e "${CYAN}This will analyze your Dispatcharr channels and identify which ones need station ID assignment.${RESET}"
  echo
  
  if ! check_dispatcharr_connection; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${CYAN}📡 Fetching channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${CYAN}🔍 Analyzing channels for missing station IDs...${RESET}"
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Channel Scan ===${RESET}"
    echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
    echo -e "${CYAN}This analyzed your Dispatcharr channels and identified which ones need station ID assignment.${RESET}"
    echo
    echo -e "${BOLD}${GREEN}=== Scan Results ===${RESET}\n"
    echo -e "${GREEN}✅ Excellent! All channels have station IDs assigned!${RESET}"
    echo
    echo -e "${CYAN}📊 Analysis Complete:${RESET}"
    local total_channels=$(echo "$channels_data" | jq 'length' 2>/dev/null || echo "0")
    
    # STANDARDIZED: Results summary table
    printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Analysis Category" "Count"
    echo "----------------------------------------"
    printf "%-25s %s\n" "Total channels scanned:" "${CYAN}$total_channels${RESET}"
    printf "%-25s %s\n" "Missing station IDs:" "${GREEN}0${RESET}"
    printf "%-25s %s\n" "Channels with IDs:" "${GREEN}$total_channels${RESET}"
    echo
    
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Your Dispatcharr channels are fully configured for station IDs"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance channel data"
    echo -e "• No station ID matching needed at this time"
    echo
    pause_for_user
    return 0
  fi
  
  echo -e "${CYAN}📋 Sorting channels by channel number...${RESET}"
  local sorted_missing_channels
  sorted_missing_channels=$(echo "$missing_channels" | sort -t$'\t' -k4 -n)
  
  # Convert to array for pagination
  mapfile -t missing_array <<< "$sorted_missing_channels"
  local total_missing=${#missing_array[@]}
  
  # Paginated display with enhanced formatting
  local offset=0
  local results_per_page=10
  
  while (( offset < total_missing )); do
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Channel Scan ===${RESET}"
    echo -e "${BLUE}📍 Step 1 of 3: Identify Channels Needing Station IDs${RESET}"
    echo -e "${CYAN}This analyzed your Dispatcharr channels and identified which ones need station ID assignment.${RESET}"
    echo
    echo -e "${BOLD}${GREEN}=== Scan Results ===${RESET}"
    echo -e "${GREEN}✅ Scan completed: $total_missing channels need station IDs${RESET}"
    echo -e "${CYAN}💡 Channels are sorted by number for easy navigation${RESET}"
    echo
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + results_per_page < total_missing ? offset + results_per_page : total_missing))
    local current_page=$(( (offset / results_per_page) + 1 ))
    local total_pages=$(( (total_missing + results_per_page - 1) / results_per_page ))
    
    echo -e "${BOLD}Showing results $start_num-$end_num of $total_missing (Page $current_page of $total_pages)${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with consistent formatting
    printf "${BOLD}${YELLOW}%-3s %-8s %-30s %-15s %-8s %s${RESET}\n" "Key" "Ch ID" "Channel Name" "Group" "Number" "Status"
    echo "--------------------------------------------------------------------------------"
    
    # Display results with letter keys and enhanced formatting
    local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
    local result_count=0
    
    for ((i = offset; i < offset + results_per_page && i < total_missing; i++)); do
      IFS=$'\t' read -r id name group number <<< "${missing_array[$i]}"
      
      local key="${key_letters[$result_count]}"
      
      # STANDARDIZED: Table row formatting with consistent patterns
      printf "${GREEN}%-3s${RESET} " "${key})"
      printf "%-8s %-30s %-15s %-8s " "$id" "${name:0:30}" "${group:0:15}" "$number"
      echo -e "${RED}Missing${RESET}"
      
      ((result_count++))
    done
    
    echo
    echo -e "${BOLD}Navigation Options:${RESET}"
    [[ $current_page -lt $total_pages ]] && echo -e "${GREEN}n)${RESET} Next page"
    [[ $current_page -gt 1 ]] && echo -e "${GREEN}p)${RESET} Previous page"
    echo -e "${GREEN}m)${RESET} Go to Interactive Station ID Matching"
    echo -e "${GREEN}q)${RESET} Back to Dispatcharr Integration menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case "$choice" in
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          offset=$((offset + results_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          offset=$((offset - results_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
          sleep 1
        fi
        ;;
      m|M)
        echo -e "${CYAN}🔄 Starting Interactive Station ID Matching...${RESET}"
        sleep 1
        interactive_stationid_matching "skip_intro"
        return 0
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        ;;
    esac
  done
  
  echo
  echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
  echo -e "• Use 'Interactive Station ID Matching' to assign station IDs"
  echo -e "• Each channel will be matched against your Local Database Search"
  echo -e "• Choose immediate apply or batch mode for changes"
  echo -e "${GREEN}💡 Tip: Start with a few channels to test the workflow${RESET}"
  
  return 0
}

interactive_stationid_matching() {
  local skip_intro="${1:-}"  # Optional parameter to skip intro pause
  
  if ! check_dispatcharr_connection; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  echo -e "${BLUE}📍 Step 2 of 3: Interactive Station ID Assignment${RESET}"
  echo -e "${CYAN}This workflow will guide you through matching Dispatcharr channels with stations from your Local Database Search.${RESET}"
  echo
  
  echo -e "${CYAN}📡 Fetching channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    echo -e "${GREEN}✅ All channels have station IDs assigned!${RESET}"
    echo -e "${CYAN}💡 Use 'Populate Other Dispatcharr Fields' to enhance channel data${RESET}"
    pause_for_user
    return 0
  fi
  
  # Clear previous matches file
  > "$DISPATCHARR_MATCHES"
  
  # Convert to array
  mapfile -t missing_array <<< "$missing_channels"
  local total_missing=${#missing_array[@]}
  
  echo -e "${GREEN}✅ Found $total_missing channels needing station IDs${RESET}"
  
  # USER CHOICE: Immediate or Batch Mode
  echo
  echo -e "${BOLD}${BLUE}=== Station ID Application Mode ===${RESET}"
  echo -e "${YELLOW}How would you like to apply station ID matches to Dispatcharr?${RESET}"
  echo
  echo -e "${GREEN}1) Immediate Mode${RESET} - Apply each match as you make it"
  echo -e "   ${CYAN}✓ Changes take effect immediately in Dispatcharr${RESET}"
  echo -e "   ${CYAN}✓ No separate commit step needed${RESET}"
  echo -e "   ${CYAN}✓ Can see results in Dispatcharr right away${RESET}"
  echo -e "   ${YELLOW}⚠️  Cannot undo individual changes${RESET}"
  echo
  echo -e "${GREEN}2) Batch Mode${RESET} - Queue matches for review and batch commit"
  echo -e "   ${CYAN}✓ Review all matches before applying to Dispatcharr${RESET}"
  echo -e "   ${CYAN}✓ Apply all changes at once${RESET}"
  echo -e "   ${CYAN}✓ Can cancel or modify before commit${RESET}"
  echo -e "   ${YELLOW}⚠️  Changes don't appear in Dispatcharr until commit${RESET}"
  echo
  
  local apply_mode=""
  while [[ -z "$apply_mode" ]]; do
    read -p "Select mode (1=immediate, 2=batch): " mode_choice
    case "$mode_choice" in
      1) apply_mode="immediate" ;;
      2) apply_mode="batch" ;;
      *) echo -e "${RED}❌ Please enter 1 or 2${RESET}" ;;
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
    echo -e "${CYAN}🔄 Starting interactive matching process...${RESET}"
    pause_for_user
  else
    echo -e "${CYAN}🔄 Ready to start matching process...${RESET}"
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
        echo -e "${CYAN}💡 Searching with cleaned name and auto-detected filters...${RESET}"
        echo
      fi
      
      # Use clean name for initial search
      local search_term="$clean_name"
      local current_page=1
      
      # Search and display loop
      while true; do
        echo -e "${CYAN}🔍 Searching for: '$search_term' (Page $current_page)${RESET}"
        
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
          echo -e "${YELLOW}⚠️  No results found for '$search_term'${RESET}"
          if [[ -n "$detected_country" ]] || [[ -n "$detected_resolution" ]]; then
            echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
          fi
        else
          echo -e "${GREEN}✅ Found $total_results total results${RESET}"
          echo
          
          # Enhanced table header with FIXED selection highlighting
          printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
          echo "--------------------------------------------------------------------------------"
          
          local station_array=()
          local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
          local result_count=0
          
          # Process TSV results with FIXED selection highlighting
          while IFS=$'\t' read -r station_id name call_sign country; do
            [[ -z "$station_id" ]] && continue
            
            # Get additional station info for better display
            local quality=$(get_station_quality "$station_id")
            
            local key="${key_letters[$result_count]}"
            
            # Format table row with CONSISTENT selection highlighting
            printf "${GREEN}%-3s${RESET} " "${key})"
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
                echo -e "${BOLD}Confirm Station ID Assignment:${RESET}"
                echo -e "Channel: ${YELLOW}$channel_name${RESET}"
                echo -e "Station: ${GREEN}$sel_name${RESET} (${CYAN}$sel_station_id${RESET})"
                echo -e "Call Sign: ${GREEN}$sel_call${RESET}"
                echo -e "Country: ${GREEN}$sel_country${RESET}"
                echo -e "Quality: ${GREEN}$sel_quality${RESET}"
                echo
                
                # APPLY MODE LOGIC: Immediate vs Batch
                if [[ "$apply_mode" == "immediate" ]]; then
                  if confirm_action "Apply this station ID immediately to Dispatcharr?"; then
                    echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
                    if update_dispatcharr_channel_epg "$channel_id" "$sel_station_id"; then
                      echo -e "${GREEN}✅ Channel updated successfully in Dispatcharr${RESET}"
                      ((immediate_success_count++))
                      # Also record for logging
                      echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    else
                      echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                      ((immediate_failure_count++))
                    fi
                    pause_for_user
                    break 2  # Exit both loops, move to next channel
                  fi
                else
                  if confirm_action "Queue this match for batch commit to Dispatcharr?"; then
                    echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    echo -e "${GREEN}✅ Match queued for batch commit${RESET}"
                    sleep 1
                    break 2  # Exit both loops, move to next channel
                  fi
                fi
              else
                echo -e "${RED}❌ Invalid selection${RESET}"
                sleep 1
              fi
            else
              echo -e "${RED}❌ No results to select from${RESET}"
              sleep 1
            fi
            ;;
          n|N)
            if [[ $current_page -lt $total_pages ]]; then
              ((current_page++))
            else
              echo -e "${YELLOW}⚠️  Already on last page${RESET}"
              sleep 1
            fi
            ;;
          p|P)
            if [[ $current_page -gt 1 ]]; then
              ((current_page--))
            else
              echo -e "${YELLOW}⚠️  Already on first page${RESET}"
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
              echo
              echo -e "${BOLD}Confirm Manual Station ID:${RESET}"
              echo -e "Channel: ${YELLOW}$channel_name${RESET}"
              echo -e "Station ID: ${CYAN}$manual_station_id${RESET} (manual entry)"
              echo
              
              if [[ "$apply_mode" == "immediate" ]]; then
                if confirm_action "Apply manual station ID immediately to Dispatcharr?"; then
                  echo -e "${CYAN}🔄 Updating channel in Dispatcharr...${RESET}"
                  if update_dispatcharr_channel_epg "$channel_id" "$manual_station_id"; then
                    echo -e "${GREEN}✅ Manual station ID applied successfully${RESET}"
                    ((immediate_success_count++))
                    echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                  else
                    echo -e "${RED}❌ Failed to update channel in Dispatcharr${RESET}"
                    ((immediate_failure_count++))
                  fi
                  pause_for_user
                fi
              else
                if confirm_action "Queue manual station ID for batch commit?"; then
                  echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                  echo -e "${GREEN}✅ Manual station ID queued for batch commit${RESET}"
                  sleep 1
                fi
              fi
              break 2  # Exit both loops, move to next channel
            fi
            ;;
          k|K)
            echo -e "${YELLOW}⚠️  Skipped: $channel_name${RESET}"
            sleep 1
            break 2  # Exit both loops, move to next channel
            ;;
          q|Q)
            echo -e "${CYAN}🔄 Ending matching session...${RESET}"
            # Check for pending matches or show immediate results
            if [[ "$apply_mode" == "immediate" ]]; then
              show_immediate_results "$immediate_success_count" "$immediate_failure_count"
            else
              check_and_offer_commit
            fi
            return 0
            ;;
          *)
            echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
            sleep 1
            ;;
        esac
      done
    done
  done
  
  echo -e "\n${GREEN}✅ Matching session completed${RESET}"
  
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

batch_update_stationids() {
  echo -e "\n${BOLD}${BLUE}📍 Step 3 of 3: Commit Station ID Changes${RESET}"
  echo -e "${CYAN}This will apply all queued station ID matches to your Dispatcharr channels.${RESET}"
  echo
  
  if [[ ! -f "$DISPATCHARR_MATCHES" ]] || [[ ! -s "$DISPATCHARR_MATCHES" ]]; then
    echo -e "${YELLOW}⚠️  No pending station ID matches found${RESET}"
    echo -e "${CYAN}💡 Run 'Interactive Station ID Matching' first to create matches${RESET}"
    echo -e "${CYAN}💡 Ensure you selected 'Batch Mode' during the matching process${RESET}"
    return 1
  fi
  
  local total_matches
  total_matches=$(wc -l < "$DISPATCHARR_MATCHES")
  
  echo -e "${GREEN}✅ Found $total_matches pending station ID matches${RESET}"
  echo
  
  # Show enhanced preview of matches with better formatting
  echo -e "${BOLD}${CYAN}=== Pending Station ID Matches ===${RESET}"
  echo -e "${YELLOW}Preview of changes that will be applied to Dispatcharr:${RESET}"
  echo
  printf "${BOLD}${YELLOW}%-8s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Channel Name" "Station ID" "Station Name" "Quality"
  echo "--------------------------------------------------------------------------------"
  
  local line_count=0
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Get quality info for the station
    local quality=$(get_station_quality "$station_id")
    
    # Format row with proper alignment
    printf "%-8s %-25s " "$channel_id" "${channel_name:0:25}"
    echo -n -e "${CYAN}${station_id}${RESET}"
    printf "%*s" $((12 - ${#station_id})) ""
    printf "%-20s " "${station_name:0:20}"
    echo -e "${GREEN}${quality}${RESET}"
    
    ((line_count++))
    # Show only first 10 for preview
    [[ $line_count -ge 10 ]] && break
  done < "$DISPATCHARR_MATCHES"
  
  if [[ $total_matches -gt 10 ]]; then
    echo -e "${CYAN}... and $((total_matches - 10)) more matches${RESET}"
  fi
  echo
  
  echo -e "${BOLD}Confirmation Required:${RESET}"
  echo -e "Total matches to apply: ${YELLOW}$total_matches${RESET}"
  echo -e "Target: ${CYAN}Dispatcharr at $DISPATCHARR_URL${RESET}"
  echo -e "Action: ${GREEN}Set station IDs for channel EPG matching${RESET}"
  echo
  
  if ! confirm_action "Apply all $total_matches station ID matches to Dispatcharr?"; then
    echo -e "${YELLOW}⚠️  Batch update cancelled${RESET}"
    echo -e "${CYAN}💡 Matches remain queued - you can commit them later${RESET}"
    return 1
  fi
  
  local success_count=0
  local failure_count=0
  local current_item=0
  
  echo -e "\n${BOLD}${CYAN}=== Applying Station ID Updates ===${RESET}"
  echo -e "${CYAN}🔄 Processing $total_matches updates to Dispatcharr...${RESET}"
  echo
  
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    ((current_item++))
    local percent=$((current_item * 100 / total_matches))
    
    # Show progress with channel info
    printf "\r${CYAN}[%3d%%] (%d/%d) Updating: %-25s → %-12s${RESET}" \
      "$percent" "$current_item" "$total_matches" "${channel_name:0:25}" "$station_id"
    
    if update_dispatcharr_channel_epg "$channel_id" "$station_id"; then
      ((success_count++))
    else
      ((failure_count++))
      echo -e "\n${RED}❌ Failed: $channel_name (ID: $channel_id)${RESET}"
    fi
  done < "$DISPATCHARR_MATCHES"
  
  # Clear progress line
  echo
  echo
  
  # Show comprehensive completion summary
  echo -e "${BOLD}${GREEN}=== Batch Update Results ===${RESET}"
  echo -e "${GREEN}✅ Successfully applied: $success_count station IDs${RESET}"
  
  if [[ $failure_count -gt 0 ]]; then
    echo -e "${RED}❌ Failed to apply: $failure_count station IDs${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr logs for failed update details${RESET}"
  fi
  
  echo -e "${CYAN}📊 Total processed: $((success_count + failure_count)) of $total_matches${RESET}"
  echo
  
  if [[ $success_count -gt 0 ]]; then
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• Changes are now active in Dispatcharr"
    echo -e "• Channels will use station IDs for EPG matching"
    echo -e "• Consider using 'Populate Other Dispatcharr Fields' to enhance remaining data"
    
    if [[ $failure_count -eq 0 ]]; then
      echo -e "${GREEN}💡 Perfect! All station IDs applied successfully${RESET}"
    fi
  fi
  
  # Clear processed matches
  echo
  echo -e "${CYAN}🧹 Clearing processed matches from queue...${RESET}"
  > "$DISPATCHARR_MATCHES"
  echo -e "${GREEN}✅ Match queue cleared${RESET}"
  
  return 0
}

populate_dispatcharr_fields() {
  if ! check_dispatcharr_connection; then
    echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
    echo -e "${CYAN}💡 Configure connection in Settings → Dispatcharr Integration${RESET}"
    echo -e "${CYAN}💡 Verify server is running and credentials are correct${RESET}"
    pause_for_user
    return 1
  fi
  
  if ! has_stations_database; then
    echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
    echo -e "${CYAN}💡 Base Station Database: Add $(basename "$BASE_STATIONS_JSON") to script directory${RESET}"
    echo -e "${CYAN}💡 User Station Database: Use 'Manage Television Markets' → 'Run User Caching'${RESET}"
    pause_for_user
    return 1
  fi
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Other Dispatcharr Fields ===${RESET}\n"
  echo -e "${BLUE}📍 Step 2 of 3: Enhance Dispatcharr Channel Data${RESET}"
  echo -e "${YELLOW}This workflow enhances your Dispatcharr channels with comprehensive station information.${RESET}"
  echo
  
  echo -e "${BOLD}How It Works:${RESET}"
  echo -e "${CYAN}1. Select channels to process (all, filtered, specific, or automatic)${RESET}"
  echo -e "${CYAN}2. For each channel, match against your Local Database${RESET}"
  echo -e "${CYAN}3. Review proposed field updates and select which to apply${RESET}"
  echo -e "${CYAN}4. Changes are applied immediately to Dispatcharr${RESET}"
  echo
  
  echo -e "${BOLD}Fields that can be populated:${RESET}"
  echo -e "${GREEN}• Channel Name${RESET} - Improve channel identification with official station names"
  echo -e "${GREEN}• TVG-ID${RESET} - Set to station call sign for proper EPG matching in certain software"
  echo -e "${GREEN}• Channel Logo${RESET} - Upload and assign official station logos"
  echo
  
  echo -e "${CYAN}💡 Channels with existing station IDs are automatically matched${RESET}"
  echo -e "${CYAN}💡 Each field update is optional - you choose what to apply${RESET}"
  echo
  
  echo -e "${CYAN}📡 Fetching all channels from Dispatcharr...${RESET}"
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}❌ Failed to retrieve channels from Dispatcharr${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and try again${RESET}"
    pause_for_user
    return 1
  fi
  
  local total_channels=$(echo "$channels_data" | jq 'length')
  echo -e "${GREEN}✅ Retrieved $total_channels channels from Dispatcharr${RESET}"
  echo
  
  # Enhanced channel selection mode with Mode 4
  echo -e "${BOLD}${BLUE}=== Channel Processing Mode ===${RESET}"
  echo -e "${YELLOW}Which channels would you like to process?${RESET}"
  echo
  echo -e "${GREEN}1) Process All Channels${RESET} - Work through every channel systematically"
  echo -e "   ${CYAN}✓ Comprehensive coverage of all channels${RESET}"
  echo -e "   ${CYAN}✓ Sorted by channel ID for logical progression${RESET}"
  echo -e "   ${CYAN}✓ Auto-matches channels with existing station IDs${RESET}"
  echo -e "   ${YELLOW}⚠️  May take time with many channels${RESET}"
  echo
  echo -e "${GREEN}2) Process Channels Missing Specific Fields${RESET} - Target channels needing data"
  echo -e "   ${CYAN}✓ Focus on channels that need improvement${RESET}"
  echo -e "   ${CYAN}✓ Choose which missing fields to target${RESET}"
  echo -e "   ${CYAN}✓ More efficient for large channel lists${RESET}"
  echo -e "   ${CYAN}✓ Auto-matches channels with existing station IDs${RESET}"
  echo
  echo -e "${GREEN}3) Process Specific Channel${RESET} - Work on one particular channel"
  echo -e "   ${CYAN}✓ Perfect for testing or fixing specific issues${RESET}"
  echo -e "   ${CYAN}✓ Quick single-channel enhancement${RESET}"
  echo -e "   ${CYAN}✓ Auto-matches if channel has existing station ID${RESET}"
  echo
  echo -e "${GREEN}4) Automatic Complete Data Replacement${RESET} - Mass update channels with station IDs"
  echo -e "   ${CYAN}✓ Automatically processes ALL channels that have station IDs${RESET}"
  echo -e "   ${CYAN}✓ Select which fields to update (name, tvg-id, logo)${RESET}"
  echo -e "   ${CYAN}✓ No user interaction required per channel${RESET}"
  echo -e "   ${RED}⚠️  WARNING: Mass replacement of potentially hundreds of channels${RESET}"
  echo
  echo -e "${GREEN}q) Cancel and Return${RESET}"
  echo
  
  read -p "Select channel processing mode: " mode_choice
  
  case "$mode_choice" in
    1) 
      echo -e "${GREEN}✅ Processing all channels in ID order${RESET}"
      process_all_channels_fields "$channels_data" 
      ;;
    2) 
      echo -e "${GREEN}✅ Processing channels with missing fields${RESET}"
      process_channels_missing_fields "$channels_data" 
      ;;
    3) 
      echo -e "${GREEN}✅ Processing specific channel${RESET}"
      process_specific_channel "$channels_data" 
      ;;
    4) 
      echo -e "${GREEN}✅ Starting automatic complete data replacement${RESET}"
      automatic_complete_data_replacement "$channels_data" 
      ;;
    q|Q|"") 
      echo -e "${YELLOW}⚠️  Field population cancelled${RESET}"
      return 0 
      ;;
    *) 
      echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
      sleep 1
      populate_dispatcharr_fields  # Restart the function
      ;;
  esac
}

process_all_channels_fields() {
  local channels_json="$1"
  
  echo -e "\n${BOLD}${CYAN}=== Processing All Channels ===${RESET}"
  echo -e "${CYAN}Organizing channels by channel number for systematic processing...${RESET}"
  
  # Sort channels by .channel_number (lowest to highest) - explicit numeric sort
  local sorted_channels
  sorted_channels=$(echo "$channels_json" | jq -c '.[] | select(.id != null)' | jq -s 'sort_by(.channel_number | tonumber)' | jq -c '.[]')
  
  if [[ -z "$sorted_channels" ]]; then
    echo -e "${RED}❌ No channels with valid IDs found${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr channel configuration${RESET}"
    pause_for_user
    return 1
  fi
  
  mapfile -t channels_array <<< "$sorted_channels"
  local total_channels=${#channels_array[@]}
  
  echo -e "${GREEN}✅ Processing $total_channels channels in channel number order${RESET}"
  echo
  
  # Always show starting point options
  local start_index=0
  
  # Check if there's valid resume state
  if [[ -n "$LAST_PROCESSED_CHANNEL_NUMBER" && -n "$LAST_PROCESSED_CHANNEL_INDEX" ]]; then
    # 3 OPTIONS: Resume state available
    echo -e "${BOLD}${YELLOW}=== Choose Starting Point ===${RESET}"
    echo -e "${CYAN}Previous session data found:${RESET}"
    echo -e "Last processed channel: ${GREEN}#$LAST_PROCESSED_CHANNEL_NUMBER${RESET}"
    echo -e "Progress: ${CYAN}$((LAST_PROCESSED_CHANNEL_INDEX + 1)) of $total_channels channels${RESET}"
    echo
    
    echo -e "${BOLD}${BLUE}Starting Point Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Resume from last processed channel (#$LAST_PROCESSED_CHANNEL_NUMBER)"
    echo -e "${GREEN}2)${RESET} Start from beginning (channel 1)"
    echo -e "${GREEN}3)${RESET} Start from specific channel number"
    echo -e "${GREEN}q)${RESET} Cancel and return"
    echo
    
    local start_choice
    while true; do
      read -p "Select starting point: " start_choice < /dev/tty
      
      case "$start_choice" in
        1)
          # Resume from next channel after last processed
          start_index=$((LAST_PROCESSED_CHANNEL_INDEX + 1))
          if [ "$start_index" -ge "$total_channels" ]; then
            echo -e "${YELLOW}⚠️  All channels have been processed${RESET}"
            echo -e "${CYAN}💡 Starting from beginning instead${RESET}"
            start_index=0
            clear_resume_state
          else
            echo -e "${GREEN}✅ Resuming from channel $((start_index + 1))${RESET}"
          fi
          break
          ;;
        2)
          start_index=0
          echo -e "${GREEN}✅ Starting from beginning${RESET}"
          clear_resume_state
          break
          ;;
        3)
          echo
          read -p "Enter channel number to start from: " custom_channel < /dev/tty
          
          if [[ "$custom_channel" =~ ^[0-9]+$ ]]; then
            # Find index for this channel number
            local found_index=-1
            for ((idx = 0; idx < total_channels; idx++)); do
              local channel_data="${channels_array[$idx]}"
              local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "0"')
              if [[ "$channel_number" == "$custom_channel" ]]; then
                found_index=$idx
                break
              fi
            done
            
            if [ "$found_index" -ge 0 ]; then
              start_index=$found_index
              echo -e "${GREEN}✅ Starting from channel #$custom_channel${RESET}"
              clear_resume_state
              break
            else
              echo -e "${RED}❌ Channel #$custom_channel not found${RESET}"
              echo -e "${CYAN}💡 Try a different channel number${RESET}"
            fi
          else
            echo -e "${RED}❌ Invalid channel number${RESET}"
          fi
          ;;
        q|Q|"")
          echo -e "${YELLOW}⚠️  Field population cancelled${RESET}"
          return 0
          ;;
        *)
          echo -e "${RED}❌ Invalid option. Please enter 1, 2, 3, or q${RESET}"
          ;;
      esac
    done
    
  else
    # 2 OPTIONS: No resume state available
    echo -e "${BOLD}${YELLOW}=== Choose Starting Point ===${RESET}"
    echo -e "${CYAN}No previous session data found.${RESET}"
    echo
    
    echo -e "${BOLD}${BLUE}Starting Point Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Start from beginning (channel 1)"
    echo -e "${GREEN}2)${RESET} Start from specific channel number"
    echo -e "${GREEN}q)${RESET} Cancel and return"
    echo
    
    local start_choice
    while true; do
      read -p "Select starting point: " start_choice < /dev/tty
      
      case "$start_choice" in
        1)
          start_index=0
          echo -e "${GREEN}✅ Starting from beginning${RESET}"
          break
          ;;
        2)
          echo
          read -p "Enter channel number to start from: " custom_channel < /dev/tty
          
          if [[ "$custom_channel" =~ ^[0-9]+$ ]]; then
            # Find index for this channel number
            local found_index=-1
            for ((idx = 0; idx < total_channels; idx++)); do
              local channel_data="${channels_array[$idx]}"
              local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "0"')
              if [[ "$channel_number" == "$custom_channel" ]]; then
                found_index=$idx
                break
              fi
            done
            
            if [ "$found_index" -ge 0 ]; then
              start_index=$found_index
              echo -e "${GREEN}✅ Starting from channel #$custom_channel${RESET}"
              break
            else
              echo -e "${RED}❌ Channel #$custom_channel not found${RESET}"
              echo -e "${CYAN}💡 Try a different channel number${RESET}"
            fi
          else
            echo -e "${RED}❌ Invalid channel number${RESET}"
          fi
          ;;
        q|Q|"")
          echo -e "${YELLOW}⚠️  Field population cancelled${RESET}"
          return 0
          ;;
        *)
          echo -e "${RED}❌ Invalid option. Please enter 1, 2, or q${RESET}"
          ;;
      esac
    done
  fi
  
  echo
  
  # Show processing plan
  if [ "$start_index" -gt 0 ]; then
    echo -e "${CYAN}📊 Processing plan: Starting from channel $((start_index + 1)) of $total_channels${RESET}"
    echo -e "${CYAN}📊 Remaining channels: $((total_channels - start_index))${RESET}"
  else
    echo -e "${CYAN}📊 Processing plan: All $total_channels channels${RESET}"
  fi
  
  echo -e "${CYAN}💡 Processing will continue automatically between channels${RESET}"
  echo
  
  # Show available controls clearly
  echo -e "${BOLD}${BLUE}Available Controls During Processing:${RESET}"
  echo -e "${GREEN}• q${RESET} - Quit entire batch processing (saves resume state)"
  echo -e "${GREEN}• k${RESET} - Skip current channel (continues to next channel)"
  echo -e "${GREEN}• s${RESET} - Search with different term for current channel"
  echo -e "${GREEN}• a-j${RESET} - Select station from search results"
  echo -e "${CYAN}💡 These options will be available during each channel's processing${RESET}"
  echo
  
  # Add initial confirmation for the processing
  local channels_to_process=$((total_channels - start_index))
  if ! confirm_action "Begin processing $channels_to_process channels?"; then
    echo -e "${YELLOW}⚠️  Batch processing cancelled${RESET}"
    return 0
  fi
  
  echo -e "${CYAN}🔄 Starting automated processing...${RESET}"
  echo -e "${YELLOW}💡 Remember: Press 'q' during any channel to stop and save progress${RESET}"
  echo
  
  for ((i = start_index; i < total_channels; i++)); do
    local channel_data="${channels_array[$i]}"
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
    
    echo -e "${BOLD}${BLUE}=== Channel $((i + 1)) of $total_channels (Channel #$channel_number) ===${RESET}"
    
    # Save resume state before processing this channel
    save_resume_state "$channel_number" "$i"
    
    # Process the channel - capture return code to handle user exit
    process_single_channel_fields "$channel_data" $((i + 1)) "$total_channels"
    local process_result=$?
    
    # Check if user chose to quit during processing
    if [[ $process_result -eq 1 ]]; then
      echo -e "\n${YELLOW}⚠️  Processing stopped by user${RESET}"
      echo -e "${CYAN}💡 Progress saved: Completed through channel #$channel_number${RESET}"
      echo -e "${CYAN}💡 Resume anytime by selecting 'Process All Channels' again${RESET}"
      pause_for_user
      return 0
    fi
    
    # Show progress status but no interruption
    if [[ $((i + 1)) -lt $total_channels ]]; then
      echo
      echo -e "${CYAN}✅ Channel #$channel_number completed. Moving to next channel...${RESET}"
      echo -e "${YELLOW}📊 Progress: $((i + 1)) of $total_channels channels processed${RESET}"
      
      # Brief pause for visual feedback, but no user input required
      sleep 1
    fi
  done
  
  # Clear resume state when all channels are completed
  clear_resume_state
  
  echo -e "\n${GREEN}✅ All channels field population workflow complete${RESET}"
  echo -e "${CYAN}💡 Processed $total_channels channels successfully${RESET}"
  echo -e "${CYAN}💡 Changes have been applied to Dispatcharr as selected${RESET}"
  echo -e "${GREEN}💡 Resume state cleared - all channels completed${RESET}"
  pause_for_user
}

save_resume_state() {
  local channel_number="$1"
  local channel_index="$2"
  
  # Update the in-memory variables
  LAST_PROCESSED_CHANNEL_NUMBER="$channel_number"
  LAST_PROCESSED_CHANNEL_INDEX="$channel_index"
  
  # Update config file
  sed -i "s/LAST_PROCESSED_CHANNEL_NUMBER=.*/LAST_PROCESSED_CHANNEL_NUMBER=\"$channel_number\"/" "$CONFIG_FILE"
  sed -i "s/LAST_PROCESSED_CHANNEL_INDEX=.*/LAST_PROCESSED_CHANNEL_INDEX=\"$channel_index\"/" "$CONFIG_FILE"
  
  echo -e "${CYAN}💾 Resume state saved: Channel $channel_number${RESET}" >&2
}

clear_resume_state() {
  # Clear in-memory variables
  LAST_PROCESSED_CHANNEL_NUMBER=""
  LAST_PROCESSED_CHANNEL_INDEX=""
  
  # Clear in config file
  sed -i "s/LAST_PROCESSED_CHANNEL_NUMBER=.*/LAST_PROCESSED_CHANNEL_NUMBER=\"\"/" "$CONFIG_FILE"
  sed -i "s/LAST_PROCESSED_CHANNEL_INDEX=.*/LAST_PROCESSED_CHANNEL_INDEX=\"\"/" "$CONFIG_FILE"
  
  echo -e "${CYAN}💾 Resume state cleared${RESET}" >&2
}

process_channels_missing_fields() {
  local channels_data="$1"
  
  echo -e "\n${BOLD}${CYAN}=== Filter Channels by Missing Fields ===${RESET}"
  echo -e "${YELLOW}Select which type of missing field to target:${RESET}"
  echo
  echo -e "${GREEN}1)${RESET} Missing Channel Names - Empty or generic names like 'Channel 123'"
  echo -e "   ${CYAN}✓ Improves channel identification${RESET}"
  echo -e "   ${CYAN}✓ Replaces generic names with official station names${RESET}"
  echo
  echo -e "${GREEN}2)${RESET} Missing TVG-ID - Empty TVG-ID fields"
  echo -e "   ${CYAN}✓ Enables proper EPG matching${RESET}"
  echo -e "   ${CYAN}✓ Sets call signs for guide data correlation${RESET}"
  echo
  echo -e "${GREEN}3)${RESET} Missing TVC Guide Station ID - Empty station ID fields"
  echo -e "   ${CYAN}✓ Enables comprehensive guide data${RESET}"
  echo -e "   ${CYAN}✓ Links channels to station information${RESET}"
  echo
  echo -e "${GREEN}4)${RESET} Missing Any of the Above - Channels with any missing field"
  echo -e "   ${CYAN}✓ Comprehensive cleanup approach${RESET}"
  echo -e "   ${CYAN}✓ Addresses all field gaps systematically${RESET}"
  echo
  
  read -p "Select filter criteria: " filter_choice
  
  local filtered_channels
  case "$filter_choice" in
    1)
      echo -e "${CYAN}🔍 Filtering for channels with missing or generic names...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.name == "" or .name == null or (.name | test("Channel [0-9]+")))')
      ;;
    2)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVG-ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvg_id == "" or .tvg_id == null)')
      ;;
    3)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVC Guide Station ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid == "" or .tvc_guide_stationid == null)')
      ;;
    4)
      echo -e "${CYAN}🔍 Filtering for channels with any missing fields...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(
        (.name == "" or .name == null or (.name | test("Channel [0-9]+"))) or
        (.tvg_id == "" or .tvg_id == null) or
        (.tvc_guide_stationid == "" or .tvc_guide_stationid == null)
      )')
      ;;
    *)
      echo -e "${RED}❌ Invalid selection${RESET}"
      sleep 1
      return 1
      ;;
  esac
  
  if [[ -z "$filtered_channels" ]]; then
    echo -e "${GREEN}✅ No channels found matching the selected criteria${RESET}"
    echo -e "${CYAN}💡 All channels already have the requested field data${RESET}"
    echo -e "${CYAN}💡 Try a different filter or use 'Process All Channels'${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "${CYAN}📋 Sorting filtered channels by channel number (lowest to highest)...${RESET}"
  
  # Sort filtered channels by .channel_number (lowest to highest) - explicit numeric sort
  local sorted_filtered_channels
  sorted_filtered_channels=$(echo "$filtered_channels" | jq -s 'sort_by(.channel_number | tonumber)')
  
  mapfile -t filtered_array < <(echo "$sorted_filtered_channels" | jq -c '.[]')
  local filtered_count=${#filtered_array[@]}
  
  echo -e "${GREEN}✅ Found $filtered_count channels matching criteria (sorted by channel number)${RESET}"
  echo -e "${CYAN}💡 Processing in channel number order for systematic coverage${RESET}"
  echo
  
  # STANDARDIZED: Show preview of filtered channels with professional table
  if [ "$filtered_count" -gt 0 ]; then
    echo -e "${BOLD}${BLUE}Preview of Filtered Channels:${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with consistent formatting
    printf "${BOLD}${YELLOW}%-6s %-8s %-25s %-15s %-10s %-10s %s${RESET}\n" "Number" "Ch ID" "Channel Name" "Group" "TVG-ID" "Station" "Issues"
    echo "--------------------------------------------------------------------------------"
    
    # Show first 10 channels as preview
    local preview_count=$((filtered_count > 10 ? 10 : filtered_count))
    for ((i = 0; i < preview_count; i++)); do
      local channel_data="${filtered_array[$i]}"
      local channel_id=$(echo "$channel_data" | jq -r '.id')
      local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
      local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
      local channel_group=$(echo "$channel_data" | jq -r '.channel_group_id // "Ungrouped"')
      local tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
      local tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')
      
      # Analyze issues for this channel
      local issues=""
      if [[ -z "$channel_name" || "$channel_name" == "null" || "$channel_name" =~ Channel\ [0-9]+ ]]; then
        issues+="Name "
      fi
      if [[ -z "$tvg_id" || "$tvg_id" == "null" ]]; then
        issues+="TVG "
      fi
      if [[ -z "$tvc_stationid" || "$tvc_stationid" == "null" ]]; then
        issues+="StID "
      fi
      
      # STANDARDIZED: Table row with consistent formatting
      printf "%-6s %-8s %-25s %-15s %-10s %-10s %s\n" \
        "$channel_number" \
        "$channel_id" \
        "${channel_name:0:25}" \
        "${channel_group:0:15}" \
        "${tvg_id:0:10}" \
        "${tvc_stationid:0:10}" \
        "${RED}$issues${RESET}"
    done
    
    if [ "$filtered_count" -gt 10 ]; then
      echo "..."
      echo -e "${CYAN}... and $((filtered_count - 10)) more channels${RESET}"
    fi
    echo
    
    # STANDARDIZED: Summary statistics table
    echo -e "${BOLD}${BLUE}Filter Results Summary:${RESET}"
    printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Statistics" "Count"
    echo "------------------------------------"
    printf "%-25s %s\n" "Total channels matched:" "${GREEN}$filtered_count${RESET}"
    printf "%-25s %s\n" "Filter criteria:" "$(case "$filter_choice" in 1) echo "Missing Names" ;; 2) echo "Missing TVG-ID" ;; 3) echo "Missing Station ID" ;; 4) echo "Any Missing Fields" ;; esac)"
    printf "%-25s %s\n" "Processing order:" "${CYAN}By channel number${RESET}"
    echo
  fi
  
  if ! confirm_action "Process these $filtered_count filtered channels?"; then
    echo -e "${YELLOW}⚠️  Filtered processing cancelled${RESET}"
    return 0
  fi
  
  for ((i = 0; i < filtered_count; i++)); do
    local channel_data="${filtered_array[$i]}"
    
    echo -e "${BOLD}${BLUE}=== Filtered Channel $((i + 1)) of $filtered_count ===${RESET}"
    
    process_single_channel_fields "$channel_data" $((i + 1)) "$filtered_count"
    
    if [[ $((i + 1)) -lt $filtered_count ]]; then
      echo
      echo -e "${BOLD}Continue Processing Filtered Channels?${RESET}"
      echo -e "Completed: $((i + 1)) of $filtered_count filtered channels"
      echo -e "Remaining: $((filtered_count - i - 1)) channels"
      echo
      
      if ! confirm_action "Continue to next filtered channel?"; then
        echo -e "${YELLOW}⚠️  Filtered processing stopped by user${RESET}"
        break
      fi
    fi
  done
  
  echo -e "\n${GREEN}✅ Filtered field population completed${RESET}"
  echo -e "${CYAN}💡 All matching channels have been processed${RESET}"
  pause_for_user
}

process_specific_channel() {
  local channels_data="$1"
  
  # Sort channels by channel number (lowest to highest) and convert to array
  local sorted_channels_array
  sorted_channels_array=$(echo "$channels_data" | jq -c 'sort_by(.channel_number | tonumber)')
  
  # Count total channels correctly
  local total_channels
  total_channels=$(echo "$sorted_channels_array" | jq 'length')
  
  local offset=0
  local channels_per_page=10  # Changed from 20 to 10 to match letter key limit
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Select Specific Channel ===${RESET}"
    echo -e "${CYAN}Browse available channels and select one for field population.${RESET}"
    echo
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + channels_per_page < total_channels ? offset + channels_per_page : total_channels))
    local current_page=$(( (offset / channels_per_page) + 1 ))
    local total_pages=$(( (total_channels + channels_per_page - 1) / channels_per_page ))
    
    echo -e "${BOLD}Available Channels (sorted by channel number, showing $start_num-$end_num of $total_channels)${RESET}"
    echo -e "${CYAN}Page $current_page of $total_pages${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with selection keys
    printf "${BOLD}${YELLOW}%-3s %-8s %-6s %-30s %-15s %s${RESET}\n" "Key" "ID" "Number" "Channel Name" "Group" "TVG-ID"
    echo "--------------------------------------------------------------------------------"
    
    # Show current page of channels with letter keys for selection
    local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
    local page_channels=()
    local row_count=0
    
    # Extract the channels for current page and store them properly
    for ((i = offset; i < offset + channels_per_page && i < total_channels; i++)); do
      local channel_json=$(echo "$sorted_channels_array" | jq -c ".[$i]")
      
      # Extract display info
      local id=$(echo "$channel_json" | jq -r '.id // "N/A"')
      local number=$(echo "$channel_json" | jq -r '.channel_number // "N/A"')
      local name=$(echo "$channel_json" | jq -r '.name // "Unnamed"')
      local group=$(echo "$channel_json" | jq -r '.channel_group_id // "Ungrouped"')
      local tvg_id=$(echo "$channel_json" | jq -r '.tvg_id // "Empty"')
      
      local key="${key_letters[$row_count]}"
      
      # STANDARDIZED: Table row formatting with selection highlighting
      printf "${GREEN}%-3s${RESET} " "${key})"
      printf "%-8s %-6s %-30s %-15s %s\n" "$id" "$number" "${name:0:30}" "${group:0:15}" "${tvg_id:0:10}"
      
      # Store the full channel JSON for selection
      page_channels+=("$channel_json")
      ((row_count++))
    done
    
    echo
    echo -e "${BOLD}${CYAN}Navigation Options:${RESET}"
    if [[ $current_page -lt $total_pages ]]; then
      echo -e "${GREEN}n)${RESET} Next page"
    fi
    if [[ $current_page -gt 1 ]]; then
      echo -e "${GREEN}p)${RESET} Previous page"
    fi
    if [[ $current_page -eq 1 && $total_pages -eq 1 ]]; then
      echo -e "${CYAN}(Single page - all channels shown)${RESET}"
    fi
    echo -e "${GREEN}q)${RESET} Cancel and return"
    echo
    
    echo -e "${BOLD}${CYAN}Channel Selection:${RESET}"
    [[ $row_count -gt 0 ]] && echo -e "${GREEN}a-j)${RESET} Select channel from the list above"
    echo -e "${CYAN}💡 Use the letter keys to select a channel for field population${RESET}"
    echo
    
    read -p "Enter selection: " choice
    
    case "$choice" in
      n|N)
        if [[ $current_page -lt $total_pages ]]; then
          offset=$((offset + channels_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on last page${RESET}"
          sleep 1
        fi
        ;;
      p|P)
        if [[ $current_page -gt 1 ]]; then
          offset=$((offset - channels_per_page))
        else
          echo -e "${YELLOW}⚠️  Already on first page${RESET}"
          sleep 1
        fi
        ;;
      a|A|b|B|c|C|d|D|e|E|f|F|g|G|h|H|i|I|j|J)
        # FIXED: Direct letter selection with proper validation
        if [[ $row_count -gt 0 ]]; then
          local letter_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
          local index=-1
          for ((idx=0; idx<10; idx++)); do
            if [[ "${key_letters[$idx]}" == "$letter_lower" ]]; then
              index=$idx
              break
            fi
          done
          
          if [[ $index -ge 0 ]] && [[ $index -lt $row_count ]]; then
            # Get channel data from our stored page_channels array
            local selected_channel="${page_channels[$index]}"
            
            if [[ -n "$selected_channel" && "$selected_channel" != "null" ]]; then
              local channel_id=$(echo "$selected_channel" | jq -r '.id')
              local channel_name=$(echo "$selected_channel" | jq -r '.name // "Unnamed"')
              local channel_number=$(echo "$selected_channel" | jq -r '.channel_number // "N/A"')
              local channel_group=$(echo "$selected_channel" | jq -r '.channel_group_id // "Ungrouped"')
              
              echo
              echo -e "${BOLD}${GREEN}Selected Channel Details:${RESET}"
              
              # STANDARDIZED: Selection confirmation table
              echo -e "${BOLD}${YELLOW}Field           Value${RESET}"
              echo "--------------------------------"
              echo -e "Channel Name:   ${GREEN}$channel_name${RESET}"
              echo -e "Channel ID:     ${CYAN}$channel_id${RESET}"
              echo -e "Number:         ${CYAN}$channel_number${RESET}"
              echo -e "Group:          ${CYAN}$channel_group${RESET}"
              echo
              
              if confirm_action "Process field population for this channel?"; then
                echo -e "${BOLD}${BLUE}=== Processing Selected Channel ===${RESET}"
                process_single_channel_fields_standalone "$selected_channel"
                local process_result=$?
                
                case $process_result in
                  0)
                    echo -e "\n${GREEN}✅ Channel field population completed${RESET}"
                    echo -e "${CYAN}💡 Changes have been applied to Dispatcharr as selected${RESET}"
                    pause_for_user
                    return 0
                    ;;
                  1)
                    # User chose to return to channel selection - continue the loop
                    continue
                    ;;
                  2)
                    # User chose to return to main menu
                    return 0
                    ;;
                esac
              else
                continue  # Stay in selection mode
              fi
            else
              echo -e "${RED}❌ Could not retrieve channel data${RESET}"
              sleep 1
            fi
          else
            echo -e "${RED}❌ Invalid selection${RESET}"
            sleep 1
          fi
        else
          echo -e "${RED}❌ No channels available for selection${RESET}"
          sleep 1
        fi
        ;;
      ""|q|Q)
        echo -e "${YELLOW}⚠️  Channel selection cancelled${RESET}"
        return 1
        ;;
      *)
        echo -e "${RED}❌ Invalid option: '$choice'${RESET}"
        echo -e "${CYAN}💡 Use letters a-j to select from the displayed channels${RESET}"
        sleep 2
        ;;
    esac
  done
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
  
  # AUTO-MATCHING LOGIC: If station ID exists, use reverse lookup instead of search
  if [[ -n "$current_tvc_stationid" && "$current_tvc_stationid" != "null" ]]; then
    echo -e "${BOLD}${GREEN}=== Auto-Matching with Existing Station ID ===${RESET}"
    echo -e "${GREEN}✅ Station ID found: $current_tvc_stationid${RESET}"
    echo -e "${CYAN}🔄 Using reverse station ID lookup instead of search...${RESET}"
    echo
    
    # Get station data from local database using the existing station ID
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
      echo -e "${CYAN}💡 Cannot auto-match without station database${RESET}"
      pause_for_user
      return 0
    fi
    
    local station_data
    station_data=$(jq -r --arg id "$current_tvc_stationid" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
    
    if [[ -n "$station_data" && "$station_data" != "null" ]]; then
      # Extract station information for auto-matching
      local station_name=$(echo "$station_data" | jq -r '.name // empty')
      local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
      local country=$(echo "$station_data" | jq -r '.country // empty')
      local quality=$(echo "$station_data" | jq -r '.videoQuality.videoType // empty')
      
      echo -e "${GREEN}✅ Station found in local database:${RESET}"
      echo -e "Station Name: ${GREEN}$station_name${RESET}"
      echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
      echo -e "Country: ${GREEN}$country${RESET}"
      echo -e "Quality: ${GREEN}$quality${RESET}"
      echo
      
      # Add user options for auto-matched stations
      echo -e "${BOLD}Options:${RESET}"
      echo -e "${GREEN}c)${RESET} Continue with field updates for this station"
      echo -e "${YELLOW}k)${RESET} Skip this channel ${CYAN}(continue to next channel)${RESET}"
      echo -e "${RED}q)${RESET} Quit field population ${CYAN}(stop entire batch processing)${RESET}"
      echo
      
      read -p "Your choice: " auto_choice < /dev/tty
      
      case "$auto_choice" in
        c|C|"")
          # Proceed with field comparison
          if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"; then
            echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
          else
            echo -e "${CYAN}💡 No field updates were applied for auto-matched station${RESET}"
          fi
          pause_for_user
          return 0
          ;;
        k|K)
          echo -e "${YELLOW}Skipped: $channel_name${RESET}"
          return 0  # Skip this channel, move to next
          ;;
        q|Q)
          echo -e "${CYAN}Field population ended by user${RESET}"
          return 1  # Signal to parent function to stop entire workflow
          ;;
        *)
          echo -e "${RED}Invalid option. Proceeding with field updates...${RESET}"
          # Default to continuing
          if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"; then
            echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
          else
            echo -e "${CYAN}💡 No field updates were applied for auto-matched station${RESET}"
          fi
          pause_for_user
          return 0
          ;;
      esac
    else
      echo -e "${YELLOW}⚠️  Station ID $current_tvc_stationid not found in local database${RESET}"
      echo -e "${CYAN}💡 Falling back to manual search method...${RESET}"
      echo
      # Fall through to manual search below
    fi
  else
    echo -e "${YELLOW}⚠️  No station ID found - using manual search method${RESET}"
    echo
    
    # Add user options for manual search
    echo -e "${BOLD}Options:${RESET}"
    echo -e "${GREEN}c)${RESET} Continue with manual station search"
    echo -e "${YELLOW}k)${RESET} Skip this channel ${CYAN}(continue to next channel)${RESET}"
    echo -e "${RED}q)${RESET} Quit field population ${CYAN}(stop entire batch processing)${RESET}"
    echo
    
    read -p "Your choice: " manual_choice < /dev/tty
    
    case "$manual_choice" in
      c|C|"")
        # Continue to manual search - fall through to search logic below
        ;;
      k|K)
        echo -e "${YELLOW}Skipped: $channel_name${RESET}"
        return 0  # Skip this channel, move to next
        ;;
      q|Q)
        echo -e "${CYAN}Field population ended by user${RESET}"
        return 1  # Signal to parent function to stop entire workflow
        ;;
      *)
        echo -e "${RED}Invalid option. Proceeding with manual search...${RESET}"
        # Default to continuing with manual search
        ;;
    esac
  fi
  
  # MANUAL SEARCH LOGIC: Original search workflow when no station ID or auto-match fails
  # Parse the channel name to get search term
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
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
      
      # IDENTICAL TABLE HEADER TO STATION ID WORKFLOW with FIXED selection highlighting
      printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
      echo "--------------------------------------------------------------------------------"
      
      local station_array=()
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
      local result_count=0
      
      # IDENTICAL RESULT PROCESSING TO STATION ID WORKFLOW with FIXED selection highlighting
      while IFS=$'\t' read -r station_id name call_sign country; do
        [[ -z "$station_id" ]] && continue
        
        # Get additional station info for better display
        local quality=$(get_station_quality "$station_id")
        
        local key="${key_letters[$result_count]}"
        
        # IDENTICAL TABLE ROW FORMATTING with CONSISTENT selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
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
    echo -e "${YELLOW}k) Skip this channel${RESET} ${CYAN}(continue to next channel)${RESET}"
    echo -e "${RED}q) Quit field population${RESET} ${CYAN}(stop entire batch processing)${RESET}"
    echo
    
    read -p "Your choice: " choice < /dev/tty
    
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
        echo -e "${CYAN}Field population ended by user${RESET}"
        return 1  # Signal to parent function to stop entire workflow
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
}

process_single_channel_fields_standalone() {
  local channel_data="$1"
  
  # Extract channel information with CORRECT field names
  local channel_id=$(echo "$channel_data" | jq -r '.id')
  local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
  local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
  local current_tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
  local current_tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')  # CORRECTED
  
  clear
  echo -e "${BOLD}${CYAN}=== Populate Channel Fields ===${RESET}\n"
  
  echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
  echo -e "Number: $channel_number | ID: $channel_id"
  echo
  
  echo -e "${BOLD}Current Field Values:${RESET}"
  echo -e "TVG-ID: ${current_tvg_id:-"${RED}(empty)${RESET}"}"
  echo -e "TVC Station ID: ${current_tvc_stationid:-"${RED}(empty)${RESET}"}"  # CORRECTED
  echo
  
  # AUTO-MATCHING LOGIC: If station ID exists, use reverse lookup instead of search
  if [[ -n "$current_tvc_stationid" && "$current_tvc_stationid" != "null" ]]; then
    echo -e "${BOLD}${GREEN}=== Auto-Matching with Existing Station ID ===${RESET}"
    echo -e "${GREEN}✅ Station ID found: $current_tvc_stationid${RESET}"
    echo -e "${CYAN}🔄 Using reverse station ID lookup instead of search...${RESET}"
    echo
    
    # Get station data from local database using the existing station ID
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
      echo -e "${CYAN}💡 Cannot auto-match without station database${RESET}"
      pause_for_user
      return 0
    fi
    
    local station_data
    station_data=$(jq -r --arg id "$current_tvc_stationid" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
    
    if [[ -n "$station_data" && "$station_data" != "null" ]]; then
      # Extract station information for auto-matching
      local station_name=$(echo "$station_data" | jq -r '.name // empty')
      local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
      local country=$(echo "$station_data" | jq -r '.country // empty')
      local quality=$(echo "$station_data" | jq -r '.videoQuality.videoType // empty')
      
      echo -e "${GREEN}✅ Station found in local database:${RESET}"
      echo -e "Station Name: ${GREEN}$station_name${RESET}"
      echo -e "Call Sign: ${GREEN}$call_sign${RESET}"
      echo -e "Country: ${GREEN}$country${RESET}"
      echo -e "Quality: ${GREEN}$quality${RESET}"
      echo
      
      # Add user options for auto-matched stations - SINGLE CHANNEL VERSION
      echo -e "${BOLD}Options:${RESET}"
      echo -e "${GREEN}c)${RESET} Continue with field updates for this station"
      echo -e "${YELLOW}r)${RESET} Return to channel selection ${CYAN}(choose different channel)${RESET}"
      echo -e "${RED}q)${RESET} Back to main menu"
      echo
      
      read -p "Your choice: " auto_choice < /dev/tty
      
      case "$auto_choice" in
        c|C|"")
          # Proceed with field comparison
          if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"; then
            echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
          else
            echo -e "${CYAN}💡 No field updates were applied for auto-matched station${RESET}"
          fi
          pause_for_user
          return 0
          ;;
        r|R)
          echo -e "${CYAN}Returning to channel selection...${RESET}"
          return 1  # Return to channel selection
          ;;
        q|Q)
          echo -e "${CYAN}Returning to main menu...${RESET}"
          return 2  # Return to main menu
          ;;
        *)
          echo -e "${RED}Invalid option. Proceeding with field updates...${RESET}"
          # Default to continuing
          if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$current_tvc_stationid" "$station_name" "$call_sign"; then
            echo -e "${GREEN}✅ Auto-matched field updates applied successfully${RESET}"
          else
            echo -e "${CYAN}💡 No field updates were applied for auto-matched station${RESET}"
          fi
          pause_for_user
          return 0
          ;;
      esac
    else
      echo -e "${YELLOW}⚠️  Station ID $current_tvc_stationid not found in local database${RESET}"
      echo -e "${CYAN}💡 Falling back to manual search method...${RESET}"
      echo
      # Fall through to manual search below
    fi
  else
    echo -e "${YELLOW}⚠️  No station ID found - using manual search method${RESET}"
    echo
    
    # Add user options for manual search - SINGLE CHANNEL VERSION
    echo -e "${BOLD}Options:${RESET}"
    echo -e "${GREEN}c)${RESET} Continue with manual station search"
    echo -e "${YELLOW}r)${RESET} Return to channel selection ${CYAN}(choose different channel)${RESET}"
    echo -e "${RED}q)${RESET} Back to main menu"
    echo
    
    read -p "Your choice: " manual_choice < /dev/tty
    
    case "$manual_choice" in
      c|C|"")
        # Continue to manual search - fall through to search logic below
        ;;
      r|R)
        echo -e "${CYAN}Returning to channel selection...${RESET}"
        return 1  # Return to channel selection
        ;;
      q|Q)
        echo -e "${CYAN}Returning to main menu...${RESET}"
        return 2  # Return to main menu
        ;;
      *)
        echo -e "${RED}Invalid option. Proceeding with manual search...${RESET}"
        # Default to continuing with manual search
        ;;
    esac
  fi
  
  # MANUAL SEARCH LOGIC: Original search workflow when no station ID or auto-match fails
  # Parse the channel name to get search term
  local parsed_data=$(parse_channel_name "$channel_name")
  IFS='|' read -r clean_name detected_country detected_resolution <<< "$parsed_data"
  
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
  
  # Search and display loop - SINGLE CHANNEL VERSION
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
        echo -e "${CYAN}💡 Try 's' to search with different term or filters${RESET}"
      fi
    else
      echo -e "${GREEN}Found $total_results total results${RESET}"
      echo
      
      # TABLE HEADER with FIXED selection highlighting
      printf "${BOLD}${YELLOW}%-3s %-12s %-30s %-10s %-8s %s${RESET}\n" "Key" "Station ID" "Channel Name" "Call Sign" "Quality" "Country"
      echo "--------------------------------------------------------------------------------"
      
      local station_array=()
      local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
      local result_count=0
      
      # RESULT PROCESSING with FIXED selection highlighting
      while IFS=$'\t' read -r station_id name call_sign country; do
        [[ -z "$station_id" ]] && continue
        
        # Get additional station info for better display
        local quality=$(get_station_quality "$station_id")
        
        local key="${key_letters[$result_count]}"
        
        # TABLE ROW FORMATTING with CONSISTENT selection highlighting
        printf "${GREEN}%-3s${RESET} " "${key})"
        echo -n -e "${CYAN}${station_id}${RESET}"
        printf "%*s" $((12 - ${#station_id})) ""
        printf "%-30s %-10s %-8s " "${name:0:30}" "${call_sign:0:10}" "${quality:0:8}"
        echo -e "${GREEN}${country}${RESET}"
        
        # LOGO DISPLAY
        if [[ "$SHOW_LOGOS" == true ]]; then
          display_logo "$station_id"
        else
          echo "[logo previews disabled]"
        fi
        echo
        
        # Store for selection
        station_array+=("$station_id|$name|$call_sign|$country|$quality")
        ((result_count++))
      done <<< "$results"
    fi
    
    # Calculate pagination info
    local total_pages=$(( (total_results + 9) / 10 ))
    [[ $total_pages -eq 0 ]] && total_pages=1
    
    echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
    echo
    
    # OPTIONS FOR SINGLE CHANNEL - Updated messaging
    echo -e "${BOLD}Options:${RESET}"
    [[ $result_count -gt 0 ]] && echo "a-j) Select a station from the results above"
    [[ $current_page -lt $total_pages ]] && echo "n) Next page"
    [[ $current_page -gt 1 ]] && echo "p) Previous page"
    echo "s) Search with different term"
    echo -e "${YELLOW}r) Return to channel selection${RESET} ${CYAN}(choose different channel)${RESET}"
    echo -e "${RED}q) Back to main menu${RESET}"
    echo
    
    read -p "Your choice: " choice < /dev/tty
    
    # OPTION HANDLING FOR SINGLE CHANNEL
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
              # Show field comparison and get user choices
              if show_field_comparison_and_update_simplified "$channel_id" "$channel_name" "$current_tvg_id" "$current_tvc_stationid" "$sel_station_id" "$sel_name" "$sel_call"; then
                echo -e "${GREEN}Field updates applied successfully${RESET}"
              else
                echo -e "${CYAN}No field updates were applied${RESET}"
              fi
              pause_for_user
              return 0  # Complete processing
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
      r|R)
        echo -e "${CYAN}Returning to channel selection...${RESET}"
        return 1  # Return to channel selection
        ;;
      q|Q)
        echo -e "${CYAN}Returning to main menu...${RESET}"
        return 2  # Return to main menu
        ;;
      *)
        echo -e "${RED}Invalid option${RESET}"
        sleep 1
        ;;
    esac
  done
}

automatic_complete_data_replacement() {
  local channels_data="$1"
  
  clear
  echo -e "${BOLD}${RED}=== ⚠️  AUTOMATIC COMPLETE DATA REPLACEMENT ⚠️  ===${RESET}\n"
  echo -e "${RED}${BOLD}WARNING: MASS DATA REPLACEMENT OPERATION${RESET}"
  echo -e "${YELLOW}This will automatically replace field data for ALL channels that have station IDs.${RESET}"
  echo -e "${YELLOW}This operation can potentially affect hundreds of channels with NO individual confirmation.${RESET}"
  echo
  
  # Analyze channels with station IDs - FIXED: Use consistent sorting
  echo -e "${CYAN}🔍 Analyzing channels with existing station IDs...${RESET}"
  local channels_with_stationids
  channels_with_stationids=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid != null and .tvc_guide_stationid != "")' | jq -s 'sort_by(.channel_number | tonumber)' | jq -c '.[]')
  
  if [[ -z "$channels_with_stationids" ]]; then
    echo -e "${YELLOW}⚠️  No channels found with existing station IDs${RESET}"
    echo -e "${CYAN}💡 Channels need station IDs before using automatic data replacement${RESET}"
    echo -e "${CYAN}💡 Use 'Interactive Station ID Matching' first to assign station IDs${RESET}"
    pause_for_user
    return 0
  fi
  
  mapfile -t stationid_channels < <(echo "$channels_with_stationids")
  local channels_count=${#stationid_channels[@]}
  
  echo -e "${GREEN}✅ Found $channels_count channels with station IDs${RESET}"
  echo
  
  # Show preview of what will be affected - FIXED: Already sorted from above
  echo -e "${BOLD}${BLUE}=== Channels That Will Be Processed ===${RESET}"
  printf "${BOLD}${YELLOW}%-8s %-6s %-25s %-12s %-20s %s${RESET}\n" "Ch ID" "Number" "Channel Name" "Station ID" "Current Name" "Current TVG"
  echo "--------------------------------------------------------------------------------"
  
  local preview_count=$((channels_count > 10 ? 10 : channels_count))
  for ((i = 0; i < preview_count; i++)); do
    local channel_data="${stationid_channels[$i]}"
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
    local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
    local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid')
    local current_tvg=$(echo "$channel_data" | jq -r '.tvg_id // "Empty"')
    
    printf "%-8s %-6s %-25s %-12s %-20s %s\n" \
      "$channel_id" \
      "$channel_number" \
      "${channel_name:0:25}" \
      "$station_id" \
      "${channel_name:0:20}" \
      "${current_tvg:0:10}"
  done
  
  if [[ $channels_count -gt 10 ]]; then
    echo -e "${CYAN}... and $((channels_count - 10)) more channels${RESET}"
  fi
  echo
  
  # Field selection for mass replacement
  echo -e "${BOLD}${BLUE}=== Field Selection for Mass Replacement ===${RESET}"
  echo -e "${YELLOW}Select which fields to update for ALL $channels_count channels:${RESET}"
  echo
  echo -e "${GREEN}1)${RESET} Channel Name - Replace with official station names"
  echo -e "${GREEN}2)${RESET} TVG-ID - Replace with station call signs"
  echo -e "${GREEN}3)${RESET} Channel Logo - Upload and assign station logos"
  echo -e "${GREEN}4)${RESET} All Fields - Replace name, TVG-ID, and logo"
  echo -e "${GREEN}c)${RESET} Custom Selection - Choose specific field combinations"
  echo
  
  local update_name=false
  local update_tvg=false
  local update_logo=false
  
  read -p "Select fields to update: " field_choice
  
  case "$field_choice" in
    1)
      update_name=true
      echo -e "${GREEN}✅ Will update: Channel Names only${RESET}"
      ;;
    2)
      update_tvg=true
      echo -e "${GREEN}✅ Will update: TVG-IDs only${RESET}"
      ;;
    3)
      update_logo=true
      echo -e "${GREEN}✅ Will update: Channel Logos only${RESET}"
      ;;
    4)
      update_name=true
      update_tvg=true
      update_logo=true
      echo -e "${GREEN}✅ Will update: All fields (Name, TVG-ID, Logo)${RESET}"
      ;;
    c|C)
      echo -e "\n${BOLD}Custom Field Selection:${RESET}"
      if confirm_action "Update channel names?"; then
        update_name=true
      fi
      if confirm_action "Update TVG-IDs?"; then
        update_tvg=true
      fi
      if confirm_action "Update channel logos?"; then
        update_logo=true
      fi
      
      local selected_fields=""
      $update_name && selected_fields+="Name "
      $update_tvg && selected_fields+="TVG-ID "
      $update_logo && selected_fields+="Logo "
      
      if [[ -z "$selected_fields" ]]; then
        echo -e "${RED}❌ No fields selected for update${RESET}"
        pause_for_user
        return 0
      fi
      
      echo -e "${GREEN}✅ Will update: $selected_fields${RESET}"
      ;;
    *)
      echo -e "${RED}❌ Invalid selection${RESET}"
      pause_for_user
      return 0
      ;;
  esac
  
  echo
  
  # CRITICAL SAFETY CONFIRMATION
  echo -e "${BOLD}${RED}=== FINAL SAFETY CONFIRMATION ===${RESET}"
  echo -e "${RED}${BOLD}⚠️  CRITICAL WARNING ⚠️${RESET}"
  echo
  echo -e "${YELLOW}You are about to automatically replace field data for $channels_count channels.${RESET}"
  echo -e "${YELLOW}This operation will:${RESET}"
  
  local operations=""
  if $update_name; then
    echo -e "${YELLOW}• Replace channel names with official station names${RESET}"
    operations+="names "
  fi
  if $update_tvg; then
    echo -e "${YELLOW}• Replace TVG-IDs with station call signs${RESET}"
    operations+="TVG-IDs "
  fi
  if $update_logo; then
    echo -e "${YELLOW}• Upload and assign station logos${RESET}"
    operations+="logos "
  fi
  
  echo
  echo -e "${RED}${BOLD}This operation CANNOT be easily undone!${RESET}"
  echo -e "${RED}Existing field data will be OVERWRITTEN without individual confirmation!${RESET}"
  echo
  echo -e "${CYAN}💡 Consider backing up your Dispatcharr configuration before proceeding${RESET}"
  echo
  
  # REQUIRE TYPING "proceed" to continue
  echo -e "${BOLD}${RED}Type the word 'proceed' (without quotes) to confirm this mass replacement:${RESET}"
  read -p "Confirmation: " safety_confirmation
  
  if [[ "$safety_confirmation" != "proceed" ]]; then
    echo -e "${YELLOW}⚠️  Automatic data replacement cancelled${RESET}"
    echo -e "${CYAN}💡 Safety confirmation failed - operation aborted${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "${GREEN}✅ Safety confirmation accepted${RESET}"
  echo
  
  # Execute mass replacement - FIXED: Use properly sorted array
  echo -e "${BOLD}${CYAN}=== Executing Automatic Data Replacement ===${RESET}"
  echo -e "${CYAN}🔄 Processing $channels_count channels automatically...${RESET}"
  echo
  
  local success_count=0
  local failure_count=0
  local processed_count=0
  
  for channel_data in "${stationid_channels[@]}"; do
    ((processed_count++))
    local percent=$((processed_count * 100 / channels_count))
    
    local channel_id=$(echo "$channel_data" | jq -r '.id')
    local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
    local station_id=$(echo "$channel_data" | jq -r '.tvc_guide_stationid')
    
    # Show progress
    printf "\r${CYAN}[%3d%%] (%d/%d) Processing: %-25s (Station ID: %s)${RESET}" \
      "$percent" "$processed_count" "$channels_count" "${channel_name:0:25}" "$station_id"
    
    # Auto-match using reverse station ID lookup
    if automatic_field_population "$channel_id" "$station_id" "$update_name" "$update_tvg" "$update_logo"; then
      ((success_count++))
      # Token refresh every configured interval
      if (( success_count % DISPATCHARR_REFRESH_INTERVAL == 0 )); then
        increment_dispatcharr_interaction "automatic updates"
      fi
    else
      ((failure_count++))
    fi
  done
  
  # Clear progress line
  echo
  echo
  
  # Show comprehensive results
  echo -e "${BOLD}${GREEN}=== Automatic Data Replacement Results ===${RESET}"
  printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Result Category" "Count"
  echo "-----------------------------------"
  printf "%-25s %s\n" "Successfully processed:" "${GREEN}$success_count channels${RESET}"
  
  if [[ $failure_count -gt 0 ]]; then
    printf "%-25s %s\n" "Failed to process:" "${RED}$failure_count channels${RESET}"
  fi
  
  printf "%-25s %s\n" "Total processed:" "${CYAN}$((success_count + failure_count)) of $channels_count${RESET}"
  
  if [[ $channels_count -gt 0 ]]; then
    local success_rate=$(( (success_count * 100) / channels_count ))
    printf "%-25s %s\n" "Success rate:" "${GREEN}${success_rate}%${RESET}"
  fi
  echo
  
  # Show what was updated
  echo -e "${BOLD}${CYAN}Fields Updated:${RESET}"
  $update_name && echo -e "${GREEN}✅ Channel Names: Updated for all successfully processed channels${RESET}"
  $update_tvg && echo -e "${GREEN}✅ TVG-IDs: Updated for all successfully processed channels${RESET}"
  $update_logo && echo -e "${GREEN}✅ Channel Logos: Updated for all successfully processed channels${RESET}"
  echo
  
  if [[ $success_count -gt 0 ]]; then
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "• All changes are now active in Dispatcharr"
    echo -e "• $success_count channels have been enhanced with station data"
    echo -e "• Channel information is now synchronized with your station database"
    
    if [[ $failure_count -eq 0 ]]; then
      echo -e "${GREEN}💡 Perfect! All channels processed successfully${RESET}"
    else
      echo -e "${YELLOW}💡 $failure_count channels need manual attention${RESET}"
    fi
  else
    echo -e "${RED}❌ No channels were successfully processed${RESET}"
    echo -e "${CYAN}💡 Check Dispatcharr connection and station database${RESET}"
  fi
  
  pause_for_user
}

automatic_field_population() {
  local channel_id="$1"
  local station_id="$2"
  local update_name="$3"
  local update_tvg="$4"
  local update_logo="$5"
  
  # Get station data from local database using reverse lookup
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  local station_data
  station_data=$(jq -r --arg id "$station_id" '.[] | select(.stationId == $id)' "$stations_file" 2>/dev/null)
  
  if [[ -z "$station_data" || "$station_data" == "null" ]]; then
    return 1  # Station not found in local database
  fi
  
  # Extract station information
  local station_name=$(echo "$station_data" | jq -r '.name // empty')
  local call_sign=$(echo "$station_data" | jq -r '.callSign // empty')
  local logo_url=$(echo "$station_data" | jq -r '.preferredImage.uri // empty')
  
  # Build update data
  local update_data="{}"
  local logo_id=""
  
  if [[ "$update_name" == "true" ]] && [[ -n "$station_name" && "$station_name" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --arg name "$station_name" '. + {name: $name}')
  fi
  
  if [[ "$update_tvg" == "true" ]] && [[ -n "$call_sign" && "$call_sign" != "null" ]]; then
    update_data=$(echo "$update_data" | jq --arg tvg_id "$call_sign" '. + {tvg_id: $tvg_id}')
  fi
  
  if [[ "$update_logo" == "true" ]] && [[ -n "$logo_url" && "$logo_url" != "null" ]]; then
    logo_id=$(upload_station_logo_to_dispatcharr "$station_name" "$logo_url")
    if [[ -n "$logo_id" && "$logo_id" != "null" ]]; then
      update_data=$(echo "$update_data" | jq --argjson logo_id "$logo_id" '. + {logo_id: $logo_id}')
    fi
  fi
  
  # Apply updates to Dispatcharr
  if [[ "$update_data" != "{}" ]]; then
    local token_file="$CACHE_DIR/dispatcharr_tokens.json"
    local access_token
    if [[ -f "$token_file" ]]; then
      access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    fi
    
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
      # Increment interaction counter BEFORE the API call
      increment_dispatcharr_interaction "automatic field updates"
      
      local response
      response=$(curl -s -X PATCH \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$update_data" \
        "${DISPATCHARR_URL}/api/channels/channels/${channel_id}/" 2>/dev/null)
      
      if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  
  return 1
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
  
  # Increment interaction counter BEFORE the API call
  increment_dispatcharr_interaction "field updates"
  
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
  
  # Increment interaction counter BEFORE the API call
  increment_dispatcharr_interaction "logo uploads"
  
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
    echo -e "   $label: ${GREEN}Available${RESET} [logo preview unavailable]"
    echo -e "   URL: $logo_url"  # Removed ${CYAN} and ${RESET}
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

run_dispatcharr_integration() {
  # Always refresh tokens when entering Dispatcharr integration
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    echo -e "${CYAN}🔄 Initializing Dispatcharr Integration...${RESET}"
    
    if ! refresh_dispatcharr_tokens; then
      echo -e "${RED}❌ Cannot continue without valid authentication${RESET}"
      echo -e "${CYAN}💡 Please check your Dispatcharr connection settings${RESET}"
      pause_for_user
      return 1
    fi
    echo
  fi
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Dispatcharr Integration ===${RESET}\n"
    
    # STANDARDIZED: Connection Status Section with detailed indicators
    echo -e "${BOLD}${BLUE}=== Connection Status ===${RESET}"
    
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
      if check_dispatcharr_connection; then
        echo -e "${GREEN}✅ Dispatcharr Integration: Active and Connected${RESET}"
        echo -e "   ${CYAN}🌐 Server: $DISPATCHARR_URL${RESET}"
        echo -e "   ${CYAN}👤 User: ${DISPATCHARR_USERNAME:-"Not configured"}${RESET}"
        
        # STANDARDIZED: Token status with age information
        local token_file="$CACHE_DIR/dispatcharr_tokens.json"
        if [[ -f "$token_file" ]]; then
          local token_time
          token_time=$(stat -c %Y "$token_file" 2>/dev/null || stat -f %m "$token_file" 2>/dev/null)
          if [[ -n "$token_time" ]]; then
            local current_time=$(date +%s)
            local age_seconds=$((current_time - token_time))
            local age_minutes=$((age_seconds / 60))
            
            if [ "$age_minutes" -lt 30 ]; then
              echo -e "   ${GREEN}🔑 Tokens: Fresh (${age_minutes}m old)${RESET}"
            elif [ "$age_minutes" -lt 60 ]; then
              echo -e "   ${YELLOW}🔑 Tokens: Valid (${age_minutes}m old)${RESET}"
            else
              local age_hours=$((age_minutes / 60))
              echo -e "   ${YELLOW}🔑 Tokens: Aging (${age_hours}h old)${RESET}"
            fi
          else
            echo -e "   ${CYAN}🔑 Tokens: Available${RESET}"
          fi
        else
          echo -e "   ${RED}🔑 Tokens: Missing${RESET}"
        fi
        
      else
        echo -e "${RED}❌ Dispatcharr Integration: Connection Failed${RESET}"
        if [[ -n "${DISPATCHARR_URL:-}" ]]; then
          echo -e "   ${CYAN}🌐 Configured Server: $DISPATCHARR_URL${RESET}"
          echo -e "   ${RED}💔 Status: Cannot reach server${RESET}"
          echo -e "   ${CYAN}💡 Verify Dispatcharr is running and accessible${RESET}"
        else
          echo -e "   ${YELLOW}⚠️  Server: Not configured${RESET}"
        fi
      fi
    else
      echo -e "${YELLOW}⚠️  Dispatcharr Integration: Disabled${RESET}"
      echo -e "   ${CYAN}💡 Enable via Settings → Dispatcharr Integration${RESET}"
      echo -e "   ${CYAN}💡 Required for channel management features${RESET}"
    fi
    
    echo
    
    # STANDARDIZED: Pending Operations Status
    echo -e "${BOLD}${BLUE}=== Pending Operations ===${RESET}"
    
    if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
      local pending_count
      pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
      echo -e "${YELLOW}📋 Pending Station ID Changes: $pending_count matches queued${RESET}"
      echo -e "   ${CYAN}💡 These matches are ready for batch commit to Dispatcharr${RESET}"
      echo -e "   ${CYAN}💡 Use 'Commit Station ID Changes' to apply them${RESET}"
    else
      echo -e "${GREEN}✅ Pending Operations: No pending changes${RESET}"
      echo -e "   ${CYAN}💡 All previous operations have been completed${RESET}"
    fi
    
    # STANDARDIZED: Database Compatibility Check
    echo
    echo -e "${BOLD}${BLUE}=== Database Compatibility ===${RESET}"
    
    local total_count=$(get_total_stations_count)
    if [ "$total_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Local Station Database: $total_count stations available${RESET}"
      echo -e "   ${CYAN}💡 Fully compatible with all Dispatcharr integration features${RESET}"
      
      # Show breakdown for user context
      local breakdown=$(get_stations_breakdown)
      local base_count=$(echo "$breakdown" | cut -d' ' -f1)
      local user_count=$(echo "$breakdown" | cut -d' ' -f2)
      
      if [ "$base_count" -gt 0 ]; then
        echo -e "   ${CYAN}📊 Base Station Database: $base_count stations${RESET}"
      fi
      if [ "$user_count" -gt 0 ]; then
        echo -e "   ${CYAN}📊 User Station Database: $user_count stations${RESET}"
      fi
    else
      echo -e "${RED}❌ Local Station Database: No station data available${RESET}"
      echo -e "   ${YELLOW}⚠️  Limited functionality: Station ID matching unavailable${RESET}"
      echo -e "   ${CYAN}💡 Build database via 'Manage Television Markets' → 'Run User Caching'${RESET}"
    fi
    
    # STANDARDIZED: Recent Activity Log
    echo
    echo -e "${BOLD}${BLUE}=== Recent Activity ===${RESET}"
    
    if [[ -f "$DISPATCHARR_LOG" ]] && [[ -s "$DISPATCHARR_LOG" ]]; then
      local log_entries=$(wc -l < "$DISPATCHARR_LOG")
      local last_activity=$(tail -1 "$DISPATCHARR_LOG" 2>/dev/null | cut -d' ' -f1-2)
      
      echo -e "${GREEN}✅ Activity Log: $log_entries operations recorded${RESET}"
      if [[ -n "$last_activity" ]]; then
        echo -e "   ${CYAN}📅 Last Activity: $last_activity${RESET}"
      fi
      
      # Show recent operation summary
      local recent_updates=$(tail -10 "$DISPATCHARR_LOG" | grep -c "Updated channel")
      local recent_failures=$(tail -10 "$DISPATCHARR_LOG" | grep -c "Failed")
      local recent_tokens=$(tail -10 "$DISPATCHARR_LOG" | grep -c "tokens generated")
      
      if [ "$recent_updates" -gt 0 ] || [ "$recent_failures" -gt 0 ] || [ "$recent_tokens" -gt 0 ]; then
        echo -e "   ${CYAN}📊 Recent Operations (last 10 entries):${RESET}"
        [ "$recent_updates" -gt 0 ] && echo -e "     ${GREEN}✅ Channel Updates: $recent_updates${RESET}"
        [ "$recent_failures" -gt 0 ] && echo -e "     ${RED}❌ Failed Operations: $recent_failures${RESET}"
        [ "$recent_tokens" -gt 0 ] && echo -e "     ${CYAN}🔑 Token Refreshes: $recent_tokens${RESET}"
      fi
    else
      echo -e "${CYAN}📝 Activity Log: No operations recorded yet${RESET}"
      echo -e "   ${CYAN}💡 Log will track operations as you use integration features${RESET}"
    fi
    
    echo
    
    # STANDARDIZED: Feature Menu with enhanced descriptions
    echo -e "${BOLD}${CYAN}=== Integration Features ===${RESET}"
    
    echo -e "${BOLD}${YELLOW}Station ID Management:${RESET}"
    echo -e "${GREEN}a)${RESET} Scan Channels for Missing Station IDs ${CYAN}(identify channels needing setup)${RESET}"
    echo -e "${GREEN}b)${RESET} Interactive Station ID Matching ${CYAN}(guided channel-to-station assignment)${RESET}"
    echo -e "${GREEN}c)${RESET} Commit Station ID Changes ${CYAN}(apply queued matches to Dispatcharr)${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}Channel Enhancement:${RESET}"
    echo -e "${GREEN}d)${RESET} Populate Other Dispatcharr Fields ${CYAN}(names, logos, TVG-IDs)${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}System Management:${RESET}"
    echo -e "${GREEN}e)${RESET} Configure Dispatcharr Connection ${CYAN}(server settings & authentication)${RESET}"
    echo -e "${GREEN}f)${RESET} View Integration Logs ${CYAN}(operation history & troubleshooting)${RESET}"
    echo -e "${GREEN}g)${RESET} Refresh Authentication Tokens ${CYAN}(manual token renewal)${RESET}"
    echo -e "${GREEN}q)${RESET} Back to Main Menu"
    echo
    
    # STANDARDIZED: Smart recommendations based on status
    if [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
      echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
      echo -e "${CYAN}   Start with option 'e' to configure your Dispatcharr connection${RESET}"
      echo
    elif ! check_dispatcharr_connection; then
      echo -e "${BOLD}${YELLOW}💡 Connection Issue Detected:${RESET}"
      echo -e "${CYAN}   Try option 'e' to reconfigure connection or 'g' to refresh tokens${RESET}"
      echo
    elif [ "$total_count" -eq 0 ]; then
      echo -e "${BOLD}${YELLOW}💡 Database Required:${RESET}"
      echo -e "${CYAN}   Build station database first via 'Manage Television Markets' from main menu${RESET}"
      echo
    elif [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
      local pending_count=$(wc -l < "$DISPATCHARR_MATCHES")
      echo -e "${BOLD}${YELLOW}💡 Pending Changes Detected:${RESET}"
      echo -e "${CYAN}   You have $pending_count station ID matches ready - try option 'c' to commit them${RESET}"
      echo
    else
      echo -e "${BOLD}${YELLOW}💡 Ready for Channel Management:${RESET}"
      echo -e "${CYAN}   Start with option 'a' to scan for channels needing station IDs${RESET}"
      echo
    fi
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      a|A) 
        echo -e "${CYAN}🔍 Starting channel scan...${RESET}"
        scan_missing_stationids 
        ;;
      b|B) 
        echo -e "${CYAN}🎯 Starting interactive matching...${RESET}"
        interactive_stationid_matching 
        ;;
      c|C) 
        echo -e "${CYAN}💾 Processing station ID changes...${RESET}"
        batch_update_stationids && pause_for_user 
        ;;
      d|D) 
        echo -e "${CYAN}📝 Starting field population...${RESET}"
        populate_dispatcharr_fields 
        ;;
      e|E) 
        echo -e "${CYAN}⚙️  Opening connection configuration...${RESET}"
        configure_dispatcharr_connection && pause_for_user 
        ;;
      f|F) 
        echo -e "${CYAN}📋 Loading integration logs...${RESET}"
        view_dispatcharr_logs && pause_for_user 
        ;;
      g|G) 
        echo -e "${CYAN}🔄 Refreshing authentication tokens...${RESET}"
        refresh_dispatcharr_tokens && pause_for_user 
        ;;
      q|Q|"") 
        echo -e "${CYAN}🔄 Returning to main menu...${RESET}"
        break 
        ;;
      *) 
        echo -e "${RED}❌ Invalid Option: '$choice'${RESET}"
        echo -e "${CYAN}💡 Please select a valid option from the menu${RESET}"
        sleep 2
        ;;
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

configure_dispatcharr_refresh_interval() {
  clear
  echo -e "${BOLD}${CYAN}=== Configure Dispatcharr Token Refresh ===${RESET}\n"
  echo -e "${BLUE}📍 Automatic Token Refresh During Channel Operations${RESET}"
  echo -e "${YELLOW}This setting controls how often authentication tokens are refreshed during long Dispatcharr operations.${RESET}"
  echo
  
  # STANDARDIZED: Show current configuration
  echo -e "${BOLD}${BLUE}Current Configuration:${RESET}"
  echo -e "Refresh Interval: ${GREEN}Every $DISPATCHARR_REFRESH_INTERVAL channel interactions${RESET}"
  echo -e "Dispatcharr Integration: $([ "$DISPATCHARR_ENABLED" = "true" ] && echo -e "${GREEN}Enabled${RESET}" || echo -e "${YELLOW}Disabled${RESET}")"
  echo
  
  # STANDARDIZED: Feature explanation
  echo -e "${BOLD}${BLUE}How Token Refresh Works:${RESET}"
  echo -e "${CYAN}• Tokens automatically refresh during long channel processing sessions${RESET}"
  echo -e "${CYAN}• Prevents authentication timeouts during bulk operations${RESET}"
  echo -e "${CYAN}• Only activates during Dispatcharr Integration workflows${RESET}"
  echo -e "${CYAN}• Refresh happens transparently - no workflow interruption${RESET}"
  echo
  
  echo -e "${BOLD}${BLUE}When Refresh Occurs:${RESET}"
  echo -e "${GREEN}✅ Interactive Station ID Matching${RESET} - After each successful assignment"
  echo -e "${GREEN}✅ Batch Station ID Updates${RESET} - Every 25 (default, configurable) successful updates"  
  echo -e "${GREEN}✅ Field Population${RESET} - After each channel's field updates"
  echo -e "${RED}❌ Other operations${RESET} - No automatic refresh (not needed)"
  echo
  
  # STANDARDIZED: Interval recommendations
  echo -e "${BOLD}${BLUE}Interval Recommendations:${RESET}"
  echo -e "${GREEN}• 10-15 interactions${RESET} - Frequent refresh, best for slow connections"
  echo -e "${GREEN}• 20-30 interactions${RESET} - Balanced (recommended for most users)"
  echo -e "${GREEN}• 30-50 interactions${RESET} - Less frequent, good for fast/reliable connections"
  echo -e "${GREEN}• 50+ interactions${RESET} - Minimal refresh, only for very fast operations"
  echo
  echo -e "${CYAN}💡 Lower numbers = more frequent refresh = more reliable but slightly slower${RESET}"
  echo -e "${CYAN}💡 Higher numbers = less frequent refresh = faster but higher timeout risk${RESET}"
  echo
  
  # STANDARDIZED: Interval configuration with validation
  echo -e "${BOLD}Step 1: Set Refresh Interval${RESET}"
  echo -e "${CYAN}💡 Current: Every $DISPATCHARR_REFRESH_INTERVAL channel interactions${RESET}"
  echo -e "${CYAN}💡 Valid range: 5-100 interactions${RESET}"
  echo -e "${CYAN}💡 Press Enter to keep current setting${RESET}"
  echo
  
  local new_interval
  while true; do
    read -p "Enter refresh interval [current: $DISPATCHARR_REFRESH_INTERVAL]: " new_interval < /dev/tty
    
    # Keep current setting if no input
    if [[ -z "$new_interval" ]]; then
      echo -e "${CYAN}💡 Keeping current setting: $DISPATCHARR_REFRESH_INTERVAL${RESET}"
      break
    fi
    
    # STANDARDIZED: Comprehensive validation
    if [[ "$new_interval" =~ ^[0-9]+$ ]]; then
      if (( new_interval >= 5 && new_interval <= 100 )); then
        DISPATCHARR_REFRESH_INTERVAL="$new_interval"
        echo -e "${GREEN}✅ Refresh interval updated: Every $new_interval channel interactions${RESET}"
        break
      else
        echo -e "${RED}❌ Interval out of valid range${RESET}"
        echo -e "${CYAN}💡 Please enter a number between 5 and 100${RESET}"
        echo -e "${CYAN}💡 Recommended: 20-30 for most users${RESET}"
      fi
    else
      echo -e "${RED}❌ Invalid number format${RESET}"
      echo -e "${CYAN}💡 Enter a whole number (e.g., 10, 15, 20)${RESET}"
    fi
    echo
  done
  
  # STANDARDIZED: Save configuration with feedback
  echo
  echo -e "${CYAN}💾 Saving token refresh configuration...${RESET}"
  
  # Update config file
  local temp_config="${CONFIG_FILE}.tmp"
  if grep -v '^DISPATCHARR_REFRESH_INTERVAL=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null; then
    echo "DISPATCHARR_REFRESH_INTERVAL=$DISPATCHARR_REFRESH_INTERVAL" >> "$temp_config"
    
    if mv "$temp_config" "$CONFIG_FILE"; then
      echo -e "${GREEN}✅ Configuration saved successfully${RESET}"
    else
      echo -e "${RED}❌ Configuration Save: Failed to save settings${RESET}"
      echo -e "${CYAN}💡 Check file permissions for: $CONFIG_FILE${RESET}"
      rm -f "$temp_config" 2>/dev/null
    fi
  else
    echo -e "${RED}❌ Configuration Save: Cannot read current config${RESET}"
    echo -e "${CYAN}💡 Check file permissions and try again${RESET}"
  fi
  
  # STANDARDIZED: Show final configuration summary
  echo
  echo -e "${BOLD}${GREEN}=== Token Refresh Configuration Summary ===${RESET}"
  echo -e "Refresh Interval: ${GREEN}Every $DISPATCHARR_REFRESH_INTERVAL channel interactions${RESET}"
  
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    echo -e "Integration Status: ${GREEN}Enabled - automatic refresh will activate${RESET}"
    echo
    echo -e "${BOLD}${CYAN}What This Means:${RESET}"
    echo -e "${CYAN}• During long Dispatcharr operations, tokens refresh automatically${RESET}"
    echo -e "${CYAN}• You'll see: '🔄 Refreshing authentication tokens (X interactions processed)'${RESET}"
    echo -e "${CYAN}• Prevents timeout during station ID matching and field population${RESET}"
    echo -e "${CYAN}• No workflow interruption - happens transparently${RESET}"
  else
    echo -e "Integration Status: ${YELLOW}Disabled - enable Dispatcharr integration to use this feature${RESET}"
    echo
    echo -e "${BOLD}${CYAN}What This Means:${RESET}"
    echo -e "${CYAN}• Setting is saved but inactive until Dispatcharr integration is enabled${RESET}"
    echo -e "${CYAN}• Enable via Settings → Configure Dispatcharr Integration${RESET}"
  fi
  
  echo
  echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
  echo -e "${GREEN}• Test the setting with 'Dispatcharr Integration' from main menu${RESET}"
  echo -e "${GREEN}• Try 'Interactive Station ID Matching' to see automatic refresh in action${RESET}"
  echo -e "${GREEN}• Adjust interval anytime via this settings menu${RESET}"
  
  return 0
}

# ============================================================================
# MARKET MANAGEMENT FUNCTIONS
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

add_market() {
  clear
  echo -e "${BOLD}${CYAN}=== Add New Market ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Geographic Market for Station Caching${RESET}"
  echo -e "${YELLOW}Markets determine which regions' stations will be cached for Local Database Search.${RESET}"
  echo
  
  # STANDARDIZED: Enhanced postal code guidance with regional examples
  echo -e "${BOLD}${BLUE}Postal Code Guidelines by Country:${RESET}"
  echo
  echo -e "${GREEN}🇺🇸 USA${RESET} - Use 5-digit ZIP codes:"
  echo -e "${CYAN}   Examples: 90210 (Beverly Hills), 10001 (New York), 60601 (Chicago)${RESET}"
  echo -e "${CYAN}   💡 Use the main ZIP code for the area, not ZIP+4 extensions${RESET}"
  echo
  echo -e "${GREEN}🇬🇧 United Kingdom${RESET} - Use district portion only:"
  echo -e "${CYAN}   Examples: SW1A (Westminster), M1 (Manchester), EH1 (Edinburgh)${RESET}"
  echo -e "${CYAN}   💡 Use the area/district code before the space, not full postcodes${RESET}"
  echo
  echo -e "${GREEN}🇨🇦 Canada${RESET} - Use forward sortation area:"
  echo -e "${CYAN}   Examples: M5V (Toronto), K1A (Ottawa), V6B (Vancouver)${RESET}"
  echo -e "${CYAN}   💡 Use the first 3 characters before the space${RESET}"
  echo
  echo -e "${CYAN}💡 If unsure, try the main area/district code first${RESET}"
  echo -e "${CYAN}💡 These formats work best with TV lineup APIs${RESET}"
  echo
  
  local country zip normalized_zip
  
  # STANDARDIZED: Country input with validation and guidance
  while true; do
    echo -e "${BOLD}Step 1: Country Selection${RESET}"
    echo -e "${CYAN}Enter the 3-letter ISO country code (e.g., USA, CAN, GBR):${RESET}"
    read -p "Country code: " country < /dev/tty
    
    if [[ -z "$country" ]]; then
      echo -e "${YELLOW}⚠️  Add Market: Operation cancelled${RESET}"
      return 1
    fi
    
    # Normalize to uppercase
    country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
    
    # Validate against known country codes
    if grep -Fxq "$country" "$VALID_CODES_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Country code '$country' is valid${RESET}"
      break
    else
      echo -e "${RED}❌ Invalid country code: '$country'${RESET}"
      echo -e "${CYAN}💡 Must be a valid 3-letter ISO code (examples: USA, CAN, GBR, DEU, FRA)${RESET}"
      echo -e "${CYAN}💡 Check the country list or try common alternatives${RESET}"
      echo
    fi
  done
  
  echo
  
  # STANDARDIZED: ZIP/Postal code input with normalization guidance
  echo -e "${BOLD}Step 2: Postal Code Entry${RESET}"
  echo -e "${CYAN}Enter the ZIP/postal code for the area you want to cache:${RESET}"
  read -p "ZIP/Postal Code: " zip < /dev/tty
  
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}⚠️  Add Market: Operation cancelled${RESET}"
    return 1
  fi
  
  # STANDARDIZED: Postal code normalization with user feedback
  echo -e "\n${CYAN}🔄 Processing postal code...${RESET}"
  
  # Normalize postal code - take only first segment if there's a space
  if [[ "$zip" == *" "* ]]; then
    normalized_zip=$(echo "$zip" | cut -d' ' -f1)
    echo -e "${YELLOW}⚠️  Postal code '$zip' normalized to '$normalized_zip'${RESET}"
    echo -e "${CYAN}💡 Using first segment only - this format works better with TV lineup APIs${RESET}"
    echo -e "${CYAN}💡 Full postcodes often don't match API expectations${RESET}"
  else
    normalized_zip="$zip"
    echo -e "${GREEN}✅ Postal code '$zip' accepted as-is${RESET}"
  fi
  
  # Remove any remaining spaces and convert to uppercase for consistency
  normalized_zip=$(echo "$normalized_zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  
  if [[ "$normalized_zip" != "$zip" ]]; then
    echo -e "${CYAN}💡 Final format: '$normalized_zip' (uppercase, no spaces)${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: Market validation and duplicate checking
  echo -e "${CYAN}🔍 Checking if market already exists...${RESET}"
  
  # Create CSV file with header if it doesn't exist
  if [ ! -f "$CSV_FILE" ]; then
    echo "Country,ZIP" > "$CSV_FILE"
    echo -e "${GREEN}✅ Created new markets configuration file${RESET}"
  fi
  
  # Check for duplicates with clear messaging
  if grep -q "^$country,$normalized_zip$" "$CSV_FILE"; then
    echo -e "${RED}❌ Market Already Exists: $country/$normalized_zip${RESET}"
    echo -e "${CYAN}💡 This exact market is already in your configuration${RESET}"
    echo -e "${CYAN}💡 Check 'Current Markets' in the main menu to see all configured markets${RESET}"
    echo
    pause_for_user
    return 1
  else
    # STANDARDIZED: Successful addition with confirmation
    echo "$country,$normalized_zip" >> "$CSV_FILE"
    echo -e "${GREEN}✅ Market Added Successfully: $country/$normalized_zip${RESET}"
    echo
    
    # Show current market count
    local total_markets=$(awk 'END {print NR-1}' "$CSV_FILE")
    echo -e "${CYAN}📊 Total configured markets: $total_markets${RESET}"
    echo
    
    # STANDARDIZED: Next steps guidance
    echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
    echo -e "${GREEN}• Add more markets if needed (different regions expand station coverage)${RESET}"
    echo -e "${GREEN}• Use 'Run User Caching' to download stations from all configured markets${RESET}"
    echo -e "${GREEN}• Stations from all markets will be combined and deduplicated automatically${RESET}"
    echo
    
    pause_for_user
    return 0
  fi
}

remove_market() {
  clear
  echo -e "${BOLD}${CYAN}=== Remove Market ===${RESET}\n"
  echo -e "${BLUE}📍 Remove Geographic Market from Configuration${RESET}"
  echo -e "${YELLOW}This will remove the market from your configuration but won't affect already-cached stations.${RESET}"
  echo
  
  # STANDARDIZED: Check if markets exist before proceeding
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${YELLOW}⚠️  No Markets Configured${RESET}"
    echo -e "${CYAN}💡 No markets found to remove${RESET}"
    echo -e "${CYAN}💡 Use 'Add Market' to configure markets first${RESET}"
    echo
    pause_for_user
    return 1
  fi
  
  # STANDARDIZED: Show current markets with professional table formatting
  local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  echo -e "${BOLD}Current Markets (${market_count} total):${RESET}"
  echo
  
  # STANDARDIZED: Professional table pattern with consistent formatting
  printf "${BOLD}${YELLOW}%-15s %-15s %s${RESET}\n" "Country" "ZIP/Postal" "Status"
  echo "------------------------------------------------"
  
  tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
    # Check if market has been cached
    local status=""
    if is_market_cached "$country" "$zip"; then
      status="${GREEN}Cached${RESET}"
    else
      status="${YELLOW}Not cached${RESET}"
    fi
    printf "%-15s %-15s %s\n" "$country" "$zip" "$status"
  done
  echo
  
  # STANDARDIZED: Market selection with validation
  local country zip
  
  echo -e "${BOLD}Step 1: Select Market to Remove${RESET}"
  echo -e "${CYAN}Enter the country code and ZIP/postal code exactly as shown above:${RESET}"
  echo
  
  read -p "Country code to remove: " country < /dev/tty
  if [[ -z "$country" ]]; then
    echo -e "${YELLOW}⚠️  Remove Market: Operation cancelled${RESET}"
    return 1
  fi
  
  # Normalize country to uppercase
  country=$(echo "$country" | tr '[:lower:]' '[:upper:]')
  
  read -p "ZIP/Postal code to remove: " zip < /dev/tty
  if [[ -z "$zip" ]]; then
    echo -e "${YELLOW}⚠️  Remove Market: Operation cancelled${RESET}"
    return 1
  fi
  
  # Normalize ZIP to uppercase and remove spaces
  zip=$(echo "$zip" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  
  echo
  
  # STANDARDIZED: Market existence validation
  echo -e "${CYAN}🔍 Checking if market exists in configuration...${RESET}"
  
  if grep -q "^$country,$zip$" "$CSV_FILE"; then
    echo -e "${GREEN}✅ Market found: $country/$zip${RESET}"
    echo
    
    # STANDARDIZED: Impact analysis and confirmation with table display
    echo -e "${BOLD}${BLUE}Removal Impact Analysis:${RESET}"
    
    # STANDARDIZED: Impact summary table
    printf "${BOLD}${YELLOW}%-20s %s${RESET}\n" "Impact Category" "Details"
    echo "----------------------------------------"
    
    # Check if market was cached
    if is_market_cached "$country" "$zip"; then
      printf "%-20s %s\n" "Cached Status:" "${YELLOW}Market has been cached${RESET}"
      printf "%-20s %s\n" "Station Impact:" "${CYAN}Stations remain in database${RESET}"
      printf "%-20s %s\n" "Future Processing:" "${CYAN}Market will be skipped${RESET}"
    else
      printf "%-20s %s\n" "Cached Status:" "${GREEN}Market not cached yet${RESET}"
      printf "%-20s %s\n" "Station Impact:" "${CYAN}No impact on database${RESET}"
      printf "%-20s %s\n" "Future Processing:" "${CYAN}Market removed from queue${RESET}"
    fi
    printf "%-20s %s\n" "Configuration:" "${RED}Will be removed${RESET}"
    echo
    
    # STANDARDIZED: Confirmation with clear consequences
    echo -e "${BOLD}Confirm Market Removal:${RESET}"
    
    # STANDARDIZED: Confirmation details table
    printf "${BOLD}${YELLOW}%-15s %s${RESET}\n" "Field" "Value"
    echo "--------------------------------"
    printf "%-15s %s\n" "Market:" "${YELLOW}$country/$zip${RESET}"
    printf "%-15s %s\n" "Action:" "${RED}Remove from configuration${RESET}"
    printf "%-15s %s\n" "Impact:" "${CYAN}Configuration only${RESET}"
    printf "%-15s %s\n" "Cached Data:" "${CYAN}Preserved${RESET}"
    echo
    
    if confirm_action "Remove market $country/$zip from configuration?"; then
      # STANDARDIZED: Perform removal with feedback
      echo -e "${CYAN}🔄 Removing market from configuration...${RESET}"
      
      # Create backup before modification
      local backup_file="${CSV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
      if cp "$CSV_FILE" "$backup_file" 2>/dev/null; then
        echo -e "${CYAN}💡 Configuration backed up to: $(basename "$backup_file")${RESET}"
      fi
      
      # Remove the market entry
      sed -i'' "/^$country,$zip$/d" "$CSV_FILE"
      
      # Verify removal
      if ! grep -q "^$country,$zip$" "$CSV_FILE"; then
        echo -e "${GREEN}✅ Market Removed Successfully: $country/$zip${RESET}"
        
        # Show updated market count
        local new_market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
        echo
        
        # STANDARDIZED: Results summary table
        printf "${BOLD}${YELLOW}%-20s %s${RESET}\n" "Removal Results" "Status"
        echo "------------------------------------"
        printf "%-20s %s\n" "Market Removed:" "${GREEN}$country/$zip${RESET}"
        printf "%-20s %s\n" "Remaining Markets:" "${CYAN}$new_market_count${RESET}"
        printf "%-20s %s\n" "Backup Created:" "${GREEN}$(basename "$backup_file")${RESET}"
        echo
        
        # STANDARDIZED: Next steps guidance
        echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
        if [ "$new_market_count" -gt 0 ]; then
          echo -e "${GREEN}• Your remaining markets are still configured for caching${RESET}"
          echo -e "${GREEN}• Cached stations from this market remain in your database${RESET}"
          echo -e "${GREEN}• Future caching will process only remaining markets${RESET}"
        else
          echo -e "${YELLOW}• No markets remain in configuration${RESET}"
          echo -e "${CYAN}• Add new markets to continue using User Cache Expansion${RESET}"
          echo -e "${CYAN}• Local Database Search still works with existing cached stations${RESET}"
        fi
        echo
        
        pause_for_user
        return 0
      else
        echo -e "${RED}❌ Market Removal Failed${RESET}"
        echo -e "${CYAN}💡 Market may not have been found or file may be read-only${RESET}"
        echo
        pause_for_user
        return 1
      fi
    else
      echo -e "${YELLOW}⚠️  Market removal cancelled${RESET}"
      echo -e "${CYAN}💡 Market configuration unchanged${RESET}"
      echo
      pause_for_user
      return 1
    fi
  else
    echo -e "${RED}❌ Market Not Found: $country/$zip${RESET}"
    echo
    
    # STANDARDIZED: Error analysis table
    echo -e "${BOLD}${BLUE}Troubleshooting Analysis:${RESET}"
    printf "${BOLD}${YELLOW}%-20s %s${RESET}\n" "Issue Category" "Suggestion"
    echo "--------------------------------------------"
    printf "%-20s %s\n" "Market Format:" "${CYAN}Check exact spelling and format${RESET}"
    printf "%-20s %s\n" "Case Sensitivity:" "${CYAN}Country codes are case-sensitive${RESET}"
    printf "%-20s %s\n" "ZIP Format:" "${CYAN}Check for spaces or formatting${RESET}"
    printf "%-20s %s\n" "Market List:" "${CYAN}Verify against table above${RESET}"
    echo
    
    echo -e "${CYAN}💡 This market is not in your current configuration${RESET}"
    echo -e "${CYAN}💡 Check the market list above for exact spelling and format${RESET}"
    echo
    pause_for_user
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

manage_markets() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Manage Television Markets ===${RESET}\n"
    
    # STANDARDIZED: Show workflow context with step indicators
    echo -e "${BLUE}📍 Step 1 of 3: Configure Geographic Markets${RESET}"
    echo -e "${YELLOW}Markets determine which regions' stations will be cached for User Cache Expansion.${RESET}"
    echo -e "${YELLOW}Stations from all configured markets will be deduplicated automatically.${RESET}"
    echo
    
    # STANDARDIZED: Enhanced workflow guidance
    echo -e "${BOLD}${BLUE}How Market Configuration Works:${RESET}"
    echo -e "${CYAN}1. Add markets (country + ZIP/postal code combinations)${RESET}"
    echo -e "${CYAN}2. Script queries TV lineup APIs for each market${RESET}"
    echo -e "${CYAN}3. Station data is downloaded and deduplicated${RESET}"
    echo -e "${CYAN}4. Local Database Search becomes available with full filtering${RESET}"
    echo
    
    # STANDARDIZED: Performance and planning tips
    echo -e "${BOLD}${BLUE}Planning Your Market Selection:${RESET}"
    echo -e "${GREEN}✅ Start Small:${RESET} Begin with 3-5 markets to test caching speed"
    echo -e "${GREEN}✅ Expand Gradually:${RESET} Add more markets later if needed"
    echo -e "${GREEN}✅ Consider Geography:${RESET} Nearby markets may have overlapping stations"
    echo -e "${YELLOW}⚠️  More Markets = Longer Caching Time${RESET} but broader station coverage"
    echo
    
    # STANDARDIZED: Current markets display with enhanced formatting and consistent table pattern
    echo -e "${BOLD}${BLUE}Current Market Configuration:${RESET}"
    if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
      local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
      echo -e "${GREEN}✅ Markets configured: $market_count${RESET}"
      echo
      
      # STANDARDIZED: Professional table formatting with consistent pattern
      printf "${BOLD}${YELLOW}%-12s %-15s %-12s %s${RESET}\n" "Country" "ZIP/Postal" "Status" "Notes"
      echo "---------------------------------------------------------------"
      
      local processed_countries=()
      awk -F, 'NR>1 {print $1}' "$CSV_FILE" 2>/dev/null | sort -u | while read -r country; do
        local first_country_entry=true
        grep "^$country," "$CSV_FILE" | while IFS=, read -r country zip; do
          local status=""
          local notes=""
          
          # Check market status
          if is_market_cached "$country" "$zip"; then
            status="${GREEN}Cached${RESET}"
            notes="Ready for search"
          elif check_market_in_base_cache "$country" "$zip" 2>/dev/null; then
            status="${YELLOW}In base${RESET}"
            notes="May be skipped"
          else
            status="${CYAN}Pending${RESET}"
            notes="Not cached yet"
          fi
          
          # STANDARDIZED: Show country name only for first entry with proper alignment
          if [ "$first_country_entry" = true ]; then
            printf "%-12s %-15s %-20s %s\n" "$country" "$zip" "$status" "$notes"
            first_country_entry=false
          else
            printf "%-12s %-15s %-20s %s\n" "" "$zip" "$status" "$notes"
          fi
        done
      done
      echo
      
      # STANDARDIZED: Summary statistics with corrected logic
      local user_cached_count=0
      local user_pending_count=0
      
      # Count only markets from the user's CSV that have been cached
      if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
        while IFS=, read -r csv_country csv_zip; do
          [[ "$csv_country" == "Country" ]] && continue
          if is_market_cached "$csv_country" "$csv_zip"; then
            ((user_cached_count++))
          else
            ((user_pending_count++))
          fi
        done < "$CSV_FILE"
        
        echo -e "${CYAN}📊 Status Summary: ${GREEN}$user_cached_count cached${RESET}, ${YELLOW}$user_pending_count pending${RESET}"
      else
        echo -e "${CYAN}📊 Status Summary: ${YELLOW}$market_count pending${RESET} (none cached yet)"
      fi
    else
      echo -e "${YELLOW}⚠️  No markets configured${RESET}"
      echo -e "${CYAN}💡 Add at least one market to enable User Cache Expansion${RESET}"
      echo -e "${CYAN}💡 Local Database Search works immediately with Base Station Database${RESET}"
    fi
    echo
    
    # STANDARDIZED: Options menu with enhanced descriptions
    echo -e "${BOLD}${CYAN}Market Management Options:${RESET}"
    echo -e "${GREEN}a)${RESET} Add Market - Configure new country/ZIP combination"
    echo -e "${GREEN}b)${RESET} Remove Market - Remove existing market from configuration"
    echo -e "${GREEN}c)${RESET} Import Markets from File - Bulk import from CSV file"
    echo -e "${GREEN}d)${RESET} Export Markets to File - Backup current configuration"
    echo -e "${GREEN}e)${RESET} Clean Up Postal Code Formats - Standardize existing entries"
    echo -e "${GREEN}f)${RESET} Force Refresh Market - Reprocess specific market (ignore base cache)"
    echo
    echo -e "${BOLD}${BLUE}Ready to Continue:${RESET}"
    echo -e "${GREEN}r)${RESET} Ready to Cache - Proceed to User Cache Expansion (Step 2 of 3)"
    echo
    echo -e "${GREEN}q)${RESET} Back to Main Menu"
    echo
    
    read -p "Select option: " choice < /dev/tty
    
    case $choice in
      a|A) 
        add_market && pause_for_user 
        ;;
      b|B) 
        remove_market && pause_for_user 
        ;;
      c|C) 
        import_markets && pause_for_user 
        ;;
      d|D) 
        export_markets && pause_for_user 
        ;;
      e|E) 
        cleanup_existing_postal_codes && pause_for_user 
        ;;
      f|F) 
        force_refresh_market && pause_for_user 
        ;;
      r|R)
        # STANDARDIZED: Ready to cache validation and transition
        local market_count
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
        
        if [[ "$market_count" -gt 0 ]]; then
          clear
          echo -e "${BOLD}${CYAN}=== Ready for User Cache Expansion ===${RESET}\n"
          echo -e "${GREEN}✅ Excellent! You have $market_count markets configured.${RESET}"
          echo
          
          # Show transition information
          echo -e "${BOLD}${BLUE}Next: User Cache Expansion (Step 2 of 3)${RESET}"
          echo -e "${CYAN}This will download and process stations from all configured markets:${RESET}"
          echo
          
          # Show what will happen
          echo -e "${BOLD}Caching Process Overview:${RESET}"
          echo -e "${CYAN}• Query TV lineup APIs for each of your $market_count markets${RESET}"
          echo -e "${CYAN}• Download station information for all found lineups${RESET}"
          echo -e "${CYAN}• Remove duplicate stations across markets${RESET}"
          echo -e "${CYAN}• Add stations to your personal User Station Database${RESET}"
          echo -e "${CYAN}• Enable full Local Database Search with filtering${RESET}"
          echo
          
          # Estimated time and resource info
          local estimated_min=$((market_count * 2))
          local estimated_max=$((market_count * 5))
          echo -e "${YELLOW}⏱️  Estimated time: $estimated_min-$estimated_max minutes${RESET}"
          echo -e "${YELLOW}📡 Estimated API calls: ~$((market_count * 3))${RESET}"
          echo -e "${CYAN}💡 Time varies based on server speed and market size${RESET}"
          echo
          
          if confirm_action "Proceed to User Cache Expansion?"; then
            echo -e "${CYAN}🔄 Transitioning to User Cache Expansion...${RESET}"
            pause_for_user
            run_user_caching
          else
            echo -e "${YELLOW}⚠️  Staying in Market Management${RESET}"
            pause_for_user
          fi
        else
          echo -e "\n${RED}❌ No Markets Configured${RESET}"
          echo -e "${CYAN}💡 Please add at least one market before proceeding to caching${RESET}"
          echo -e "${CYAN}💡 Use 'Add Market' to configure your first market${RESET}"
          echo
          
          if confirm_action "Add your first market now?"; then
            add_market
          fi
          pause_for_user
        fi
        ;;
      q|Q|"") 
        break 
        ;;
      *) 
        echo -e "${RED}❌ Invalid Option: '$choice'${RESET}"
        echo -e "${CYAN}💡 Please select a valid option from the menu${RESET}"
        sleep 2
        ;;
    esac
  done
}

# ============================================================================
# LOCAL CACHING FUNCTIONS
# ============================================================================

perform_caching() {
  # Check if server is configured for API operations - REQUIRED for user caching
  if [[ -z "${CHANNELS_URL:-}" ]]; then
    clear
    echo -e "${BOLD}${CYAN}=== User Cache Expansion ===${RESET}"
    echo -e "${BLUE}📍 Step 2 of 3: Build Local Station Database${RESET}"
    echo
    echo -e "${RED}❌ Channels DVR Integration: Server not configured${RESET}"
    echo -e "${CYAN}💡 User Cache Expansion requires a Channels DVR server to function${RESET}"
    echo -e "${CYAN}💡 The server provides access to lineup and station data APIs${RESET}"
    echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server${RESET}"
    echo
    echo -e "${BOLD}${CYAN}Why Channels DVR Server is Required:${RESET}"
    echo -e "${CYAN}• Fetch TV lineup data for your configured markets${RESET}"
    echo -e "${CYAN}• Download station information for each lineup${RESET}"
    echo -e "${CYAN}• Build your personal station database${RESET}"
    echo
    echo -e "${BOLD}${CYAN}Available Alternatives:${RESET}"
    echo -e "${GREEN}1)${RESET} Configure Channels DVR server to enable User Cache Expansion"
    echo -e "${GREEN}2)${RESET} Use Local Database Search with existing Base Station Database"
    echo -e "${GREEN}3)${RESET} Return to main menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1)
        echo -e "\n${CYAN}🔄 Opening Channels DVR server configuration...${RESET}"
        if configure_channels_server; then
          # Update config file
          sed -i "s|CHANNELS_URL=.*|CHANNELS_URL=\"$CHANNELS_URL\"|" "$CONFIG_FILE"
          echo -e "\n${GREEN}✅ Server configured successfully!${RESET}"
          echo -e "${CYAN}🔄 Starting User Cache Expansion...${RESET}"
          pause_for_user
          # Restart the function with server now configured
          perform_caching
        else
          echo -e "${YELLOW}⚠️  Server configuration cancelled${RESET}"
          echo -e "${CYAN}💡 User Cache Expansion requires Channels DVR server${RESET}"
        fi
        return
        ;;
      2)
        echo -e "\n${CYAN}🔄 User Cache Expansion cancelled${RESET}"
        echo -e "${CYAN}💡 You can use Local Database Search with existing stations${RESET}"
        return
        ;;
      3|"")
        echo -e "\n${CYAN}🔄 Returning to main menu${RESET}"
        return
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please try again.${RESET}"
        sleep 1
        perform_caching  # Restart function
        return
        ;;
    esac
  fi

  # Server is configured - proceed with user caching
  echo -e "${GREEN}✅ Channels DVR server configured: $CHANNELS_URL${RESET}"
  echo -e "${CYAN}🔗 Testing server connection...${RESET}"
  
  # Test server connection before starting caching process
  if ! curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null 2>&1; then
    echo -e "${RED}❌ Channels DVR Integration: Cannot connect to server${RESET}"
    echo -e "${CYAN}💡 Server: $CHANNELS_URL${RESET}"
    echo -e "${CYAN}💡 Verify Channels DVR server is running${RESET}"
    echo -e "${CYAN}💡 Check server IP address and port in Settings${RESET}"
    echo
    
    if ! confirm_action "Continue anyway? (caching will likely fail)"; then
      echo -e "${YELLOW}⚠️  User Cache Expansion cancelled${RESET}"
      return 1
    fi
  else
    echo -e "${GREEN}✅ Server connection confirmed${RESET}"
  fi

  echo -e "\n${CYAN}🔄 Starting user station cache build from configured markets...${RESET}"
  echo -e "${CYAN}💡 This will query your Channels DVR server to build your personal station database${RESET}"
  
  # Initialize user cache and state tracking
  init_user_cache
  init_cache_state_tracking
  
  # Clean up temporary files (but preserve user and base caches)
  echo -e "${CYAN}🧹 Preparing cache environment...${RESET}"
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log
  # Remove any legacy master JSON files during cleanup
  rm -f "$CACHE_DIR"/all_stations_master.json* "$CACHE_DIR"/working_stations.json* 2>/dev/null || true
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR"
  > "$LINEUP_CACHE"

  # Fetch lineups for each market WITH STATE TRACKING AND BASE CACHE CHECKING
  echo -e "\n${BOLD}${BLUE}Phase 1: Market Lineup Discovery${RESET}"
  echo -e "${CYAN}📊 Fetching TV lineups from configured markets...${RESET}"
  local markets_processed=0
  local markets_failed=0
  local total_markets=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
  
  while IFS=, read -r COUNTRY ZIP; do
    [[ "$COUNTRY" == "Country" ]] && continue
    ((markets_processed++))
    
    # Skip if force refresh is not active and this exact market is in base cache
    if [[ "$FORCE_REFRESH_ACTIVE" != "true" ]] && check_market_in_base_cache "$COUNTRY" "$ZIP"; then
      echo -e "${CYAN}📋 [$markets_processed/$total_markets] Skipping $COUNTRY/$ZIP (exact market in base cache)${RESET}"
      # Record as processed with 0 lineups to maintain state tracking
      record_market_processed "$COUNTRY" "$ZIP" 0
      continue
    fi

    if [[ "$FORCE_REFRESH_ACTIVE" == "true" ]]; then
      echo -e "${CYAN}🔄 [$markets_processed/$total_markets] Force refreshing $COUNTRY/$ZIP (ignoring base cache)${RESET}"
    else
      echo -e "${CYAN}📡 [$markets_processed/$total_markets] Querying lineups for $COUNTRY/$ZIP${RESET}"
    fi
    
    # API call with enhanced error handling
    local response
    response=$(curl -s --connect-timeout 10 --max-time 20 "$CHANNELS_URL/tms/lineups/$COUNTRY/$ZIP" 2>/dev/null)
    local curl_exit_code=$?
    
    # Handle API errors during caching
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for $COUNTRY/$ZIP:${RESET}"
      case $curl_exit_code in
        6)
          echo -e "${CYAN}💡 Could not resolve hostname - check server IP${RESET}"
          ;;
        7)
          echo -e "${CYAN}💡 Connection refused - verify server is running${RESET}"
          ;;
        28)
          echo -e "${CYAN}💡 Timeout - server may be slow${RESET}"
          ;;
        *)
          echo -e "${CYAN}💡 Connection failed (error $curl_exit_code)${RESET}"
          ;;
      esac
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
      echo -e "${CYAN}💡 Server returned non-JSON data${RESET}"
      ((markets_failed++))
      # Record market as processed with 0 lineups
      record_market_processed "$COUNTRY" "$ZIP" 0
    fi
  done < "$CSV_FILE"
  
  # Show market processing summary
  echo -e "\n${BOLD}${GREEN}✅ Market Processing Summary:${RESET}"
  echo -e "${GREEN}Markets processed: $markets_processed${RESET}"
  if [[ $markets_failed -gt 0 ]]; then
    echo -e "${RED}Markets failed: $markets_failed${RESET}"
    echo -e "${CYAN}💡 Failed markets may have connectivity issues${RESET}"
  fi

  # Process lineups WITH STATE TRACKING
  echo -e "\n${BOLD}${BLUE}Phase 2: Lineup Processing & Deduplication${RESET}"
  echo -e "${CYAN}📊 Processing and deduplicating TV lineups...${RESET}"
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
  
  echo -e "${CYAN}📋 Lineups before dedup: $pre_dedup_lineups${RESET}"
  echo -e "${CYAN}📋 Lineups after dedup: $post_dedup_lineups${RESET}"
  echo -e "${GREEN}✅ Duplicate lineups removed: $dup_lineups_removed${RESET}"

  # Fetch stations for each lineup WITH STATE TRACKING AND ERROR HANDLING
  echo -e "\n${BOLD}${BLUE}Phase 3: Station Data Collection${RESET}"
  echo -e "${CYAN}📡 Fetching station information from lineups...${RESET}"
  local lineups_processed=0
  local lineups_failed=0
  local total_lineups=$(wc -l < cache/unique_lineups.txt)
  
  while read LINEUP; do
    ((lineups_processed++))
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    
    echo -e "${CYAN}📡 [$lineups_processed/$total_lineups] Fetching stations for $LINEUP${RESET}"
    
    # API call with enhanced error handling
    local curl_response
    curl_response=$(curl -s --connect-timeout 10 --max-time 20 "$CHANNELS_URL/dvr/guide/stations/$LINEUP" 2>/dev/null)
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
      echo -e "${RED}❌ API Error for lineup $LINEUP:${RESET}"
      case $curl_exit_code in
        7)
          echo -e "${CYAN}💡 Connection refused - server may be busy${RESET}"
          ;;
        28)
          echo -e "${CYAN}💡 Timeout - large lineup may need more time${RESET}"
          ;;
        *)
          echo -e "${CYAN}💡 Connection failed (error $curl_exit_code)${RESET}"
          ;;
      esac
      ((lineups_failed++))
      record_lineup_processed "$LINEUP" "UNK" "UNK" 0
      continue
    fi
    
    echo "$curl_response" > "$station_file"
    
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
    if [ -f "$station_file" ] && echo "$curl_response" | jq empty 2>/dev/null; then
      stations_found=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
      echo -e "${GREEN}✅ Found $stations_found stations${RESET}"
    else
      echo -e "${RED}❌ Invalid JSON response for lineup $LINEUP${RESET}"
      ((lineups_failed++))
    fi
    
    record_lineup_processed "$LINEUP" "$country_code" "$source_zip" "$stations_found"
    
  done < cache/unique_lineups.txt
  
  # Show lineup processing summary
  echo -e "\n${BOLD}${GREEN}✅ Lineup Processing Summary:${RESET}"
  echo -e "${GREEN}Lineups processed: $lineups_processed${RESET}"
  if [[ $lineups_failed -gt 0 ]]; then
    echo -e "${RED}Lineups failed: $lineups_failed${RESET}"
    echo -e "${CYAN}💡 Failed lineups may have server connectivity issues${RESET}"
  fi

  # Process and deduplicate stations with country injection
  echo -e "\n${BOLD}${BLUE}Phase 4: Station Processing & Country Assignment${RESET}"
  echo -e "${CYAN}🔄 Processing stations and injecting country codes...${RESET}"
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
      
      echo -e "${CYAN}📋 Processing lineup $LINEUP (Country: $country_code)${RESET}"
      
      # Count stations before processing
      if echo "$station_file" | jq empty 2>/dev/null; then
        local lineup_count=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
        pre_dedup_stations=$((pre_dedup_stations + lineup_count))
        
        # Inject country code and source into each station
        jq --arg country "$country_code" --arg source "user" \
           'map(. + {country: $country, source: $source})' \
           "$station_file" >> "$temp_stations_file.tmp"
      fi
    fi
  done < cache/unique_lineups.txt

  # Now flatten, deduplicate, and sort
  echo -e "\n${BOLD}${BLUE}Phase 5: Final Deduplication & Organization${RESET}"
  echo -e "${CYAN}🔄 Combining and deduplicating station data...${RESET}"
  jq -s 'flatten | sort_by((.name // "") | length) | reverse | unique_by(.stationId)' "$temp_stations_file.tmp" \
    | jq 'map(.name = (.name // empty))' > "$temp_stations_file"

  # Clean up intermediate temp file
  rm -f "$temp_stations_file.tmp"

  local post_dedup_stations=$(jq length "$temp_stations_file")
  local dup_stations_removed=$((pre_dedup_stations - post_dedup_stations))
  
  echo -e "${CYAN}📋 Stations before dedup: $pre_dedup_stations${RESET}"
  echo -e "${CYAN}📋 Stations after dedup: $post_dedup_stations${RESET}"
  echo -e "${GREEN}✅ Duplicate stations removed: $dup_stations_removed${RESET}"

  # Enhancement phase with statistics capture
  echo -e "\n${BOLD}${BLUE}Phase 6: Station Data Enhancement${RESET}"
  echo -e "${CYAN}🔄 Enhancing station information...${RESET}"
  local enhanced_count
  enhanced_count=$(enhance_stations "$start_time" "$temp_stations_file")
  
  # Save to USER cache (merge with existing if present)
  echo -e "\n${BOLD}${BLUE}Phase 7: User Cache Integration${RESET}"
  echo -e "${CYAN}💾 Adding stations to user cache...${RESET}"
  
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

  show_user_caching_summary "$dup_lineups_removed" "$dup_stations_removed" "$human_duration" "$enhanced_count"
  
  # Clean up temporary files including our temp stations file
  cleanup_combined_cache
  rm -f "$temp_stations_file"
}

enhance_stations() {
  local start_time="$1"
  local stations_file="$2"  # The file to enhance (passed as parameter)
  
  echo -e "${CYAN}🔄 Starting station data enhancement process...${RESET}"
  local tmp_json="$CACHE_DIR/enhancement_tmp_$(date +%s).json"
  > "$tmp_json"

  mapfile -t stations < <(jq -c '.[]' "$stations_file")
  local total_stations=${#stations[@]}
  local enhanced_from_api=0

  echo -e "${CYAN}📊 Processing $total_stations stations for enhancement...${RESET}"
  
  for ((i = 0; i < total_stations; i++)); do
    local station="${stations[$i]}"
    local current=$((i + 1))
    local percent=$((current * 100 / total_stations))
    
    # STANDARDIZED: Show progress bar BEFORE processing
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
  
  # STANDARDIZED: Clear progress line and show completion
  echo
  echo -e "${GREEN}✅ Station enhancement completed successfully${RESET}"
  echo -e "${CYAN}📊 Enhanced $enhanced_from_api stations via API lookup${RESET}"
  
  # STANDARDIZED: File operation feedback
  echo -e "${CYAN}💾 Finalizing enhanced station data...${RESET}"
  mv "$tmp_json" "$stations_file"
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Enhanced station data saved successfully${RESET}"
  else
    echo -e "${RED}❌ Station Enhancement: Failed to save enhanced data${RESET}"
    echo -e "${CYAN}💡 Check disk space and file permissions${RESET}"
  fi

  # Return only the API enhancement count (no cache enhancement)
  echo "$enhanced_from_api"
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

show_user_caching_summary() {
  local dup_lineups_removed="$1"
  local dup_stations_removed="$2"
  local human_duration="$3"
  local enhanced_from_api="${4:-0}"
  
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
    echo "Stations Enhanced via API:  $enhanced_from_api"
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

# ============================================================================
# CACHE MANAGEMENT MENUS
# ============================================================================

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

show_detailed_cache_stats() {
  clear
  echo -e "${BOLD}${CYAN}=== Detailed Cache Statistics ===${RESET}\n"
  echo -e "${BLUE}📊 Comprehensive Analysis of Your Station Database and Cache System${RESET}"
  echo
  
  # STANDARDIZED: Station Database Analysis Section
  echo -e "${BOLD}${BLUE}=== Station Database Analysis ===${RESET}"
  
  local stations_file
  stations_file=$(get_effective_stations_file)
  if [ $? -eq 0 ]; then
    local total_stations=$(jq 'length' "$stations_file")
    
    echo -e "${GREEN}✅ Station Database: Active and accessible${RESET}"
    echo -e "${CYAN}📊 Total Stations: ${BOLD}$total_stations${RESET}"
    echo
    
    # STANDARDIZED: Quality Breakdown with visual indicators
    echo -e "${BOLD}${YELLOW}Quality Distribution:${RESET}"
    local hdtv_count=$(jq '[.[] | select(.videoQuality.videoType == "HDTV")] | length' "$stations_file")
    local sdtv_count=$(jq '[.[] | select(.videoQuality.videoType == "SDTV")] | length' "$stations_file")
    local uhdtv_count=$(jq '[.[] | select(.videoQuality.videoType == "UHDTV")] | length' "$stations_file")
    local unknown_quality=$(jq '[.[] | select(.videoQuality.videoType == null or .videoQuality.videoType == "")] | length' "$stations_file")
    
    if [ "$hdtv_count" -gt 0 ]; then
      local hdtv_percent=$((hdtv_count * 100 / total_stations))
      echo -e "  ${GREEN}📺 HDTV Stations: $hdtv_count (${hdtv_percent}%)${RESET} - High Definition"
    fi
    
    if [ "$sdtv_count" -gt 0 ]; then
      local sdtv_percent=$((sdtv_count * 100 / total_stations))
      echo -e "  ${YELLOW}📺 SDTV Stations: $sdtv_count (${sdtv_percent}%)${RESET} - Standard Definition"
    fi
    
    if [ "$uhdtv_count" -gt 0 ]; then
      local uhdtv_percent=$((uhdtv_count * 100 / total_stations))
      echo -e "  ${CYAN}📺 UHDTV Stations: $uhdtv_count (${uhdtv_percent}%)${RESET} - Ultra High Definition (4K)"
    fi
    
    if [ "$unknown_quality" -gt 0 ]; then
      local unknown_percent=$((unknown_quality * 100 / total_stations))
      echo -e "  ${RED}📺 Unknown Quality: $unknown_quality (${unknown_percent}%)${RESET}"
    fi
    echo
    
    # STANDARDIZED: Country Coverage Analysis
    echo -e "${BOLD}${YELLOW}Geographic Coverage:${RESET}"
    local countries=$(jq -r '[.[] | .country // "Unknown"] | unique | .[]' "$stations_file" 2>/dev/null)
    if [ -n "$countries" ]; then
      while read -r country; do
        if [[ -n "$country" && "$country" != "Unknown" && "$country" != "null" ]]; then
          local country_count=$(jq --arg c "$country" '[.[] | select((.country // "Unknown") == $c)] | length' "$stations_file")
          local country_percent=$((country_count * 100 / total_stations))
          
          # Country-specific icons and descriptions
          case "$country" in
            USA)
              echo -e "  ${GREEN}🇺🇸 United States: $country_count stations (${country_percent}%)${RESET}"
              ;;
            CAN)
              echo -e "  ${GREEN}🇨🇦 Canada: $country_count stations (${country_percent}%)${RESET}"
              ;;
            GBR)
              echo -e "  ${GREEN}🇬🇧 United Kingdom: $country_count stations (${country_percent}%)${RESET}"
              ;;
            DEU)
              echo -e "  ${GREEN}🇩🇪 Germany: $country_count stations (${country_percent}%)${RESET}"
              ;;
            FRA)
              echo -e "  ${GREEN}🇫🇷 France: $country_count stations (${country_percent}%)${RESET}"
              ;;
            *)
              echo -e "  ${CYAN}🌍 $country: $country_count stations (${country_percent}%)${RESET}"
              ;;
          esac
        fi
      done <<< "$countries"
      
      # Handle Unknown countries
      local unknown_countries=$(jq --arg c "Unknown" '[.[] | select((.country // "Unknown") == $c)] | length' "$stations_file")
      if [ "$unknown_countries" -gt 0 ]; then
        local unknown_percent=$((unknown_countries * 100 / total_stations))
        echo -e "  ${YELLOW}❓ Unknown/Unspecified: $unknown_countries stations (${unknown_percent}%)${RESET}"
      fi
    else
      echo -e "  ${RED}❌ No country information available${RESET}"
    fi
  else
    echo -e "${RED}❌ Station Database: Not accessible${RESET}"
    echo -e "${CYAN}💡 Expected: Base cache file ($(basename "$BASE_STATIONS_JSON")) in script directory${RESET}"
    echo -e "${CYAN}💡 Alternative: Build user cache via 'Manage Television Markets'${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: Cache Source Breakdown
  echo -e "${BOLD}${BLUE}=== Cache Source Analysis ===${RESET}"
  
  local breakdown=$(get_stations_breakdown)
  local base_count=$(echo "$breakdown" | cut -d' ' -f1)
  local user_count=$(echo "$breakdown" | cut -d' ' -f2)
  local total_count=$(get_total_stations_count)
  
  if [ "$base_count" -gt 0 ]; then
    local base_size=$(ls -lh "$BASE_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
    local base_percent=$((base_count * 100 / total_count))
    echo -e "${GREEN}✅ Base Station Cache: $base_count stations (${base_percent}%)${RESET}"
    echo -e "   ${CYAN}📁 File: $(basename "$BASE_STATIONS_JSON")${RESET}"
    echo -e "   ${CYAN}📊 Size: ${base_size:-"unknown"}${RESET}"
    echo -e "   ${CYAN}💡 Source: Distributed with script (comprehensive coverage)${RESET}"
  else
    echo -e "${RED}❌ Base Station Cache: Not found${RESET}"
    echo -e "   ${CYAN}📁 Expected: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
  fi
  
  if [ "$user_count" -gt 0 ]; then
    local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
    local user_percent=$((user_count * 100 / total_count))
    echo -e "${GREEN}✅ User Station Cache: $user_count stations (${user_percent}%)${RESET}"
    echo -e "   ${CYAN}📁 File: $(basename "$USER_STATIONS_JSON")${RESET}"
    echo -e "   ${CYAN}📊 Size: ${user_size:-"unknown"}${RESET}"
    echo -e "   ${CYAN}💡 Source: Built from your configured markets${RESET}"
  else
    echo -e "${YELLOW}⚠️  User Station Cache: Empty${RESET}"
    echo -e "   ${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: File System Breakdown
  echo -e "${BOLD}${BLUE}=== Cache File System Analysis ===${RESET}"
  
  if [ -d "$CACHE_DIR" ]; then
    echo -e "${GREEN}✅ Cache Directory: Active${RESET}"
    echo -e "   ${CYAN}📁 Location: $CACHE_DIR${RESET}"
    
    # Core cache files
    echo
    echo -e "${BOLD}${YELLOW}Core Cache Files:${RESET}"
    
    if [ -f "$BASE_STATIONS_JSON" ]; then
      local base_size=$(ls -lh "$BASE_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
      echo -e "  ${GREEN}📄 Base Station Cache: ${base_size:-"unknown"}${RESET}"
    else
      echo -e "  ${RED}📄 Base Station Cache: Missing${RESET}"
    fi
    
    if [ -f "$USER_STATIONS_JSON" ]; then
      local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
      echo -e "  ${GREEN}📄 User Station Cache: ${user_size:-"unknown"}${RESET}"
    else
      echo -e "  ${YELLOW}📄 User Station Cache: Not created${RESET}"
    fi
    
    if [ -f "$BASE_CACHE_MANIFEST" ]; then
      local manifest_size=$(ls -lh "$BASE_CACHE_MANIFEST" 2>/dev/null | awk '{print $5}')
      echo -e "  ${GREEN}📄 Base Cache Manifest: ${manifest_size:-"unknown"}${RESET}"
    else
      echo -e "  ${YELLOW}📄 Base Cache Manifest: Missing${RESET}"
    fi
    
    # State tracking files
    echo
    echo -e "${BOLD}${YELLOW}State Tracking Files:${RESET}"
    
    if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
      local markets_size=$(ls -lh "$CACHED_MARKETS" 2>/dev/null | awk '{print $5}')
      local markets_entries=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
      echo -e "  ${GREEN}📄 Market Tracking: ${markets_size:-"unknown"} ($markets_entries entries)${RESET}"
    else
      echo -e "  ${YELLOW}📄 Market Tracking: Empty${RESET}"
    fi
    
    if [ -f "$CACHED_LINEUPS" ] && [ -s "$CACHED_LINEUPS" ]; then
      local lineups_size=$(ls -lh "$CACHED_LINEUPS" 2>/dev/null | awk '{print $5}')
      local lineups_entries=$(jq -s 'length' "$CACHED_LINEUPS" 2>/dev/null || echo "0")
      echo -e "  ${GREEN}📄 Lineup Tracking: ${lineups_size:-"unknown"} ($lineups_entries entries)${RESET}"
    else
      echo -e "  ${YELLOW}📄 Lineup Tracking: Empty${RESET}"
    fi
    
    if [ -f "$LINEUP_TO_MARKET" ] && [ -s "$LINEUP_TO_MARKET" ]; then
      local mapping_size=$(ls -lh "$LINEUP_TO_MARKET" 2>/dev/null | awk '{print $5}')
      local mapping_entries=$(jq 'length' "$LINEUP_TO_MARKET" 2>/dev/null || echo "0")
      echo -e "  ${GREEN}📄 Lineup Mapping: ${mapping_size:-"unknown"} ($mapping_entries mappings)${RESET}"
    else
      echo -e "  ${YELLOW}📄 Lineup Mapping: Empty${RESET}"
    fi
    
    # Cache subdirectories
    echo
    echo -e "${BOLD}${YELLOW}Cache Subdirectories:${RESET}"
    
    if [ -d "$LOGO_DIR" ]; then
      local logo_count=$(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)
      local logo_size=$(du -sh "$LOGO_DIR" 2>/dev/null | cut -f1)
      if [ "$logo_count" -gt 0 ]; then
        echo -e "  ${GREEN}🖼️  Logo Cache: ${logo_size:-"unknown"} ($logo_count logos)${RESET}"
      else
        echo -e "  ${YELLOW}🖼️  Logo Cache: Empty${RESET}"
      fi
    else
      echo -e "  ${RED}🖼️  Logo Cache: Directory missing${RESET}"
    fi
    
    if [ -d "$BACKUP_DIR" ]; then
      local backup_count=$(find "$BACKUP_DIR" -name "*.backup.*" 2>/dev/null | wc -l)
      local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
      if [ "$backup_count" -gt 0 ]; then
        echo -e "  ${GREEN}💾 Backup Storage: ${backup_size:-"unknown"} ($backup_count backups)${RESET}"
      else
        echo -e "  ${YELLOW}💾 Backup Storage: Empty${RESET}"
      fi
    else
      echo -e "  ${RED}💾 Backup Storage: Directory missing${RESET}"
    fi
    
    if [ -d "$STATION_CACHE_DIR" ]; then
      local station_files=$(find "$STATION_CACHE_DIR" -name "*.json" 2>/dev/null | wc -l)
      local station_size=$(du -sh "$STATION_CACHE_DIR" 2>/dev/null | cut -f1)
      if [ "$station_files" -gt 0 ]; then
        echo -e "  ${GREEN}🗂️  Station Working Files: ${station_size:-"unknown"} ($station_files files)${RESET}"
      else
        echo -e "  ${YELLOW}🗂️  Station Working Files: Clean${RESET}"
      fi
    else
      echo -e "  ${RED}🗂️  Station Working Files: Directory missing${RESET}"
    fi
    
    # Temporary files analysis
    echo
    echo -e "${BOLD}${YELLOW}Temporary Files Analysis:${RESET}"
    local temp_count=$(find "$CACHE_DIR" -name "last_raw_*.json" 2>/dev/null | wc -l)
    local temp_size=$(find "$CACHE_DIR" -name "last_raw_*.json" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
    
    if [ "$temp_count" -gt 0 ]; then
      echo -e "  ${YELLOW}🗃️  API Response Files: ${temp_size} ($temp_count files)${RESET}"
      echo -e "     ${CYAN}💡 These can be safely cleaned up to free disk space${RESET}"
    else
      echo -e "  ${GREEN}🗃️  API Response Files: Clean${RESET}"
    fi
    
    # Total directory size
    echo
    local total_cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    echo -e "${BOLD}${CYAN}📊 Total Cache Directory Size: ${total_cache_size:-"unknown"}${RESET}"
    
  else
    echo -e "${RED}❌ Cache Directory: Not found${RESET}"
    echo -e "   ${CYAN}💡 Expected location: $CACHE_DIR${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: Market Configuration Analysis
  echo -e "${BOLD}${BLUE}=== Market Configuration Analysis ===${RESET}"
  
  if [ -f "$CSV_FILE" ]; then
    local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
    echo -e "${GREEN}✅ Market Configuration: Active${RESET}"
    echo -e "${CYAN}📊 Total Configured Markets: $market_count${RESET}"
    
    if [ "$market_count" -gt 0 ]; then
      echo
      echo -e "${BOLD}${YELLOW}Markets by Country:${RESET}"
      awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort | uniq -c | sort -rn | while read -r count country; do
        case "$country" in
          USA)
            echo -e "  ${GREEN}🇺🇸 United States: $count markets${RESET}"
            ;;
          CAN)
            echo -e "  ${GREEN}🇨🇦 Canada: $count markets${RESET}"
            ;;
          GBR)
            echo -e "  ${GREEN}🇬🇧 United Kingdom: $count markets${RESET}"
            ;;
          *)
            echo -e "  ${CYAN}🌍 $country: $count markets${RESET}"
            ;;
        esac
      done
    fi
  else
    echo -e "${YELLOW}⚠️  Market Configuration: No markets configured${RESET}"
    echo -e "   ${CYAN}💡 Configure markets via 'Manage Television Markets'${RESET}"
  fi
  
  echo
  
  # STANDARDIZED: Processing State Summary  
  echo -e "${BOLD}${BLUE}=== Processing State Summary ===${RESET}"
  show_cache_state_stats
  
  echo
  echo -e "${BOLD}${CYAN}=== System Status Summary ===${RESET}"
  
  # Simple, actionable status indicators
  if [ "$total_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Station Database: Ready for use ($total_count stations)${RESET}"
  else
    echo -e "${RED}❌ Station Database: No data available${RESET}"
    echo -e "   ${CYAN}💡 Use 'Manage Television Markets' → 'Run User Caching' to build database${RESET}"
  fi
  
  if [ -d "$CACHE_DIR" ] && [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✅ Cache System: Properly configured${RESET}"
  else
    echo -e "${RED}❌ Cache System: Configuration issues detected${RESET}"
  fi
  
  # Show cleanup recommendation if many temp files
  local temp_files=$(find "$CACHE_DIR" -name "*.tmp" -o -name "last_raw_*.json" 2>/dev/null | wc -l)
  if [ "$temp_files" -gt 20 ]; then
    echo -e "${YELLOW}💡 Maintenance: Consider cleaning $temp_files temporary files${RESET}"
    echo -e "   ${CYAN}Use 'Clear Temporary Files' to free disk space${RESET}"
  fi
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

advanced_cache_operations() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Advanced Cache Operations ===${RESET}\n"
    
    echo -e "${BOLD}${CYAN}Advanced Options:${RESET}"
    echo -e "${GREEN}1)${RESET} Refresh Specific Market (ZIP code)"
    echo -e "${GREEN}2)${RESET} Refresh Specific Lineup"
    echo -e "${GREEN}3)${RESET} Reset State Tracking"
    echo -e "${GREEN}4)${RESET} Rebuild Base Cache from User Cache"
    echo -e "${GREEN}5)${RESET} View Raw Cache Files"
    echo -e "${GREEN}6)${RESET} Validate Cache Integrity"
    echo -e "${GREEN}q)${RESET} Back to Cache Management"
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

cache_management_main_menu() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Local Cache Management ===${RESET}\n"
    
    # STANDARDIZED: Enhanced cache status display with consistent patterns
    local breakdown=$(get_stations_breakdown)
    local base_count=$(echo "$breakdown" | cut -d' ' -f1)
    local user_count=$(echo "$breakdown" | cut -d' ' -f2)
    local total_count=$(get_total_stations_count)
    
    echo -e "${BOLD}${BLUE}=== Current Cache Status ===${RESET}"
    
    # STANDARDIZED: Base Cache Status with clear indicators
    if [ "$base_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Base Station Database: $base_count stations${RESET}"
      echo -e "   ${CYAN}📁 File: $(basename "$BASE_STATIONS_JSON") (distributed cache)${RESET}"
      echo -e "   ${CYAN}📊 Coverage: Comprehensive USA, CAN, and GBR stations${RESET}"
    else
      echo -e "${RED}❌ Base Station Database: Not found${RESET}"
      echo -e "   ${YELLOW}📁 Expected: $(basename "$BASE_STATIONS_JSON") in script directory${RESET}"
      echo -e "   ${CYAN}💡 Contact script distributor for base database file${RESET}"
    fi
    
    # STANDARDIZED: User Cache Status with actionable information
    if [ "$user_count" -gt 0 ]; then
      echo -e "${GREEN}✅ User Station Database: $user_count stations${RESET}"
      echo -e "   ${CYAN}📁 File: $(basename "$USER_STATIONS_JSON") (your additions)${RESET}"
      
      # Show user cache health
      if [ -f "$USER_STATIONS_JSON" ]; then
        local user_size=$(ls -lh "$USER_STATIONS_JSON" 2>/dev/null | awk '{print $5}')
        echo -e "   ${CYAN}📊 Size: $user_size${RESET}"
      fi
    else
      echo -e "${YELLOW}⚠️  User Station Database: Empty${RESET}"
      echo -e "   ${CYAN}💡 Build via 'Manage Television Markets' → 'Run User Caching'${RESET}"
      echo -e "   ${CYAN}💡 Add custom markets to expand station coverage${RESET}"
    fi
    
    # STANDARDIZED: Combined Status Summary
    echo -e "${CYAN}📊 Total Available Stations: ${BOLD}$total_count${RESET}"
    
    # STANDARDIZED: Search Capability Status
    if [ "$total_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Local Database Search: Fully operational${RESET}"
      echo -e "   ${CYAN}💡 Search, filter, and browse all cached stations${RESET}"
    else
      echo -e "${RED}❌ Local Database Search: No station data available${RESET}"
      echo -e "   ${CYAN}💡 Build station database to enable search features${RESET}"
    fi
    
    echo
    
    # STANDARDIZED: Cache Processing State with visual indicators
    echo -e "${BOLD}${BLUE}=== Processing State ===${RESET}"
    
    # FIXED: Show market configuration status with proper numeric validation
    local market_count=0
    local cached_markets=0
    local pending_markets=0
    
    if [ -f "$CSV_FILE" ]; then
      market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
      # FIXED: Ensure market_count is numeric
      [[ "$market_count" =~ ^[0-9]+$ ]] || market_count=0
    fi
    
    # FIXED: Always calculate cached_markets and pending_markets regardless of market_count
    if [ -f "$CACHED_MARKETS" ] && [ -s "$CACHED_MARKETS" ]; then
      cached_markets=$(jq -s 'length' "$CACHED_MARKETS" 2>/dev/null || echo "0")
      # FIXED: Ensure cached_markets is numeric
      [[ "$cached_markets" =~ ^[0-9]+$ ]] || cached_markets=0
    fi
    # FIXED: Safe arithmetic with validated numeric values (always available)
    pending_markets=$((market_count - cached_markets))
    
    if [ "$market_count" -gt 0 ]; then
      echo -e "${GREEN}✅ Market Configuration: $market_count markets configured${RESET}"
      
      if [ "$cached_markets" -gt 0 ]; then
        echo -e "   ${GREEN}📊 Cached Markets: $cached_markets${RESET}"
      fi
      if [ "$pending_markets" -gt 0 ]; then
        echo -e "   ${YELLOW}📊 Pending Markets: $pending_markets${RESET}"
        echo -e "   ${CYAN}💡 Use 'Incremental Update' to process pending markets${RESET}"
      fi
    else
      echo -e "${YELLOW}⚠️  Market Configuration: No markets configured${RESET}"
      echo -e "   ${CYAN}💡 Configure markets via 'Manage Television Markets'${RESET}"
    fi
    
    # STANDARDIZED: Cache Health Indicators
    echo
    echo -e "${BOLD}${BLUE}=== Cache Health ===${RESET}"
    
    # Total cache directory size
    if [ -d "$CACHE_DIR" ]; then
      local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
      echo -e "${CYAN}📊 Total Cache Size: $cache_size${RESET}"
      
      # Count different types of cache files
      local temp_count=$(find "$CACHE_DIR" -name "last_raw_*.json" 2>/dev/null | wc -l)
      local logo_count=$(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)
      local backup_count=$(find "$BACKUP_DIR" -name "*.backup.*" 2>/dev/null | wc -l)
      
      if [ "$temp_count" -gt 0 ]; then
        echo -e "${YELLOW}📊 Temporary Files: $temp_count${RESET} ${CYAN}(consider cleanup)${RESET}"
      else
        echo -e "${GREEN}📊 Temporary Files: Clean${RESET}"
      fi
      
      if [ "$logo_count" -gt 0 ]; then
        echo -e "${GREEN}📊 Logo Cache: $logo_count logos${RESET}"
      else
        echo -e "${CYAN}📊 Logo Cache: Empty${RESET}"
      fi
      
      if [ "$backup_count" -gt 0 ]; then
        echo -e "${GREEN}📊 Backup Files: $backup_count backups${RESET}"
      else
        echo -e "${CYAN}📊 Backup Files: None${RESET}"
      fi
    else
      echo -e "${RED}❌ Cache Directory: Not found${RESET}"
      echo -e "   ${CYAN}💡 Directory: $CACHE_DIR${RESET}"
    fi
    
    # STANDARDIZED: Last Activity Indicator
    if [ -f "$CACHE_STATE_LOG" ] && [ -s "$CACHE_STATE_LOG" ]; then
      local last_activity=$(tail -1 "$CACHE_STATE_LOG" 2>/dev/null | cut -d' ' -f1-2)
      if [ -n "$last_activity" ]; then
        echo -e "${CYAN}📊 Last Cache Activity: $last_activity${RESET}"
      fi
    fi
    
    echo
    
    # STANDARDIZED: Operations Menu with consistent formatting
    echo -e "${BOLD}${CYAN}=== Cache Management Operations ===${RESET}"
    echo -e "${GREEN}a)${RESET} Incremental Update ${CYAN}(add new markets only)${RESET}"
    echo -e "${GREEN}b)${RESET} Full User Cache Refresh ${CYAN}(rebuild entire user cache)${RESET}"
    echo -e "${GREEN}c)${RESET} View Cache Statistics ${CYAN}(detailed breakdown)${RESET}"
    echo -e "${GREEN}d)${RESET} Export Combined Database to CSV ${CYAN}(backup/external use)${RESET}"
    echo -e "${GREEN}e)${RESET} Clear User Cache ${CYAN}(remove custom stations)${RESET}"
    echo -e "${GREEN}f)${RESET} Clear Temporary Files ${CYAN}(cleanup disk space)${RESET}"
    echo -e "${GREEN}g)${RESET} Advanced Cache Operations ${CYAN}(developer tools)${RESET}"
    echo -e "${GREEN}q)${RESET} Back to Main Menu"
    echo
    
    # STANDARDIZED: Smart recommendations based on status
    if [ "$total_count" -eq 0 ] && [ "$market_count" -eq 0 ]; then
      echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
      echo -e "${CYAN}   1. First: Use 'Manage Television Markets' from main menu${RESET}"
      echo -e "${CYAN}   2. Then: Return here for 'Incremental Update'${RESET}"
      echo
    elif [ "$total_count" -eq 0 ] && [ "$market_count" -gt 0 ]; then
      echo -e "${BOLD}${YELLOW}💡 Quick Start Recommendation:${RESET}"
      echo -e "${CYAN}   Try option 'a' Incremental Update to build your station database${RESET}"
      echo
    elif [ "$pending_markets" -gt 0 ]; then
      echo -e "${BOLD}${YELLOW}💡 Recommendation:${RESET}"
      echo -e "${CYAN}   You have $pending_markets unprocessed markets - try 'a' Incremental Update${RESET}"
      echo
    fi
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) 
        echo -e "${CYAN}🔄 Starting incremental cache update...${RESET}"
        run_incremental_update && pause_for_user 
        ;;
      b|B) 
        echo -e "${CYAN}🔄 Starting full user cache refresh...${RESET}"
        run_full_user_refresh && pause_for_user 
        ;;
      c|C) 
        echo -e "${CYAN}📊 Loading detailed cache statistics...${RESET}"
        show_detailed_cache_stats && pause_for_user 
        ;;
      d|D) 
        echo -e "${CYAN}📤 Starting database export...${RESET}"
        export_stations_to_csv && pause_for_user 
        ;;
      e|E) 
        echo -e "${CYAN}🗑️  Opening user cache management...${RESET}"
        clear_user_cache && pause_for_user 
        ;;
      f|F) 
        echo -e "${CYAN}🧹 Starting temporary file cleanup...${RESET}"
        clear_temp_files && pause_for_user 
        ;;
      g|G) 
        echo -e "${CYAN}🔧 Opening advanced cache operations...${RESET}"
        advanced_cache_operations 
        ;;
      q|Q|"") 
        echo -e "${CYAN}🔄 Returning to main menu...${RESET}"
        break 
        ;;
      *) 
        echo -e "${RED}❌ Invalid Option: '$choice'${RESET}"
        echo -e "${CYAN}💡 Please select a valid option from the menu${RESET}"
        sleep 2
        ;;
    esac
  done
}

# ============================================================================
# SETTINGS MANAGEMENT FUNCTIONS
# ============================================================================

process_channels_missing_fields() {
  local channels_data="$1"
  
  echo -e "\n${BOLD}${CYAN}=== Filter Channels by Missing Fields ===${RESET}"
  echo -e "${YELLOW}Select which type of missing field to target:${RESET}"
  echo
  echo -e "${GREEN}1)${RESET} Missing Channel Names - Empty or generic names like 'Channel 123'"
  echo -e "   ${CYAN}✓ Improves channel identification${RESET}"
  echo -e "   ${CYAN}✓ Replaces generic names with official station names${RESET}"
  echo
  echo -e "${GREEN}2)${RESET} Missing TVG-ID - Empty TVG-ID fields"
  echo -e "   ${CYAN}✓ Enables proper EPG matching${RESET}"
  echo -e "   ${CYAN}✓ Sets call signs for guide data correlation${RESET}"
  echo
  echo -e "${GREEN}3)${RESET} Missing TVC Guide Station ID - Empty station ID fields"
  echo -e "   ${CYAN}✓ Enables comprehensive guide data${RESET}"
  echo -e "   ${CYAN}✓ Links channels to station information${RESET}"
  echo
  echo -e "${GREEN}4)${RESET} Missing Any of the Above - Channels with any missing field"
  echo -e "   ${CYAN}✓ Comprehensive cleanup approach${RESET}"
  echo -e "   ${CYAN}✓ Addresses all field gaps systematically${RESET}"
  echo
  
  read -p "Select filter criteria: " filter_choice
  
  local filtered_channels
  case "$filter_choice" in
    1)
      echo -e "${CYAN}🔍 Filtering for channels with missing or generic names...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.name == "" or .name == null or (.name | test("Channel [0-9]+")))')
      ;;
    2)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVG-ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvg_id == "" or .tvg_id == null)')
      ;;
    3)
      echo -e "${CYAN}🔍 Filtering for channels with missing TVC Guide Station ID...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(.tvc_guide_stationid == "" or .tvc_guide_stationid == null)')
      ;;
    4)
      echo -e "${CYAN}🔍 Filtering for channels with any missing fields...${RESET}"
      filtered_channels=$(echo "$channels_data" | jq -c '.[] | select(
        (.name == "" or .name == null or (.name | test("Channel [0-9]+"))) or
        (.tvg_id == "" or .tvg_id == null) or
        (.tvc_guide_stationid == "" or .tvc_guide_stationid == null)
      )')
      ;;
    *)
      echo -e "${RED}❌ Invalid selection${RESET}"
      sleep 1
      return 1
      ;;
  esac
  
  if [[ -z "$filtered_channels" ]]; then
    echo -e "${GREEN}✅ No channels found matching the selected criteria${RESET}"
    echo -e "${CYAN}💡 All channels already have the requested field data${RESET}"
    echo -e "${CYAN}💡 Try a different filter or use 'Process All Channels'${RESET}"
    pause_for_user
    return 0
  fi
  
  echo -e "${CYAN}📋 Sorting filtered channels by channel number (lowest to highest)...${RESET}"
  
  # Sort filtered channels by .channel_number (lowest to highest) - explicit numeric sort
  local sorted_filtered_channels
  sorted_filtered_channels=$(echo "$filtered_channels" | jq -s 'sort_by(.channel_number | tonumber)')
  
  mapfile -t filtered_array < <(echo "$sorted_filtered_channels" | jq -c '.[]')
  local filtered_count=${#filtered_array[@]}
  
  echo -e "${GREEN}✅ Found $filtered_count channels matching criteria (sorted by channel number)${RESET}"
  echo -e "${CYAN}💡 Processing in channel number order for systematic coverage${RESET}"
  echo
  
  # STANDARDIZED: Show preview of filtered channels with professional table
  if [ "$filtered_count" -gt 0 ]; then
    echo -e "${BOLD}${BLUE}Preview of Filtered Channels:${RESET}"
    echo
    
    # STANDARDIZED: Professional table header with consistent formatting
    printf "${BOLD}${YELLOW}%-6s %-8s %-25s %-15s %-10s %-10s %s${RESET}\n" "Number" "Ch ID" "Channel Name" "Group" "TVG-ID" "Station" "Issues"
    echo "--------------------------------------------------------------------------------"
    
    # Show first 10 channels as preview
    local preview_count=$((filtered_count > 10 ? 10 : filtered_count))
    for ((i = 0; i < preview_count; i++)); do
      local channel_data="${filtered_array[$i]}"
      local channel_id=$(echo "$channel_data" | jq -r '.id')
      local channel_name=$(echo "$channel_data" | jq -r '.name // "Unnamed"')
      local channel_number=$(echo "$channel_data" | jq -r '.channel_number // "N/A"')
      local channel_group=$(echo "$channel_data" | jq -r '.channel_group_id // "Ungrouped"')
      local tvg_id=$(echo "$channel_data" | jq -r '.tvg_id // ""')
      local tvc_stationid=$(echo "$channel_data" | jq -r '.tvc_guide_stationid // ""')
      
      # Analyze issues for this channel
      local issues=""
      if [[ -z "$channel_name" || "$channel_name" == "null" || "$channel_name" =~ Channel\ [0-9]+ ]]; then
        issues+="Name "
      fi
      if [[ -z "$tvg_id" || "$tvg_id" == "null" ]]; then
        issues+="TVG "
      fi
      if [[ -z "$tvc_stationid" || "$tvc_stationid" == "null" ]]; then
        issues+="StID "
      fi
      
      # STANDARDIZED: Table row with consistent formatting
      printf "%-6s %-8s %-25s %-15s %-10s %-10s %s\n" \
        "$channel_number" \
        "$channel_id" \
        "${channel_name:0:25}" \
        "${channel_group:0:15}" \
        "${tvg_id:0:10}" \
        "${tvc_stationid:0:10}" \
        "${RED}$issues${RESET}"
    done
    
    if [ "$filtered_count" -gt 10 ]; then
      echo "..."
      echo -e "${CYAN}... and $((filtered_count - 10)) more channels${RESET}"
    fi
    echo
    
    # STANDARDIZED: Summary statistics table
    echo -e "${BOLD}${BLUE}Filter Results Summary:${RESET}"
    printf "${BOLD}${YELLOW}%-25s %s${RESET}\n" "Statistics" "Count"
    echo "------------------------------------"
    printf "%-25s %s\n" "Total channels matched:" "${GREEN}$filtered_count${RESET}"
    printf "%-25s %s\n" "Filter criteria:" "$(case "$filter_choice" in 1) echo "Missing Names" ;; 2) echo "Missing TVG-ID" ;; 3) echo "Missing Station ID" ;; 4) echo "Any Missing Fields" ;; esac)"
    printf "%-25s %s\n" "Processing order:" "${CYAN}By channel number${RESET}"
    echo
  fi
  
  if ! confirm_action "Process these $filtered_count filtered channels?"; then
    echo -e "${YELLOW}⚠️  Filtered processing cancelled${RESET}"
    return 0
  fi
  
  for ((i = 0; i < filtered_count; i++)); do
    local channel_data="${filtered_array[$i]}"
    
    echo -e "${BOLD}${BLUE}=== Filtered Channel $((i + 1)) of $filtered_count ===${RESET}"
    
    process_single_channel_fields "$channel_data" $((i + 1)) "$filtered_count"
    
    if [[ $((i + 1)) -lt $filtered_count ]]; then
      echo
      echo -e "${BOLD}Continue Processing Filtered Channels?${RESET}"
      echo -e "Completed: $((i + 1)) of $filtered_count filtered channels"
      echo -e "Remaining: $((filtered_count - i - 1)) channels"
      echo
      
      if ! confirm_action "Continue to next filtered channel?"; then
        echo -e "${YELLOW}⚠️  Filtered processing stopped by user${RESET}"
        break
      fi
    fi
  done
  
  echo -e "\n${GREEN}✅ Filtered field population completed${RESET}"
  echo -e "${CYAN}💡 All matching channels have been processed${RESET}"
  pause_for_user
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
  if [[ ! "$new_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ "$new_ip" != "localhost" ]]; then
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
  clear
  echo -e "${BOLD}${CYAN}=== Logo Display Configuration ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Station Logo Previews${RESET}"
  echo -e "${YELLOW}Logo display shows station logos during search results and station details.${RESET}"
  echo
  
  # Check viu dependency
  if ! command -v viu &> /dev/null; then
    echo -e "${RED}❌ Logo Display: Dependency missing${RESET}"
    echo -e "${CYAN}💡 Logo display requires the 'viu' terminal image viewer${RESET}"
    echo
    
    echo -e "${BOLD}${BLUE}How to Install viu:${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}Option 1 - Rust/Cargo (Recommended):${RESET}"
    echo -e "${CYAN}cargo install viu${RESET}"
    echo
    echo -e "${BOLD}${YELLOW}Option 2 - Package Manager:${RESET}"
    echo -e "${CYAN}# Ubuntu/Debian:${RESET}"
    echo -e "${CYAN}sudo apt install viu${RESET}"
    echo
    echo -e "${CYAN}# macOS (Homebrew):${RESET}"
    echo -e "${CYAN}brew install viu${RESET}"
    echo
    echo -e "${CYAN}# Arch Linux:${RESET}"
    echo -e "${CYAN}sudo pacman -S viu${RESET}"
    echo
    echo -e "${BOLD}${CYAN}After Installation:${RESET}"
    echo -e "${CYAN}💡 Return to this menu to enable logo display${RESET}"
    echo -e "${CYAN}💡 Logos will appear in search results and station details${RESET}"
    echo -e "${CYAN}💡 Works best with terminals that support true color${RESET}"
    echo
    
    pause_for_user
    return 1
  fi
  
  # viu is available - show current status and toggle options
  echo -e "${GREEN}✅ Logo Display: viu dependency available${RESET}"
  echo
  
  echo -e "${BOLD}${BLUE}Current Configuration:${RESET}"
  if [ "$SHOW_LOGOS" = "true" ]; then
    echo -e "${GREEN}✅ Logo Display: Enabled${RESET}"
    echo -e "${CYAN}💡 Station logos will appear in search results and details${RESET}"
    echo -e "${CYAN}💡 Logos are cached locally for faster display${RESET}"
  else
    echo -e "${YELLOW}⚠️  Logo Display: Disabled${RESET}"
    echo -e "${CYAN}💡 Search results will show text-only station information${RESET}"
    echo -e "${CYAN}💡 Enable to see visual station logos during searches${RESET}"
  fi
  echo
  
  echo -e "${BOLD}${BLUE}Logo Display Features:${RESET}"
  echo -e "${GREEN}• Visual station identification during searches${RESET}"
  echo -e "${GREEN}• Automatic logo downloading and caching${RESET}"
  echo -e "${GREEN}• Optimized display size for terminal viewing${RESET}"
  echo -e "${GREEN}• Works with Local Database Search and API Search${RESET}"
  echo
  
  # Toggle confirmation
  if [ "$SHOW_LOGOS" = "true" ]; then
    if confirm_action "Disable logo display?"; then
      SHOW_LOGOS=false
      echo -e "${YELLOW}⚠️  Logo display disabled${RESET}"
      echo -e "${CYAN}💡 Search results will show text-only information${RESET}"
    else
      echo -e "${CYAN}💡 Logo display remains enabled${RESET}"
    fi
  else
    if confirm_action "Enable logo display?"; then
      SHOW_LOGOS=true
      echo -e "${GREEN}✅ Logo display enabled${RESET}"
      echo -e "${CYAN}💡 Station logos will now appear during search results${RESET}"
      echo -e "${CYAN}💡 First logo display may take a moment to download and cache${RESET}"
    else
      echo -e "${CYAN}💡 Logo display remains disabled${RESET}"
    fi
  fi
  
  # Update config file
  sed -i "s/SHOW_LOGOS=.*/SHOW_LOGOS=$SHOW_LOGOS/" "$CONFIG_FILE"
  echo -e "${GREEN}✅ Configuration saved${RESET}"
  
  return 0
}

configure_resolution_filter() {
  clear
  echo -e "${BOLD}${CYAN}=== Resolution Filter Configuration ===${RESET}\n"
  echo -e "${BLUE}📍 Configure Search Resolution Filtering${RESET}"
  echo -e "${YELLOW}Resolution filtering limits search results to specific video quality levels.${RESET}"
  echo -e "${CYAN}This helps focus on channels that match your viewing preferences.${RESET}"
  echo
  
  # STANDARDIZED: Show current configuration with detailed status
  echo -e "${BOLD}${BLUE}Current Configuration:${RESET}"
  if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    echo -e "Status: ${GREEN}Enabled${RESET}"
    echo -e "Active Filters: ${YELLOW}$ENABLED_RESOLUTIONS${RESET}"
    echo -e "Effect: ${CYAN}Search results show only stations with selected quality levels${RESET}"
  else
    echo -e "Status: ${YELLOW}Disabled${RESET}"
    echo -e "Active Filters: ${CYAN}None${RESET}"
    echo -e "Effect: ${CYAN}Search results show stations of all quality levels${RESET}"
  fi
  echo
  
  # STANDARDIZED: Resolution quality guide with detailed explanations
  echo -e "${BOLD}${BLUE}Video Quality Levels Explained:${RESET}"
  echo
  echo -e "${GREEN}SDTV${RESET} - Standard Definition Television"
  echo -e "${CYAN}  • Resolution: 480i/480p (720x480)${RESET}"
  echo
  echo -e "${GREEN}HDTV${RESET} - High Definition Television"
  echo -e "${CYAN}  • Resolution: 720p (1280x720) or 1080i/1080p (1920x1080)${RESET}"
  echo
  echo -e "${GREEN}UHDTV${RESET} - Ultra High Definition Television (4K)"
  echo -e "${CYAN}  • Resolution: 2160p (3840x2160)${RESET}"
  echo
  
  # STANDARDIZED: Enable/disable decision with clear guidance
  echo -e "${BOLD}Step 1: Resolution Filter Mode${RESET}"
  echo -e "${CYAN}💡 Enable to filter search results by video quality${RESET}"
  echo -e "${CYAN}💡 Disable to see all stations regardless of quality${RESET}"
  echo
  
  if confirm_action "Enable resolution filtering?"; then
    FILTER_BY_RESOLUTION=true
    echo -e "${GREEN}✅ Resolution filtering enabled${RESET}"
    echo
    
    # STANDARDIZED: Multi-selection with comprehensive validation
    echo -e "${BOLD}Step 2: Quality Level Selection${RESET}"
    echo -e "${CYAN}💡 Select one or more quality levels to include in search results${RESET}"
    echo -e "${CYAN}💡 Multiple selections give you broader coverage${RESET}"
    echo -e "${CYAN}💡 Single selections focus on specific quality${RESET}"
    echo
    
    echo -e "${BOLD}Available Resolution Options:${RESET}"
    echo -e "${GREEN}1)${RESET} SDTV - Standard Definition (480i/480p)"
    echo -e "${GREEN}2)${RESET} HDTV - High Definition (720p/1080i/1080p)"
    echo -e "${GREEN}3)${RESET} UHDTV - Ultra High Definition (4K/2160p)"
    echo
    echo -e "${BOLD}Selection Methods:${RESET}"
    echo -e "${CYAN}• Individual: Enter numbers separated by spaces (e.g., '1 2' for SDTV+HDTV)${RESET}"
    echo -e "${CYAN}• Names: Enter resolution names separated by spaces (e.g., 'SDTV HDTV')${RESET}"
    echo -e "${CYAN}• All: Enter 'all' to include all quality levels${RESET}"
    echo
    
    local selected_resolutions valid_resolutions=""
    
    while true; do
      read -p "Select resolutions (numbers, names, or 'all'): " selected_resolutions < /dev/tty
      
      if [[ -z "$selected_resolutions" ]]; then
        echo -e "${RED}❌ No selection made${RESET}"
        echo -e "${CYAN}💡 You must select at least one resolution level${RESET}"
        continue
      fi
      
      # Normalize input
      selected_resolutions=$(echo "$selected_resolutions" | tr '[:lower:]' '[:upper:]')
      
      # Handle 'ALL' selection
      if [[ "$selected_resolutions" =~ ALL ]]; then
        valid_resolutions="SDTV,HDTV,UHDTV"
        echo -e "${GREEN}✅ All resolution levels selected: SDTV, HDTV, UHDTV${RESET}"
        break
      fi
      
      # STANDARDIZED: Process individual selections with validation
      local selections_array=($selected_resolutions)
      local temp_valid=""
      local invalid_selections=""
      
      for selection in "${selections_array[@]}"; do
        case "$selection" in
          1|SDTV)
            if [[ ! "$temp_valid" =~ SDTV ]]; then
              temp_valid+="SDTV,"
            fi
            ;;
          2|HDTV)
            if [[ ! "$temp_valid" =~ HDTV ]]; then
              temp_valid+="HDTV,"
            fi
            ;;
          3|UHDTV)
            if [[ ! "$temp_valid" =~ UHDTV ]]; then
              temp_valid+="UHDTV,"
            fi
            ;;
          *)
            invalid_selections+="$selection "
            ;;
        esac
      done
      
      # STANDARDIZED: Validation results with helpful feedback
      if [[ -n "$invalid_selections" ]]; then
        echo -e "${RED}❌ Invalid selections ignored: $invalid_selections${RESET}"
        echo -e "${CYAN}💡 Valid options: 1/SDTV, 2/HDTV, 3/UHDTV, or 'all'${RESET}"
      fi
      
      if [[ -n "$temp_valid" ]]; then
        valid_resolutions="${temp_valid%,}"  # Remove trailing comma
        echo -e "${GREEN}✅ Valid resolution levels selected: $valid_resolutions${RESET}"
        
        # Show what this selection means
        echo
        echo -e "${BOLD}${BLUE}Your Selection Impact:${RESET}"
        IFS=',' read -ra RESOLUTION_LIST <<< "$valid_resolutions"
        for res in "${RESOLUTION_LIST[@]}"; do
          case "$res" in
            SDTV)
              echo -e "${CYAN}• SDTV: Standard definition channels will be included${RESET}"
              ;;
            HDTV)
              echo -e "${CYAN}• HDTV: High definition channels will be included${RESET}"
              ;;
            UHDTV)
              echo -e "${CYAN}• UHDTV: Ultra-high definition (4K) channels will be included${RESET}"
              ;;
          esac
        done
        echo -e "${CYAN}• Channels with other quality levels will be hidden from search results${RESET}"
        echo
        
        if confirm_action "Confirm these resolution filter settings?"; then
          break
        else
          echo -e "${CYAN}💡 Try a different selection${RESET}"
          echo
        fi
      else
        echo -e "${RED}❌ No valid resolution levels selected${RESET}"
        echo -e "${CYAN}💡 You must select at least one valid option${RESET}"
        echo
      fi
    done
    
    ENABLED_RESOLUTIONS="$valid_resolutions"
    
  else
    FILTER_BY_RESOLUTION=false
    ENABLED_RESOLUTIONS="SDTV,HDTV,UHDTV"  # Reset to all when disabled
    echo -e "${YELLOW}⚠️  Resolution filtering disabled${RESET}"
    echo -e "${CYAN}💡 Search results will show stations of all quality levels${RESET}"
  fi
  
  # STANDARDIZED: Save configuration with feedback
  echo
  echo -e "${CYAN}💾 Saving resolution filter configuration...${RESET}"
  
  # Update config file with error handling
  local temp_config="${CONFIG_FILE}.tmp"
  if grep -v -E '^FILTER_BY_RESOLUTION=|^ENABLED_RESOLUTIONS=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null; then
    {
      echo "FILTER_BY_RESOLUTION=$FILTER_BY_RESOLUTION"
      echo "ENABLED_RESOLUTIONS=\"$ENABLED_RESOLUTIONS\""
    } >> "$temp_config"
    
    if mv "$temp_config" "$CONFIG_FILE"; then
      echo -e "${GREEN}✅ Configuration saved successfully${RESET}"
    else
      echo -e "${RED}❌ Configuration Save: Failed to save settings${RESET}"
      echo -e "${CYAN}💡 Check file permissions for: $CONFIG_FILE${RESET}"
      rm -f "$temp_config" 2>/dev/null
    fi
  else
    echo -e "${RED}❌ Configuration Save: Cannot read current config${RESET}"
    echo -e "${CYAN}💡 Check file permissions and try again${RESET}"
  fi
  
  # STANDARDIZED: Show final configuration summary
  echo
  echo -e "${BOLD}${GREEN}=== Resolution Filter Summary ===${RESET}"
  echo -e "Status: $([ "$FILTER_BY_RESOLUTION" = "true" ] && echo -e "${GREEN}Enabled${RESET}" || echo -e "${YELLOW}Disabled${RESET}")"
  
  if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
    echo -e "Active Filters: ${GREEN}$ENABLED_RESOLUTIONS${RESET}"
    echo
    echo -e "${BOLD}${CYAN}What This Means:${RESET}"
    echo -e "${CYAN}• Local Database Search will only show stations with selected quality levels${RESET}"
    echo -e "${CYAN}• Stations with other quality levels will be filtered out${RESET}"
    echo -e "${CYAN}• You can disable filtering anytime to see all stations${RESET}"
    echo -e "${CYAN}• Filter applies to search results, not your cached station data${RESET}"
  else
    echo
    echo -e "${BOLD}${CYAN}What This Means:${RESET}"
    echo -e "${CYAN}• Local Database Search will show stations of all quality levels${RESET}"
    echo -e "${CYAN}• No filtering based on video resolution${RESET}"
    echo -e "${CYAN}• You can enable filtering anytime to focus on specific qualities${RESET}"
  fi
  
  echo
  echo -e "${BOLD}${CYAN}Next Steps:${RESET}"
  echo -e "${GREEN}• Test your filter settings with 'Search Local Database'${RESET}"
  echo -e "${GREEN}• Adjust settings anytime via Settings → Configure Resolution Filter${RESET}"
  echo -e "${GREEN}• Configure country filters for additional search refinement${RESET}"
  
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

settings_menu() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Settings ===${RESET}\n"
    
    display_current_settings
    
    echo -e "${BOLD}${CYAN}Configuration Options:${RESET}"
    echo -e "${GREEN}a)${RESET} Change Channels DVR Server"
    echo -e "${GREEN}b)${RESET} Toggle Logo Display"
    echo -e "${GREEN}c)${RESET} Configure Resolution Filter"
    echo -e "${GREEN}d)${RESET} Configure Country Filter"
    echo -e "${GREEN}e)${RESET} View Cache Statistics"
    echo -e "${GREEN}f)${RESET} Reset All Settings"
    echo -e "${GREEN}g)${RESET} Export Settings"
    echo -e "${GREEN}h)${RESET} Export Station Database to CSV"
    echo -e "${GREEN}i)${RESET} Configure Dispatcharr Integration"
    # NEW: Add refresh interval option
    echo -e "${GREEN}j)${RESET} Configure Dispatcharr Token Refresh"
    echo -e "${GREEN}k)${RESET} Developer Information"
    echo -e "${GREEN}q)${RESET} Back to Main Menu"
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
      # NEW: Add refresh interval configuration
      j|J) configure_dispatcharr_refresh_interval && pause_for_user ;;
      k|K) developer_information && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

# ============================================================================
# DEVELOPER INFORMATION FUNCTIONS
# ============================================================================

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

developer_information() {
  while true; do
    clear
    echo -e "${BOLD}${BLUE}=== Developer Information ===${RESET}\n"
    echo -e "${YELLOW}This section contains technical details for script developers and maintainers.${RESET}"
    echo -e "${CYAN}End users typically don't need this information.${RESET}"
    echo
    
    echo -e "${BOLD}${CYAN}Technical Options:${RESET}"
    echo -e "${GREEN}a)${RESET} File System Layout"
    echo -e "${GREEN}b)${RESET} Base Cache Manifest Status"
    echo -e "${GREEN}c)${RESET} Cache State Tracking Details"
    echo -e "${GREEN}d)${RESET} Function Dependencies Map"
    echo -e "${GREEN}e)${RESET} Base Cache Manifest Creation Guide"
    echo -e "${GREEN}f)${RESET} Debug: Raw Cache Files"
    echo -e "${GREEN}g)${RESET} Script Architecture Overview"
    echo -e "${GREEN}q)${RESET} Back to Settings"
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

# ============================================================================
# MAIN APPLICATION ENTRY POINT
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
    
    echo -e "${BOLD}${CYAN}Main Menu:${RESET}"
    echo -e "${GREEN}1)${RESET} Search Local Database"
    echo -e "${GREEN}2)${RESET} Dispatcharr Integration"
    echo -e "${GREEN}3)${RESET} Manage Television Markets for User Cache"
    echo -e "${GREEN}4)${RESET} Run User Caching"
    echo -e "${GREEN}5)${RESET} Direct API Search"
    echo -e "${GREEN}6)${RESET} Reverse Station ID Lookup"
    echo -e "${GREEN}7)${RESET} Local Cache Management"
    echo -e "${GREEN}8)${RESET} Settings"
    echo -e "${GREEN}q)${RESET} Quit"
    echo
    
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

# ============================================================================
# APPLICATION INITIALIZATION AND STARTUP
# ============================================================================

# Initialize application
setup_config
check_dependencies
setup_directories

# Start main application
main_menu