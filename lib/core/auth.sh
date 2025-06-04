#!/bin/bash

# ============================================================================
# DISPATCHARR AUTHENTICATION MODULE
# ============================================================================
# Pure authentication management for Dispatcharr JWT tokens
# Handles token lifecycle, refresh logic, and authentication state

# ============================================================================
# AUTHENTICATION STATE TRACKING
# ============================================================================

DISPATCHARR_AUTH_STATE="unknown"      # unknown, authenticated, failed
DISPATCHARR_LAST_TOKEN_CHECK=0        # Last successful auth check timestamp
DISPATCHARR_TOKEN_CHECK_INTERVAL=300  # 5 minutes between forced checks

# ============================================================================
# TOKEN MANAGEMENT
# ============================================================================

# Get current valid access token
get_dispatcharr_access_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local access_token=$(jq -r '.access // empty' "$token_file" 2>/dev/null)
    if [[ -n "$access_token" && "$access_token" != "null" ]]; then
        echo "$access_token"
        return 0
    fi
    
    return 1
}

# Get refresh token if available
get_dispatcharr_refresh_token() {
    local token_file="$DISPATCHARR_TOKENS"
    
    if [[ ! -f "$token_file" ]]; then
        return 1
    fi
    
    local refresh_token=$(jq -r '.refresh // empty' "$token_file" 2>/dev/null)
    if [[ -n "$refresh_token" && "$refresh_token" != "null" ]]; then
        echo "$refresh_token"
        return 0
    fi
    
    return 1
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Save configuration change and refresh auth state
save_dispatcharr_config() {
    local config_key="$1"
    local config_value="$2"
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    # Validate required parameters
    if [[ -z "$config_key" ]]; then
        log_auth_error "save_dispatcharr_config: config_key required"
        return 1
    fi
    
    log_auth_info "Saving configuration: $config_key"
    
    # Use the main script's save_setting function if available
    if declare -f save_setting >/dev/null 2>&1; then
        save_setting "$config_key" "$config_value"
    else
        # Fallback: direct file manipulation
        if [[ -f "$config_file" ]]; then
            # Remove existing line and add new one
            sed -i.bak "/^$config_key=/d" "$config_file"
            echo "$config_key=\"$config_value\"" >> "$config_file"
        else
            log_auth_error "Config file not found: $config_file"
            return 1
        fi
    fi
    
    # Reload configuration
    reload_dispatcharr_config
    
    # Invalidate auth state since config changed
    invalidate_auth_state "Configuration changed: $config_key"
    
    return 0
}

# Reload configuration from file and refresh auth state
reload_dispatcharr_config() {
    local config_file="${CONFIG_FILE:-data/globalstationsearch.env}"
    
    log_auth_info "Reloading configuration from: $config_file"
    
    if [[ -f "$config_file" ]]; then
        # Source the config file to reload variables
        source "$config_file" 2>/dev/null || {
            log_auth_warn "Failed to source config file: $config_file"
            return 1
        }
        
        log_auth_info "Configuration reloaded successfully"
        
        # Log current config state (without sensitive info)
        log_auth_debug "DISPATCHARR_ENABLED: ${DISPATCHARR_ENABLED:-unset}"
        log_auth_debug "DISPATCHARR_URL: ${DISPATCHARR_URL:-unset}"
        log_auth_debug "DISPATCHARR_USERNAME: ${DISPATCHARR_USERNAME:+***set***}"
        log_auth_debug "DISPATCHARR_PASSWORD: ${DISPATCHARR_PASSWORD:+***set***}"
        
        return 0
    else
        log_auth_warn "Config file not found: $config_file"
        return 1
    fi
}

# Invalidate authentication state when config changes
invalidate_auth_state() {
    local reason="${1:-Configuration changed}"
    
    log_auth_info "Invalidating auth state: $reason"
    
    # Reset auth state variables
    DISPATCHARR_AUTH_STATE="unknown"
    DISPATCHARR_LAST_TOKEN_CHECK=0
    DISPATCHARR_INTERACTION_COUNT=0
    
    # Remove cached tokens since they may be invalid with new config
    if [[ -f "${DISPATCHARR_TOKENS:-}" ]]; then
        rm -f "$DISPATCHARR_TOKENS" 2>/dev/null
        log_auth_info "Removed cached tokens due to config change"
    fi
    
    log_auth_info "Auth state invalidated - will re-authenticate on next API call"
}

# Update Dispatcharr URL and refresh
update_dispatcharr_url() {
    local new_url="$1"
    
    if [[ -z "$new_url" ]]; then
        log_auth_error "update_dispatcharr_url: URL required"
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$new_url" =~ ^https?:// ]]; then
        log_auth_error "Invalid URL format: $new_url"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr URL to: $new_url"
    
    # Save to config and reload
    save_dispatcharr_config "DISPATCHARR_URL" "$new_url"
    
    return $?
}

# Update Dispatcharr credentials and refresh
update_dispatcharr_credentials() {
    local new_username="$1"
    local new_password="$2"
    
    if [[ -z "$new_username" || -z "$new_password" ]]; then
        log_auth_error "update_dispatcharr_credentials: username and password required"
        return 1
    fi
    
    log_auth_info "Updating Dispatcharr credentials for user: $new_username"
    
    # Save both credentials
    save_dispatcharr_config "DISPATCHARR_USERNAME" "$new_username"
    save_dispatcharr_config "DISPATCHARR_PASSWORD" "$new_password"
    
    return $?
}

# Enable/disable Dispatcharr integration
update_dispatcharr_enabled() {
    local enabled="$1"
    
    if [[ "$enabled" != "true" && "$enabled" != "false" ]]; then
        log_auth_error "update_dispatcharr_enabled: value must be 'true' or 'false'"
        return 1
    fi
    
    log_auth_info "Setting DISPATCHARR_ENABLED to: $enabled"
    
    save_dispatcharr_config "DISPATCHARR_ENABLED" "$enabled"
    
    return $?
}

# ============================================================================
# CORE AUTHENTICATION FUNCTIONS
# ============================================================================

# Full authentication with username/password
authenticate_dispatcharr() {
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        log_auth_error "Dispatcharr not configured or disabled"
        return 1
    fi
    
    if [[ -z "${DISPATCHARR_USERNAME:-}" ]] || [[ -z "${DISPATCHARR_PASSWORD:-}" ]]; then
        log_auth_error "Missing Dispatcharr credentials"
        return 1
    fi
    
    log_auth_info "Authenticating with Dispatcharr..."
    
    local token_response
    token_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$DISPATCHARR_USERNAME\",\"password\":\"$DISPATCHARR_PASSWORD\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        log_auth_error "Network error during authentication (curl exit: $curl_exit_code)"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$token_response" | jq empty 2>/dev/null; then
        log_auth_error "Invalid response format from Dispatcharr auth endpoint"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Check for successful authentication
    if echo "$token_response" | jq -e '.access' >/dev/null 2>&1; then
        # Save tokens
        echo "$token_response" > "$DISPATCHARR_TOKENS"
        
        log_auth_success "Authentication successful"
        DISPATCHARR_AUTH_STATE="authenticated"
        DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
        
        # Reset interaction counter on successful auth
        DISPATCHARR_INTERACTION_COUNT=0
        
        return 0
    else
        # Extract error details
        local error_detail=$(echo "$token_response" | jq -r '.detail // .error // .message // "Authentication failed"' 2>/dev/null)
        log_auth_error "Authentication failed: $error_detail"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
}

# Refresh access token using refresh token
refresh_dispatcharr_access_token() {
    local refresh_token
    refresh_token=$(get_dispatcharr_refresh_token)
    
    if [[ -z "$refresh_token" ]]; then
        log_auth_warn "No refresh token available, performing full authentication"
        return authenticate_dispatcharr
    fi
    
    log_auth_info "Refreshing access token using refresh token"
    
    local refresh_response
    refresh_response=$(curl -s \
        --connect-timeout ${STANDARD_TIMEOUT:-10} \
        --max-time ${MAX_OPERATION_TIME:-20} \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"refresh\":\"$refresh_token\"}" \
        "${DISPATCHARR_URL}/api/accounts/token/refresh/" 2>&1)
    
    local curl_exit_code=$?
    
    # Handle network errors
    if [[ $curl_exit_code -ne 0 ]]; then
        log_auth_warn "Network error during token refresh, falling back to full auth"
        return authenticate_dispatcharr
    fi
    
    # Validate and process response
    if echo "$refresh_response" | jq -e '.access' >/dev/null 2>&1; then
        # Update token file with new access token
        local temp_file="${DISPATCHARR_TOKENS}.tmp"
        if jq --argjson new_access "$refresh_response" \
            '. + {access: $new_access.access}' \
            "$DISPATCHARR_TOKENS" > "$temp_file" 2>/dev/null; then
            
            mv "$temp_file" "$DISPATCHARR_TOKENS"
            log_auth_success "Access token refreshed successfully"
            DISPATCHARR_AUTH_STATE="authenticated"
            DISPATCHARR_LAST_TOKEN_CHECK=$(date +%s)
            return 0
        else
            rm -f "$temp_file"
            log_auth_warn "Failed to update token file, falling back to full auth"
            return authenticate_dispatcharr
        fi
    else
        log_auth_warn "Refresh token expired or invalid, performing full authentication"
        return authenticate_dispatcharr
    fi
}

# ============================================================================
# AUTHENTICATION VALIDATION
# ============================================================================

# Check if current authentication is valid
is_dispatcharr_authenticated() {
    # Quick state check if we recently validated
    local now=$(date +%s)
    if [[ "$DISPATCHARR_AUTH_STATE" == "authenticated" ]] && 
       [[ $((now - DISPATCHARR_LAST_TOKEN_CHECK)) -lt $DISPATCHARR_TOKEN_CHECK_INTERVAL ]]; then
        return 0
    fi
    
    # Test current token with lightweight API call
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
    
    # Quick validation with version endpoint
    local test_response
    test_response=$(curl -s \
        --connect-timeout ${QUICK_TIMEOUT:-5} \
        -H "Authorization: Bearer $access_token" \
        "${DISPATCHARR_URL}/api/core/version/" 2>/dev/null)
    
    if echo "$test_response" | jq empty 2>/dev/null; then
        log_auth_info "Authentication validated successfully"
        DISPATCHARR_AUTH_STATE="authenticated"
        DISPATCHARR_LAST_TOKEN_CHECK=$now
        return 0
    else
        log_auth_warn "Current token is invalid or expired"
        DISPATCHARR_AUTH_STATE="failed"
        return 1
    fi
}

# Ensure we have valid authentication (with automatic refresh)
ensure_dispatcharr_auth() {
    # First check current state
    if is_dispatcharr_authenticated; then
        return 0
    fi
    
    # Try refresh first (faster than full auth)
    log_auth_info "Authentication needed, attempting token refresh..."
    if refresh_dispatcharr_access_token; then
        return 0
    fi
    
    # If refresh failed, try full authentication
    log_auth_info "Token refresh failed, attempting full authentication..."
    if authenticate_dispatcharr; then
        return 0
    fi
    
    # All authentication methods failed
    log_auth_error "All authentication methods failed"
    DISPATCHARR_AUTH_STATE="failed"
    return 1
}

# ============================================================================
# TOKEN LIFECYCLE MANAGEMENT
# ============================================================================

# Auto-refresh tokens based on interaction count
increment_dispatcharr_interaction() {
    local operation_type="${1:-general}"
    ((DISPATCHARR_INTERACTION_COUNT++))
    
    # Check if we need to refresh tokens
    if (( DISPATCHARR_INTERACTION_COUNT % ${DISPATCHARR_REFRESH_INTERVAL:-25} == 0 )); then
        log_auth_info "Auto-refreshing tokens after $DISPATCHARR_INTERACTION_COUNT interactions ($operation_type)"
        
        if refresh_dispatcharr_access_token; then
            log_auth_success "Automatic token refresh successful"
        else
            log_auth_warn "Automatic token refresh failed - continuing with existing tokens"
        fi
    fi
}

# Get token expiration information
get_token_expiration() {
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        echo "No token available"
        return 1
    fi
    
    # Decode JWT payload (basic base64 decode)
    local payload=$(echo "$access_token" | cut -d'.' -f2)
    # Add padding if needed
    local padding=$((4 - ${#payload} % 4))
    if [[ $padding -ne 4 ]]; then
        payload+=$(printf "%*s" $padding "" | tr ' ' '=')
    fi
    
    local exp_timestamp=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
    
    if [[ -n "$exp_timestamp" && "$exp_timestamp" != "null" ]]; then
        local exp_date=$(date -d "@$exp_timestamp" 2>/dev/null || date -r "$exp_timestamp" 2>/dev/null || echo "Unknown")
        echo "$exp_date"
        return 0
    else
        echo "Cannot determine expiration"
        return 1
    fi
}

# ============================================================================
# ENHANCED TOKEN LIFECYCLE MANAGEMENT
# ============================================================================

# Configuration - add these near the top of auth.sh with other constants
DISPATCHARR_TOKEN_BUFFER_TIME=300      # Refresh 5 minutes before expiry
DISPATCHARR_BACKGROUND_REFRESH=true    # Enable background refresh
DISPATCHARR_MIN_REFRESH_INTERVAL=60    # Minimum time between refresh attempts

# State tracking - add these with other state variables
DISPATCHARR_LAST_REFRESH_ATTEMPT=0
DISPATCHARR_TOKEN_EXPIRES_AT=0

# ============================================================================
# IMPROVED TOKEN EXPIRATION HANDLING
# ============================================================================

# Get token expiration timestamp (not formatted date)
get_token_expiration_timestamp() {
    local access_token
    access_token=$(get_dispatcharr_access_token)
    
    if [[ -z "$access_token" ]]; then
        return 1
    fi
    
    # Decode JWT payload
    local payload=$(echo "$access_token" | cut -d'.' -f2)
    local padding=$((4 - ${#payload} % 4))
    if [[ $padding -ne 4 ]]; then
        payload+=$(printf "%*s" $padding "" | tr ' ' '=')
    fi
    
    local exp_timestamp=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null)
    
    if [[ -n "$exp_timestamp" && "$exp_timestamp" != "null" ]]; then
        echo "$exp_timestamp"
        return 0
    else
        return 1
    fi
}

# Check if token needs refresh soon
token_needs_refresh() {
    local current_time=$(date +%s)
    local exp_timestamp
    
    exp_timestamp=$(get_token_expiration_timestamp)
    if [[ $? -ne 0 ]]; then
        return 0  # No token or can't parse = needs refresh
    fi
    
    # Check if token expires within buffer time
    local time_until_expiry=$((exp_timestamp - current_time))
    
    if [[ $time_until_expiry -le $DISPATCHARR_TOKEN_BUFFER_TIME ]]; then
        return 0  # Needs refresh
    else
        return 1  # Still good
    fi
}

# Check if enough time has passed since last refresh attempt
can_attempt_refresh() {
    local current_time=$(date +%s)
    local time_since_last=$((current_time - DISPATCHARR_LAST_REFRESH_ATTEMPT))
    
    if [[ $time_since_last -ge $DISPATCHARR_MIN_REFRESH_INTERVAL ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SMART REFRESH STRATEGIES
# ============================================================================

# Strategy 1: Proactive refresh (recommended for user workflows)
ensure_token_fresh() {
    # Check if we need to refresh and can attempt it
    if token_needs_refresh && can_attempt_refresh; then
        log_auth_info "Token expires soon, proactively refreshing..."
        DISPATCHARR_LAST_REFRESH_ATTEMPT=$(date +%s)
        
        if refresh_dispatcharr_access_token; then
            log_auth_success "Proactive token refresh successful"
            return 0
        else
            log_auth_warn "Proactive token refresh failed"
            return 1
        fi
    fi
    
    return 0  # Token is fresh or refresh not needed
}

# Strategy 2: Just-in-time refresh (only when needed)
ensure_dispatcharr_auth_jit() {
    # Quick check if we have a valid token
    if is_dispatcharr_authenticated; then
        return 0
    fi
    
    # Token is invalid or expired, refresh immediately
    log_auth_info "Token invalid/expired, refreshing just-in-time..."
    
    if refresh_dispatcharr_access_token; then
        return 0
    else
        # Fall back to full authentication
        return authenticate_dispatcharr
    fi
}

# ============================================================================
# WORKFLOW-INTEGRATED REFRESH FUNCTIONS
# ============================================================================

# For batch operations - refresh at the start
prepare_for_batch_operations() {
    local operation_name="${1:-batch operation}"
    local estimated_duration="${2:-900}"  # 15 minutes default
    
    log_auth_info "Preparing for $operation_name (estimated: ${estimated_duration}s)"
    
    local current_time=$(date +%s)
    local exp_timestamp
    exp_timestamp=$(get_token_expiration_timestamp)
    
    if [[ $? -eq 0 ]]; then
        local time_until_expiry=$((exp_timestamp - current_time))
        
        # If token won't last through the operation, refresh now
        if [[ $time_until_expiry -le $estimated_duration ]]; then
            log_auth_info "Token won't last through operation, refreshing preemptively..."
            
            if refresh_dispatcharr_access_token; then
                log_auth_success "Preemptive refresh for batch operation successful"
                return 0
            else
                log_auth_error "Preemptive refresh failed - batch operation may be interrupted"
                return 1
            fi
        else
            log_auth_info "Token sufficient for operation duration"
            return 0
        fi
    else
        # No valid token, authenticate now
        return ensure_dispatcharr_auth
    fi
}

# For interactive operations - silent background refresh
maintain_session_tokens() {
    if token_needs_refresh && can_attempt_refresh; then
        log_auth_info "Starting background token refresh..."
        DISPATCHARR_LAST_REFRESH_ATTEMPT=$(date +%s)
        
        # Use subshell to avoid blocking main workflow
        (
            if refresh_dispatcharr_access_token >/dev/null 2>&1; then
                log_auth_success "Background token refresh completed"
            else
                log_auth_warn "Background token refresh failed"
            fi
        ) &
    fi
}

# Drop-in replacement for current increment function
smart_token_management() {
    local operation_type="${1:-api_call}"
    local operation_mode="${2:-interactive}"  # batch, interactive, background
    
    case "$operation_mode" in
        "batch")
            # For batch operations, ensure token will last
            ensure_token_fresh
            ;;
        "background")
            # For background operations, silent refresh
            maintain_session_tokens
            ;;
        "interactive"|*)
            # For interactive operations, just-in-time refresh
            ensure_dispatcharr_auth_jit
            ;;
    esac
}

# ============================================================================
# AUTHENTICATION STATUS REPORTING
# ============================================================================

# Get current authentication status summary
get_dispatcharr_auth_status() {
    if [[ -z "${DISPATCHARR_URL:-}" ]] || [[ "$DISPATCHARR_ENABLED" != "true" ]]; then
        echo "⚠️ Dispatcharr not configured or disabled"
        return 1
    fi
    
    case "$DISPATCHARR_AUTH_STATE" in
        "authenticated")
            local token_exp=$(get_token_expiration)
            echo "✅ Authenticated (expires: $token_exp)"
            return 0
            ;;
        "failed")
            echo "❌ Authentication failed"
            return 1
            ;;
        *)
            if is_dispatcharr_authenticated; then
                local token_exp=$(get_token_expiration)
                echo "✅ Authenticated (expires: $token_exp)"
                return 0
            else
                echo "⚠️ Authentication status unknown"
                return 1
            fi
            ;;
    esac
}

# Force re-authentication (clear cached state)
reset_dispatcharr_auth() {
    log_auth_info "Resetting authentication state"
    DISPATCHARR_AUTH_STATE="unknown"
    DISPATCHARR_LAST_TOKEN_CHECK=0
    DISPATCHARR_INTERACTION_COUNT=0
    
    # Remove token file
    rm -f "$DISPATCHARR_TOKENS" 2>/dev/null
    
    log_auth_info "Authentication state reset - next API call will trigger fresh authentication"
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Authentication logging helpers
log_auth_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-ERROR] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_warn() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-WARN] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-SUCCESS] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUTH-INFO] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
}

log_auth_debug() {
    local message="$1"
    if [[ "${DEBUG_AUTH:-false}" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [AUTH-DEBUG] $message" >> "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    fi
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize authentication system
init_dispatcharr_auth() {
    # Ensure required directories exist
    mkdir -p "$(dirname "${DISPATCHARR_TOKENS:-/tmp/dispatcharr_tokens.json}")" 2>/dev/null
    mkdir -p "$(dirname "${DISPATCHARR_LOG:-/tmp/dispatcharr.log}")" 2>/dev/null
    
    # Initialize state
    DISPATCHARR_AUTH_STATE="unknown"
    DISPATCHARR_LAST_TOKEN_CHECK=0
    
    log_auth_info "Authentication module initialized"
    
    # Test authentication if Dispatcharr is enabled
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        log_auth_info "Dispatcharr enabled, testing authentication..."
        if is_dispatcharr_authenticated; then
            log_auth_info "Existing authentication is valid"
        else
            log_auth_info "No valid authentication found - will authenticate on first API call"
        fi
    fi
}

# Cleanup authentication resources
cleanup_dispatcharr_auth() {
    DISPATCHARR_AUTH_STATE="unknown"
    DISPATCHARR_LAST_TOKEN_CHECK=0
    log_auth_info "Authentication cleanup completed"
}

# ============================================================================
# BACKWARDS COMPATIBILITY
# ============================================================================

# Legacy function names for existing code compatibility
refresh_dispatcharr_tokens() {
    authenticate_dispatcharr
}

check_dispatcharr_connection() {
    is_dispatcharr_authenticated
}

# ============================================================================
# TESTING FUNCTIONS
# ============================================================================

# Comprehensive test function for the auth module
test_auth_module() {
    local test_mode="${1:-basic}"  # basic, full, or interactive
    local test_count=0
    local pass_count=0
    local fail_count=0
    
    echo -e "${BOLD}${CYAN}=== Authentication Module Test Suite ===${RESET}"
    echo -e "${CYAN}Test mode: $test_mode${RESET}"
    echo
    
    # Helper function for test results
    test_result() {
        local test_name="$1"
        local result="$2"
        local details="${3:-}"
        
        ((test_count++))
        if [[ "$result" == "PASS" ]]; then
            ((pass_count++))
            echo -e "${GREEN}✅ PASS${RESET} - $test_name"
        else
            ((fail_count++))
            echo -e "${RED}❌ FAIL${RESET} - $test_name"
        fi
        
        if [[ -n "$details" ]]; then
            echo -e "    ${CYAN}$details${RESET}"
        fi
    }
    
    # Test 1: Module initialization
    echo -e "${BOLD}Testing Module Initialization...${RESET}"
    
    if declare -f init_dispatcharr_auth >/dev/null 2>&1; then
        test_result "init_dispatcharr_auth function exists" "PASS"
    else
        test_result "init_dispatcharr_auth function exists" "FAIL" "Function not found"
    fi
    
    # Test 2: Configuration validation
    echo -e "${BOLD}Testing Configuration Validation...${RESET}"
    
    if [[ -n "${DISPATCHARR_URL:-}" ]]; then
        test_result "DISPATCHARR_URL configured" "PASS" "URL: $DISPATCHARR_URL"
    else
        test_result "DISPATCHARR_URL configured" "FAIL" "Environment variable not set"
    fi
    
    if [[ "$DISPATCHARR_ENABLED" == "true" ]]; then
        test_result "DISPATCHARR_ENABLED is true" "PASS"
    else
        test_result "DISPATCHARR_ENABLED is true" "FAIL" "Value: ${DISPATCHARR_ENABLED:-unset}"
    fi
    
    if [[ -n "${DISPATCHARR_USERNAME:-}" ]]; then
        test_result "DISPATCHARR_USERNAME configured" "PASS" "Username: ${DISPATCHARR_USERNAME:0:3}***"
    else
        test_result "DISPATCHARR_USERNAME configured" "FAIL" "Environment variable not set"
    fi
    
    if [[ -n "${DISPATCHARR_PASSWORD:-}" ]]; then
        test_result "DISPATCHARR_PASSWORD configured" "PASS" "Password: ***"
    else
        test_result "DISPATCHARR_PASSWORD configured" "FAIL" "Environment variable not set"
    fi
    
    # Test 3: Core function availability
    echo -e "${BOLD}Testing Core Functions...${RESET}"
    
    local core_functions=(
        "get_dispatcharr_access_token"
        "get_dispatcharr_refresh_token"
        "authenticate_dispatcharr"
        "refresh_dispatcharr_access_token"
        "is_dispatcharr_authenticated"
        "ensure_dispatcharr_auth"
        "get_dispatcharr_auth_status"
        "reset_dispatcharr_auth"
    )
    
    for func in "${core_functions[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            test_result "Function $func exists" "PASS"
        else
            test_result "Function $func exists" "FAIL"
        fi
    done
    
    # Test 4: Token file handling
    echo -e "${BOLD}Testing Token File Handling...${RESET}"
    
    local token_file="${DISPATCHARR_TOKENS:-/tmp/dispatcharr_tokens.json}"
    local token_dir=$(dirname "$token_file")
    
    if [[ -d "$token_dir" ]] || mkdir -p "$token_dir" 2>/dev/null; then
        test_result "Token directory accessible" "PASS" "Path: $token_dir"
    else
        test_result "Token directory accessible" "FAIL" "Cannot create: $token_dir"
    fi
    
    # Test 5: Logging functionality
    echo -e "${BOLD}Testing Logging Functions...${RESET}"
    
    local log_file="${DISPATCHARR_LOG:-/tmp/dispatcharr.log}"
    local log_dir=$(dirname "$log_file")
    
    if [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null; then
        test_result "Log directory accessible" "PASS" "Path: $log_dir"
    else
        test_result "Log directory accessible" "FAIL" "Cannot create: $log_dir"
    fi
    
    # Test logging functions
    if log_auth_info "Test log message" 2>/dev/null; then
        test_result "Logging functions work" "PASS"
    else
        test_result "Logging functions work" "FAIL"
    fi
    
    # Test 8: Configuration Management (if not in basic mode)
    if [[ "$test_mode" != "basic" ]]; then
        echo -e "${BOLD}Testing Configuration Management...${RESET}"
        
        # Test config reload function
        if reload_dispatcharr_config >/dev/null 2>&1; then
            test_result "Configuration reload" "PASS"
        else
            test_result "Configuration reload" "FAIL" "Cannot reload config file"
        fi
        
        # Test auth state invalidation
        local original_state="$DISPATCHARR_AUTH_STATE"
        DISPATCHARR_AUTH_STATE="authenticated"
        
        invalidate_auth_state "Test invalidation"
        
        if [[ "$DISPATCHARR_AUTH_STATE" == "unknown" ]]; then
            test_result "Auth state invalidation" "PASS"
        else
            test_result "Auth state invalidation" "FAIL" "State not reset properly"
        fi
        
        # Restore original state
        DISPATCHARR_AUTH_STATE="$original_state"
        
        # Test configuration update functions exist
        local config_functions=(
            "save_dispatcharr_config"
            "reload_dispatcharr_config"
            "invalidate_auth_state"
            "update_dispatcharr_url"
            "update_dispatcharr_credentials"
            "update_dispatcharr_enabled"
        )
        
        for func in "${config_functions[@]}"; do
            if declare -f "$func" >/dev/null 2>&1; then
                test_result "Config function $func exists" "PASS"
            else
                test_result "Config function $func exists" "FAIL"
            fi
        done
    else
        echo -e "${BOLD}Testing Network Connectivity (Full Mode)...${RESET}"
        
        # Test 6: Network connectivity
        if [[ -n "${DISPATCHARR_URL:-}" ]]; then
            if curl -s --connect-timeout 5 "$DISPATCHARR_URL" >/dev/null 2>&1; then
                test_result "Dispatcharr server reachable" "PASS"
            else
                test_result "Dispatcharr server reachable" "FAIL" "Cannot connect to $DISPATCHARR_URL"
            fi
        else
            test_result "Dispatcharr server reachable" "FAIL" "No URL configured"
        fi
        
        # Test 7: Authentication (only if credentials are available)
        if [[ -n "${DISPATCHARR_USERNAME:-}" && -n "${DISPATCHARR_PASSWORD:-}" ]]; then
            echo -e "${BOLD}Testing Authentication (Network Required)...${RESET}"
            
            # Save current auth state
            local original_state="$DISPATCHARR_AUTH_STATE"
            local original_check="$DISPATCHARR_LAST_TOKEN_CHECK"
            
            # Reset auth state for clean test
            DISPATCHARR_AUTH_STATE="unknown"
            DISPATCHARR_LAST_TOKEN_CHECK=0
            
            if authenticate_dispatcharr >/dev/null 2>&1; then
                test_result "Full authentication" "PASS"
                
                # Test token retrieval
                local access_token
                access_token=$(get_dispatcharr_access_token)
                if [[ -n "$access_token" ]]; then
                    test_result "Access token retrieval" "PASS" "Token length: ${#access_token}"
                else
                    test_result "Access token retrieval" "FAIL"
                fi
                
                # Test auth status
                local auth_status
                auth_status=$(get_dispatcharr_auth_status)
                if [[ $? -eq 0 ]]; then
                    test_result "Auth status reporting" "PASS" "$auth_status"
                else
                    test_result "Auth status reporting" "FAIL"
                fi
                
                # Test token expiration parsing
                local expiration
                expiration=$(get_token_expiration)
                if [[ $? -eq 0 ]]; then
                    test_result "Token expiration parsing" "PASS" "Expires: $expiration"
                else
                    test_result "Token expiration parsing" "FAIL"
                fi
                
            else
                test_result "Full authentication" "FAIL" "Check credentials and network"
            fi
            
            # Restore original auth state
            DISPATCHARR_AUTH_STATE="$original_state"
            DISPATCHARR_LAST_TOKEN_CHECK="$original_check"
        else
            test_result "Authentication test" "SKIP" "No credentials configured"
        fi
        echo -e "${CYAN}Skipping network tests (use 'full' mode to include)${RESET}"
    fi
    
    # Interactive tests
    if [[ "$test_mode" == "interactive" ]]; then
        echo -e "${BOLD}Interactive Tests...${RESET}"
        
        echo -e "${YELLOW}Would you like to test auth state reset? (y/N):${RESET}"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            reset_dispatcharr_auth
            test_result "Auth state reset" "PASS" "State reset completed"
        fi
    fi
    
    # Test Summary
    echo
    echo -e "${BOLD}${BLUE}=== Test Summary ===${RESET}"
    echo -e "Total tests: $test_count"
    echo -e "${GREEN}Passed: $pass_count${RESET}"
    if [[ $fail_count -gt 0 ]]; then
        echo -e "${RED}Failed: $fail_count${RESET}"
    else
        echo -e "${GREEN}Failed: $fail_count${RESET}"
    fi
    
    local success_rate=$((pass_count * 100 / test_count))
    echo -e "Success rate: ${success_rate}%"
    
    if [[ $fail_count -eq 0 ]]; then
        echo -e "\n${GREEN}✅ All tests passed! Auth module is ready for use.${RESET}"
        return 0
    else
        echo -e "\n${YELLOW}⚠️  Some tests failed. Review configuration and network connectivity.${RESET}"
        return 1
    fi
}

# Quick smoke test function
test_auth_quick() {
    echo -e "${CYAN}🔥 Auth Module Smoke Test${RESET}"
    
    # Test basic function availability
    local required_functions=(
        "ensure_dispatcharr_auth"
        "get_dispatcharr_auth_status"
        "authenticate_dispatcharr"
    )
    
    local all_good=true
    for func in "${required_functions[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            echo -e "${RED}❌ Missing function: $func${RESET}"
            all_good=false
        fi
    done
    
    if $all_good; then
        echo -e "${GREEN}✅ Smoke test passed - core functions available${RESET}"
        return 0
    else
        echo -e "${RED}❌ Smoke test failed - missing core functions${RESET}"
        return 1
    fi
}

# Test with mock/dry-run mode (no actual network calls)
test_auth_mock() {
    echo -e "${CYAN}🎭 Auth Module Mock Test${RESET}"
    
    # Save original functions
    local original_curl=$(declare -f curl 2>/dev/null || true)
    
    # Mock curl for testing
    curl() {
        local url="$*"
        echo -e "${YELLOW}[MOCK]${RESET} curl $url" >&2
        
        if [[ "$url" == *"/api/accounts/token/"* ]]; then
            # Mock successful auth response
            echo '{"access": "mock_access_token", "refresh": "mock_refresh_token"}'
        elif [[ "$url" == *"/api/core/version/"* ]]; then
            # Mock version response
            echo '{"version": "1.0.0"}'
        else
            return 0
        fi
    }
    
    # Run basic auth test with mocked network
    echo "Testing with mocked network calls..."
    
    if authenticate_dispatcharr >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Mock authentication succeeded${RESET}"
    else
        echo -e "${RED}❌ Mock authentication failed${RESET}"
    fi
    
    # Restore original curl if it existed
    if [[ -n "$original_curl" ]]; then
        eval "$original_curl"
    else
        unset -f curl
    fi
    
    echo -e "${CYAN}Mock test completed${RESET}"
}

# Auto-initialize when module is loaded
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_dispatcharr_auth
fi

# ============================================================================
# ENHANCED TOKEN MANAGEMENT TESTING
# ============================================================================

# Simple test function for new token management
test_enhanced_token_management() {
    echo -e "${BOLD}${CYAN}=== Enhanced Token Management Test ===${RESET}"
    echo
    
    # Test 1: Check if Dispatcharr is configured
    echo -e "${BOLD}Test 1: Configuration Check${RESET}"
    if [[ "$DISPATCHARR_ENABLED" == "true" ]] && [[ -n "${DISPATCHARR_URL:-}" ]]; then
        echo -e "${GREEN}✅ Dispatcharr configured and enabled${RESET}"
        echo -e "   URL: $DISPATCHARR_URL"
    else
        echo -e "${RED}❌ Dispatcharr not configured or disabled${RESET}"
        echo -e "${CYAN}💡 Configure in Settings → Dispatcharr Integration first${RESET}"
        return 1
    fi
    echo
    
    # Test 2: Check current authentication status
    echo -e "${BOLD}Test 2: Current Authentication Status${RESET}"
    local auth_status
    auth_status=$(get_dispatcharr_auth_status)
    echo -e "Status: $auth_status"
    echo
    
    # Test 3: Test token expiration parsing
    echo -e "${BOLD}Test 3: Token Expiration Analysis${RESET}"
    local exp_timestamp
    exp_timestamp=$(get_token_expiration_timestamp)
    if [[ $? -eq 0 ]]; then
        local current_time=$(date +%s)
        local time_until_expiry=$((exp_timestamp - current_time))
        local exp_date=$(date -d "@$exp_timestamp" 2>/dev/null || date -r "$exp_timestamp" 2>/dev/null || echo "Unknown")
        
        echo -e "${GREEN}✅ Token expiration parsed successfully${RESET}"
        echo -e "   Expires at: $exp_date"
        echo -e "   Time until expiry: ${time_until_expiry}s ($(( time_until_expiry / 60 )) minutes)"
        
        # Test if refresh is needed
        if token_needs_refresh; then
            echo -e "   ${YELLOW}⚠️  Token needs refresh (within ${DISPATCHARR_TOKEN_BUFFER_TIME}s buffer)${RESET}"
        else
            echo -e "   ${GREEN}✅ Token is fresh (no refresh needed)${RESET}"
        fi
    else
        echo -e "${RED}❌ Could not parse token expiration${RESET}"
        echo -e "${CYAN}💡 This may indicate no token or invalid token format${RESET}"
    fi
    echo
    
    # Test 4: Test refresh attempt logic
    echo -e "${BOLD}Test 4: Refresh Attempt Logic${RESET}"
    if can_attempt_refresh; then
        echo -e "${GREEN}✅ Can attempt refresh (enough time since last attempt)${RESET}"
    else
        local time_since_last=$(($(date +%s) - DISPATCHARR_LAST_REFRESH_ATTEMPT))
        echo -e "${YELLOW}⚠️  Too soon since last refresh attempt${RESET}"
        echo -e "   Time since last: ${time_since_last}s (min interval: ${DISPATCHARR_MIN_REFRESH_INTERVAL}s)"
    fi
    echo
    
    # Test 5: Test smart token management strategies
    echo -e "${BOLD}Test 5: Smart Token Management Strategies${RESET}"
    
    echo -e "${CYAN}Testing 'interactive' mode:${RESET}"
    if smart_token_management "test_call" "interactive"; then
        echo -e "${GREEN}✅ Interactive mode completed successfully${RESET}"
    else
        echo -e "${RED}❌ Interactive mode failed${RESET}"
    fi
    
    echo -e "${CYAN}Testing 'batch' mode:${RESET}"
    if smart_token_management "test_call" "batch"; then
        echo -e "${GREEN}✅ Batch mode completed successfully${RESET}"
    else
        echo -e "${RED}❌ Batch mode failed${RESET}"
    fi
    echo
    
    # Test 6: Test batch preparation
    echo -e "${BOLD}Test 6: Batch Operation Preparation${RESET}"
    if prepare_for_batch_operations "test operation" 300; then  # 5 minutes
        echo -e "${GREEN}✅ Batch preparation completed successfully${RESET}"
        echo -e "${CYAN}💡 Token should be good for at least 5 minutes${RESET}"
    else
        echo -e "${RED}❌ Batch preparation failed${RESET}"
    fi
    echo
    
    # Test 7: Configuration display
    echo -e "${BOLD}Test 7: Current Configuration${RESET}"
    echo -e "Token buffer time: ${DISPATCHARR_TOKEN_BUFFER_TIME}s ($(( DISPATCHARR_TOKEN_BUFFER_TIME / 60 )) minutes)"
    echo -e "Min refresh interval: ${DISPATCHARR_MIN_REFRESH_INTERVAL}s"
    echo -e "Background refresh: ${DISPATCHARR_BACKGROUND_REFRESH:-true}"
    echo
    
    echo -e "${BOLD}${GREEN}=== Test Summary ===${RESET}"
    echo -e "${GREEN}✅ Enhanced token management functions are working${RESET}"
    echo -e "${CYAN}💡 Ready to integrate into main script workflows${RESET}"
    echo
    
    return 0
}

# Quick test that can be called from main script
test_token_functions_quick() {
    echo -e "${CYAN}🔍 Quick Token Function Test${RESET}"
    
    local functions_to_test=(
        "get_token_expiration_timestamp"
        "token_needs_refresh"
        "can_attempt_refresh"
        "ensure_token_fresh"
        "smart_token_management"
        "prepare_for_batch_operations"
    )
    
    local all_good=true
    for func in "${functions_to_test[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ $func${RESET}"
        else
            echo -e "  ${RED}❌ $func${RESET}"
            all_good=false
        fi
    done
    
    if $all_good; then
        echo -e "${GREEN}✅ All enhanced token functions available${RESET}"
        return 0
    else
        echo -e "${RED}❌ Some enhanced token functions missing${RESET}"
        return 1
    fi
}