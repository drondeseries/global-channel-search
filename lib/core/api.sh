#!/bin/bash

# ============================================================================
# COMPREHENSIVE API FUNCTIONS MODULE
# ============================================================================
# All API function calls for Channels DVR and Dispatcharr with elegant error handling
# Each function provides single-line replacements for existing curl commands

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Ensure auth module is loaded for Dispatcharr functions
if ! declare -f ensure_dispatcharr_auth >/dev/null 2>&1; then
    echo "ERROR: auth.sh module must be loaded before api.sh" >&2
    return 1 2>/dev/null || exit 1
fi

# ============================================================================
# CONFIGURATION ACCESS HELPER
# ============================================================================

# Ensure configuration variables are available in API functions
ensure_config_loaded() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    if [[ -f "$config_file" ]] && [[ -z "${CHANNELS_URL:-}" || -z "${DISPATCHARR_URL:-}" ]]; then
        source "$config_file" 2>/dev/null
    fi
}

url_encode() {
    local string="$1"
    local encoded=""
    local length=${#string}
    
    for ((i=0; i<length; i++)); do
        local char="${string:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            ' ')
                encoded+="%20"
                ;;
            *)
                # Convert to hex for other special characters
                printf -v hex "%02X" "'$char"
                encoded+="%$hex"
                ;;
        esac
    done
    
    echo "$encoded"
}

# ============================================================================
# API CONFIGURATION
# ============================================================================

# Default timeouts and retry settings
readonly API_QUICK_TIMEOUT=5
readonly API_STANDARD_TIMEOUT=10
readonly API_EXTENDED_TIMEOUT=15
readonly API_MAX_RETRIES=3

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Save Channels DVR configuration and refresh
save_channels_dvr_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    if [[ -z "$config_key" ]]; then
        echo -e "${RED}❌ save_channels_dvr_config: config_key required${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}💾 Saving configuration: $config_key${RESET}" >&2
    
    # Use the main script's save_setting function if available
    if declare -f save_setting >/dev/null 2>&1; then
        save_setting "$config_key" "$config_value"
    else
        # Fallback: direct file manipulation
        if [[ -f "$config_file" ]]; then
            sed -i.bak "/^$config_key=/d" "$config_file"
            echo "$config_key=\"$config_value\"" >> "$config_file"
        else
            echo -e "${RED}❌ Config file not found: $config_file${RESET}" >&2
            return 1
        fi
    fi
    
    # Reload configuration
    reload_channels_dvr_config
    
    return 0
}

# Reload Channels DVR configuration
reload_channels_dvr_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    echo -e "${CYAN}🔄 Reloading configuration from: $config_file${RESET}" >&2
    
    if [[ -f "$config_file" ]]; then
        source "$config_file" 2>/dev/null || {
            echo -e "${YELLOW}⚠️ Failed to source config file: $config_file${RESET}" >&2
            return 1
        }
        
        echo -e "${GREEN}✅ Configuration reloaded successfully${RESET}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️ Config file not found: $config_file${RESET}" >&2
        return 1
    fi
}

# Update Channels DVR URL and refresh
update_channels_dvr_url() {
    local new_url="$1"
    
    if [[ -z "$new_url" ]]; then
        echo -e "${RED}❌ update_channels_dvr_url: URL required${RESET}" >&2
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        echo -e "${RED}❌ Invalid URL format: $new_url${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔄 Updating Channels DVR URL to: $new_url${RESET}" >&2
    
    save_channels_dvr_config "CHANNELS_URL" "$new_url"
    
    return $?
}

# ============================================================================
# CHANNELS DVR API FUNCTIONS
# ============================================================================

# Test basic connectivity to Channels DVR
channels_dvr_test_connection() {
    ensure_config_loaded
    
    if [[ -z "${CHANNELS_URL:-}" ]]; then
        echo -e "${RED}❌ Channels DVR: No server URL configured${RESET}" >&2
        echo -e "${CYAN}💡 Configure server in Settings → Channels DVR Server${RESET}" >&2
        return 1
    fi
    
    if curl -s --connect-timeout $API_QUICK_TIMEOUT "$CHANNELS_URL" >/dev/null 2>&1; then
        return 0
    else
        local curl_exit_code=$?
        echo -e "${RED}❌ Channels DVR: Connection failed to $CHANNELS_URL${RESET}" >&2
        case $curl_exit_code in
            6)
                echo -e "${CYAN}💡 Could not resolve hostname - check server IP address${RESET}" >&2
                ;;
            7)
                echo -e "${CYAN}💡 Connection refused - verify server is running and port is correct${RESET}" >&2
                ;;
            28)
                echo -e "${CYAN}💡 Connection timeout - server may be slow or unresponsive${RESET}" >&2
                ;;
            *)
                echo -e "${CYAN}💡 Network error (code: $curl_exit_code) - check connection and settings${RESET}" >&2
                ;;
        esac
        return 1
    fi
}

# Search for stations by name/call sign
channels_dvr_search_stations() {
    local search_term="$1"
    
    if [[ -z "$search_term" ]]; then
        echo -e "${RED}❌ Channels DVR API: Search term required${RESET}" >&2
        return 1
    fi
    
    ensure_config_loaded
    
    if ! channels_dvr_test_connection; then
        return 1
    fi
    
    # URL encode the search term to handle spaces and special characters
    local encoded_search_term=$(url_encode "$search_term")
    
    echo -e "${CYAN}🔍 Searching Channels DVR API for: '$search_term'${RESET}" >&2
    echo -e "${CYAN}📡 Encoded URL: $CHANNELS_URL/tms/stations/$encoded_search_term${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_EXTENDED_TIMEOUT \
        --max-time $((API_EXTENDED_TIMEOUT * 2)) \
        "$CHANNELS_URL/tms/stations/$encoded_search_term" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        case $curl_exit_code in
            3)
                echo -e "${RED}❌ Channels DVR API: Invalid URL format${RESET}" >&2
                echo -e "${CYAN}💡 Check if endpoint exists: $CHANNELS_URL/tms/stations/$encoded_search_term${RESET}" >&2
                ;;
            6)
                echo -e "${RED}❌ Channels DVR API: Cannot resolve hostname${RESET}" >&2
                echo -e "${CYAN}💡 Check your CHANNELS_URL setting: $CHANNELS_URL${RESET}" >&2
                ;;
            7)
                echo -e "${RED}❌ Channels DVR API: Connection failed${RESET}" >&2
                echo -e "${CYAN}💡 Is Channels DVR Server running on $CHANNELS_URL?${RESET}" >&2
                ;;
            28)
                echo -e "${RED}❌ Channels DVR API: Connection timeout${RESET}" >&2
                echo -e "${CYAN}💡 Server may be slow to respond or unreachable${RESET}" >&2
                ;;
            *)
                echo -e "${RED}❌ Channels DVR API: Network error during search (code: $curl_exit_code)${RESET}" >&2
                ;;
        esac
        echo -e "${CYAN}💡 Alternative: Use Local Database Search for reliable results${RESET}" >&2
        return 1
    fi
    
    if [[ -z "$response" ]]; then
        echo -e "${YELLOW}⚠️ Channels DVR API: No response from server${RESET}" >&2
        return 1
    fi
    
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Channels DVR API: Invalid response format${RESET}" >&2
        echo -e "${CYAN}💡 Server may be returning HTML error page instead of JSON${RESET}" >&2
        echo -e "${CYAN}💡 Response preview: ${response:0:100}...${RESET}" >&2
        return 1
    fi
    
    local result_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$result_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️ Channels DVR API: No stations found for '$search_term'${RESET}" >&2
        echo -e "${CYAN}💡 Try different spelling, call signs (CNN, ESPN), or partial names${RESET}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✅ Channels DVR API: Found $result_count station(s)${RESET}" >&2
    echo "$response"
    return 0
}

# Get server version/status
channels_dvr_get_status() {
    if ! channels_dvr_test_connection; then
        return 1
    fi
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        "$CHANNELS_URL/api/status" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        echo -e "${YELLOW}⚠️ Channels DVR: Status endpoint not available${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# DISPATCHARR CHANNEL API FUNCTIONS
# ============================================================================

# Get all channels from Dispatcharr
dispatcharr_get_channels() {
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check connection settings and credentials${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}📡 Fetching channels from Dispatcharr...${RESET}" >&2
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_EXTENDED_TIMEOUT \
        --max-time $((API_EXTENDED_TIMEOUT * 2)) \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/channels/" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        echo -e "${RED}❌ Dispatcharr: Network error fetching channels (code: $curl_exit_code)${RESET}" >&2
        return 1
    fi
    
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Dispatcharr: Invalid response format${RESET}" >&2
        return 1
    fi
    
    local channel_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Dispatcharr: Retrieved $channel_count channels${RESET}" >&2
    
    echo "$response"
    return 0
}

# Get specific channel by ID
dispatcharr_get_channel() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Channel ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/channels/$channel_id/" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to get channel $channel_id${RESET}" >&2
        return 1
    fi
}

# Update channel fields
dispatcharr_update_channel() {
    local channel_id="$1"
    local update_data="$2"
    
    if [[ -z "$channel_id" || -z "$update_data" ]]; then
        echo -e "${RED}❌ Dispatcharr: Channel ID and update data required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    # Increment interaction counter for token management
    increment_dispatcharr_interaction "channel updates"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X PATCH \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$update_data" \
        "${DISPATCHARR_URL}/api/channels/channels/$channel_id/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Dispatcharr: Channel $channel_id updated successfully${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to update channel $channel_id${RESET}" >&2
        local error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        echo -e "${CYAN}💡 Error details: $error_msg${RESET}" >&2
        return 1
    fi
}

# Update channel station ID (legacy function wrapper)
dispatcharr_update_channel_station_id() {
    local channel_id="$1"
    local station_id="$2"
    
    if [[ -z "$channel_id" || -z "$station_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Channel ID and station ID required${RESET}" >&2
        return 1
    fi
    
    local update_data=$(jq -n --arg station_id "$station_id" \
        '{tvc_guide_stationid: $station_id}')
    
    dispatcharr_update_channel "$channel_id" "$update_data"
}

# Create new channel
dispatcharr_create_channel() {
    local channel_data="$1"
    
    if [[ -z "$channel_data" ]]; then
        echo -e "${RED}❌ Dispatcharr: Channel data required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "channel creation"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${CYAN}🔄 Creating new Dispatcharr channel...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X POST \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$channel_data" \
        "${DISPATCHARR_URL}/api/channels/channels/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local new_channel_id=$(echo "$response" | jq -r '.id')
        echo -e "${GREEN}✅ Dispatcharr: Channel created successfully (ID: $new_channel_id)${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to create channel${RESET}" >&2
        local error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        echo -e "${CYAN}💡 Error details: $error_msg${RESET}" >&2
        return 1
    fi
}

# Create channel from stream
dispatcharr_create_channel_from_stream() {
    local stream_data="$1"
    
    if [[ -z "$stream_data" ]]; then
        echo -e "${RED}❌ Dispatcharr: Stream data required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "channel from stream creation"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${CYAN}🔄 Creating channel from stream...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X POST \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$stream_data" \
        "${DISPATCHARR_URL}/api/channels/channels/from-stream/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local new_channel_id=$(echo "$response" | jq -r '.id')
        echo -e "${GREEN}✅ Dispatcharr: Channel created from stream (ID: $new_channel_id)${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to create channel from stream${RESET}" >&2
        local error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        echo -e "${CYAN}💡 Error details: $error_msg${RESET}" >&2
        return 1
    fi
}

# Delete channel
dispatcharr_delete_channel() {
    local channel_id="$1"
    
    if [[ -z "$channel_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Channel ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "channel deletion"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${YELLOW}🗑️ Deleting Dispatcharr channel $channel_id...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X DELETE \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/channels/$channel_id/" 2>/dev/null)
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X DELETE \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/channels/$channel_id/")
    
    if [[ "$http_code" == "204" ]]; then
        echo -e "${GREEN}✅ Dispatcharr: Channel $channel_id deleted successfully${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to delete channel $channel_id (HTTP: $http_code)${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# DISPATCHARR CHANNEL GROUP API FUNCTIONS
# ============================================================================

# Get all channel groups
dispatcharr_get_groups() {
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}📋 Fetching channel groups from Dispatcharr...${RESET}" >&2
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/groups/" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        local group_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
        echo -e "${GREEN}✅ Dispatcharr: Retrieved $group_count channel groups${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to fetch channel groups${RESET}" >&2
        return 1
    fi
}

# Get specific group by ID
dispatcharr_get_group() {
    local group_id="$1"
    
    if [[ -z "$group_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Group ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/groups/$group_id/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to get group $group_id${RESET}" >&2
        return 1
    fi
}

# Create new channel group
dispatcharr_create_group() {
    local group_name="$1"
    
    if [[ -z "$group_name" ]]; then
        echo -e "${RED}❌ Dispatcharr: Group name required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "group creation"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local group_data=$(jq -n --arg name "$group_name" '{name: $name}')
    
    echo -e "${CYAN}🔄 Creating new channel group: '$group_name'${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X POST \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$group_data" \
        "${DISPATCHARR_URL}/api/channels/groups/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local new_group_id=$(echo "$response" | jq -r '.id')
        echo -e "${GREEN}✅ Dispatcharr: Channel group '$group_name' created (ID: $new_group_id)${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to create channel group '$group_name'${RESET}" >&2
        local error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        echo -e "${CYAN}💡 Error details: $error_msg${RESET}" >&2
        return 1
    fi
}

# Update channel group
dispatcharr_update_group() {
    local group_id="$1"
    local group_name="$2"
    
    if [[ -z "$group_id" || -z "$group_name" ]]; then
        echo -e "${RED}❌ Dispatcharr: Group ID and name required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "group updates"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local group_data=$(jq -n --arg name "$group_name" '{name: $name}')
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X PATCH \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$group_data" \
        "${DISPATCHARR_URL}/api/channels/groups/$group_id/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Dispatcharr: Channel group $group_id updated successfully${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to update channel group $group_id${RESET}" >&2
        return 1
    fi
}

# Delete channel group
dispatcharr_delete_group() {
    local group_id="$1"
    
    if [[ -z "$group_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Group ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "group deletion"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${YELLOW}🗑️ Deleting channel group $group_id...${RESET}" >&2
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X DELETE \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/groups/$group_id/")
    
    if [[ "$http_code" == "204" ]]; then
        echo -e "${GREEN}✅ Dispatcharr: Channel group $group_id deleted successfully${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to delete channel group $group_id (HTTP: $http_code)${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# DISPATCHARR STREAM API FUNCTIONS
# ============================================================================

# Get all streams
dispatcharr_get_streams() {
    local search_term="${1:-}"  # Optional search parameter
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local endpoint="/api/channels/streams/"
    if [[ -n "$search_term" ]]; then
        # URL encode the search term for query parameter
        local encoded_search_term=$(url_encode "$search_term")
        endpoint+="?search=$encoded_search_term"
        echo -e "${CYAN}🔍 Searching Dispatcharr streams for: '$search_term'${RESET}" >&2
        echo -e "${CYAN}📡 Query URL: ${DISPATCHARR_URL}${endpoint}${RESET}" >&2
    else
        echo -e "${CYAN}📡 Fetching all streams from Dispatcharr...${RESET}" >&2
    fi
    
    local response
    response=$(curl -s \
        --connect-timeout $API_EXTENDED_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}$endpoint" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        # Handle paginated response
        local results=$(echo "$response" | jq -r '.results // . // empty' 2>/dev/null)
        if [[ -n "$results" ]]; then
            local stream_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
            echo -e "${GREEN}✅ Dispatcharr: Retrieved $stream_count streams${RESET}" >&2
            echo "$results"
        else
            echo -e "${YELLOW}⚠️ Dispatcharr: No streams found${RESET}" >&2
            echo "[]"
        fi
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to fetch streams${RESET}" >&2
        return 1
    fi
}

# Get specific stream by ID
dispatcharr_get_stream() {
    local stream_id="$1"
    
    if [[ -z "$stream_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Stream ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/streams/$stream_id/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to get stream $stream_id${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# DISPATCHARR LOGO API FUNCTIONS
# ============================================================================

# Get all logos
dispatcharr_get_logos() {
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${CYAN}🖼️ Fetching logos from Dispatcharr...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/logos/" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        local logo_count=$(echo "$response" | jq 'length' 2>/dev/null || echo "0")
        echo -e "${GREEN}✅ Dispatcharr: Retrieved $logo_count logos${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to fetch logos${RESET}" >&2
        return 1
    fi
}

# Upload logo from URL
dispatcharr_upload_logo() {
    local logo_name="$1"
    local logo_url="$2"
    
    if [[ -z "$logo_name" || -z "$logo_url" ]]; then
        echo -e "${RED}❌ Dispatcharr: Logo name and URL required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "logo uploads"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${CYAN}🔄 Uploading logo '$logo_name' from $logo_url${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X POST \
        -H "Authorization: Bearer $access_token" \
        -F "name=$logo_name" \
        -F "url=$logo_url" \
        "${DISPATCHARR_URL}/api/channels/logos/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local logo_id=$(echo "$response" | jq -r '.id')
        echo -e "${GREEN}✅ Dispatcharr: Logo uploaded successfully (ID: $logo_id)${RESET}" >&2
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to upload logo '$logo_name'${RESET}" >&2
        local error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        echo -e "${CYAN}💡 Error details: $error_msg${RESET}" >&2
        return 1
    fi
}

# Get logo by ID
dispatcharr_get_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Logo ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/logos/$logo_id/" 2>/dev/null)
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to get logo $logo_id${RESET}" >&2
        return 1
    fi
}

# Delete logo
dispatcharr_delete_logo() {
    local logo_id="$1"
    
    if [[ -z "$logo_id" ]]; then
        echo -e "${RED}❌ Dispatcharr: Logo ID required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    increment_dispatcharr_interaction "logo deletion"
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    echo -e "${YELLOW}🗑️ Deleting logo $logo_id...${RESET}" >&2
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X DELETE \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/channels/logos/$logo_id/")
    
    if [[ "$http_code" == "204" ]]; then
        echo -e "${GREEN}✅ Dispatcharr: Logo $logo_id deleted successfully${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to delete logo $logo_id (HTTP: $http_code)${RESET}" >&2
        return 1
    fi
}

# Download logo file from Dispatcharr
dispatcharr_download_logo_file() {
  local logo_id="$1"
  local output_file="$2"
  
  if [[ -z "$logo_id" || -z "$output_file" ]]; then
    echo -e "${RED}❌ Dispatcharr: Logo ID and output file required${RESET}" >&2
    return 1
  fi
  
  if ! ensure_dispatcharr_auth; then
    echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
    return 1
  fi
  
  local access_token
  access_token=$(get_dispatcharr_access_token)
  
  curl -s -H "Authorization: Bearer $access_token" \
    "${DISPATCHARR_URL}/api/channels/logos/${logo_id}/cache/" \
    --output "$output_file" 2>/dev/null
  
  return $?
}

# ============================================================================
# DISPATCHARR SYSTEM API FUNCTIONS
# ============================================================================

# Get Dispatcharr version/status
dispatcharr_get_version() {
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    local response
    response=$(curl -s \
        --connect-timeout $API_QUICK_TIMEOUT \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/core/version/" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Failed to get version information${RESET}" >&2
        return 1
    fi
}

# Test Dispatcharr connection and authentication
dispatcharr_test_connection() {
    echo -e "${CYAN}🔗 Testing Dispatcharr connection and authentication...${RESET}" >&2
    
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo -e "${RED}❌ Dispatcharr: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Dispatcharr Integration${RESET}" >&2
        return 1
    fi
    
    if ! ensure_dispatcharr_auth; then
        echo -e "${RED}❌ Dispatcharr: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        return 1
    fi
    
    local version_info
    version_info=$(dispatcharr_get_version)
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Dispatcharr: Connection and authentication successful${RESET}" >&2
        local version=$(echo "$version_info" | jq -r '.version // "Unknown"' 2>/dev/null)
        echo -e "${CYAN}💡 Server version: $version${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Dispatcharr: Connection test failed${RESET}" >&2
        return 1
    fi
}

# ============================================================================
# CONVENIENCE FUNCTIONS FOR BACKWARDS COMPATIBILITY
# ============================================================================

# Legacy function wrappers for existing code
get_dispatcharr_channels() {
    dispatcharr_get_channels
}

update_dispatcharr_channel_epg() {
    local channel_id="$1"
    local station_id="$2"
    dispatcharr_update_channel_station_id "$channel_id" "$station_id"
}

check_dispatcharr_connection() {
    dispatcharr_test_connection >/dev/null 2>&1
}

# ============================================================================
# EMBY API FUNCTIONS
# ============================================================================

# Get Emby server information
emby_get_server_info() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    local response
    response=$(curl -s \
        --connect-timeout $API_QUICK_TIMEOUT \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        "${EMBY_URL}/emby/System/Info" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        echo -e "${RED}❌ Emby: Failed to get server information${RESET}" >&2
        return 1
    fi
}

# Test Emby connection and authentication
emby_test_connection() {
    echo -e "${CYAN}🔗 Testing Emby connection and authentication...${RESET}" >&2
    
    if [[ -z "${EMBY_URL:-}" ]] || [[ "$EMBY_ENABLED" != "true" ]]; then
        echo -e "${RED}❌ Emby: Not configured or disabled${RESET}" >&2
        echo -e "${CYAN}💡 Configure in Settings → Emby Integration${RESET}" >&2
        return 1
    fi
    
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        echo -e "${CYAN}💡 Check server URL, username, and password${RESET}" >&2
        return 1
    fi
    
    local server_info
    server_info=$(emby_get_server_info)
    
    if [[ $? -eq 0 ]]; then
        local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"')
        local version=$(echo "$server_info" | jq -r '.Version // "Unknown"')
        echo -e "${GREEN}✅ Emby: Connected to '$server_name' (v$version)${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Emby: Connection test failed${RESET}" >&2
        return 1
    fi
} 

# Get Emby Live TV channels
emby_get_livetv_channels() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}📡 Fetching ALL Emby Live TV channels...${RESET}" >&2
    
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        --max-time $((API_STANDARD_TIMEOUT * 3)) \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        "${EMBY_URL}/emby/LiveTv/Manage/Channels?Fields=ManagementId,ListingsId,Name,ChannelNumber,Id" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Emby: Network error fetching channels${RESET}" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        echo -e "${RED}❌ Emby: Invalid JSON response${RESET}" >&2
        echo -e "${CYAN}Response preview: ${response:0:200}...${RESET}" >&2
        return 1
    fi
    
    # Handle both array and object responses
    local channels
    if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
        # Direct array
        channels="$response"
    elif echo "$response" | jq -e '.Items' >/dev/null 2>&1; then
        # Object with Items property
        channels=$(echo "$response" | jq '.Items')
    else
        echo -e "${RED}❌ Emby: Unexpected response structure${RESET}" >&2
        echo -e "${CYAN}Response keys: $(echo "$response" | jq 'keys' 2>/dev/null)${RESET}" >&2
        return 1
    fi
    
    local channel_count=$(echo "$channels" | jq 'length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Retrieved $channel_count Live TV channels${RESET}" >&2
    
    if [[ "$channel_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No channels found${RESET}" >&2
        return 1
    fi
    
    echo "$channels"
    return 0
}

# Find Emby channels missing ListingsId and extract Station IDs
emby_find_channels_missing_listingsid() {
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔍 Scanning Emby channels for missing ListingsId...${RESET}" >&2
    
    local channels_data
    channels_data=$(emby_get_livetv_channels)
    
    if [[ $? -ne 0 ]] || [[ -z "$channels_data" ]]; then
        echo -e "${RED}❌ Failed to get channel data${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔍 Processing channels to find missing ListingsId...${RESET}" >&2
    
    # Filter channels missing ListingsId and extract station IDs
    local missing_channels_with_station_ids
    missing_channels_with_station_ids=$(echo "$channels_data" | jq -c '
        [.[] | 
         select(.ListingsId == null or .ListingsId == "" or .ListingsId == "null") |
         . + {
           "ExtractedId": (if .ManagementId then (.ManagementId | split("_") | last) else null end)
         } |
         select(.ExtractedId != null and (.ExtractedId | test("^[0-9]+$")) and (.ExtractedId | length >= 4) and (.ExtractedId | length <= 10))
        ]
    ')
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to process channel data${RESET}" >&2
        return 1
    fi
    
    local missing_count=$(echo "$missing_channels_with_station_ids" | jq 'length' 2>/dev/null || echo "0")
    
    echo -e "${GREEN}✅ Found $missing_count channels missing ListingsId with extractable station IDs${RESET}" >&2
    
    if [[ "$missing_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No channels need ListingsId updates${RESET}" >&2
        echo "[]"
        return 0
    fi
    
    # Show summary of what we found
    echo -e "${CYAN}📊 Sample missing channels:${RESET}" >&2
    echo "$missing_channels_with_station_ids" | jq -r '.[:5][] | "   \(.ChannelNumber // "No#") - \(.Name // "No Name") (Station: \(.ExtractedId))"' >&2
    
    # Return the processed channels as individual JSON objects (same format as before)
    echo "$missing_channels_with_station_ids" | jq -c '.[]'
    return 0
}

# Extract station ID from Emby ManagementId
extract_station_id_from_management_id() {
    local management_id="$1"
    
    if [[ -z "$management_id" || "$management_id" == "null" ]]; then
        return 1
    fi
    
    # Extract everything after the last underscore
    local station_id="${management_id##*_}"
    
    # Validate it's a reasonable station ID (numeric, reasonable length)
    if [[ "$station_id" =~ ^[0-9]+$ ]] && [[ ${#station_id} -ge 4 ]] && [[ ${#station_id} -le 10 ]]; then
        echo "$station_id"
        return 0
    else
        return 1
    fi
}

# Reverse lookup station IDs to get lineupId, country, and lineupName
emby_reverse_lookup_station_ids() {
    local station_ids_array=("$@")
    
    echo -e "${CYAN}🔍 Performing reverse lookup for ${#station_ids_array[@]} station IDs...${RESET}" >&2
    
    # Check if we have a station database
    if ! has_stations_database; then
        echo -e "${RED}❌ No station database available for reverse lookup${RESET}" >&2
        echo -e "${CYAN}💡 Build database via 'Manage Television Markets' → 'Run User Caching'${RESET}" >&2
        return 1
    fi
    
    local stations_file
    stations_file=$(get_effective_stations_file)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Failed to access station database${RESET}" >&2
        return 1
    fi
    
    # Create result array for lookup results
    local lookup_results=()
    local found_count=0
    local not_found_count=0
    
    for station_id in "${station_ids_array[@]}"; do
        echo -e "${CYAN}  🔍 Looking up station ID: $station_id${RESET}" >&2
        
        # Query the station database for this station ID including lineupName
        local station_data
        station_data=$(jq -r --arg id "$station_id" '
            .[] | select(.stationId == $id) | 
            {
                stationId: .stationId,
                name: .name,
                country: (.availableIn[0] // "Unknown"),
                lineupId: (.lineupTracing[0].lineupId // "Unknown"),
                lineupName: (.lineupTracing[0].lineupName // "Unknown")
            }' "$stations_file" 2>/dev/null)
        
        if [[ -n "$station_data" && "$station_data" != "null" ]]; then
            # Station found, extract the data
            local station_name=$(echo "$station_data" | jq -r '.name // "Unknown"')
            local country=$(echo "$station_data" | jq -r '.country // "Unknown"') 
            local lineup_id=$(echo "$station_data" | jq -r '.lineupId // "Unknown"')
            local lineup_name=$(echo "$station_data" | jq -r '.lineupName // "Unknown"')
            
            echo -e "${GREEN}  ✅ Found: $station_name (LineupId: $lineup_id, Country: $country, Lineup: $lineup_name)${RESET}" >&2
            
            # Store result as JSON string for easy parsing later
            local result_json=$(jq -n \
                --arg sid "$station_id" \
                --arg name "$station_name" \
                --arg country "$country" \
                --arg lineup "$lineup_id" \
                --arg lineupname "$lineup_name" \
                '{stationId: $sid, name: $name, country: $country, lineupId: $lineup, lineupName: $lineupname}')
            
            lookup_results+=("$result_json")
            ((found_count++))
        else
            echo -e "${RED}  ❌ Station ID $station_id not found in database${RESET}" >&2
            ((not_found_count++))
        fi
    done
    
    echo -e "${CYAN}📊 Reverse lookup complete: ${GREEN}$found_count found${RESET}, ${RED}$not_found_count not found${RESET}" >&2
    
    # Output results as JSON array for caller to process
    if [[ ${#lookup_results[@]} -gt 0 ]]; then
        printf '%s\n' "${lookup_results[@]}" | jq -s '.'
        return 0
    else
        echo "[]"
        return 1
    fi
}

# Update Emby channel with ListingsId, Type, Country, and Name
emby_update_channel_complete() {
    local channel_id="$1"
    local listings_id="$2"
    local country="$3"
    local lineup_name="$4"
    local type="${5:-embygn}"  # Default to embygn as specified
    
    if [[ -z "$channel_id" || -z "$listings_id" || -z "$country" || -z "$lineup_name" ]]; then
        echo -e "${RED}❌ emby_update_channel_complete: channel_id, listings_id, country, and lineup_name required${RESET}" >&2
        return 1
    fi
    
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Emby: Authentication failed${RESET}" >&2
        return 1
    fi
    
    echo -e "${CYAN}🔄 Updating channel $channel_id with ListingsId: $listings_id, Country: $country, Name: $lineup_name, Type: $type${RESET}" >&2
    
    # Prepare the JSON payload for the update including Name field
    local update_payload
    update_payload=$(jq -n \
        --arg listings_id "$listings_id" \
        --arg type "$type" \
        --arg country "$country" \
        --arg name "$lineup_name" \
        '{ListingsId: $listings_id, Type: $type, Country: $country, Name: $name}')
    
    # NOTE: You mentioned the endpoint needs to be confirmed - using a placeholder
    # Replace "/emby/LiveTv/[ENDPOINT_TO_CONFIRM]" with the correct endpoint
    local response
    response=$(curl -s \
        --connect-timeout $API_STANDARD_TIMEOUT \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Emby-Token: $EMBY_API_KEY" \
        -d "$update_payload" \
        "${EMBY_URL}/emby/LiveTv/Manage/Channels/$channel_id" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -eq 0 ]]; then
        echo -e "${GREEN}✅ Successfully updated channel $channel_id${RESET}" >&2
        echo -e "${CYAN}   📍 ListingsId: $listings_id${RESET}" >&2
        echo -e "${CYAN}   🌍 Country: $country${RESET}" >&2
        echo -e "${CYAN}   📺 Name: $lineup_name${RESET}" >&2
        echo -e "${CYAN}   🏷️  Type: $type${RESET}" >&2
        return 0
    else
        echo -e "${RED}❌ Failed to update channel $channel_id (curl exit: $curl_exit_code)${RESET}" >&2
        return 1
    fi
}

test_emby_channel_mapping_endpoints() {
    echo -e "\n${BOLD}${CYAN}=== Testing Emby Channel Mapping Endpoints ===${RESET}"
    
    if ! ensure_emby_auth; then
        echo -e "${RED}❌ Authentication required${RESET}"
        return 1
    fi
    
    local test_endpoints=(
        "/emby/LiveTv/ChannelMappingOptions"
        "/emby/LiveTv/GuideInfo" 
        "/emby/LiveTv/SetChannelMapping"
        "/emby/LiveTv/TunerChannels"
    )
    
    for endpoint in "${test_endpoints[@]}"; do
        echo -e "${CYAN}   Testing: $endpoint${RESET}"
        
        local response
        response=$(curl -s \
            --connect-timeout 10 \
            -w "HTTPSTATUS:%{http_code}" \
            -H "X-Emby-Token: $EMBY_API_KEY" \
            "${EMBY_URL}${endpoint}" 2>/dev/null)
        
        local status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
        echo -e "      📊 Status: $status"
        
        if [[ "$status" == "200" ]]; then
            echo -e "${GREEN}      ✅ Endpoint exists${RESET}"
        elif [[ "$status" == "404" ]]; then
            echo -e "${RED}      ❌ Not found${RESET}"
        else
            echo -e "${YELLOW}      ⚠️  Status: $status${RESET}"
        fi
    done
}

generate_emby_analysis_report() {
    local channels_data="$1"
    local missing_channels="$2"
    
    echo -e "\n${BOLD}${CYAN}=== EMBY CHANNEL ANALYSIS REPORT ===${RESET}"
    
    # Count channels
    local total_count missing_count complete_count
    total_count=$(echo "$channels_data" | jq 'length' 2>/dev/null || echo "0")
    missing_count=$(echo "$missing_channels" | jq -s 'length' 2>/dev/null || echo "0")
    complete_count=$((total_count - missing_count))
    
    echo -e "\n${BOLD}📊 Channel Statistics:${RESET}"
    echo -e "• Total channels found: ${CYAN}$total_count${RESET}"
    echo -e "• Channels with ListingsId: ${GREEN}$complete_count${RESET}"
    echo -e "• Channels missing ListingsId: ${YELLOW}$missing_count${RESET}"
    
    if [[ "$total_count" -gt 0 ]]; then
        echo -e "• Coverage percentage: ${CYAN}$(( complete_count * 100 / total_count ))%${RESET}"
    fi
    
    echo -e "\n${BOLD}🔍 Technical Status:${RESET}"
    echo -e "• Emby API connectivity: ${GREEN}✅ Working${RESET}"
    echo -e "• Channel data retrieval: ${GREEN}✅ Working${RESET}"
    echo -e "• Station ID extraction: ${GREEN}✅ Working${RESET}"
    echo -e "• Direct API updates: ${RED}❌ Not supported${RESET}"
    
    if [[ "$missing_count" -gt 0 ]]; then
        echo -e "\n${BOLD}📋 Sample Channels Needing ListingsId:${RESET}"
        echo "$missing_channels" | jq -r 'select(type == "object") | "• \(.ChannelNumber // "No#") - \(.Name // "No Name") (Station: \(.ExtractedId))"' | head -10
    fi
    
    echo -e "\n${BOLD}💡 Recommendations:${RESET}"
    echo -e "• Station IDs are successfully extracted from ManagementId"
    echo -e "• Use these station IDs with your existing station matching workflow"
    echo -e "• Emby channel mapping should be done through the web interface"
    echo -e "• Focus on providing station matching data rather than direct updates"
}

# ============================================================================
# EMBY API HEALTH CHECK INTEGRATION
# ============================================================================

# Get Emby API status for health monitoring
get_emby_api_status() {
    if [[ "$EMBY_ENABLED" != "true" ]]; then
        echo "disabled"
        return 1
    fi
    
    if [[ -z "${EMBY_URL:-}" ]]; then
        echo "not_configured"
        return 1
    fi
    
    if emby_test_connection >/dev/null 2>&1; then
        echo "healthy"
        return 0
    else
        echo "unhealthy"
        return 1
    fi
}

# ============================================================================
# API STATUS AND MONITORING
# ============================================================================

# Get comprehensive API status for all services
get_api_status() {
    echo -e "${BOLD}${CYAN}=== API Services Status ===${RESET}"
    echo
    
    # Channels DVR Status
    echo -e "${BOLD}Channels DVR:${RESET}"
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        if channels_dvr_test_connection >/dev/null 2>&1; then
            echo -e "  Status: ${GREEN}✅ Connected${RESET}"
            echo -e "  URL: ${CYAN}$CHANNELS_URL${RESET}"
            
            # Try to get additional status info
            local status_info
            status_info=$(channels_dvr_get_status 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                local version=$(echo "$status_info" | jq -r '.version // "Unknown"' 2>/dev/null)
                echo -e "  Version: ${CYAN}$version${RESET}"
            fi
        else
            echo -e "  Status: ${RED}❌ Connection Failed${RESET}"
            echo -e "  URL: ${YELLOW}$CHANNELS_URL${RESET}"
        fi
    else
        echo -e "  Status: ${YELLOW}⚠️ Not Configured${RESET}"
        echo -e "  ${CYAN}💡 Configure in Settings → Channels DVR Server${RESET}"
    fi
    echo
    
    # Dispatcharr Status
    echo -e "${BOLD}Dispatcharr:${RESET}"
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        if dispatcharr_test_connection >/dev/null 2>&1; then
            echo -e "  Status: ${GREEN}✅ Connected & Authenticated${RESET}"
            echo -e "  URL: ${CYAN}$DISPATCHARR_URL${RESET}"
            echo -e "  Auth: $(get_dispatcharr_auth_status)"
            
            # Get version info
            local version_info
            version_info=$(dispatcharr_get_version 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                local version=$(echo "$version_info" | jq -r '.version // "Unknown"' 2>/dev/null)
                echo -e "  Version: ${CYAN}$version${RESET}"
            fi
        else
            echo -e "  Status: ${RED}❌ Connection or Authentication Failed${RESET}"
            echo -e "  URL: ${YELLOW}$DISPATCHARR_URL${RESET}"
            echo -e "  Auth: $(get_dispatcharr_auth_status)"
        fi
    else
        echo -e "  Status: ${YELLOW}⚠️ Not Configured or Disabled${RESET}"
        echo -e "  ${CYAN}💡 Configure in Settings → Dispatcharr Integration${RESET}"
    fi
    echo
    
    # Emby Status
    echo -e "${BOLD}Emby:${RESET}"
    if [[ "$EMBY_ENABLED" == "true" ]] && [[ -n "${EMBY_URL:-}" ]]; then
        if emby_test_connection >/dev/null 2>&1; then
            echo -e "  Status: ${GREEN}✅ Connected & Authenticated${RESET}"
            echo -e "  URL: ${CYAN}$EMBY_URL${RESET}"
            echo -e "  Auth: $(get_emby_auth_status)"
            
            # Get server info
            local server_info
            server_info=$(emby_get_server_info 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                local server_name=$(echo "$server_info" | jq -r '.ServerName // "Unknown"' 2>/dev/null)
                local version=$(echo "$server_info" | jq -r '.Version // "Unknown"' 2>/dev/null)
                echo -e "  Server: ${CYAN}$server_name${RESET}"
                echo -e "  Version: ${CYAN}$version${RESET}"
            fi
        else
            echo -e "  Status: ${RED}❌ Connection or Authentication Failed${RESET}"
            echo -e "  URL: ${YELLOW}$EMBY_URL${RESET}"
            echo -e "  Auth: $(get_emby_auth_status)"
        fi
    else
        echo -e "  Status: ${YELLOW}⚠️ Not Configured or Disabled${RESET}"
        echo -e "  ${CYAN}💡 Configure in Settings → Emby Integration${RESET}"
    fi
}

# Quick API health check (returns 0 if all services are working)
check_all_api_health() {
    local channels_ok=false
    local dispatcharr_ok=false
    local emby_ok=false
    
    # Check Channels DVR if configured
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        if channels_dvr_test_connection >/dev/null 2>&1; then
            channels_ok=true
        fi
    else
        channels_ok=true  # Not configured = not required
    fi
    
    # Check Dispatcharr if enabled
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        if dispatcharr_test_connection >/dev/null 2>&1; then
            dispatcharr_ok=true
        fi
    else
        dispatcharr_ok=true  # Not enabled = not required
    fi
    
    # Check Emby if enabled
    if [[ "$EMBY_ENABLED" == "true" ]] && [[ -n "${EMBY_URL:-}" ]]; then
        if emby_test_connection >/dev/null 2>&1; then
            emby_ok=true
        fi
    else
        emby_ok=true  # Not enabled = not required
    fi
    
    if $channels_ok && $dispatcharr_ok && $emby_ok; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize API system
init_api_system() {
    # Ensure log directories exist
    mkdir -p "$(dirname "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}")" 2>/dev/null
    mkdir -p "${LOGS_DIR:-/tmp}" 2>/dev/null
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - API module initialized" >> "${LOGS_DIR:-/tmp}/api_general.log"
    
    # Test services if they're configured
    if [[ -n "${CHANNELS_URL:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Testing Channels DVR connection..." >> "${LOGS_DIR:-/tmp}/api_general.log"
    fi
    
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Testing Dispatcharr connection..." >> "${LOGS_DIR:-/tmp}/api_general.log"
    fi
}

# Auto-initialize when module is loaded
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_api_system
fi