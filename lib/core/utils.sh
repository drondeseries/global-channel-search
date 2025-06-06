#!/bin/bash
# lib/core/utils.sh - Core Utility Functions
# Safe utility functions with no external dependencies

# ============================================================================
# USER INTERACTION UTILITIES
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

# ============================================================================
# PROGRESS AND DISPLAY UTILITIES
# ============================================================================

show_progress_bar() {
  local current="$1"
  local total="$2"
  local percent="$3"
  local start_time="$4"
  
  # FIXED: Better ETA calculation with proper floating-point handling
  local remaining_fmt="calculating..."
  if (( current > 2 )); then  # Wait for a few items for better accuracy
    local now elapsed
    if command -v bc &> /dev/null && [[ "$start_time" == *.* ]]; then
      # Use bc for floating-point precision if available
      now=$(date +%s.%N)
      elapsed=$(echo "$now - $start_time" | bc 2>/dev/null)
      # FIXED: Use bc for all floating-point comparisons
      if [[ -n "$elapsed" ]] && [[ $(echo "$elapsed > 0" | bc 2>/dev/null) -eq 1 ]]; then
        local avg_time_per=$(echo "scale=3; $elapsed / $current" | bc 2>/dev/null)
        if [[ -n "$avg_time_per" ]]; then
          local remaining_seconds=$(echo "scale=0; $avg_time_per * ($total - $current)" | bc 2>/dev/null)
          # FIXED: Convert to integer before arithmetic comparison
          remaining_seconds=${remaining_seconds%%.*}  # Remove decimal part
          if [[ -n "$remaining_seconds" ]] && [[ "$remaining_seconds" =~ ^[0-9]+$ ]] && (( remaining_seconds >= 0 )); then
            if (( remaining_seconds < 60 )); then
              remaining_fmt="${remaining_seconds}s"
            elif (( remaining_seconds < 3600 )); then
              local minutes=$((remaining_seconds / 60))
              local seconds=$((remaining_seconds % 60))
              remaining_fmt=$(printf "%dm %ds" "$minutes" "$seconds")
            else
              local hours=$((remaining_seconds / 3600))
              local minutes=$(((remaining_seconds % 3600) / 60))
              remaining_fmt=$(printf "%dh %dm" "$hours" "$minutes")
            fi
          fi
        fi
      fi
    else
      # Fallback to integer math for better compatibility
      now=$(date +%s)
      local start_seconds=${start_time%%.*}  # Extract integer part
      elapsed=$((now - start_seconds))
      
      if (( elapsed > 0 )); then
        # Calculate average time per item in seconds
        local avg_time_per=$((elapsed / current))
        if (( avg_time_per >= 0 )); then
          local remaining_items=$((total - current))
          local remaining_seconds=$((avg_time_per * remaining_items))
          
          if (( remaining_seconds < 60 )); then
            remaining_fmt="${remaining_seconds}s"
          elif (( remaining_seconds < 3600 )); then
            local minutes=$((remaining_seconds / 60))
            local seconds=$((remaining_seconds % 60))
            remaining_fmt=$(printf "%dm %ds" "$minutes" "$seconds")
          else
            local hours=$((remaining_seconds / 3600))
            local minutes=$(((remaining_seconds % 3600) / 60))
            remaining_fmt=$(printf "%dh %dm" "$hours" "$minutes")
          fi
        fi
      fi
    fi
  else
    remaining_fmt="starting..."
  fi
  
  # Create simple progress bar with Unicode blocks for better visibility
  local bar_width=20
  local filled=$((percent * bar_width / 100))
  local bar=""
  local i=0
  
  # Build progress bar
  while (( i < filled )); do
    bar+="█"
    ((i++))
  done
  while (( i < bar_width )); do
    bar+="░"
    ((i++))
  done

  # Show progress with better formatting
  printf "\r%3d%% [%s] %d/%d - ETA: %s" "$percent" "$bar" "$current" "$total" "$remaining_fmt" >&2
  
  # FIXED: Only add newline when completely finished
  if (( current == total )); then
    echo >&2
  fi
}

# ============================================================================
# UNIVERSAL CONFIGURATION SAVING
# ============================================================================

save_setting() {
    local setting_name="$1"
    local setting_value="$2"
    local config_file="${3:-$CONFIG_FILE}"
    
    # Create temp file
    local temp_config="${config_file}.tmp"
    
    # Remove existing setting
    grep -v "^${setting_name}=" "$config_file" > "$temp_config" 2>/dev/null || touch "$temp_config"
    
    # Add new setting
    echo "${setting_name}=\"${setting_value}\"" >> "$temp_config"
    
    # Atomic update
    if mv "$temp_config" "$config_file"; then
        return 0
    else
        rm -f "$temp_config" 2>/dev/null
        return 1
    fi
}

# Universal input validation
validate_input() {
    local validation_type="$1"
    local input="$2"
    shift 2
    local constraints=("$@")
    
    case "$validation_type" in
        "ip_address")
            _validate_ip_address "$input"
            ;;
        "port")
            _validate_port "$input" "${constraints[0]:-1}" "${constraints[1]:-65535}"
            ;;
        "numeric_range")
            _validate_numeric_range "$input" "${constraints[0]}" "${constraints[1]}"
            ;;
        "choice_list")
            _validate_choice_list "$input" "${constraints[@]}"
            ;;
        "multi_choice_list")
            _validate_multi_choice_list "$input" "${constraints[@]}"
            ;;
        "non_empty")
            _validate_non_empty "$input"
            ;;
    esac
}

# Universal connection testing
test_connection() {
    local connection_type="$1"
    local target="$2"
    local timeout="${3:-5}"
    
    case "$connection_type" in
        "http")
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "api_endpoint")
            curl -s --connect-timeout "$timeout" "$target/api" >/dev/null 2>&1 || \
            curl -s --connect-timeout "$timeout" "$target" >/dev/null 2>&1
            ;;
        "dispatcharr")
            test_dispatcharr_connection "$target" "$timeout"
            ;;
    esac
}

# Universal setting status display
show_setting_status() {
    local setting_name="$1"
    local setting_value="$2"
    local setting_description="$3"
    local status_type="${4:-info}"
    
    echo -e "${BOLD}${BLUE}$setting_description:${RESET}"
    
    case "$status_type" in
        "enabled")
            echo -e "Status: ${GREEN}Enabled${RESET}"
            echo -e "Value: ${YELLOW}$setting_value${RESET}"
            ;;
        "disabled")
            echo -e "Status: ${YELLOW}Disabled${RESET}"
            ;;
        "configured")
            echo -e "Status: ${GREEN}Configured${RESET}"
            echo -e "Value: ${CYAN}$setting_value${RESET}"
            ;;
        "not_configured")
            echo -e "Status: ${RED}Not Configured${RESET}"
            ;;
        *)
            echo -e "Current: ${CYAN}$setting_value${RESET}"
            ;;
    esac
}