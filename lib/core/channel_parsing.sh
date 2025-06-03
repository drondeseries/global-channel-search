#!/bin/bash

# === Channel Name Parsing Framework ===
# Comprehensive channel name analysis and parsing for station matching

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Helper function to check if a word exists as a separate word (not part of another word)
word_exists() {
    local text="$1"
    local word="$2"
    # Add spaces around text to simplify boundary checking
    local padded_text=" $text "
    local padded_word=" $word "
    # Check if the padded word exists in the padded text
    [[ "$padded_text" == *"$padded_word"* ]]
}

# Helper function to remove a word safely (only if it's a separate word)
remove_word() {
    local text="$1"
    local word="$2"
    # Remove the word and clean up extra spaces
    echo "$text" | sed -E "s/(^|[[:space:]])$word([[:space:]]|$)/ /g" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# ============================================================================
# CORE CHANNEL PARSING FUNCTIONS
# ============================================================================

# Main channel parsing function - returns cleaned name and detected attributes
parse_channel_name() {
    local channel_name="$1"
    local debug_mode="${2:-false}"
    
    # Initialize variables
    local clean_name="$channel_name"
    local detected_country=""
    local detected_resolution=""
    local detected_language=""
    local confidence_score=0
    
    # Step 0: Handle special character separators FIRST
    clean_name=$(handle_special_separators "$clean_name")
    
    # Step 1: Country detection - check for separate words only
    if word_exists "$clean_name" "US" || word_exists "$clean_name" "USA"; then
        detected_country="USA"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "US")
        clean_name=$(remove_word "$clean_name" "USA")
    elif word_exists "$clean_name" "CA" || word_exists "$clean_name" "CAN" || word_exists "$clean_name" "CANADA"; then
        detected_country="CAN" 
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "CA")
        clean_name=$(remove_word "$clean_name" "CAN")
        clean_name=$(remove_word "$clean_name" "CANADA")
    elif word_exists "$clean_name" "UK" || word_exists "$clean_name" "GBR" || word_exists "$clean_name" "BRITAIN"; then
        detected_country="GBR"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "UK")
        clean_name=$(remove_word "$clean_name" "GBR")
        clean_name=$(remove_word "$clean_name" "BRITAIN")
    elif word_exists "$clean_name" "DE" || word_exists "$clean_name" "DEU" || word_exists "$clean_name" "GERMANY"; then
        detected_country="DEU"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "DE")
        clean_name=$(remove_word "$clean_name" "DEU")
        clean_name=$(remove_word "$clean_name" "GERMANY")
    elif word_exists "$clean_name" "FR" || word_exists "$clean_name" "FRA" || word_exists "$clean_name" "FRANCE"; then
        detected_country="FRA"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "FR")
        clean_name=$(remove_word "$clean_name" "FRA")
        clean_name=$(remove_word "$clean_name" "FRANCE")
    elif word_exists "$clean_name" "ES" || word_exists "$clean_name" "ESP" || word_exists "$clean_name" "SPAIN"; then
        detected_country="ESP"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "ES")
        clean_name=$(remove_word "$clean_name" "ESP")
        clean_name=$(remove_word "$clean_name" "SPAIN")
    elif word_exists "$clean_name" "IT" || word_exists "$clean_name" "ITA" || word_exists "$clean_name" "ITALY"; then
        detected_country="ITA"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "IT")
        clean_name=$(remove_word "$clean_name" "ITA")
        clean_name=$(remove_word "$clean_name" "ITALY")
    elif word_exists "$clean_name" "JP" || word_exists "$clean_name" "JPN" || word_exists "$clean_name" "JAPAN"; then
        detected_country="JPN"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "JP")
        clean_name=$(remove_word "$clean_name" "JPN")
        clean_name=$(remove_word "$clean_name" "JAPAN")
    elif word_exists "$clean_name" "AU" || word_exists "$clean_name" "AUS" || word_exists "$clean_name" "AUSTRALIA"; then
        detected_country="AUS"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "AU")
        clean_name=$(remove_word "$clean_name" "AUS")
        clean_name=$(remove_word "$clean_name" "AUSTRALIA")
    fi

    # Step 2: Resolution detection patterns (order matters - check highest quality first)
    if word_exists "$clean_name" "4K" || word_exists "$clean_name" "UHD" || word_exists "$clean_name" "UHDTV" || [[ "$clean_name" =~ Ultra[[:space:]]*HD ]]; then
        detected_resolution="UHDTV"
        confidence_score=$((confidence_score + 30))
        clean_name=$(remove_word "$clean_name" "4K")
        clean_name=$(remove_word "$clean_name" "UHD") 
        clean_name=$(remove_word "$clean_name" "UHDTV")
        clean_name=$(echo "$clean_name" | sed -E 's/Ultra[[:space:]]*HD/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    elif word_exists "$clean_name" "FHD" || [[ "$clean_name" =~ (^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$) ]]; then
        # FIXED: Remove standalone "HD" check that was too broad - now only matches FHD and specific resolutions
        detected_resolution="HDTV"
        confidence_score=$((confidence_score + 25))
        clean_name=$(remove_word "$clean_name" "FHD")
        clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])(1080[ip]?|720[ip]?)([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    elif word_exists "$clean_name" "HD" && ! [[ "$clean_name" =~ [0-9] ]]; then
        # FIXED: Only match "HD" if it's standalone and there are no numbers in the name (to avoid "4 MORE" matches)
        detected_resolution="HDTV"
        confidence_score=$((confidence_score + 25))
        clean_name=$(remove_word "$clean_name" "HD")
    elif word_exists "$clean_name" "SD" || [[ "$clean_name" =~ (^|[[:space:]])480[ip]?([[:space:]]|$) ]]; then
        detected_resolution="SDTV"
        confidence_score=$((confidence_score + 25))
        clean_name=$(remove_word "$clean_name" "SD")
        clean_name=$(echo "$clean_name" | sed -E 's/(^|[[:space:]])480[ip]?([[:space:]]|$)/ /g' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    fi
    
    # Step 3: Language detection
    if word_exists "$clean_name" "ENGLISH" || word_exists "$clean_name" "ENG" || word_exists "$clean_name" "EN"; then
        detected_language="en"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "ENGLISH")
        clean_name=$(remove_word "$clean_name" "ENG")
        clean_name=$(remove_word "$clean_name" "EN")
    elif word_exists "$clean_name" "SPANISH" || word_exists "$clean_name" "ESPANOL" || word_exists "$clean_name" "SPA"; then
        detected_language="es"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "SPANISH")
        clean_name=$(remove_word "$clean_name" "ESPANOL")
        clean_name=$(remove_word "$clean_name" "SPA")
    elif word_exists "$clean_name" "FRENCH" || word_exists "$clean_name" "FRANCAIS"; then
        detected_language="fr"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "FRENCH")
        clean_name=$(remove_word "$clean_name" "FRANCAIS")
    elif word_exists "$clean_name" "GERMAN" || word_exists "$clean_name" "DEUTSCH"; then
        detected_language="de"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "GERMAN")
        clean_name=$(remove_word "$clean_name" "DEUTSCH")
    elif word_exists "$clean_name" "ITALIAN" || word_exists "$clean_name" "ITALIANO"; then
        detected_language="it"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "ITALIAN")
        clean_name=$(remove_word "$clean_name" "ITALIANO")
    elif word_exists "$clean_name" "PORTUGUESE"; then
        detected_language="pt"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "PORTUGUESE")
    elif word_exists "$clean_name" "JAPANESE"; then
        detected_language="ja"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "JAPANESE")
    elif word_exists "$clean_name" "CHINESE" || word_exists "$clean_name" "MANDARIN"; then
        detected_language="zh"
        confidence_score=$((confidence_score + 20))
        clean_name=$(remove_word "$clean_name" "CHINESE")
        clean_name=$(remove_word "$clean_name" "MANDARIN")
    fi
    
    # Step 4: Final cleanup
    clean_name=$(perform_general_cleanup "$clean_name")
    
    # Debug output
    if [[ "$debug_mode" == "true" ]]; then
        echo "DEBUG: Original: '$channel_name'" >&2
        echo "DEBUG: After separator handling: '$(handle_special_separators "$channel_name")'" >&2
        echo "DEBUG: Final cleaned: '$clean_name'" >&2
        echo "DEBUG: Country: '$detected_country'" >&2
        echo "DEBUG: Resolution: '$detected_resolution'" >&2
        echo "DEBUG: Language: '$detected_language'" >&2
        echo "DEBUG: Confidence: $confidence_score" >&2
    fi
    
    # Return format: clean_name|country|resolution|language|confidence
    echo "$clean_name|$detected_country|$detected_resolution|$detected_language|$confidence_score"
}

# ============================================================================
# SPECIAL CHARACTER SEPARATOR HANDLING
# ============================================================================

handle_special_separators() {
    local input_name="$1"
    local clean_name="$input_name"
    
    # Replace special character separators with spaces
    # This must happen BEFORE any other parsing to ensure proper separation of tokens
    
    # Check if we have separators to avoid unnecessary processing
    if [[ "$clean_name" =~ [\|★◉:►▶→»≫—–=〉〈⟩⟨◆♦◊⬥●•] ]]; then
        # Replace separators with spaces - handle each type
        clean_name=$(echo "$clean_name" | sed 's/[\|★◉:►▶→»≫—–=〉〈⟩⟨◆♦◊⬥●•]/ /g')
        
        # Normalize spacing after separator replacement
        clean_name=$(echo "$clean_name" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    fi
    
    echo "$clean_name"
}

# ============================================================================
# GENERAL CLEANUP FUNCTIONS
# ============================================================================

perform_general_cleanup() {
    local input_name="$1"
    local clean_name="$input_name"
    
    # Remove common prefixes and suffixes
    clean_name=$(remove_common_prefixes "$clean_name")
    clean_name=$(remove_common_suffixes "$clean_name")
    clean_name=$(remove_remaining_special_characters "$clean_name")
    clean_name=$(normalize_spacing "$clean_name")
    clean_name=$(remove_generic_terms "$clean_name")
    
    echo "$clean_name"
}

remove_common_prefixes() {
    local name="$1"
    
    # Remove common channel prefixes - use word boundaries
    name=$(echo "$name" | sed -E 's/^(CHANNEL|CH|NETWORK|NET|TV|TELEVISION|DIGITAL|CABLE|SATELLITE|STREAM|LIVE|24\/7|24-7)[[:space:]]+//gi')
    
    echo "$name"
}

remove_common_suffixes() {
    local name="$1"
    
    # Remove common channel suffixes - use word boundaries
    name=$(echo "$name" | sed -E 's/[[:space:]]+(CHANNEL|CH|NETWORK|NET|TV|TELEVISION|DIGITAL|LIVE|STREAM|PLUS|\+|24\/7|24-7)$//gi')
    
    echo "$name"
}

remove_remaining_special_characters() {
    local name="$1"
    
    # Remove or replace remaining special characters (after separator handling)
    # Replace underscores and hyphens with spaces
    name=$(echo "$name" | tr '_-' '  ')
    
    # Remove brackets and parentheses
    name=$(echo "$name" | tr -d '()[]{}<>')
    
    # Remove remaining special symbols
    name=$(echo "$name" | tr -d '#@$%^&*')
    
    # Remove trailing punctuation
    name=$(echo "$name" | sed 's/[[:punct:]]*$//')
    
    echo "$name"
}

normalize_spacing() {
    local name="$1"
    
    # Normalize whitespace
    name=$(echo "$name" | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    echo "$name"
}

remove_generic_terms() {
    local name="$1"
    
    # Remove very generic terms that don't help with matching
    name=$(echo "$name" | sed -E 's/\b(THE|A|AN|AND|OR|OF|IN|ON|AT|TO|FOR|WITH|OFFICIAL|ORIGINAL|PREMIUM|EXCLUSIVE|ONLINE|DIGITAL|STREAMING|BROADCAST)\b/ /gi')
    
    # Final spacing cleanup after term removal
    name=$(normalize_spacing "$name")
    
    echo "$name"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Extract call sign patterns from channel names
extract_call_sign() {
    local channel_name="$1"
    local call_sign=""
    
    # Common call sign patterns
    if [[ "$channel_name" =~ \b([KWCN][A-Z]{2,4})\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    elif [[ "$channel_name" =~ \b([A-Z]{3,5})[[:space:]]*TV\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    elif [[ "$channel_name" =~ \b([A-Z]{2,4})[[:space:]]*[0-9]+\b ]]; then
        call_sign="${BASH_REMATCH[1]}"
    fi
    
    echo "$call_sign"
}

# Get parsing confidence level description
get_confidence_description() {
    local confidence="$1"
    
    if [[ $confidence -ge 50 ]]; then
        echo "High"
    elif [[ $confidence -ge 30 ]]; then
        echo "Medium"
    elif [[ $confidence -ge 15 ]]; then
        echo "Low"
    else
        echo "Minimal"
    fi
}

# Test channel parsing with multiple examples including special separators
test_channel_parsing() {
    local test_channels=(
        "CNN USA HD"
        "BBC One UK"
        "ESPN★4K UHD"
        "Discovery Channel:Canada"
        "Fox News|HD English"
        "Channel 5◉UK SD"
        "ABC Family►USA 1080p"
        "TV5→France French"
        "NHK●Japan HD"
        "History Channel★USA★HD"
        "Comedy Central|USA|720p"
        "National Geographic◉4K◉English"
        "Generic Channel Name"
        "BONUS"
        "BUSINESS NEWS"
        "TRUST TV"
        "US ESPN"
        "ESPN US"
        "ESPN HD US"
        "MUSIC CA"
        "DEUTSCHE WELLE DE"
        "4K NATURE"
        "PREMIUM HD"
        "STANDARD SD"
        "MUSIC"
        "US: ESPN"
        "ESPN | HD"
        "HBO ★ Premium"
        "CNN ◉ News US"
        "UK: BBC HD"
        "Sports:CA"
    )
    
    echo "=== Channel Parsing Test Results ==="
    echo
    
    for channel in "${test_channels[@]}"; do
        echo "Original: '$channel'"
        local result=$(parse_channel_name "$channel")
        IFS='|' read -r clean_name country resolution language confidence <<< "$result"
        
        echo "  Clean: '$clean_name'"
        [[ -n "$country" ]] && echo "  Country: $country"
        [[ -n "$resolution" ]] && echo "  Resolution: $resolution"
        [[ -n "$language" ]] && echo "  Language: $language"
        echo "  Confidence: $confidence ($(get_confidence_description "$confidence"))"
        echo
    done
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Functions are automatically available when this module is sourced
# No explicit exports needed - sourcing makes all functions available in the calling script

# Optional: Log successful module load
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Module was sourced, not executed directly
    true  # Functions are now available
fi
