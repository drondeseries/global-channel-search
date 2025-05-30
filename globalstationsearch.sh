#!/bin/bash

# === Global Station Search ===
# Description: Television station search tool using Channels DVR API
# Created: 2025/05/26
# Last Modified: 2025/05/28
VERSION="1.0.1-RC"

# TERMINAL STYLING
ESC="\033"
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
UNDERLINE="${ESC}[4m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"

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
MASTER_JSON="$CACHE_DIR/all_stations_deduped.json"
FINAL_JSON="$CACHE_DIR/all_stations_final.json"
CALLSIGN_CACHE="enhancement_cache.json"
API_SEARCH_RESULTS="$CACHE_DIR/api_search_results.tsv"

# DISPATCHARR FILES
DISPATCHARR_CACHE="$CACHE_DIR/dispatcharr_channels.json"
DISPATCHARR_MATCHES="$CACHE_DIR/dispatcharr_matches.tsv"
DISPATCHARR_LOG="$CACHE_DIR/dispatcharr_operations.log"
DISPATCHARR_TOKENS="$CACHE_DIR/dispatcharr_tokens.json"

# TEMPORARY FILES
TEMP_CONFIG="${CONFIG_FILE}.tmp"
SEARCH_RESULTS="$CACHE_DIR/search_results.tsv"
ENHANCED_LOG="$CACHE_DIR/enhanced_stations.log"

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
  if [ -f "$FINAL_JSON" ]; then
    local station_count
    station_count=$(jq length "$FINAL_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Station Database: $station_count stations cached${RESET}"
    echo -e "${GREEN}✅ Local Search: Available with full features${RESET}"
  else
    echo -e "${YELLOW}⚠️  Station Database: No data cached${RESET}"
    echo -e "${YELLOW}⚠️  Local Search: Not available - run caching first${RESET}"
  fi
  
  local market_count
  market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
  echo -e "📍 Markets Configured: $market_count"
  echo -e "🔗 Channels DVR: $CHANNELS_URL"
  if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
    if check_dispatcharr_connection 2>/dev/null; then
      echo -e "${GREEN}✅ Dispatcharr: Connected ($DISPATCHARR_URL)${RESET}"
    else
      echo -e "${RED}❌ Dispatcharr: Connection Failed${RESET}"
    fi
  else
    echo -e "${YELLOW}🔌 Dispatcharr: Integration Disabled${RESET}"
  fi
  echo
}

check_database_exists() {
  if [ ! -f "$FINAL_JSON" ]; then
    clear
    echo -e "${BOLD}${RED}❌ Local Search Not Available${RESET}\n"
    
    echo -e "${YELLOW}Local search requires a cached station database.${RESET}"
    echo -e "${YELLOW}The database is created by running the local caching process.${RESET}"
    echo
    
    show_workflow_guidance
    
    echo -e "${BOLD}${CYAN}What would you like to do?${RESET}"
    echo -e "${GREEN}1.${RESET} Configure markets and run local caching (recommended)"
    echo -e "${GREEN}2.${RESET} Use Direct API Search instead (limited features)"
    echo -e "${GREEN}3.${RESET} Return to main menu"
    echo
    
    read -p "Select option (1-3): " choice
    
    case $choice in
      1)
        echo -e "\n${GREEN}Great! Let's set up your markets first...${RESET}"
        pause_for_user
        manage_markets
        return 1
        ;;
      2)
        echo -e "\n${CYAN}Redirecting to Direct API Search...${RESET}"
        pause_for_user
        run_direct_api_search
        return 1
        ;;
      3|"")
        return 1
        ;;
      *)
        show_invalid_choice
        return 1
        ;;
    esac
  fi
  return 0
}

show_workflow_guidance() {
  echo -e "${BOLD}${BLUE}=== Getting Started Workflow ===${RESET}"
  echo
  echo -e "${YELLOW}📋 Recommended Steps:${RESET}"
  echo -e "${GREEN}1.${RESET} ${BOLD}Manage Markets${RESET} - Configure the geographic regions you're interested in"
  echo -e "   • Add countries/ZIP codes for your desired coverage areas"
  echo -e "   • More markets = more stations but longer caching time"
  echo
  echo -e "${GREEN}2.${RESET} ${BOLD}Run Local Caching${RESET} - Download and deduplicate stations from your markets"
  echo -e "   • Fetches all available stations from configured markets"
  echo -e "   • Deduplicates stations across markets automatically"
  echo -e "   • Enables full-featured local search with filtering"
  echo
  echo -e "${GREEN}3.${RESET} ${BOLD}Search Stations${RESET} - Full-featured search with all options"
  echo -e "   • Filter by resolution (HDTV, SDTV, UHDTV)"
  echo -e "   • Filter by country"
  echo -e "   • Browse logos and detailed information"
  echo -e "   • Unlimited results"
  echo
  echo -e "${CYAN}💡 Alternative: Direct API Search${RESET}"
  echo -e "   • No setup required - works immediately"
  echo -e "   • Limited to 10 results per search"
  echo -e "   • No filtering options available"
  echo -e "   • No country information"
  echo
}

# ============================================================================
# CONFIGURATION SETUP
# ============================================================================

setup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    if source "$CONFIG_FILE" 2>/dev/null; then
      if [[ -z "${CHANNELS_URL:-}" ]]; then
        echo -e "${RED}Error: Invalid config file - missing CHANNELS_URL${RESET}"
        rm "$CONFIG_FILE"
        echo -e "${YELLOW}Corrupted config removed. Let's set it up again.${RESET}"
      else
        # Set defaults for filter settings if not in config file
        FILTER_BY_RESOLUTION=${FILTER_BY_RESOLUTION:-false}
        ENABLED_RESOLUTIONS=${ENABLED_RESOLUTIONS:-"SDTV,HDTV,UHDTV"}
        FILTER_BY_COUNTRY=${FILTER_BY_COUNTRY:-false}
        ENABLED_COUNTRIES=${ENABLED_COUNTRIES:-""}

        # Set defaults for Dispatcharr settings if not in config file
        DISPATCHARR_URL=${DISPATCHARR_URL:-""}
        DISPATCHARR_USERNAME=${DISPATCHARR_USERNAME:-""}
        DISPATCHARR_PASSWORD=${DISPATCHARR_PASSWORD:-""}
        DISPATCHARR_ENABLED=${DISPATCHARR_ENABLED:-false}
        
        # CREATE SAMPLE MARKETS FILE IF IT DOESN'T EXIST
        if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
          echo -e "\n${YELLOW}Creating sample markets file...${RESET}"
          
          cat > "$CSV_FILE" << 'EOF'
Country,ZIP
USA,10001
USA,48201
USA,60614
USA,33101
USA,90210
USA,02101
CAN,M5V
GBR,SW1A
GBR,G1
GBR,EH1
USA,75201
USA,20001
USA,30309
USA,19101
USA,77002
USA,94102
USA,33602
EOF
          
          echo -e "${GREEN}Sample markets created with major cities:${RESET}"
          echo -e "${YELLOW}Detroit, New York, Chicago, Boston, Washington DC,"
          echo -e "Philadelphia, Atlanta, Miami, Tampa, Dallas, Houston,"
          echo -e "Los Angeles, San Francisco, Toronto, London${RESET}"
          echo
          echo -e "${BOLD}${CYAN}IMPORTANT:${RESET} ${YELLOW}Before running your first local cache, consider"
          echo -e "modifying the markets list to match your preferences.${RESET}"
          echo -e "You can add/remove markets using the market management options."
          pause_for_user
        fi
        
        return 0
      fi
    else
      echo -e "${RED}Error: Cannot source config file${RESET}"
      rm "$CONFIG_FILE"
      echo -e "${YELLOW}Corrupted config removed. Let's set it up again.${RESET}"
    fi
  fi

  # Config file doesn't exist or was corrupted
  create_new_config
}

create_new_config() {
  echo -e "${YELLOW}Config file not found. Let's set it up.${RESET}"
  
  local ip port
  
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
  
  # Test connection
  echo "Testing connection to $ip:$port..."
  if ! curl -s --connect-timeout 5 "http://$ip:$port" >/dev/null; then
    echo -e "${RED}Warning: Cannot connect to Channels DVR at $ip:$port${RESET}"
    if ! confirm_action "Continue anyway?"; then
      echo "Setup cancelled."
      exit 1
    fi
  else
    echo -e "${GREEN}Connection successful!${RESET}"
  fi
  
# Write config file
{
  echo "CHANNELS_URL=\"http://$ip:$port\""
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
  
  # CREATE SAMPLE MARKETS FILE IF IT DOESN'T EXIST
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "\n${YELLOW}Creating sample markets file...${RESET}"
    
    cat > "$CSV_FILE" << 'EOF'
Country,ZIP
USA,10001
USA,48201
USA,60614
USA,33101
USA,90210
USA,02101
CAN,M5V
GBR,SW1A
GBR,G1
GBR,EH1
USA,75201
USA,20001
USA,30309
USA,19101
USA,77002
USA,94102
USA,33602
EOF
    
    echo -e "${GREEN}Sample markets created with major cities:${RESET}"
    echo -e "${YELLOW}Detroit, New York, Chicago, Boston, Washington DC,"
    echo -e "Philadelphia, Atlanta, Miami, Tampa, Dallas, Houston,"
    echo -e "Los Angeles, San Francisco, Toronto, London${RESET}"
    echo
    echo -e "${BOLD}${CYAN}IMPORTANT:${RESET} ${YELLOW}Before running your first local cache, consider"
    echo -e "modifying the markets list to match your preferences.${RESET}"
    echo -e "You can add/remove markets using the market management options."
    pause_for_user
  fi
  
  source "$CONFIG_FILE"
  FILTER_BY_RESOLUTION=${FILTER_BY_RESOLUTION:-false}
  ENABLED_RESOLUTIONS=${ENABLED_RESOLUTIONS:-"SDTV,HDTV,UHDTV"}
  FILTER_BY_COUNTRY=${FILTER_BY_COUNTRY:-false}
  ENABLED_COUNTRIES=${ENABLED_COUNTRIES:-""}
  echo -e "${GREEN}Configuration saved successfully!${RESET}"
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

  # Check for optional viu dependency
  if check_dependency "viu" "false" "viu is not installed, logo previews disabled. Enable in settings after installing viu"; then
    SHOW_LOGOS=true
  else
    SHOW_LOGOS=false
  fi

  # Update SHOW_LOGOS in config file safely
  if [ -f "$CONFIG_FILE" ]; then
    local temp_config="${CONFIG_FILE}.tmp"
    grep -v '^SHOW_LOGOS=' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || true
    echo "SHOW_LOGOS=$SHOW_LOGOS" >> "$temp_config"
    mv "$temp_config" "$CONFIG_FILE"
  fi
}

# ============================================================================
# DIRECTORY AND FILE SETUP
# ============================================================================

setup_directories() {
  mkdir -p "$CACHE_DIR" || {
    echo -e "${RED}Error: Cannot create cache directory${RESET}"
    exit 1
  }

  mkdir -p "$BACKUP_DIR" "$LOGO_DIR" "$STATION_CACHE_DIR" || {
    echo -e "${RED}Error: Cannot create cache subdirectories${RESET}"
    exit 1
  }

  if [ ! -f "$VALID_CODES_FILE" ]; then
    echo "Downloading valid country codes..."
    if ! curl -s --connect-timeout 10 --max-time 30 \
        "https://raw.githubusercontent.com/lukes/ISO-3166-Countries-with-Regional-Codes/master/all/all.json" \
        | jq -r '.[]."alpha-3"' \
        | sort -u > "$VALID_CODES_FILE"; then
      echo -e "${RED}Error: Failed to download country codes${RESET}"
      echo "Creating minimal fallback list..."
      echo -e "USA\nCAN\nGBR\nAUS\nDEU\nFRA" > "$VALID_CODES_FILE"
    else
      echo -e "${GREEN}Country codes downloaded successfully${RESET}"
    fi
  fi
}

# ============================================================================
# CACHE MANAGEMENT FUNCTIONS
# ============================================================================

cleanup_cache() {
  echo -e "${YELLOW}Cleaning up cached station files...${RESET}"
  
  if [ -d "$STATION_CACHE_DIR" ]; then
    rm -f "$STATION_CACHE_DIR"/*.json 2>/dev/null || true
    echo "  ✓ Station cache files removed"
  fi
  
  rm -f "$ENHANCED_LOG" 2>/dev/null || true
  rm -f "$CACHE_DIR"/enhanced_stations_tmp.log 2>/dev/null || true
  echo "  ✓ Enhancement logs removed"
  
  rm -f "$CACHE_DIR"/last_raw_*.json 2>/dev/null || true
  echo "  ✓ Raw API response files removed"
  
  rm -f "$CACHE_DIR"/*.tmp 2>/dev/null || true
  echo "  ✓ Temporary files removed"

  rm -f "$API_SEARCH_RESULTS" 2>/dev/null || true
  echo "  ✓ API search results removed"
  
  echo -e "${GREEN}Cache cleanup completed${RESET}"
}

# ============================================================================
# CALLSIGN CACHING FUNCTIONS
# ============================================================================

lookup_callsign_in_cache() {
  local callSign="$1"
  if [ -f "$CALLSIGN_CACHE" ]; then
    jq -r --arg cs "$callSign" 'if has($cs) then .[$cs] else empty end' "$CALLSIGN_CACHE"
  fi
}

add_callsign_to_cache() {
  local callSign="$1"
  local json_data="$2"
  local tmp_file="${CALLSIGN_CACHE}.tmp"
  
  # Validate inputs
  if [[ -z "$callSign" || "$callSign" == "null" ]]; then
    return 1
  fi
  
  if [[ -z "$json_data" || "$json_data" == "null" ]]; then
    return 1
  fi
  
  # Double-check JSON validity
  if ! echo "$json_data" | jq empty 2>/dev/null; then
    return 1
  fi
  
  # Initialize cache file if needed
  if [ ! -f "$CALLSIGN_CACHE" ]; then 
    echo '{}' > "$CALLSIGN_CACHE"
  fi
  
  # Use jq with error handling - suppress all error output
  if ! jq --arg cs "$callSign" --argjson data "$json_data" '. + {($cs): $data}' "$CALLSIGN_CACHE" > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    return 1
  fi
  
  mv "$tmp_file" "$CALLSIGN_CACHE" 2>/dev/null || return 1
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
  
  echo "$channels_data" | jq -r '
    .[] | 
    select((.tvc_guide_stationid // "") == "" or (.tvc_guide_stationid // "") == null) |
    [.id, .name, .channel_group_id // "Ungrouped", .channel_number // 0] | 
    @tsv
  ' 2>/dev/null
}

search_stations_by_name() {
  local search_term="$1"
  local page="${2:-1}"
  local results_per_page=10
  local start_index=$(( (page - 1) * results_per_page ))
  
  if [[ ! -f "$FINAL_JSON" ]]; then
    echo "Error: Station database not found" >&2
    return 1
  fi
  
  # Simple search - no confidence scoring
  jq -r --arg term "$search_term" --argjson start "$start_index" --argjson limit "$results_per_page" '
    [.[] | 
      select(
        (.name // "" | ascii_downcase | contains($term | ascii_downcase)) or
        (.callSign // "" | ascii_downcase | contains($term | ascii_downcase))
      )
    ] |
    .[$start:$start+$limit] |
    .[] |
    [.stationId, .name, .callSign, (.country // "UNK")] |
    @tsv
  ' "$FINAL_JSON" 2>/dev/null
}

get_total_search_results() {
  local search_term="$1"
  
  if [[ ! -f "$FINAL_JSON" ]]; then
    return 1
  fi
  
  jq -r --arg term "$search_term" '
    [.[] | 
      select(
        (.name // "" | ascii_downcase | contains($term | ascii_downcase)) or
        (.callSign // "" | ascii_downcase | contains($term | ascii_downcase))
      )
    ] |
    length
  ' "$FINAL_JSON" 2>/dev/null
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
    echo
    
    echo -e "${BOLD}Options:${RESET}"
    echo "1) Configure Dispatcharr Connection"
    echo "2) Scan Channels for Missing Station IDs"
    echo "3) Interactive Station ID Matching"
    echo "4) Commit Station ID Changes"
    echo "5) View Integration Logs"
    echo "6) Refresh Authentication Tokens"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1) configure_dispatcharr_connection && pause_for_user ;;
      2) scan_missing_stationids && pause_for_user ;;
      3) interactive_stationid_matching ;;
      4) batch_update_stationids && pause_for_user ;;
      5) view_dispatcharr_logs && pause_for_user ;;
      6) refresh_dispatcharr_tokens && pause_for_user ;;
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
    return 1
  fi
  
  if [[ ! -f "$FINAL_JSON" ]]; then
    echo -e "${RED}No station database found. Please run local caching first.${RESET}"
    return 1
  fi
  
  echo "Fetching channels from Dispatcharr..."
  local channels_data
  channels_data=$(get_dispatcharr_channels)
  
  if [[ -z "$channels_data" ]]; then
    echo -e "${RED}Failed to fetch channels from Dispatcharr${RESET}"
    return 1
  fi
  
  echo "Analyzing channels for missing station IDs..."
  local missing_channels
  missing_channels=$(find_channels_missing_stationid "$channels_data")
  
  if [[ -z "$missing_channels" ]]; then
    echo -e "${GREEN}All channels have station IDs assigned!${RESET}"
    return 0
  fi
  
  local missing_count
  missing_count=$(echo "$missing_channels" | wc -l)
  
  echo -e "${YELLOW}Found $missing_count channels missing station IDs:${RESET}"
  echo
  
  printf "${BOLD}%-8s %-30s %-15s %s${RESET}\n" "ID" "Channel Name" "Group" "Number"
  echo "------------------------------------------------------------------------"
  
  echo "$missing_channels" | while IFS=$'\t' read -r id name group number; do
    printf "%-8s %-30s %-15s %s\n" "$id" "$name" "$group" "$number"
  done
  
  echo
  echo -e "${CYAN}Next: Use 'Interactive Station ID Matching' to resolve these${RESET}"
  return 0
}

interactive_stationid_matching() {
  if ! check_dispatcharr_connection; then
    echo -e "${RED}Cannot connect to Dispatcharr. Please configure connection first.${RESET}"
    pause_for_user
    return 1
  fi
  
  if [[ ! -f "$FINAL_JSON" ]]; then
    echo -e "${RED}No station database found. Please run local caching first.${RESET}"
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
  echo "Starting interactive matching process..."
  pause_for_user
  
  for ((i = 0; i < total_missing; i++)); do
    IFS=$'\t' read -r channel_id channel_name group number <<< "${missing_array[$i]}"
    
    # Skip empty lines
    [[ -z "$channel_id" ]] && continue
    
    # Main matching loop for this channel
    while true; do
      clear
      echo -e "${BOLD}${CYAN}=== Channel Station ID Assignment ===${RESET}\n"
      
      echo -e "${BOLD}Channel: ${YELLOW}$channel_name${RESET}"
      echo -e "Group: $group | Number: $number | ID: $channel_id"
      echo -e "Progress: $((i + 1)) of $total_missing"
      echo
      
      # Initial search with channel name
      local search_term="$channel_name"
      local current_page=1
      
      # Search and display loop
      while true; do
        echo -e "${CYAN}Searching for: '$search_term' (Page $current_page)${RESET}"
        
        local results
        results=$(search_stations_by_name "$search_term" "$current_page")
        
        local total_results
        total_results=$(get_total_search_results "$search_term")
        
        if [[ -z "$results" ]]; then
          echo -e "${YELLOW}No results found for '$search_term'${RESET}"
        else
          echo -e "${GREEN}Found $total_results total results${RESET}"
          echo
          
          printf "${BOLD}%-3s %-12s %-30s %-10s %-8s${RESET}\n" "Key" "Station ID" "Name" "Call Sign" "Country"
          echo "--------------------------------------------------------------------------------"
          
          local station_array=()
          local key_letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j")
          local result_count=0
          
          while IFS=$'\t' read -r station_id name call_sign country; do
            [[ -z "$station_id" ]] && continue
            
            local key="${key_letters[$result_count]}"
            printf "%-3s %-12s %-30s %-10s %-8s\n" "$key)" "$station_id" "${name:0:30}" "$call_sign" "$country"
            station_array+=("$station_id|$name|$call_sign|$country")
            ((result_count++))
          done <<< "$results"
          
          echo
          
          # Calculate pagination info
          local total_pages=$(( (total_results + 9) / 10 ))
          [[ $total_pages -eq 0 ]] && total_pages=1
          
          echo -e "${BOLD}Page $current_page of $total_pages${RESET}"
        fi
        
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
                IFS='|' read -r sel_station_id sel_name sel_call sel_country <<< "$selected"
                
                echo
                echo -e "${BOLD}Selected Station:${RESET}"
                echo "  Station ID: $sel_station_id"
                echo "  Name: $sel_name"
                echo "  Call Sign: $sel_call"
                echo "  Country: $sel_country"
                echo
                
                read -p "Use this station? (y/n): " confirm < /dev/tty
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                  if update_dispatcharr_channel_epg "$channel_id" "$sel_station_id"; then
                    echo -e "${GREEN}✅ Successfully updated channel${RESET}"
                    echo -e "$channel_id\t$channel_name\t$sel_station_id\t$sel_name\t100" >> "$DISPATCHARR_MATCHES"
                    pause_for_user
                    break 2  # Exit both loops, move to next channel
                  else
                    echo -e "${RED}❌ Failed to update channel${RESET}"
                    pause_for_user
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
              if update_dispatcharr_channel_epg "$channel_id" "$manual_station_id"; then
                echo -e "${GREEN}✅ Successfully updated channel with manual ID${RESET}"
                echo -e "$channel_id\t$channel_name\t$manual_station_id\tManual Entry\t100" >> "$DISPATCHARR_MATCHES"
                pause_for_user
                break 2  # Exit both loops, move to next channel
              else
                echo -e "${RED}❌ Failed to update channel${RESET}"
                pause_for_user
              fi
            fi
            ;;
          k|K)
            echo -e "${YELLOW}Skipped: $channel_name${RESET}"
            break 2  # Exit both loops, move to next channel
            ;;
          q|Q)
            echo -e "${CYAN}Matching session ended${RESET}"
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
  if [[ -f "$DISPATCHARR_MATCHES" ]] && [[ -s "$DISPATCHARR_MATCHES" ]]; then
    local match_count
    match_count=$(wc -l < "$DISPATCHARR_MATCHES")
    echo -e "${CYAN}Applied $match_count matches${RESET}"
  fi
  pause_for_user
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
  
  # Show preview of matches
  echo -e "${BOLD}Pending Matches:${RESET}"
  printf "${BOLD}%-8s %-25s %-12s %-20s${RESET}\n" "Ch ID" "Channel Name" "Station ID" "Match Source"
  echo "------------------------------------------------------------------------"
  
  local line_count=0
  while IFS=$'\t' read -r channel_id channel_name station_id station_name confidence; do
    printf "%-8s %-25s %-12s %-20s\n" "$channel_id" "${channel_name:0:25}" "$station_id" "${station_name:0:20}"
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
    
    echo -n "Updating: $channel_name -> $station_id ... "
    
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
  echo -e "${GREEN}Successful: $success_count${RESET}"
  [[ $failure_count -gt 0 ]] && echo -e "${RED}Failed: $failure_count${RESET}"
  
  # Clear processed matches
  > "$DISPATCHARR_MATCHES"
  echo -e "${CYAN}Match queue cleared${RESET}"
  
  return 0
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

get_available_countries() {
  if [ -f "$CSV_FILE" ] && [ -s "$CSV_FILE" ]; then
    awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort -u | tr '\n' ',' | sed 's/,$//'
  else
    echo ""
  fi
}

build_resolution_filter() {
  if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
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
  if [ "$FILTER_BY_COUNTRY" = "true" ] && [ -n "$ENABLED_COUNTRIES" ]; then
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
  mkdir -p "$LOGO_DIR"
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Station Search ===${RESET}\n"
    
    # Show filter status
    local filter_status=""
    if [ "$FILTER_BY_RESOLUTION" = "true" ]; then
      filter_status+="${YELLOW}Resolution: $ENABLED_RESOLUTIONS${RESET}"
    fi
    
    if [ "$FILTER_BY_COUNTRY" = "true" ]; then
      if [ -n "$filter_status" ]; then
        filter_status+=" | "
      fi
      filter_status+="${GREEN}Country: $ENABLED_COUNTRIES${RESET}"
    fi
    
    if [ -n "$filter_status" ]; then
      echo -e "Active Filters: $filter_status"
    else
      echo -e "Filters: ${RED}None Active${RESET}"
    fi
    echo
    
    read -p "Search by name or call sign (or 'q' to return to main menu): " SEARCH_TERM
    
    case "$SEARCH_TERM" in
      q|Q|"") break ;;
      *)
        if [[ -z "$SEARCH_TERM" || "$SEARCH_TERM" =~ ^[[:space:]]*$ ]]; then
          echo -e "${RED}Please enter a search term${RESET}"
          pause_for_user
          continue
        fi
        
        perform_search "$SEARCH_TERM"
        ;;
    esac
  done
}

perform_search() {
  local search_term="$1"
  
  # Escape special regex characters for safety
  local escaped_term=$(echo "$search_term" | sed 's/[[\.*^$()+?{|]/\\&/g')
  
  # Build filters
  local resolution_filter=$(build_resolution_filter)
  local country_filter=$(build_country_filter)
  
  jq -r --arg term "$escaped_term" --arg exact_term "$search_term" '
    .[] | select(
      ((.name // "" | test($term; "i")) or
       (.callSign // "" | test($term; "i")) or
       (.name // "" | . == $exact_term) or
       (.callSign // "" | . == $exact_term))
      '"$resolution_filter"'
      '"$country_filter"'
    ) | [.name, .callSign, (.videoQuality.videoType // ""), .stationId, (.country // "UNK")] | @tsv
  ' "$FINAL_JSON" > "$SEARCH_RESULTS"
  
  display_search_results "$search_term"
}

display_search_results() {
  local search_term="$1"
  
  mapfile -t RESULTS < "$SEARCH_RESULTS"
  local count=${#RESULTS[@]}
  
  # Build filter info for display
  local filter_info=""
  if [ "$FILTER_BY_RESOLUTION" = "true" ] || [ "$FILTER_BY_COUNTRY" = "true" ]; then
    filter_info=" (filtered by:"
    [ "$FILTER_BY_RESOLUTION" = "true" ] && filter_info+=" Resolution: $ENABLED_RESOLUTIONS"
    [ "$FILTER_BY_COUNTRY" = "true" ] && filter_info+=" Country: $ENABLED_COUNTRIES"
    filter_info+=")"
  fi
  
  # Show search result count with filter info
  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No results found for '$search_term'$filter_info${RESET}"
    pause_for_user
    return
  fi
  
  echo -e "${GREEN}Found $count result(s) for '$search_term'$filter_info${RESET}"
  
  local offset=0
  
  while (( offset < count )); do
    clear
    
    # Calculate current page info
    local start_num=$((offset + 1))
    local end_num=$((offset + 10 < count ? offset + 10 : count))
    
    # Show pagination info with filter status
    echo -e "${GREEN}Found $count result(s) for '$search_term'$filter_info${RESET}"
    echo -e "${BOLD}Showing results $start_num-$end_num of $count${RESET}"
    echo
    
    printf "${BOLD}${YELLOW}%-30s %-10s %-8s %-8s %-12s${RESET}\n" "Channel Name" "Call Sign" "Quality" "Country" "Station ID"
    echo "--------------------------------------------------------------------------------"
    
    for ((i = offset; i < offset + 10 && i < count; i++)); do
      IFS=$'\t' read -r NAME CALLSIGN RES STID COUNTRY <<< "${RESULTS[$i]}" 
      printf "%-30s %-10s %-8s ${GREEN}%-8s${RESET} ${CYAN}%-12s${RESET}\n" "$NAME" "$CALLSIGN" "$RES" "$COUNTRY" "$STID"
      
      display_logo "$STID"
      echo
    done
    
    offset=$((offset + 10))
    
    # Pagination navigation
    if (( offset < count )); then
      echo -e "\n${BOLD}Navigation:${RESET}"
      read -p "Press Enter for more results, or 'q' to return to search: " NEXT
      case "$NEXT" in
        q|Q) break ;;
      esac
    else
      echo -e "\n${GREEN}End of results${RESET}"
      pause_for_user
      break
    fi
  done
}

display_logo() {
  local stid="$1"
  local logo_file="$LOGO_DIR/${stid}.png"
  
  if [[ "$SHOW_LOGOS" == true ]]; then
    if [[ ! -f "$logo_file" ]]; then
      local logo_url=$(jq -r --arg id "$stid" '.[] | select(.stationId == $id) | .preferredImage.uri // empty' "$FINAL_JSON" | head -n 1)
      if [[ -n "$logo_url" ]]; then
        curl -sL "$logo_url" --output "$logo_file" 2>/dev/null
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
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Direct API Search ===${RESET}\n"
    
    echo -e "${YELLOW}⚠️  IMPORTANT LIMITATIONS:${RESET}"
    echo -e "${RED}• Results limited to 6 stations per search${RESET}"
    echo -e "${RED}• No country information available${RESET}"
    echo -e "${RED}• Cannot be filtered by resolution or country${RESET}"
    echo -e "${RED}• Less robust than local cache search${RESET}"
    echo
    echo -e "${GREEN}💡 For better results: Use 'Local Caching' + 'Search Stations'${RESET}"
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
    echo "r) Ready to Cache - Go to Local Caching"
    echo "q) Back to Main Menu"
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) add_market && pause_for_user ;;
      b|B) remove_market && pause_for_user ;;
      c|C) import_markets && pause_for_user ;;
      d|D) export_markets && pause_for_user ;;
      e|E) cleanup_existing_postal_codes && pause_for_user ;;
      r|R) 
        local market_count
        market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
        if [[ "$market_count" -gt 0 ]]; then
          echo -e "\n${GREEN}Excellent! You have $market_count markets configured.${RESET}"
          echo -e "${CYAN}Proceeding to Local Caching...${RESET}"
          pause_for_user
          run_local_caching
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
      echo "e) Cache Management"
      echo "f) Reset All Settings"
      echo "g) Export Settings"
      echo "h) Export Station Database to CSV"
      echo "i) Configure Dispatcharr Integration"
      echo "q) Back to Main Menu"
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) change_server_settings && pause_for_user ;;
      b|B) toggle_logo_display && pause_for_user ;;
      c|C) configure_resolution_filter && pause_for_user ;;
      d|D) configure_country_filter && pause_for_user ;;
      e|E) cache_management_menu ;;
      f|F) reset_all_settings && pause_for_user ;;
      g|G) export_settings && pause_for_user ;;
      h|H) export_stations_to_csv && pause_for_user ;;
      i|I) configure_dispatcharr_connection && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

display_current_settings() {
  echo -e "${BOLD}Current Configuration:${RESET}"
  echo "Server: $CHANNELS_URL"
  echo "Logo Display: $([ "$SHOW_LOGOS" = "true" ] && echo -e "${GREEN}Enabled${RESET}" || echo -e "${RED}Disabled${RESET}")"
  
  if command -v viu &> /dev/null; then
    echo -e "   └─ viu status: ${GREEN}Available${RESET}"
  else
    echo -e "   └─ viu status: ${RED}Not installed${RESET}"
  fi
  
  echo "Resolution Filter: $([ "$FILTER_BY_RESOLUTION" = "true" ] && echo -e "${GREEN}Enabled${RESET} ${YELLOW}($ENABLED_RESOLUTIONS)${RESET}" || echo -e "${RED}Disabled${RESET}")"
  echo "Country Filter: $([ "$FILTER_BY_COUNTRY" = "true" ] && echo -e "${GREEN}Enabled${RESET} ${YELLOW}($ENABLED_COUNTRIES)${RESET}" || echo -e "${RED}Disabled${RESET}")"
  
  if [ -f "$FINAL_JSON" ]; then
    local station_count=$(jq length "$FINAL_JSON" 2>/dev/null || echo "0")
    echo -e "Station Database: ${GREEN}$station_count stations${RESET}"
  else
    echo -e "Station Database: ${YELLOW}No data cached${RESET}"
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
    echo -e "${RED}Cannot enable logo display: viu is not installed${RESET}"
    echo "Install viu with: cargo install viu"
    return 1
  fi
  
  if [ "$SHOW_LOGOS" = "true" ]; then
    SHOW_LOGOS=false
    echo -e "${YELLOW}Logo display disabled${RESET}"
  else
    SHOW_LOGOS=true
    echo -e "${GREEN}Logo display enabled${RESET}"
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

cache_management_menu() {
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Settings > Cache Management ===${RESET}\n"
    
    display_cache_statistics
    
    echo -e "${BOLD}Options:${RESET}"
    echo "1) Clear All Cache"
    echo "2) Clear Station Cache Only"
    echo "3) Clear Temporary Files Only"
    echo "4) Clear Logo Cache"
    echo "5) View Detailed Statistics"
    echo "q) Back to Settings"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1) clear_all_cache && pause_for_user ;;
      2) clear_station_cache && pause_for_user ;;
      3) clear_temp_files && pause_for_user ;;
      4) clear_logo_cache && pause_for_user ;;
      5) show_detailed_cache_stats && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

display_cache_statistics() {
  echo -e "${BOLD}Cache Statistics:${RESET}"
  [ -f "$FINAL_JSON" ] && echo "Stations: $(jq length "$FINAL_JSON" 2>/dev/null || echo "0")"
  [ -f "$LINEUP_CACHE" ] && echo "Lineups: $(wc -l < "$LINEUP_CACHE" 2>/dev/null || echo "0")"
  [ -f "$CALLSIGN_CACHE" ] && echo "Callsign cache: $(jq 'keys | length' "$CALLSIGN_CACHE" 2>/dev/null || echo "0") entries"
  [ -d "$LOGO_DIR" ] && echo "Logos cached: $(find "$LOGO_DIR" -name "*.png" 2>/dev/null | wc -l)"
  [ -f "$API_SEARCH_RESULTS" ] && echo "API search results: $(wc -l < "$API_SEARCH_RESULTS" 2>/dev/null || echo "0") entries"
  echo "Total cache size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
  echo
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
    rm -f "$STATION_CACHE_DIR"/*.json "$MASTER_JSON" "$FINAL_JSON"
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
  
  if [ -f "$FINAL_JSON" ]; then
    echo "Station Database:"
    echo "  Total stations: $(jq length "$FINAL_JSON")"
    echo "  HDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "HDTV")] | length' "$FINAL_JSON")"
    echo "  SDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "SDTV")] | length' "$FINAL_JSON")"
    echo "  UHDTV stations: $(jq '[.[] | select(.videoQuality.videoType == "UHDTV")] | length' "$FINAL_JSON")"
    
    # Show country breakdown if available
    local countries=$(jq -r '[.[] | .country // "UNK"] | unique | .[]' "$FINAL_JSON" 2>/dev/null)
    if [ -n "$countries" ]; then
      echo "  Countries:"
      while read -r country; do
        local count=$(jq --arg c "$country" '[.[] | select((.country // "UNK") == $c)] | length' "$FINAL_JSON")
        echo "    $country: $count stations"
      done <<< "$countries"
    fi
  fi
  
  if [ -d "$CACHE_DIR" ]; then
    echo -e "\nCache Directory Breakdown:"
    du -sh "$CACHE_DIR"/* 2>/dev/null | sort -hr
  fi
  
  if [ -f "$CSV_FILE" ]; then
    local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
    echo -e "\nMarket Configuration: $market_count markets"
  fi
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
    echo "Version: $VERSION"
    echo
    echo "Server: $CHANNELS_URL"
    echo "Logo Display: $SHOW_LOGOS"
    echo "Resolution Filter: $FILTER_BY_RESOLUTION"
    echo "Enabled Resolutions: $ENABLED_RESOLUTIONS"
    echo "Country Filter: $FILTER_BY_COUNTRY"
    echo "Enabled Countries: $ENABLED_COUNTRIES"
    echo
    echo "Markets:"
    [ -f "$CSV_FILE" ] && cat "$CSV_FILE"
  } > "$settings_file"
  
  echo -e "${GREEN}Settings exported to: $settings_file${RESET}"
  return 0
}

export_stations_to_csv() {
  echo -e "\n${BOLD}Export Station Database to CSV${RESET}"
  
  if [ ! -f "$FINAL_JSON" ]; then
    echo -e "${RED}No station database found. Run local caching first.${RESET}"
    return 1
  fi
  
  local station_count
  station_count=$(jq length "$FINAL_JSON" 2>/dev/null || echo "0")
  echo "Station database contains: $station_count stations"
  echo
  
  # Generate filename with timestamp
  local csv_file="stations_export_$(date +%Y%m%d_%H%M%S).csv"
  read -p "Export filename [default: $csv_file]: " filename
  filename=${filename:-$csv_file}
  
  echo "Exporting stations to CSV..."
  
  # Create CSV with comprehensive station data
  {
    # CSV Header
    echo "Station_ID,Name,Call_Sign,Country,Video_Quality,Network,Genre,Language,Logo_URL,Description"
    
    # Export station data
    jq -r '.[] | [
      .stationId // "",
      .name // "",
      .callSign // "",
      .country // "",
      .videoQuality.videoType // "",
      .network // "",
      (.genre // [] | join("; ")),
      .language // "",
      .preferredImage.uri // "",
      .description // ""
    ] | @csv' "$FINAL_JSON"
  } > "$filename"
  
  if [ $? -eq 0 ]; then
    local exported_count
    exported_count=$(tail -n +2 "$filename" | wc -l)
    echo -e "${GREEN}✅ Successfully exported $exported_count stations to: $filename${RESET}"
    
    # Show file info
    local file_size
    file_size=$(ls -lh "$filename" | awk '{print $5}')
    echo -e "${CYAN}📄 File size: $file_size${RESET}"
    
    # Show sample of exported data
    echo -e "\n${BOLD}Sample of exported data:${RESET}"
    head -3 "$filename" | while IFS= read -r line; do
      echo "  $line"
    done
    
    echo -e "\n${CYAN}💡 This CSV can be opened in Excel, LibreOffice, or imported into databases${RESET}"
  else
    echo -e "${RED}❌ Failed to export stations to CSV${RESET}"
    return 1
  fi
  
  return 0
}

# ============================================================================
# LOCAL CACHING FUNCTIONS
# ============================================================================

run_local_caching() {
  clear
  echo -e "${BOLD}${CYAN}=== Local Caching ===${RESET}\n"
  
  echo -e "${BLUE}📊 Step 2 of 3: Build Local Station Database${RESET}"
  echo -e "${YELLOW}This process will:${RESET}"
  echo -e "• Query all configured markets for available stations"
  echo -e "• Deduplicate stations that appear in multiple markets"
  echo -e "• Cache station details locally for fast searching"
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
  
  if ! confirm_action "Continue with local caching?"; then
    echo -e "${YELLOW}Local caching cancelled${RESET}"
    return 1
  fi
  
  perform_caching
}

perform_caching() {
  echo -e "\n${YELLOW}Full refresh initiated. Purging lineup and station caches...${RESET}"
  
  # Clean up old cache files
  rm -f "$LINEUP_CACHE" cache/unique_lineups.txt "$MASTER_JSON" "$FINAL_JSON" "$STATION_CACHE_DIR"/*.json cache/enhanced_stations.log
  
  local start_time=$(date +%s.%N)
  mkdir -p "cache" "$STATION_CACHE_DIR"
  [ ! -f "$CALLSIGN_CACHE" ] && echo '{}' > "$CALLSIGN_CACHE"
  > "$LINEUP_CACHE"

  # Fetch lineups for each market
  while IFS=, read -r COUNTRY ZIP; do
    [[ "$COUNTRY" == "Country" ]] && continue
    echo "Querying lineups for $COUNTRY / $ZIP"
    local response=$(curl -s "$CHANNELS_URL/tms/lineups/$COUNTRY/$ZIP")
    echo "$response" > "cache/last_raw_${COUNTRY}_${ZIP}.json"
    if echo "$response" | jq -e . > /dev/null 2>&1; then
      echo "$response" | jq -c '.[]' >> "$LINEUP_CACHE"
    else
      echo "Invalid JSON from $COUNTRY $ZIP, skipping."
    fi
  done < "$CSV_FILE"

  # Process lineups
  local pre_dedup_lineups=$(jq -r '.lineupId' "$LINEUP_CACHE" | wc -l)
  sort -u "$LINEUP_CACHE" | jq -r '.lineupId' | sort -u > cache/unique_lineups.txt
  local post_dedup_lineups=$(wc -l < cache/unique_lineups.txt)
  local dup_lineups_removed=$((pre_dedup_lineups - post_dedup_lineups))

  # Fetch stations for each lineup
  while read LINEUP; do
    local station_file="$STATION_CACHE_DIR/${LINEUP}.json"
    echo "Fetching stations for $LINEUP"
    curl -s "$CHANNELS_URL/dvr/guide/stations/$LINEUP" -o "$station_file"
  done < cache/unique_lineups.txt

  # Process and deduplicate stations with country injection
  echo "Processing stations and injecting country codes..."
  local pre_dedup_stations=0
  > "$MASTER_JSON.tmp"

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
      
      # Inject country code into each station and append to temp file
      jq --arg country "$country_code" 'map(. + {country: $country})' "$station_file" >> "$MASTER_JSON.tmp"
    fi
  done < cache/unique_lineups.txt

  # Now flatten, deduplicate, and sort
  echo "Flattening and deduplicating stations..."
  jq -s 'flatten | sort_by((.name // "") | length) | reverse | unique_by(.stationId)' "$MASTER_JSON.tmp" \
    | jq 'map(.name = (.name // empty))' > "$MASTER_JSON"

  # Clean up temp file
  rm -f "$MASTER_JSON.tmp"

  local post_dedup_stations=$(jq length "$MASTER_JSON")
  local dup_stations_removed=$((pre_dedup_stations - post_dedup_stations))

  # Enhancement phase
  enhance_stations "$start_time"
  
  # Backup and finalize
  backup_existing_data
  jq -s '.' "$MASTER_JSON" > "$FINAL_JSON"

  # Calculate duration and show summary
  local end_time=$(date +%s)
  local duration=$((end_time - ${start_time%%.*}))
  local human_duration=$(printf '%02dh %02dm %02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

  show_caching_summary "$dup_lineups_removed" "$dup_stations_removed" "$human_duration"
}

enhance_stations() {
  local start_time="$1"
  
  echo "Enhancing final station list by callsign..."
  local tmp_json="cache/all_stations_tmp.json"
  local completed_log="cache/enhanced_stations.log"
  local tmp_log="cache/enhanced_stations_tmp.log"
  
  touch "$completed_log"
  > "$tmp_log"

  mapfile -t stations < <(jq -c '.[]' "$MASTER_JSON")
  local total_stations=${#stations[@]}
  local enhanced_from_cache=0
  local enhanced_from_api=0

  for ((i = 0; i < total_stations; i++)); do
    local station="${stations[$i]}"
    local current=$((i + 1))
    local percent=$((current * 100 / total_stations))
    
    # Progress bar
    show_progress_bar "$current" "$total_stations" "$percent" "$start_time"

    local callSign=$(echo "$station" | jq -r '.callSign')
    if grep -q "^$callSign$" "$completed_log"; then
      echo "$station" >> "$tmp_json"
      continue
    fi

    local name=$(echo "$station" | jq -r '.name')
    if [[ -z "$name" || "$name" == "null" ]]; then
      if [[ -n "$callSign" && "$callSign" != "null" ]]; then
        local enhanced_data=$(lookup_callsign_in_cache "$callSign")
        if [[ -n "$enhanced_data" ]]; then
          station=$(echo "$station" "$enhanced_data" | jq -s '.[0] * (.[1])')
          ((enhanced_from_cache++))
        else
          # Query API and enhance
          local api_response=$(curl -s "$CHANNELS_URL/tms/stations/$callSign")
          local current_station_id=$(echo "$station" | jq -r '.stationId')
          local station_info=$(echo "$api_response" | jq -c --arg id "$current_station_id" '.[] | select(.stationId == $id) // empty')
          
          if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
            if echo "$station_info" | jq empty 2>/dev/null; then
              station=$(echo "$station" "$station_info" | jq -s '.[0] * .[1]')
              local json_string=$(echo "$station_info" | jq -c . 2>/dev/null)
              if [[ -n "$json_string" && "$json_string" != "null" ]]; then
                add_callsign_to_cache "$callSign" "$json_string" 2>/dev/null || true
              fi
              ((enhanced_from_api++))
            fi
          fi
        fi
      fi
    fi

    echo "$station" >> "$tmp_json"
    echo "$callSign" >> "$tmp_log"
  done
  
  echo
  echo -e "\nEnhancement complete."
  mv "$tmp_json" "$MASTER_JSON"
  sort -u "$tmp_log" >> "$completed_log"
  rm -f "$tmp_log"
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

  printf "\rEnhancing station %d of %d [%d%%] [%s%s] ETA: %s" \
    "$current" "$total" "$percent" "$bar" "$spaces" "$remaining_fmt"
}

backup_existing_data() {
  if [ -f "$FINAL_JSON" ]; then
    echo "Backing up existing final station list to cache/backups..."
    mkdir -p cache/backups
    for ((i=9; i>=1; i--)); do
      if [ -f "cache/backups/all_stations_final.json.bak.$i" ]; then
        local next=$((i + 1))
        mv "cache/backups/all_stations_final.json.bak.$i" "cache/backups/all_stations_final.json.bak.$next"
      fi
    done
    mv "$FINAL_JSON" "cache/backups/all_stations_final.json.bak.1"
    [ -f "cache/backups/all_stations_final.json.bak.11" ] && rm -f "cache/backups/all_stations_final.json.bak.11"
  fi
}

show_caching_summary() {
  local dup_lineups_removed="$1"
  local dup_stations_removed="$2"
  local human_duration="$3"
  
  local num_countries=$(awk -F, 'NR>1 {print $1}' "$CSV_FILE" | sort -u | awk 'END {print NR}')
  local num_markets=$(awk 'END {print NR-1}' "$CSV_FILE")
  local num_lineups=$(awk 'END {print NR}' cache/unique_lineups.txt)
  local num_stations=$(jq 'length' "$FINAL_JSON")

  echo -e "\n=== Caching Summary ==="
  echo "Total Countries:            $num_countries"
  echo "Total Markets:              $num_markets"
  echo "Total Lineups:              $num_lineups"
  echo "Duplicate Lineups Removed:  $dup_lineups_removed"
  echo "Total Stations:             $num_stations"
  echo "Duplicate Stations Removed: $dup_stations_removed"
  echo "Time to Complete:           $human_duration"
  echo "Final station list saved to $FINAL_JSON"
  echo -e "${GREEN}Caching completed successfully!${RESET}"
}

# ============================================================================
# MAIN MENU AND APPLICATION ENTRY POINT
# ============================================================================

main_menu() {
  trap cleanup_cache EXIT
  
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== Global Station Search - Version $VERSION ===${RESET}\n"
    
    show_system_status
    
    # Show workflow guidance for new users
    if [ ! -f "$FINAL_JSON" ]; then
      show_workflow_guidance
    fi
    
    echo -e "${BOLD}Main Menu:${RESET}"
    echo "1) Manage Television Markets"
    echo "2) Run Local Caching" 
    echo "3) Search Stations (Local Cache)"
    echo "4) Direct API Search"
    echo "5) Dispatcharr Integration"
    echo "6) Settings"
    echo "q) Quit"
    
    read -p "Select option: " choice
    
    case $choice in
      1) manage_markets ;;
      2) run_local_caching && pause_for_user ;;
      3) check_database_exists && run_search_interface ;;
      4) run_direct_api_search ;;
      5) 
        if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
          run_dispatcharr_integration
        else
          echo -e "${YELLOW}Dispatcharr integration is disabled${RESET}"
          echo -e "${CYAN}Enable it in Settings > Dispatcharr Configuration${RESET}"
          pause_for_user
        fi
        ;;
      6) settings_menu ;;
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