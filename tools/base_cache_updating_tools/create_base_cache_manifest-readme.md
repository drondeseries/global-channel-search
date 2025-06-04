Base Cache Manifest Creator
Overview
The Base Cache Manifest Creator (create_base_cache_manifest.sh) is a standalone tool for generating comprehensive manifests from base station cache data. This tool is designed for script maintainers and distributors, not end users.
Purpose
The manifest system enables efficient user caching by:
Preventing Redundant Processing: Skips markets and lineups already covered by the base cache
Optimizing User Experience: Reduces caching time for end users
Maintaining Data Integrity: Ensures accurate tracking of what's included in distributed base caches
When to Run This Tool
Required Scenarios:
✅ New Base Cache Creation: After building a fresh base cache from scratch
✅ Base Cache Updates: When adding new markets/countries to an existing base cache
✅ Data Migration: When migrating from legacy cache systems
✅ Distribution Preparation: Before packaging base cache for distribution
Optional Scenarios:
🔄 Verification: To validate existing manifest accuracy
🔄 Troubleshooting: When users report incorrect skipping behavior
Never Needed:
❌ Regular end-user operations (searching, user caching)
❌ Configuration changes (settings, markets, filters)
❌ Script updates that don't affect base cache content
Prerequisites
Required Files:
all_stations_base.json              # Base station cache (primary data)
sampled_markets.csv                 # Markets used to build base cache
cache/cached_markets.jsonl          # Market processing state
cache/cached_lineups.jsonl          # Lineup processing state  
cache/lineup_to_market.json         # Lineup-to-market mapping
Required Tools:
jq (JSON processor)
awk (text processing)
Standard UNIX tools (sort, wc, etc.)
Usage
Basic Usage
bash
# Create manifest with default settings
./create_base_cache_manifest.sh

# Verbose output to see detailed progress
./create_base_cache_manifest.sh -v

# Force overwrite existing manifest
./create_base_cache_manifest.sh -f
Advanced Usage
bash
# Preview without creating (dry run)
./create_base_cache_manifest.sh --dry-run

# Custom file locations
./create_base_cache_manifest.sh \
  --base-cache custom_base.json \
  --manifest custom_manifest.json \
  --csv custom_markets.csv

# Different cache directory
./create_base_cache_manifest.sh --cache-dir /path/to/cache
Command Line Options
Option	Description	Default
-h, --help	Show help message and exit	
-v, --verbose	Enable detailed progress output	Disabled
-f, --force	Overwrite existing manifest file	Disabled
-n, --dry-run	Preview actions without creating manifest	Disabled
--base-cache FILE	Base cache JSON file	all_stations_base.json
--manifest FILE	Output manifest file	all_stations_base_manifest.json
--csv FILE	Markets CSV file	sampled_markets.csv
--cache-dir DIR	Cache directory containing state files	cache
Output
Success Output:
Base Cache Manifest Creator v1.0.0

[INFO] Analyzing input data...
[INFO] Base cache contains: 11754 stations
[INFO] Markets CSV contains: 3505 markets
[INFO] Cached lineups: 1932 unique lineups (from 9660 entries)
[INFO] Processing markets from CSV...
[INFO] Processed: 3505 markets
[INFO] Processing lineups from cache state...
[INFO] Processed: 1932 unique lineups
[INFO] Processing countries from base cache...
[INFO] Processed: 3 countries
[INFO] Reading lineup to market mapping...
[INFO] Assembling manifest in pieces to avoid argument limits...
[INFO] Manifest created successfully!

=== Manifest Summary ===
Created: 2025-05-31T15:30:45-04:00
Base Cache File: all_stations_base.json
Manifest Version: 1.0.0

Statistics:
  Total Stations: 11754
  Total Markets: 3505
  Total Lineups: 1932
  Countries: USA, CAN, GBR

Manifest File: all_stations_base_manifest.json
File Size: 2.1M

✅ Base cache manifest ready for distribution!
Generated Manifest Structure:
json
{
  "created": "2025-05-31T15:30:45-04:00",
  "base_cache_file": "all_stations_base.json",
  "manifest_version": "1.0.0",
  "description": "Complete base cache manifest with all unique markets and lineups",
  "markets": [
    {"country": "USA", "zip": "10001"},
    {"country": "USA", "zip": "90210"},
    ...
  ],
  "lineups": [
    {"lineup_id": "USA-NY56789-X"},
    {"lineup_id": "CAN-0005993-X"},
    ...
  ],
  "lineup_to_market": { ... },
  "countries": [ ... ],
  "stats": {
    "total_stations": 11754,
    "total_markets": 3505,
    "total_lineups": 1932,
    "countries_covered": ["USA", "CAN", "GBR"]
  }
}
Integration with Main Script
The main Global Station Search script automatically:
Loads existing manifests on startup (init_base_cache_manifest())
Checks market coverage before user caching (check_country_coverage_in_base_cache())
Skips covered markets to prevent redundant processing
Provides force refresh options when needed
Troubleshooting
Common Issues:
"Base cache file not found"
Ensure all_stations_base.json exists in the current directory
Use --base-cache to specify different location
"Cached markets file not found"
Ensure cache state files exist from original base cache creation
Use --cache-dir to specify different cache location
"Argument list too long"
This should not occur with the current implementation
Contact maintainer if this error appears
"Invalid JSON in manifest"
Usually indicates interrupted creation process
Re-run with --force to overwrite corrupted manifest
Validation:
bash
# Check manifest validity
jq empty all_stations_base_manifest.json

# View manifest statistics
jq '.stats' all_stations_base_manifest.json

# Check specific data
jq '.markets | length' all_stations_base_manifest.json
jq '.lineups | length' all_stations_base_manifest.json
Best Practices
Before Running:
Verify all prerequisite files exist and contain expected data
Backup existing manifest if it exists
Use --dry-run first to preview changes
After Running:
Validate generated manifest with jq empty
Check statistics match expectations
Test with main script to ensure proper skipping behavior
Include manifest in distribution package
Maintenance:
Re-run when base cache content changes
Keep documentation updated with any new requirements
Version control both base cache and manifest together
Distribution Notes
When distributing the Global Station Search script:
Include both files: all_stations_base.json + all_stations_base_manifest.json
Place in script directory: Same location as main script
Test manifest loading: Verify main script recognizes manifest on startup
Document coverage: Note which countries/markets are included
Version: 1.0.0
Last Updated: 2025-05-31
Maintainer: Global Station Search Project
