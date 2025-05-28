#!/bin/bash

# === Global Station Search ===
# Description: Television station search tool using Channels DVR API
# Created: 2025/05/26
# Last Modified: 2025/05/27
VERSION="0.6.0-beta"

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
    local station_count=$(jq length "$FINAL_JSON" 2>/dev/null || echo "0")
    echo -e "${GREEN}Station Database: $station_count stations cached${RESET}"
  else
    echo -e "${YELLOW}Station Database: No data cached - run caching first${RESET}"
  fi
  
  local market_count=$(awk 'END {print NR-1}' "$CSV_FILE" 2>/dev/null || echo "0")
  echo -e "Markets Configured: $market_count"
  echo -e "Server: $CHANNELS_URL"
  echo
}

check_database_exists() {
  if [ ! -f "$FINAL_JSON" ]; then
    echo -e "${RED}No station database found. Please run caching first.${RESET}"
    pause_for_user
    return 1
  fi
  return 0
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
    
    show_current_markets
    
    echo -e "${BOLD}Options:${RESET}"
    echo "a) Add Market"
    echo "b) Remove Market"
    echo "c) Import Markets from File"
    echo "d) Export Markets to File"
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) add_market && pause_for_user ;;
      b|B) remove_market && pause_for_user ;;
      c|C) import_markets && pause_for_user ;;
      d|D) export_markets && pause_for_user ;;
      q|Q|"") break ;;
      *) show_invalid_choice ;;
    esac
  done
}

add_market() {
  echo -e "\n${BOLD}Add New Market${RESET}"
  
  local country zip
  
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
  
  # Create CSV file with header if it doesn't exist
  if [ ! -f "$CSV_FILE" ]; then
    echo "Country,ZIP" > "$CSV_FILE"
  fi
  
  if grep -q "^$country,$zip$" "$CSV_FILE"; then
    echo -e "${RED}Market $country/$zip already exists${RESET}"
    return 1
  else
    echo "$country,$zip" >> "$CSV_FILE"
    echo -e "${GREEN}Added market: $country/$zip${RESET}"
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
    echo "q) Back to Main Menu"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      a|A) change_server_settings && pause_for_user ;;
      b|B) toggle_logo_display && pause_for_user ;;
      c|C) configure_resolution_filter && pause_for_user ;;
      d|D) configure_country_filter && pause_for_user ;;
      e|E) cache_management_menu ;;
      f|F) reset_all_settings && pause_for_user ;;
      g|G) export_settings && pause_for_user ;;
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

# ============================================================================
# LOCAL CACHING FUNCTIONS
# ============================================================================

run_local_caching() {
  clear
  echo -e "${BOLD}${CYAN}=== Local Caching ===${RESET}\n"
  
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    echo -e "${RED}No markets configured. Please add markets first.${RESET}"
    return 1
  fi
  
  local market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  echo -e "${YELLOW}This will refresh all lineups and channels for $market_count configured markets.${RESET}"
  echo -e "This process may take considerable time for large market lists."
  echo
  
  if ! confirm_action "Continue with full cache refresh?"; then
    echo -e "${YELLOW}Cache refresh cancelled${RESET}"
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
    
    echo -e "${BOLD}Main Menu:${RESET}"
    echo "1) Manage Television Markets"
    echo "2) Run Local Caching"
    echo "3) Search Stations"
    echo "4) Settings"
    echo "q) Quit"
    echo
    
    read -p "Select option: " choice
    
    case $choice in
      1) manage_markets ;;
      2) run_local_caching && pause_for_user ;;
      3) check_database_exists && run_search_interface ;;
      4) settings_menu ;;
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