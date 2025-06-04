# Base Cache Update Process

**Global Station Search - Base Cache Maintenance Guide**

This document provides step-by-step instructions for updating the base cache with user contributions, maintaining data integrity, and regenerating the base cache manifest.

## When to Update Base Cache

**Required Scenarios:**
- ✅ Large user contributions (1000+ stations)
- ✅ New geographic coverage areas
- ✅ Significant data quality improvements
- ✅ Major market additions from users

**Optional Scenarios:**
- 🔄 Small user contributions (can be incorporated as-needed)
- 🔄 Data validation updates
- 🔄 Quality improvements

## Prerequisites

**Required Files from User:**
- `all_stations_user.json` - User's station database
- `cached_markets.jsonl` - User's market processing state
- `cached_lineups.jsonl` - User's lineup processing state
- `sampled_markets.csv` - User's markets configuration
- `lineup_to_market.json` - User's lineup mapping (if available)

**Required Tools:**
- `jq` (JSON processor)
- `curl` (for API access)
- `create_base_cache_manifest.sh` (standalone manifest creator)
- Standard UNIX tools (awk, sort, wc, etc.)

**Required Base Files:**
- `all_stations_base.json` - Current base station cache
- `all_stations_base_manifest.json` - Current base cache manifest
- `sampled_markets.csv` - Current markets configuration
- Cache state files in `cache/` directory

## Step-by-Step Process

### Step 1: Data Validation and Backup

**Validate received files:**
```bash
echo "=== File Validation ==="
jq empty all_stations_user.json && echo "✅ User stations: Valid JSON" || echo "❌ Invalid JSON"
jq -s empty cached_markets.jsonl && echo "✅ Cached markets: Valid JSONL" || echo "❌ Invalid JSONL"
jq -s empty cached_lineups.jsonl && echo "✅ Cached lineups: Valid JSONL" || echo "❌ Invalid JSONL"
head -5 sampled_markets.csv  # Verify CSV format

echo "=== Data Counts ==="
echo "User stations: $(jq 'length' all_stations_user.json)"
echo "User markets: $(jq -s 'length' cached_markets.jsonl)"
echo "User lineups: $(jq -s 'length' cached_lineups.jsonl)"
echo "CSV markets: $(awk 'END {print NR-1}' sampled_markets.csv)"
```

**Create backups:**
```bash
echo "=== Creating Backups ==="
MERGE_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "Merge timestamp: $MERGE_TIMESTAMP"

# Backup current base cache files
cp all_stations_base.json all_stations_base.json.backup_${MERGE_TIMESTAMP}
cp all_stations_base_manifest.json all_stations_base_manifest.json.backup_${MERGE_TIMESTAMP}

# Backup current markets and state files
if [ -f sampled_markets.csv ]; then
    cp sampled_markets.csv sampled_markets.csv.backup_${MERGE_TIMESTAMP}
fi

mkdir -p cache_backup_${MERGE_TIMESTAMP}
cp cache/cached_markets.jsonl cache_backup_${MERGE_TIMESTAMP}/ 2>/dev/null || true
cp cache/cached_lineups.jsonl cache_backup_${MERGE_TIMESTAMP}/ 2>/dev/null || true
cp cache/lineup_to_market.json cache_backup_${MERGE_TIMESTAMP}/ 2>/dev/null || true

echo "✅ Backups created with timestamp: $MERGE_TIMESTAMP"
```

### Step 2: Merge Station Data

**Combine station databases:**
```bash
echo "=== Merging Station Data ==="
echo "Starting station merge..."

# Merge stations (user data takes precedence for duplicates)
jq -s '
  .[0] as $base | .[1] as $user |
  # Get user station IDs to identify duplicates
  ($user | map(.stationId)) as $user_ids |
  # Filter base stations to exclude those already in user cache
  ($base | map(select(.stationId | IN($user_ids[]) | not))) as $filtered_base |
  # Combine filtered base + all user stations
  $filtered_base + $user |
  # Sort by name for consistency
  sort_by(.name // "")
' all_stations_base.json all_stations_user.json > all_stations_base_new.json

# Standardize source field to "base" for all entries
echo "Standardizing source field..."
jq 'map(.source = "base")' all_stations_base_new.json > all_stations_base_final.json
mv all_stations_base_final.json all_stations_base_new.json

# Verify the merge
echo "=== Merge Verification ==="
echo "Original base stations: $(jq 'length' all_stations_base.json)"
echo "User stations: $(jq 'length' all_stations_user.json)"
echo "New merged stations: $(jq 'length' all_stations_base_new.json)"

ORIGINAL_BASE=$(jq 'length' all_stations_base.json)
USER_STATIONS=$(jq 'length' all_stations_user.json)
NEW_TOTAL=$(jq 'length' all_stations_base_new.json)
DUPLICATES_FOUND=$(($ORIGINAL_BASE + $USER_STATIONS - $NEW_TOTAL))

echo "Duplicates removed: $DUPLICATES_FOUND"

# Verify source field standardization
echo "Source field verification:"
SOURCE_CHECK=$(jq -r '.[] | .source' all_stations_base_new.json | sort | uniq -c)
echo "$SOURCE_CHECK"

# Validate merged file
jq empty all_stations_base_new.json && echo "✅ Merged file is valid JSON" || echo "❌ JSON validation failed"
```

### Step 3: Merge Market Configuration

**Combine market CSV files:**
```bash
echo "=== Merging Market Configuration ==="

# Rename user file to avoid confusion
mv sampled_markets.csv user_sampled_markets.csv

# Merge CSV files (remove duplicates)
{
  if [ -f sampled_markets.csv.backup_${MERGE_TIMESTAMP} ]; then
    head -1 sampled_markets.csv.backup_${MERGE_TIMESTAMP}
    tail -n +2 sampled_markets.csv.backup_${MERGE_TIMESTAMP}
  else
    echo "Country,ZIP"
  fi
  tail -n +2 user_sampled_markets.csv
} | sort -u > sampled_markets_new.csv

# Verify merge
ORIGINAL_MARKETS=$([ -f sampled_markets.csv.backup_${MERGE_TIMESTAMP} ] && awk 'END {print NR-1}' sampled_markets.csv.backup_${MERGE_TIMESTAMP} || echo "0")
USER_MARKETS=$(awk 'END {print NR-1}' user_sampled_markets.csv)
COMBINED_MARKETS=$(awk 'END {print NR-1}' sampled_markets_new.csv)

echo "Original markets: $ORIGINAL_MARKETS"
echo "User markets: $USER_MARKETS"
echo "Combined markets: $COMBINED_MARKETS"
echo "Market duplicates removed: $(($ORIGINAL_MARKETS + $USER_MARKETS - $COMBINED_MARKETS))"
```

### Step 4: Merge State Tracking Files

**Combine JSONL state files:**
```bash
echo "=== Merging State Tracking Files ==="

# Merge cached markets (remove duplicates by country+zip)
{
  if [ -f cache/cached_markets.jsonl ]; then
    cat cache/cached_markets.jsonl
  fi
  cat cached_markets.jsonl
} | jq -s 'unique_by(.country + "," + .zip)' | jq -c '.[]' > cache/cached_markets_new.jsonl

# Merge cached lineups (remove duplicates by lineup_id)
{
  if [ -f cache/cached_lineups.jsonl ]; then
    cat cache/cached_lineups.jsonl
  fi
  cat cached_lineups.jsonl
} | jq -s 'unique_by(.lineup_id)' | jq -c '.[]' > cache/cached_lineups_new.jsonl

# Merge lineup-to-market mapping
if [ -f lineup_to_market.json ]; then
  if [ -f cache/lineup_to_market.json ]; then
    jq -s '.[0] * .[1]' cache/lineup_to_market.json lineup_to_market.json > cache/lineup_to_market_new.json
  else
    cp lineup_to_market.json cache/lineup_to_market_new.json
  fi
else
  if [ -f cache/lineup_to_market.json ]; then
    cp cache/lineup_to_market.json cache/lineup_to_market_new.json
  else
    echo "{}" > cache/lineup_to_market_new.json
  fi
fi

# Verify state merges
echo "Cached markets merged: $(jq -s 'length' cache/cached_markets_new.jsonl)"
echo "Cached lineups merged: $(jq -s 'length' cache/cached_lineups_new.jsonl)"
echo "Lineup mappings: $(jq 'length' cache/lineup_to_market_new.json)"

# Validate JSON
jq empty cache/cached_markets_new.jsonl && echo "✅ Markets: Valid JSON" || echo "❌ Invalid JSON"
jq empty cache/cached_lineups_new.jsonl && echo "✅ Lineups: Valid JSON" || echo "❌ Invalid JSON"
jq empty cache/lineup_to_market_new.json && echo "✅ Mapping: Valid JSON" || echo "❌ Invalid JSON"
```

### Step 5: Replace Files Atomically

**Replace all files at once:**
```bash
echo "=== Replacing Files Atomically ==="

# Replace station cache
mv all_stations_base_new.json all_stations_base.json
echo "✅ Station database updated"

# Replace market configuration
mv sampled_markets_new.csv sampled_markets.csv
echo "✅ Market configuration updated"

# Replace state tracking files
mv cache/cached_markets_new.jsonl cache/cached_markets.jsonl
mv cache/cached_lineups_new.jsonl cache/cached_lineups.jsonl
mv cache/lineup_to_market_new.json cache/lineup_to_market.json
echo "✅ State tracking files updated"

# Update cache state log
echo "$(date '+%Y-%m-%d %H:%M:%S') - Merged user cache data (timestamp: $MERGE_TIMESTAMP)" >> cache/cache_state.log
echo "✅ Cache state log updated"

# Verify final status
echo "=== Final File Status ==="
echo "Base stations: $(jq 'length' all_stations_base.json)"
echo "Markets in CSV: $(awk 'END {print NR-1}' sampled_markets.csv)"
echo "Cached markets: $(jq -s 'length' cache/cached_markets.jsonl)"
echo "Cached lineups: $(jq -s 'length' cache/cached_lineups.jsonl)"
echo "Lineup mappings: $(jq 'length' cache/lineup_to_market.json)"
```

### Step 6: Regenerate Base Cache Manifest

**Use the standalone manifest creator:**
```bash
echo "=== Regenerating Base Cache Manifest ==="

# Ensure manifest creator exists
if [ ! -f create_base_cache_manifest.sh ]; then
    echo "❌ create_base_cache_manifest.sh not found"
    echo "This tool is required to regenerate the manifest"
    exit 1
fi

chmod +x create_base_cache_manifest.sh

# Run manifest creator with verbose output and force overwrite
./create_base_cache_manifest.sh -v -f

# Verify manifest was created successfully
if [ -f all_stations_base_manifest.json ] && jq empty all_stations_base_manifest.json; then
    echo "✅ Manifest created successfully"
    
    # Show new statistics
    echo "=== New Manifest Statistics ==="
    jq '.stats' all_stations_base_manifest.json
    
    echo "Countries covered: $(jq -r '.stats.countries_covered | join(", ")' all_stations_base_manifest.json)"
    echo "Total markets: $(jq '.stats.total_markets' all_stations_base_manifest.json)"
    echo "Total lineups: $(jq '.stats.total_lineups' all_stations_base_manifest.json)"
    echo "Total stations: $(jq '.stats.total_stations' all_stations_base_manifest.json)"
else
    echo "❌ Manifest creation failed"
    exit 1
fi
```

### Step 7: Validation and Testing

**Comprehensive validation:**
```bash
echo "=== Comprehensive Validation ==="

# Basic file integrity
echo "File integrity check:"
jq empty all_stations_base.json && echo "✅ Base cache: Valid JSON" || echo "❌ Invalid JSON"
jq empty all_stations_base_manifest.json && echo "✅ Manifest: Valid JSON" || echo "❌ Invalid JSON"

# Data consistency validation
STATIONS_IN_CACHE=$(jq 'length' all_stations_base.json)
STATIONS_IN_MANIFEST=$(jq '.stats.total_stations' all_stations_base_manifest.json)

echo "Consistency check:"
echo "  Cache file: $STATIONS_IN_CACHE stations"
echo "  Manifest stats: $STATIONS_IN_MANIFEST stations"

if [ "$STATIONS_IN_CACHE" -eq "$STATIONS_IN_MANIFEST" ]; then
    echo "  ✅ Station counts match"
else
    echo "  ❌ Station counts don't match"
fi

# Data quality check
NULL_NAMES=$(jq '[.[] | select(.name == null or .name == "")] | length' all_stations_base.json)
NO_STATION_ID=$(jq '[.[] | select(.stationId == null or .stationId == "")] | length' all_stations_base.json)

echo "Data quality:"
echo "  Stations with missing names: $NULL_NAMES"
echo "  Stations with missing IDs: $NO_STATION_ID"

# Sample data verification
echo "Sample countries: $(jq -r '[.[] | .country // "Unknown"] | unique | join(", ")' all_stations_base.json)"
```

### Step 8: Create Distribution Package

**Package for distribution:**
```bash
echo "=== Creating Distribution Package ==="

DISTRIBUTION_DIR="base_cache_distribution_${MERGE_TIMESTAMP}"
mkdir -p "$DISTRIBUTION_DIR"

# Copy essential files
cp all_stations_base.json "$DISTRIBUTION_DIR/"
cp all_stations_base_manifest.json "$DISTRIBUTION_DIR/"

# Create distribution documentation
cat > "$DISTRIBUTION_DIR/README.txt" << EOF
Global Station Search - Enhanced Base Cache Distribution
Generated: $(date)
Merge Timestamp: $MERGE_TIMESTAMP

=== STATISTICS ===
Total Stations: $(jq '.stats.total_stations' all_stations_base_manifest.json)
Total Markets: $(jq '.stats.total_markets' all_stations_base_manifest.json)
Total Lineups: $(jq '.stats.total_lineups' all_stations_base_manifest.json)
Countries: $(jq -r '.stats.countries_covered | join(", ")' all_stations_base_manifest.json)

=== INSTALLATION ===
1. Place both JSON files in the same directory as globalstationsearch.sh
2. The script will automatically detect and use both files

=== FILE INTEGRITY ===
Base Cache MD5: $(md5sum all_stations_base.json | cut -d' ' -f1)
Manifest MD5: $(md5sum all_stations_base_manifest.json | cut -d' ' -f1)
EOF

echo "✅ Distribution package created: $DISTRIBUTION_DIR/"
ls -lh "$DISTRIBUTION_DIR"
```

## Best Practices

**Before Starting:**
- ✅ Always create timestamped backups
- ✅ Validate all input files thoroughly
- ✅ Test manifest creator on small datasets first
- ✅ Document the source and scope of contributions

**During Process:**
- ✅ Verify each step before proceeding
- ✅ Check data counts and consistency
- ✅ Monitor for duplicate removal effectiveness
- ✅ Validate JSON integrity at each step
- ✅ Standardize source field to maintain consistent base cache metadata

**After Completion:**
- ✅ Test the updated base cache with main script
- ✅ Verify manifest loading and market skipping
- ✅ Document changes and statistics
- ✅ Create distribution package with documentation

## Troubleshooting

**Common Issues:**

1. **"Argument list too long" during manifest creation**
   - Use chunked manifest creator for large datasets
   - Process lineups in smaller batches

2. **JSON validation failures**
   - Check for encoding issues (UTF-8 required)
   - Validate individual files before merging
   - Look for trailing commas or malformed entries

3. **Inconsistent station counts**
   - Verify deduplication logic worked correctly
   - Check for corrupted source files
   - Ensure all merge steps completed successfully
   - Verify source field standardization completed

4. **Source field inconsistencies**
   - All stations should have source = "base" after merge
   - Check: `jq -r '.[] | .source' all_stations_base.json | sort | uniq -c`
   - Should show only "base" entries

5. **Manifest loading issues**
   - Verify manifest structure matches expected format
   - Check file permissions and accessibility
   - Test manifest functions independently

**Recovery:**
If anything goes wrong, restore from backups:
```bash
cp all_stations_base.json.backup_${MERGE_TIMESTAMP} all_stations_base.json
cp all_stations_base_manifest.json.backup_${MERGE_TIMESTAMP} all_stations_base_manifest.json
cp sampled_markets.csv.backup_${MERGE_TIMESTAMP} sampled_markets.csv
cp -r cache_backup_${MERGE_TIMESTAMP}/* cache/
```

## Version History

- **v1.0.0** - Initial base cache update process
- **v1.1.0** - Added chunked manifest creation support
- **v1.2.0** - Enhanced validation and error handling

---

**Maintainer:** Global Station Search Project  
**Last Updated:** $(date +%Y-%m-%d)  
**Document Version:** 1.2.0