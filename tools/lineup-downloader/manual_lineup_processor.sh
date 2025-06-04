#!/bin/bash

# Manual Lineup Processor
# Downloads stations from specific lineup IDs and creates files for base cache incorporation
# Version 1.4.0 - Fixed Country Code Extraction from Lineup IDs

# More resilient error handling - allow unset variables in some contexts
set -uo pipefail
# Note: Removed -e flag and modified -u handling

# Configuration
CHANNELS_URL="http://localhost:8089"  # Modify as needed
OUTPUT_DIR="manual_lineup_output"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to extract country code from lineup ID
extract_country_code() {
    local lineup_id="$1"
    
    # Extract the prefix before the first dash
    if [[ "$lineup_id" =~ ^([A-Z]{3})-.*$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo -e "${RED}Error: Cannot extract country code from lineup ID: $lineup_id${RESET}" >&2
        echo -e "${RED}Expected format: XXX-... where XXX is a 3-letter country code${RESET}" >&2
        exit 1
    fi
}

# Usage
usage() {
    echo "Usage: $0 [options] <lineup_file>"
    echo ""
    echo "Options:"
    echo "  -s, --server URL    Channels DVR server URL (default: $CHANNELS_URL)"
    echo "  -o, --output DIR    Output directory (default: $OUTPUT_DIR)"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Example:"
    echo "  $0 my_lineups.txt"
    echo "  $0 --server http://192.168.1.100:8089 special_lineups.txt"
    echo ""
    echo "Lineup file format:"
    echo "  One lineup ID per line"
    echo "  Lines starting with # are comments"
    echo "  Example:"
    echo "    # Special streaming lineups"
    echo "    USA-STREAMING-001"
    echo "    CAN-SATELLITE-999"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            CHANNELS_URL="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            LINEUP_FILE="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "${LINEUP_FILE:-}" ]]; then
    echo -e "${RED}Error: Lineup file required${RESET}"
    usage
    exit 1
fi

if [[ ! -f "$LINEUP_FILE" ]]; then
    echo -e "${RED}Error: Lineup file not found: $LINEUP_FILE${RESET}"
    exit 1
fi

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${RESET}"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed${RESET}"
    exit 1
fi

# Test server connection
echo -e "${CYAN}Testing connection to Channels DVR server...${RESET}"
if ! curl -s --connect-timeout 5 "$CHANNELS_URL" >/dev/null; then
    echo -e "${RED}Error: Cannot connect to Channels DVR at $CHANNELS_URL${RESET}"
    exit 1
fi
echo -e "${GREEN}✅ Server connection successful${RESET}"

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo -e "${GREEN}Created output directory: $OUTPUT_DIR${RESET}"

# Read lineup IDs from file
echo -e "\n${BOLD}Reading lineup IDs from file...${RESET}"
lineups=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$line" ]]; then
            lineups+=("$line")
        fi
    fi
done < "$LINEUP_FILE"

lineup_count=${#lineups[@]}
if [[ $lineup_count -eq 0 ]]; then
    echo -e "${RED}Error: No valid lineup IDs found in file${RESET}"
    exit 1
fi

echo -e "${GREEN}Found $lineup_count lineup IDs to process${RESET}"

# Show lineup preview with detected countries
echo -e "\n${BOLD}Lineup IDs to process:${RESET}"
for ((i=0; i<lineup_count && i<10; i++)); do
    lineup_id="${lineups[$i]}"
    country_code=$(extract_country_code "$lineup_id")
    echo "  $((i+1)). $lineup_id (Country: $country_code)"
done
[[ $lineup_count -gt 10 ]] && echo "  ... and $((lineup_count - 10)) more"

read -p "Continue? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled${RESET}"
    exit 0
fi

# Create working directories
STATION_CACHE_DIR="$OUTPUT_DIR/stations"
mkdir -p "$STATION_CACHE_DIR"

# Process each lineup
echo -e "\n${BOLD}${BLUE}=== Processing Lineups ===${RESET}"
successful_lineups=0
failed_lineups=0
empty_lineups=0
total_stations_raw=0
processed_lineups_data=()

for ((i=0; i<lineup_count; i++)); do
    lineup_id="${lineups[$i]}"
    current=$((i + 1))
    
    # Extract country code for this lineup
    country_code=$(extract_country_code "$lineup_id")
    
    echo -e "\n${CYAN}[$current/$lineup_count] Processing: $lineup_id (Country: $country_code)${RESET}"
    
    # Create safe filename
    safe_filename=$(echo "$lineup_id" | sed 's/[^a-zA-Z0-9._-]/_/g')
    station_file="$STATION_CACHE_DIR/${safe_filename}.json"
    
    # Download stations with explicit error handling
    echo "  Downloading stations..."
    
    # Use explicit error handling instead of relying on set -e
    download_success=false
    if curl -s --connect-timeout 15 --max-time 60 \
        "$CHANNELS_URL/dvr/guide/stations/$lineup_id" -o "$station_file" 2>/dev/null; then
        download_success=true
    fi
    
    if [[ "$download_success" == true ]]; then
        # Validate response with explicit error handling
        validation_success=false
        station_count=0
        
        if [[ -f "$station_file" ]]; then
            # Check if it's valid JSON
            if jq empty "$station_file" 2>/dev/null; then
                station_count=$(jq 'length' "$station_file" 2>/dev/null || echo "0")
                if [[ "$station_count" =~ ^[0-9]+$ ]]; then
                    validation_success=true
                fi
            fi
        fi
        
        if [[ "$validation_success" == true ]]; then
            if [[ "$station_count" -gt 0 ]]; then
                echo -e "  ${GREEN}✅ Downloaded $station_count stations${RESET}"
                
                # Enhance with metadata - use the extracted country code
                enhancement_success=false
                if jq --arg lineup "$lineup_id" --arg source "manual" --arg timestamp "$TIMESTAMP" --arg country "$country_code" \
                   'map(. + {
                     lineup_id: $lineup, 
                     source: $source, 
                     country: $country,
                     processed_timestamp: $timestamp
                   })' "$station_file" > "$station_file.tmp" 2>/dev/null; then
                    
                    if [[ -f "$station_file.tmp" ]] && jq empty "$station_file.tmp" 2>/dev/null; then
                        mv "$station_file.tmp" "$station_file"
                        enhancement_success=true
                    else
                        rm -f "$station_file.tmp" 2>/dev/null
                    fi
                fi
                
                if [[ "$enhancement_success" == true ]]; then
                    # Track for state files (include country code)
                    processed_lineups_data+=("$lineup_id:$station_count:$country_code")
                    
                    ((successful_lineups++))
                    total_stations_raw=$((total_stations_raw + station_count))
                else
                    echo -e "  ${YELLOW}⚠️  Downloaded stations but enhancement failed${RESET}"
                    ((failed_lineups++))
                    rm -f "$station_file" "$station_file.tmp" 2>/dev/null
                fi
            else
                echo -e "  ${YELLOW}⚠️  Lineup exists but contains no stations${RESET}"
                ((empty_lineups++))
                rm -f "$station_file" 2>/dev/null
            fi
        else
            echo -e "  ${RED}❌ Invalid response or corrupted data${RESET}"
            ((failed_lineups++))
            rm -f "$station_file" 2>/dev/null
        fi
    else
        echo -e "  ${RED}❌ Download failed (network error or lineup not found)${RESET}"
        ((failed_lineups++))
        rm -f "$station_file" 2>/dev/null
    fi
    
    # Clean up any temporary files
    rm -f "$station_file.tmp" 2>/dev/null
done

# Show processing summary
echo -e "\n${BOLD}Lineup Processing Summary:${RESET}"
echo -e "${GREEN}✅ Successful: $successful_lineups lineups${RESET}"
echo -e "${YELLOW}⚠️  Empty: $empty_lineups lineups${RESET}"
echo -e "${RED}❌ Failed: $failed_lineups lineups${RESET}"
echo -e "${CYAN}📊 Total: $lineup_count lineups processed${RESET}"

if [[ $successful_lineups -eq 0 ]]; then
    echo -e "\n${RED}❌ No lineups were successfully processed${RESET}"
    echo -e "${YELLOW}This could mean:${RESET}"
    echo -e "  • Lineup IDs are incorrect or don't exist"
    echo -e "  • Server is not responding properly"
    echo -e "  • Network connectivity issues"
    echo -e "  • All lineups are empty (contain no stations)"
    exit 1
fi

echo -e "\n${GREEN}Proceeding with $successful_lineups successful lineups...${RESET}"

# Create combined station file
if [[ $successful_lineups -gt 0 ]]; then
    echo -e "\n${BOLD}${BLUE}=== Creating Combined Files ===${RESET}"
    
    # Combine all stations into proper JSON array
    echo "Combining station files into proper JSON array..."
    master_json="$OUTPUT_DIR/all_stations_master.json"
    
    # Check if any station files exist
    if ! ls "$STATION_CACHE_DIR"/*.json >/dev/null 2>&1; then
        echo -e "${RED}❌ No station files found to process${RESET}"
        exit 1
    fi
    
    # Use jq to properly combine all individual lineup files into array
    jq -s 'add' "$STATION_CACHE_DIR"/*.json > "$master_json"
    
    # Verify it's valid JSON
    if ! jq empty "$master_json" 2>/dev/null; then
        echo -e "${RED}❌ Failed to create valid combined JSON${RESET}"
        exit 1
    fi
    
    echo "✅ Combined JSON array created successfully"
    
    # Flatten, deduplicate, and sort (matching main workflow exactly)
    echo "Deduplicating stations..."
    jq 'sort_by((.name // "") | length) | reverse | unique_by(.stationId)' "$master_json" \
      | jq 'map(.name = (.name // empty))' > "$master_json.tmp"
    mv "$master_json.tmp" "$master_json"
    
    final_station_count=$(jq 'length' "$master_json")
    duplicates_removed=$((total_stations_raw - final_station_count))
    
    echo -e "${GREEN}✅ Combined and deduplicated stations file created${RESET}"
    echo "  Raw stations: $total_stations_raw"
    echo "  Final stations: $final_station_count"
    echo "  Duplicates removed: $duplicates_removed"
    
    # ENHANCEMENT PHASE
    echo -e "\n${BOLD}${BLUE}=== Enhancement Phase ===${RESET}"
    echo "Processing final station list with enhancement..."
    
    enhanced_stations="$OUTPUT_DIR/all_stations_manual.json"
    
    # Read stations into array for processing with error handling
    if ! mapfile -t stations < <(jq -c '.[]' "$master_json" 2>/dev/null); then
        echo -e "${RED}❌ Failed to read stations from master file${RESET}"
        exit 1
    fi
    
    total_stations=${#stations[@]}
    enhanced_from_api=0
    api_errors=0
    enhanced_stations_array=()
    
    echo "Enhancing $total_stations stations..."
    
    for ((i = 0; i < total_stations; i++)); do
        station="${stations[$i]}"
        current=$((i + 1))
        percent=$((current * 100 / total_stations))
        
        # Show progress every 10% or every 100 stations
        if (( current % 100 == 0 )) || (( percent % 10 == 0 && percent != 0 )); then
            printf "\rEnhancing stations: %d/%d (%d%%) - Enhanced: %d, API errors: %d" \
                "$current" "$total_stations" "$percent" "$enhanced_from_api" "$api_errors"
        fi
        
        # Extract fields with error handling
        callSign=""
        name=""
        if callSign=$(echo "$station" | jq -r '.callSign // empty' 2>/dev/null); then
            name=$(echo "$station" | jq -r '.name // empty' 2>/dev/null)
        else
            # If we can't parse the station, keep original
            enhanced_stations_array+=("$station")
            continue
        fi
        
        # Only enhance if station has callsign but missing name
        if [[ -n "$callSign" && "$callSign" != "null" && ( -z "$name" || "$name" == "null" ) ]]; then
            # Try API enhancement with error handling
            api_response=""
            if api_response=$(curl -s --connect-timeout 5 --max-time 10 "$CHANNELS_URL/tms/stations/$callSign" 2>/dev/null); then
                if [[ -n "$api_response" ]] && echo "$api_response" | jq empty 2>/dev/null; then
                    current_station_id=""
                    if current_station_id=$(echo "$station" | jq -r '.stationId' 2>/dev/null); then
                        station_info=""
                        if station_info=$(echo "$api_response" | jq -c --arg id "$current_station_id" '.[] | select(.stationId == $id) // empty' 2>/dev/null); then
                            if [[ -n "$station_info" && "$station_info" != "null" && "$station_info" != "{}" ]]; then
                                # Try to merge the data
                                enhanced_station=""
                                if enhanced_station=$(echo "$station" "$station_info" | jq -s '.[0] * .[1]' 2>/dev/null); then
                                    if [[ -n "$enhanced_station" ]] && echo "$enhanced_station" | jq empty 2>/dev/null; then
                                        station="$enhanced_station"
                                        ((enhanced_from_api++))
                                    else
                                        ((api_errors++))
                                    fi
                                else
                                    ((api_errors++))
                                fi
                            fi
                        fi
                    fi
                else
                    ((api_errors++))
                fi
            else
                ((api_errors++))
            fi
        fi
        
        # Add station to array (enhanced or original)
        enhanced_stations_array+=("$station")
    done
    
    # Clear the progress line and show completion
    echo
    echo -e "${GREEN}✅ Enhancement complete${RESET}"
    echo "  Enhanced from API: $enhanced_from_api"
    [[ $api_errors -gt 0 ]] && echo -e "${YELLOW}  API errors (non-fatal): $api_errors${RESET}"
    
    # Create final JSON array from enhanced stations
    echo "Creating final JSON array..."
    printf '%s\n' "${enhanced_stations_array[@]}" | jq -s '.' > "$enhanced_stations"
    
    # Validate final file
    if jq empty "$enhanced_stations" 2>/dev/null; then
        echo -e "${GREEN}✅ Enhanced stations file is valid JSON array${RESET}"
        echo "  Final station count: $(jq 'length' "$enhanced_stations")"
    else
        echo -e "${RED}❌ Enhanced stations file has JSON errors${RESET}"
        exit 1
    fi
    
    # Continue with rest of file creation...
    echo -e "\n${BOLD}${BLUE}=== Creating State Files ===${RESET}"
    
    # Create CSV file for markets (using extracted country codes)
    echo "Creating markets CSV..."
    markets_csv="$OUTPUT_DIR/sampled_markets_manual.csv"
    {
        echo "Country,ZIP"
        # Create fake geographic entries for manual lineups using extracted country codes
        for lineup_data in "${processed_lineups_data[@]}"; do
            lineup_id=$(echo "$lineup_data" | cut -d':' -f1)
            country_code=$(echo "$lineup_data" | cut -d':' -f3)
            # Create a fake ZIP based on lineup ID
            fake_zip=$(echo "$lineup_id" | sed 's/[^0-9A-Z]//g' | head -c 6)
            [[ -z "$fake_zip" ]] && fake_zip="MANUAL"
            echo "$country_code,$fake_zip"
        done
    } > "$markets_csv"
    
    echo -e "${GREEN}✅ Markets CSV created${RESET}"
    
    # Create cached markets JSONL
    echo "Creating cached markets state..."
    cached_markets="$OUTPUT_DIR/cached_markets_manual.jsonl"
    > "$cached_markets"
    
    for lineup_data in "${processed_lineups_data[@]}"; do
        lineup_id=$(echo "$lineup_data" | cut -d':' -f1)
        country_code=$(echo "$lineup_data" | cut -d':' -f3)
        fake_zip=$(echo "$lineup_id" | sed 's/[^0-9A-Z]//g' | head -c 6)
        [[ -z "$fake_zip" ]] && fake_zip="MANUAL"
        
        # Create market entry
        jq -n --arg country "$country_code" --arg zip "$fake_zip" --arg timestamp "$(date -Iseconds)" \
            '{country: $country, zip: $zip, timestamp: $timestamp, lineups_found: 1}' >> "$cached_markets"
    done
    
    echo -e "${GREEN}✅ Cached markets state created${RESET}"
    
    # Create cached lineups JSONL
    echo "Creating cached lineups state..."
    cached_lineups="$OUTPUT_DIR/cached_lineups_manual.jsonl"
    > "$cached_lineups"
    
    for lineup_data in "${processed_lineups_data[@]}"; do
        lineup_id=$(echo "$lineup_data" | cut -d':' -f1)
        station_count=$(echo "$lineup_data" | cut -d':' -f2)
        
        jq -n --arg lineup "$lineup_id" --arg timestamp "$(date -Iseconds)" --argjson stations "$station_count" \
            '{lineup_id: $lineup, timestamp: $timestamp, stations_found: $stations}' >> "$cached_lineups"
    done
    
    echo -e "${GREEN}✅ Cached lineups state created${RESET}"
    
    # Create lineup-to-market mapping
    echo "Creating lineup-to-market mapping..."
    lineup_mapping="$OUTPUT_DIR/lineup_to_market_manual.json"
    
    {
        echo "{"
        first=true
        for lineup_data in "${processed_lineups_data[@]}"; do
            lineup_id=$(echo "$lineup_data" | cut -d':' -f1)
            country_code=$(echo "$lineup_data" | cut -d':' -f3)
            fake_zip=$(echo "$lineup_id" | sed 's/[^0-9A-Z]//g' | head -c 6)
            [[ -z "$fake_zip" ]] && fake_zip="MANUAL"
            
            if [[ "$first" != true ]]; then
                echo ","
            fi
            first=false
            
            echo -n "  \"$lineup_id\": {\"country\": \"$country_code\", \"zip\": \"$fake_zip\"}"
        done
        echo ""
        echo "}"
    } > "$lineup_mapping"
    
    echo -e "${GREEN}✅ Lineup-to-market mapping created${RESET}"
    
    # Show country code summary
    echo -e "\n${BOLD}Country Code Summary:${RESET}"
    declare -A country_counts
    for lineup_data in "${processed_lineups_data[@]}"; do
        country_code=$(echo "$lineup_data" | cut -d':' -f3)
        ((country_counts["$country_code"]++))
    done
    
    for country in "${!country_counts[@]}"; do
        echo -e "  ${GREEN}$country: ${country_counts[$country]} lineups${RESET}"
    done
    
    # Update integration instructions to mention country code extraction
    echo "Creating integration instructions..."
    instructions="$OUTPUT_DIR/INTEGRATION_INSTRUCTIONS.txt"
    cat > "$instructions" << INSTRUCTIONS_EOF
Manual Lineup Processing Results
Generated: $(date)
Timestamp: $TIMESTAMP

=== SUMMARY ===
Successful lineups: $successful_lineups
Failed lineups: $failed_lineups
Empty lineups: $empty_lineups
Total stations (raw): $total_stations_raw
Final stations (deduplicated): $final_station_count
Duplicates removed: $duplicates_removed
Enhanced from API: $enhanced_from_api

=== COUNTRY CODE EXTRACTION ===
Country codes are automatically extracted from lineup IDs:
INSTRUCTIONS_EOF
    
    for country in "${!country_counts[@]}"; do
        echo "$country: ${country_counts[$country]} lineups" >> "$instructions"
    done
    
    cat >> "$instructions" << INSTRUCTIONS_EOF2

=== ENHANCEMENT DETAILS ===
- Stations missing names were enhanced via TMS API calls
- Enhancement preserves original data and adds missing fields
- $enhanced_from_api stations received enhanced metadata
- API errors: $api_errors (non-fatal, stations still processed)
- Country codes extracted from lineup ID prefixes (CAN-, GBR-, USA-, etc.)

=== FILES CREATED ===
1. all_stations_manual.json - Station data ready for base cache merge (ENHANCED JSON ARRAY)
2. sampled_markets_manual.csv - Markets CSV with proper country codes
3. cached_markets_manual.jsonl - Market processing state
4. cached_lineups_manual.jsonl - Lineup processing state
5. lineup_to_market_manual.json - Lineup-to-market mapping
6. stations/ - Individual lineup station files

=== INTEGRATION STEPS ===

To incorporate these stations into your base cache:

1. BACKUP your current base cache:
   cp all_stations_base.json all_stations_base.json.backup_$(date +%Y%m%d_%H%M%S)
   cp all_stations_base_manifest.json all_stations_base_manifest.json.backup_$(date +%Y%m%d_%H%M%S)

2. MERGE station data:
   jq -s '.[0] + .[1] | unique_by(.stationId) | sort_by(.name // "")' \\
     all_stations_base.json $OUTPUT_DIR/all_stations_manual.json > all_stations_base_new.json
   
   # Standardize source field to "base" for all entries
   jq 'map(.source = "base")' all_stations_base_new.json > all_stations_base_final.json
   mv all_stations_base_final.json all_stations_base.json

3. MERGE markets CSV (if you want to track these):
   tail -n +2 $OUTPUT_DIR/sampled_markets_manual.csv >> sampled_markets.csv

4. MERGE state files (if you want state tracking):
   cat $OUTPUT_DIR/cached_markets_manual.jsonl >> cache/cached_markets.jsonl
   cat $OUTPUT_DIR/cached_lineups_manual.jsonl >> cache/cached_lineups.jsonl
   
   # Merge lineup mapping
   jq -s '.[0] * .[1]' cache/lineup_to_market.json $OUTPUT_DIR/lineup_to_market_manual.json > temp_mapping.json
   mv temp_mapping.json cache/lineup_to_market.json

5. REGENERATE base cache manifest:
   ./create_base_cache_manifest.sh -v -f

6. VALIDATE the result:
   jq 'length' all_stations_base.json  # Should show increased count
   jq empty all_stations_base_manifest.json  # Should validate
   jq 'type' all_stations_base.json  # Should show "array"

=== LINEUP IDs PROCESSED ===
INSTRUCTIONS_EOF2
    
    for lineup_data in "${processed_lineups_data[@]}"; do
        lineup_id=$(echo "$lineup_data" | cut -d':' -f1)
        station_count=$(echo "$lineup_data" | cut -d':' -f2)
        country_code=$(echo "$lineup_data" | cut -d':' -f3)
        echo "$lineup_id ($station_count stations, Country: $country_code)" >> "$instructions"
    done
    
    echo -e "${GREEN}✅ Integration instructions created${RESET}"
    
    # Final summary
    echo -e "\n${BOLD}${GREEN}=== Processing Complete ===${RESET}"
    echo -e "${GREEN}✅ Successfully processed $successful_lineups lineups${RESET}"
    [[ $failed_lineups -gt 0 ]] && echo -e "${YELLOW}⚠️  Failed to process $failed_lineups lineups${RESET}"
    [[ $empty_lineups -gt 0 ]] && echo -e "${YELLOW}⚠️  Empty lineups encountered: $empty_lineups${RESET}"
    echo -e "${GREEN}✅ Created $final_station_count unique stations${RESET}"
    echo -e "${GREEN}✅ Enhanced $enhanced_from_api stations from API${RESET}"
    echo -e "${GREEN}✅ Extracted proper country codes from lineup IDs${RESET}"
    echo -e "${GREEN}✅ All files ready for base cache integration${RESET}"
    echo -e "${GREEN}✅ Output is valid JSON array format${RESET}"
    echo
    echo -e "${BOLD}Output directory: $OUTPUT_DIR${RESET}"
    echo -e "${BOLD}Next step: Follow instructions in $instructions${RESET}"
    
else
    echo -e "\n${RED}❌ No lineups were successfully processed${RESET}"
    exit 1
fi