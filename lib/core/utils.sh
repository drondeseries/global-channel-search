#!/bin/bash
# lib/core/utils.sh - Core Utility Functions
# Part of Global Station Search v1.3.3+
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