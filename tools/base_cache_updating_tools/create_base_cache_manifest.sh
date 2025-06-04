#!/bin/bash

# ============================================================================
# BASE CACHE MANIFEST CREATOR
# ============================================================================
# Description: Standalone script to create base cache manifests for distribution
# Usage: ./create_base_cache_manifest.sh [options]
# Created: 2025/05/31
# Version: 1.0.0
# ============================================================================

# TERMINAL STYLING
ESC="\033"
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"

# VERSION
VERSION="1.0.0"

# DEFAULT FILE PATHS (can be overridden with command line arguments)
BASE_STATIONS_JSON="all_stations_base.json"
BASE_CACHE_MANIFEST="all_stations_base_manifest.json"
CSV_FILE="sampled_markets.csv"
CACHE_DIR="cache"
CACHED_MARKETS="$CACHE_DIR/cached_markets.jsonl"
CACHED_LINEUPS="$CACHE_DIR/cached_lineups.jsonl"
LINEUP_TO_MARKET="$CACHE_DIR/lineup_to_market.json"

# Command line options
FORCE_OVERWRITE=false
VERBOSE=false
DRY_RUN=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

show_usage() {
  echo "Base Cache Manifest Creator v$VERSION"
  echo
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -v, --verbose           Enable verbose output"
  echo "  -f, --force             Force overwrite existing manifest"
  echo "  -n, --dry-run           Show what would be done without creating manifest"
  echo "  --base-cache FILE       Base cache JSON file (default: $BASE_STATIONS_JSON)"
  echo "  --manifest FILE         Output manifest file (default: $BASE_CACHE_MANIFEST)"
  echo "  --csv FILE              Markets CSV file (default: $CSV_FILE)"
  echo "  --cache-dir DIR         Cache directory (default: $CACHE_DIR)"
  echo
  echo "Examples:"
  echo "  $0                      Create manifest with default settings"
  echo "  $0 -f -v               Force create with verbose output"
  echo "  $0 --dry-run            Preview what would be created"
  echo
}

log_info() {
  echo -e "${GREEN}[INFO]${RESET} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $1"
}

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${CYAN}[VERBOSE]${RESET} $1"
  fi
}

confirm_action() {
  local message="$1"
  local default="${2:-n}"
  
  read -p "$message (y/n) [default: $default]: " response
  response=${response:-$default}
  [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_requirements() {
  log_verbose "Validating requirements..."
  
  # Check for required tools
  for tool in jq awk; do
    if ! command -v "$tool" &> /dev/null; then
      log_error "Required tool '$tool' not found"
      return 1
    fi
  done
  
  # Check base cache file
  if [ ! -f "$BASE_STATIONS_JSON" ] || [ ! -s "$BASE_STATIONS_JSON" ]; then
    log_error "Base cache file not found or empty: $BASE_STATIONS_JSON"
    return 1
  fi
  
  # Validate base cache JSON
  if ! jq empty "$BASE_STATIONS_JSON" 2>/dev/null; then
    log_error "Base cache file contains invalid JSON: $BASE_STATIONS_JSON"
    return 1
  fi
  
  # Check CSV file
  if [ ! -f "$CSV_FILE" ] || [ ! -s "$CSV_FILE" ]; then
    log_error "Markets CSV file not found or empty: $CSV_FILE"
    return 1
  fi
  
  # Check cache directory and state files
  if [ ! -d "$CACHE_DIR" ]; then
    log_error "Cache directory not found: $CACHE_DIR"
    return 1
  fi
  
  if [ ! -f "$CACHED_MARKETS" ] || [ ! -s "$CACHED_MARKETS" ]; then
    log_error "Cached markets file not found or empty: $CACHED_MARKETS"
    return 1
  fi
  
  if [ ! -f "$CACHED_LINEUPS" ] || [ ! -s "$CACHED_LINEUPS" ]; then
    log_error "Cached lineups file not found or empty: $CACHED_LINEUPS"
    return 1
  fi
  
  log_verbose "All requirements validated successfully"
  return 0
}

check_existing_manifest() {
  if [ -f "$BASE_CACHE_MANIFEST" ]; then
    if [ "$FORCE_OVERWRITE" = true ]; then
      log_warn "Existing manifest will be overwritten: $BASE_CACHE_MANIFEST"
      return 0
    else
      log_error "Manifest file already exists: $BASE_CACHE_MANIFEST"
      echo "Use --force to overwrite or specify a different output file"
      return 1
    fi
  fi
  return 0
}

# ============================================================================
# DATA PROCESSING FUNCTIONS
# ============================================================================

analyze_input_data() {
  log_info "Analyzing input data..."
  
  # Analyze base cache
  local station_count=$(jq 'length' "$BASE_STATIONS_JSON")
  log_info "Base cache contains: $station_count stations"
  
  # Analyze CSV markets
  local csv_market_count=$(awk 'END {print NR-1}' "$CSV_FILE")
  log_info "Markets CSV contains: $csv_market_count markets"
  
  # Analyze cached lineups
  local unique_lineups=$(jq -r '.lineup_id // empty' "$CACHED_LINEUPS" 2>/dev/null | grep -v '^$' | sort -u | wc -l)
  local total_lineup_lines=$(wc -l < "$CACHED_LINEUPS")
  log_info "Cached lineups: $unique_lineups unique lineups (from $total_lineup_lines entries)"
  
  # Show sample data if verbose
  if [ "$VERBOSE" = true ]; then
    log_verbose "Sample markets from CSV:"
    head -4 "$CSV_FILE" | tail -3 | while IFS=, read -r country zip; do
      log_verbose "  • $country/$zip"
    done
    
    log_verbose "Sample countries from base cache:"
    jq -r '[.[] | select(.country != null)] | group_by(.country) | map(.[0].country) | .[0:3] | join(", ")' "$BASE_STATIONS_JSON"
  fi
}

process_markets() {
  log_info "Processing markets from CSV..."
  
  local markets_file="$CACHE_DIR/temp_markets.json"
  
  log_verbose "Converting CSV to JSON format..."
  {
    echo "["
    local first_market=true
    tail -n +2 "$CSV_FILE" | while IFS=, read -r country zip; do
      if [ "$first_market" = true ]; then
        first_market=false
      else
        echo ","
      fi
      echo "  {\"country\":\"$country\",\"zip\":\"$zip\"}"
    done
    echo "]"
  } > "$markets_file"
  
  local actual_market_count=$(jq 'length' "$markets_file")
  log_info "Processed: $actual_market_count markets"
}

process_lineups() {
  log_info "Processing lineups from cache state..."
  
  local lineups_file="$CACHE_DIR/temp_unique_lineups.json"
  
  log_verbose "Extracting unique lineup IDs..."
  local temp_ids_file="$CACHE_DIR/temp_lineup_ids.txt"
  
  # Extract unique lineup IDs to a temporary file
  jq -r '.lineup_id // empty' "$CACHED_LINEUPS" 2>/dev/null | grep -v '^$' | sort -u > "$temp_ids_file"
  
  log_verbose "Creating JSON array from unique lineup IDs..."
  echo "[" > "$lineups_file"
  
  local processed_lineups=0
  local first_entry=true
  
  # Read from the temporary file instead of using pipe in subshell
  while IFS= read -r lineup_id; do
    if [ -n "$lineup_id" ]; then
      # Add comma if not first entry
      if [ "$first_entry" = true ]; then
        first_entry=false
      else
        echo "," >> "$lineups_file"
      fi
      
      # Add lineup entry
      echo "  {\"lineup_id\": \"$lineup_id\"}" >> "$lineups_file"
      
      ((processed_lineups++))
      
      # Progress indicator
      if [ "$VERBOSE" = true ] && [ $((processed_lineups % 200)) -eq 0 ]; then
        log_verbose "Processed $processed_lineups unique lineups..."
      fi
    fi
  done < "$temp_ids_file"
  
  # Close JSON array
  echo "]" >> "$lineups_file"
  
  # Clean up temporary file
  rm -f "$temp_ids_file"
  
  log_info "Processed: $processed_lineups unique lineups"
}

process_countries() {
  log_info "Processing countries from base cache..."
  
  local countries_data=$(jq '
    [.[] | select(.country != null and .country != "")] |
    group_by(.country) |
    map({
      country: .[0].country,
      station_count: length
    })
  ' "$BASE_STATIONS_JSON")
  
  local country_count=$(echo "$countries_data" | jq 'length')
  log_info "Processed: $country_count countries"
  
  if [ "$VERBOSE" = true ]; then
    log_verbose "Countries found:"
    echo "$countries_data" | jq -r '.[] | "  • \(.country): \(.station_count) stations"' >&2
  fi
  
  echo "$countries_data"
}

process_lineup_mapping() {
  log_info "Processing lineup to market mapping..."
  
  local mapping_file="$CACHE_DIR/temp_lineup_mapping.json"
  
  if [ ! -f "$LINEUP_TO_MARKET" ] || [ ! -s "$LINEUP_TO_MARKET" ]; then
    log_verbose "No lineup mapping file found, creating empty mapping"
    echo "{}" > "$mapping_file"
    return 0
  fi
  
  # Check if the mapping file is valid JSON and get its size
  if ! jq empty "$LINEUP_TO_MARKET" 2>/dev/null; then
    log_warn "Lineup mapping file contains invalid JSON, using empty mapping"
    echo "{}" > "$mapping_file"
    return 0
  fi
  
  local mapping_size=$(wc -c < "$LINEUP_TO_MARKET")
  log_verbose "Lineup mapping file size: $mapping_size bytes"
  
  # If the file is reasonably small (less than 100KB), copy it directly
  if [ "$mapping_size" -lt 102400 ]; then
    log_verbose "Copying lineup mapping directly (small file)"
    cp "$LINEUP_TO_MARKET" "$mapping_file"
  else
    # For larger files, we need to process in chunks to avoid argument limits
    log_verbose "Processing large lineup mapping in chunks..."
    
    # Start with empty object
    echo "{}" > "$mapping_file"
    
    # Get all keys and process them in batches
    local temp_keys_file="$CACHE_DIR/temp_mapping_keys.txt"
    jq -r 'keys[]' "$LINEUP_TO_MARKET" > "$temp_keys_file"
    
    local processed_keys=0
    local batch_size=100
    local temp_batch_file="$CACHE_DIR/temp_batch_mapping.json"
    
    while IFS= read -r key; do
      if [ -n "$key" ]; then
        # Get the value for this key and add it to the mapping
        local value=$(jq -r --arg k "$key" '.[$k]' "$LINEUP_TO_MARKET")
        
        # Add this key-value pair to the mapping file
        jq --arg k "$key" --arg v "$value" '. + {($k): $v}' "$mapping_file" > "$mapping_file.tmp"
        mv "$mapping_file.tmp" "$mapping_file"
        
        ((processed_keys++))
        
        # Progress indicator
        if [ "$VERBOSE" = true ] && [ $((processed_keys % batch_size)) -eq 0 ]; then
          log_verbose "Processed $processed_keys lineup mappings..."
        fi
      fi
    done < "$temp_keys_file"
    
    # Clean up temporary files
    rm -f "$temp_keys_file" "$temp_batch_file"
    
    log_info "Processed: $processed_keys lineup mappings"
  fi
  
  # Verify the processed mapping is valid JSON
  if ! jq empty "$mapping_file" 2>/dev/null; then
    log_warn "Processed lineup mapping is invalid JSON, using empty mapping"
    echo "{}" > "$mapping_file"
  fi
}

# ============================================================================
# MANIFEST CREATION
# ============================================================================

create_manifest() {
  log_info "Creating base cache manifest..."
  
  if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN: Would create manifest at $BASE_CACHE_MANIFEST"
    return 0
  fi
  
  # Process all data components with fixed file paths
  local markets_file="$CACHE_DIR/temp_markets.json"
  local lineups_file="$CACHE_DIR/temp_unique_lineups.json"
  local mapping_file="$CACHE_DIR/temp_lineup_mapping.json"

  # Process markets
  process_markets
  if [ $? -ne 0 ] || [ ! -f "$markets_file" ]; then
    log_error "Failed to process markets"
    return 1
  fi

  # Process lineups  
  process_lineups
  if [ $? -ne 0 ] || [ ! -f "$lineups_file" ]; then
    log_error "Failed to process lineups"
    return 1
  fi

  # Process lineup mapping
  process_lineup_mapping
  if [ $? -ne 0 ] || [ ! -f "$mapping_file" ]; then
    log_error "Failed to process lineup mapping"
    return 1
  fi

  # Process countries
  log_info "Processing countries from base cache..."
  local countries_data=$(jq '
    [.[] | select(.country != null and .country != "")] |
    group_by(.country) |
    map({
      country: .[0].country,
      station_count: length
    })
  ' "$BASE_STATIONS_JSON")

  local country_count=$(echo "$countries_data" | jq 'length')
  log_info "Processed: $country_count countries"

  if [ "$VERBOSE" = true ]; then
    log_verbose "Countries found:"
    echo "$countries_data" | jq -r '.[] | "  • \(.country): \(.station_count) stations"'
  fi

  if [ -z "$countries_data" ] || ! echo "$countries_data" | jq empty 2>/dev/null; then
    log_error "Failed to process countries"
    return 1
  fi
  
  log_info "Assembling manifest in pieces to avoid argument limits..."
  
  # Create base structure
  log_verbose "Creating base structure..."
  jq -n \
    --arg created "$(date -Iseconds)" \
    --arg base_cache_file "$(basename "$BASE_STATIONS_JSON")" \
    --arg version "$VERSION" \
    '{
      created: $created,
      base_cache_file: $base_cache_file,
      manifest_version: $version,
      description: "Complete base cache manifest with all unique markets and lineups",
      note: "Generated by standalone manifest creator for distribution"
    }' > "$BASE_CACHE_MANIFEST"
  
  # Add markets from file
  log_verbose "Adding markets..."
  if [ -f "$markets_file" ] && [ -s "$markets_file" ]; then
    jq --slurpfile markets "$markets_file" '. + {markets: $markets[0]}' "$BASE_CACHE_MANIFEST" > "${BASE_CACHE_MANIFEST}.tmp"
    mv "${BASE_CACHE_MANIFEST}.tmp" "$BASE_CACHE_MANIFEST"
  else
    log_error "Markets file not found: $markets_file"
    return 1
  fi
  
  # Add lineups from file
  log_verbose "Adding lineups..."
  if [ -f "$lineups_file" ] && [ -s "$lineups_file" ]; then
    jq --slurpfile lineups "$lineups_file" '. + {lineups: $lineups[0]}' "$BASE_CACHE_MANIFEST" > "${BASE_CACHE_MANIFEST}.tmp"
    mv "${BASE_CACHE_MANIFEST}.tmp" "$BASE_CACHE_MANIFEST"
  else
    log_error "Lineups file not found: $lineups_file"
    return 1
  fi
  
  # Add countries
  log_verbose "Adding countries..."
  jq --argjson countries "$countries_data" '. + {countries: $countries}' "$BASE_CACHE_MANIFEST" > "${BASE_CACHE_MANIFEST}.tmp"
  mv "${BASE_CACHE_MANIFEST}.tmp" "$BASE_CACHE_MANIFEST"
  
  # Add lineup mapping from file
  log_verbose "Adding lineup mapping..."
  if [ -f "$mapping_file" ] && [ -s "$mapping_file" ]; then
    jq --slurpfile mapping "$mapping_file" '. + {lineup_to_market: $mapping[0]}' "$BASE_CACHE_MANIFEST" > "${BASE_CACHE_MANIFEST}.tmp"
    mv "${BASE_CACHE_MANIFEST}.tmp" "$BASE_CACHE_MANIFEST"
  else
    log_error "Lineup mapping file not found: $mapping_file"
    return 1
  fi
  
  # Add statistics
  log_verbose "Adding statistics..."
  jq '. + {stats: {
    total_stations: (.countries | map(.station_count) | add // 0),
    total_markets: (.markets | length),
    total_lineups: (.lineups | length),
    countries_covered: (.countries | map(.country))
  }}' "$BASE_CACHE_MANIFEST" > "${BASE_CACHE_MANIFEST}.tmp"
  mv "${BASE_CACHE_MANIFEST}.tmp" "$BASE_CACHE_MANIFEST"
  
  # Clean up temporary files
  rm -f "$markets_file" "$lineups_file" "$mapping_file"
  
  # Verify manifest
  if [ -f "$BASE_CACHE_MANIFEST" ] && [ -s "$BASE_CACHE_MANIFEST" ] && jq empty "$BASE_CACHE_MANIFEST" 2>/dev/null; then
    log_info "Manifest created successfully!"
    return 0
  else
    log_error "Manifest creation failed or resulted in invalid JSON"
    return 1
  fi
}

show_manifest_summary() {
  if [ ! -f "$BASE_CACHE_MANIFEST" ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi
  
  echo
  echo -e "${BOLD}${GREEN}=== Manifest Summary ===${RESET}"
  
  jq -r '
    "Created: " + .created +
    "\nBase Cache File: " + .base_cache_file +
    "\nManifest Version: " + .manifest_version +
    "\n" +
    "\nStatistics:" +
    "\n  Total Stations: " + (.stats.total_stations | tostring) +
    "\n  Total Markets: " + (.stats.total_markets | tostring) +
    "\n  Total Lineups: " + (.stats.total_lineups | tostring) +
    "\n  Countries: " + (.stats.countries_covered | join(", ")) +
    "\n" +
    "\nManifest File: " + input_filename
  ' "$BASE_CACHE_MANIFEST"
  
  local file_size=$(ls -lh "$BASE_CACHE_MANIFEST" | awk '{print $5}')
  echo "File Size: $file_size"
  
  echo
  echo -e "${GREEN}✅ Base cache manifest ready for distribution!${RESET}"
}

# ============================================================================
# COMMAND LINE PARSING
# ============================================================================

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_usage
        exit 0
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -f|--force)
        FORCE_OVERWRITE=true
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      --base-cache)
        BASE_STATIONS_JSON="$2"
        shift 2
        ;;
      --manifest)
        BASE_CACHE_MANIFEST="$2"
        shift 2
        ;;
      --csv)
        CSV_FILE="$2"
        shift 2
        ;;
      --cache-dir)
        CACHE_DIR="$2"
        CACHED_MARKETS="$CACHE_DIR/cached_markets.jsonl"
        CACHED_LINEUPS="$CACHE_DIR/cached_lineups.jsonl"
        LINEUP_TO_MARKET="$CACHE_DIR/lineup_to_market.json"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo -e "${BOLD}${CYAN}Base Cache Manifest Creator v$VERSION${RESET}"
  echo
  
  # Parse command line arguments
  parse_arguments "$@"
  
  # Show configuration if verbose
  if [ "$VERBOSE" = true ]; then
    log_verbose "Configuration:"
    log_verbose "  Base Cache: $BASE_STATIONS_JSON"
    log_verbose "  Output Manifest: $BASE_CACHE_MANIFEST"
    log_verbose "  Markets CSV: $CSV_FILE"
    log_verbose "  Cache Directory: $CACHE_DIR"
    log_verbose "  Force Overwrite: $FORCE_OVERWRITE"
    log_verbose "  Dry Run: $DRY_RUN"
    echo
  fi
  
  # Validate requirements
  if ! validate_requirements; then
    log_error "Validation failed. Cannot proceed."
    exit 1
  fi
  
  # Check for existing manifest
  if ! check_existing_manifest; then
    exit 1
  fi
  
  # Analyze input data
  analyze_input_data
  
  # Ask for confirmation unless forced
  if [ "$FORCE_OVERWRITE" != true ] && [ "$DRY_RUN" != true ]; then
    echo
    if ! confirm_action "Proceed with manifest creation?"; then
      log_info "Operation cancelled by user"
      exit 0
    fi
  fi
  
  # Create the manifest
  if create_manifest; then
    show_manifest_summary
    exit 0
  else
    log_error "Manifest creation failed"
    exit 1
  fi
}

# Run main function with all arguments
main "$@"