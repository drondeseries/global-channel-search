# Global Station Search

A comprehensive television station search tool that (optionally) integrates with Channels DVR and Dispatcharr to provide enhanced station discovery and automated Dispatcharr field population.

## Version 1.4.0

**MAJOR RELEASE (1.4.0) - 2025-06-02**
- **New Modular Framework** - Complete architecture overhaul with lib/ directory structure
- **Major Code Reduction** - Eliminated 1000+ lines of duplicate code
- Fixed broken Channels DVR API search functionality
- Resolved critical user cache building issues
- More consistent UI/UX patterns across all menus
- Advanced channel name regex parsing

**Previous Patch (1.3.3) - 2025-06-02**
- Bug fixes from 1.3.2 update

**1.3.2:**
- Fixed broken dispatcharr token refresh logic
- Added `increment_dispatcharr_interaction()` calls to all Dispatcharr API functions
- Removed manual counting from batch operations for automatic refresh
- Added save and resume state handling to Dispatcharr all channels workflow
- Added ability to start at any channel in the Dispatcharr all channels workflow
- Users can now resume from last processed channel, start fresh, or pick specific channel number
- Resume state persists between script runs via configuration file

**1.3.1:**
- **Enhanced Dispatcharr Workflows** - Significantly improved efficiency and user experience
- **Streamlined Channel Processing** - Removed disruptive prompts for smoother batch operations
- **Improved Channel Name Parsing** - Enhanced regex logic with helper functions for better auto-matching
- **Consistent Channel Sorting** - Fixed sorting across all Dispatcharr workflows (lowest to highest channel number)
- **Better Navigation Controls** - Added proper escape options and single-channel processing modes
- **Enhanced Guidance** - Updated instructions and messaging for better accuracy across functions
- **Improved Error Handling** - Better backup handling and recovery mechanisms
- **Code Cleanup** - Removed broken features and improved overall consistency

**Previous Major Release (1.3.0):**
- Command line flags (`-v`, `-h`, `--version-info`)
- USA and GBR streaming channels added to base cache
- Enhanced Dispatcharr logo integration with API workflow
- Fixed global country search filter
- Menu consistency improvements

## Features

### No Setup Required
- **Comprehensive Base Cache** - Thousands of pre-loaded stations from USA, Canada, and UK, including streaming channels
- **Search immediately**
- **Optional Expansion** - Add custom markets only if you need additional coverage

### 🔍 **Powerful Search**
- **Local Database Search** - Searching happens locally, without API calls
- **Direct API Search** - Real-time queries to Channels DVR server (requires Channels DVR integration)
- **Smart Filtering** - Filter by resolution (SDTV, HDTV, UHDTV) and country
- **Logo Display** - Visual station logos (requires viu and a compatible terminal)
- **Advanced Channel Name Parsing** - Intelligent channel name analysis with auto-detection of country, resolution, and language
- **Reverse Station ID Lookup**

### 🔧 **Dispatcharr Integration**
- **Automated Station ID Matching** - Interactive matching for channels missing station IDs
- **Complete Field Population** - Automatically populate channel name, TVG-ID, station ID, and logos
- **Visual Comparison** - See current vs. proposed logos side-by-side
- **Batch Processing Modes** - Choose immediate apply or queue for review
- **Automatic Data Replacement** - Mass update all channels with station IDs
- **Resume Support** - Continue processing from where you left off

### 🌍 **Market Management**
- **Granular Control** - Add specific ZIP codes/postal codes for any country
- **Smart Caching** - Incremental updates only process new markets
- **Base Cache Awareness** - Automatically skips markets already covered
- **Force Refresh** - Override base cache when you need specific market processing
- **Enhanced Validation** - Country and postal code normalization and validation

## Requirements

### Required
- **jq** - JSON processing
- **curl** - HTTP requests
- **bash 4.0+** - Shell environment

### Optional
- **viu** - Logo previews and display
- **bc** - Progress calculations during caching
- **Channels DVR server** - For Direct API Search and adding channels using user cache
- **Dispatcharr** - For automated channel field population

## Installation

1. **Download the script:**
```bash
git clone https://github.com/egyptiangio/global-channel-search
cd global-channel-search
```

2. **Make executable:**
```bash
chmod +x globalstationsearch.sh
```

3. **Install dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install jq curl

# macOS
brew install jq curl

# Optional: Logo preview support
Install viu - https://github.com/atanunq/viu
```

## Quick Start

### Option 1: Immediate Use (Recommended)
```bash
./globalstationsearch.sh
```
Select **"Search Local Database"** - works immediately with thousands of pre-loaded stations!

### Option 2: Command Line Help
```bash
./globalstationsearch.sh --help           # Usage help
./globalstationsearch.sh --version        # Version number
./globalstationsearch.sh --version-info   # Detailed version info
```

## File Structure

```
globalstationsearch.sh              # Main script
all_stations_base.json              # Pre-loaded station database
all_stations_base_manifest.json     # Base cache coverage manifest

lib/                                # Modular framework (new in 1.4.0)
├── core/                           # Core functionality
│   ├── utils.sh                    # Utility functions
│   ├── config.sh                   # Configuration management
│   ├── settings.sh                 # Settings framework
│   ├── cache.sh                    # Cache management
│   └── channel_parsing.sh          # Channel name parsing
└── ui/                             # User interface
    ├── display.sh                  # Display formatting
    └── menus.sh                    # Menu framework

data/                               # Configuration and user data
├── globalstationsearch.env         # Configuration file
├── valid_country_codes.txt         # ISO country codes
├── logs/                           # Operation logs
│   ├── cache_state.log             # Cache operation history
│   └── dispatcharr_operations.log  # Dispatcharr integration logs
├── user_cache/                     # User cache directory
│   ├── all_stations_user.json      # Your custom stations
│   ├── sampled_markets.csv         # Your custom markets
│   ├── cached_markets.jsonl        # Market processing state
│   ├── cached_lineups.jsonl        # Lineup processing state
│   └── lineup_to_market.json       # Lineup-to-market mapping
└── backups/                        # Backup directory
    ├── config_backups/             # Configuration backups
    ├── cache_backups/              # Cache backups
    └── export_backups/             # Export backups

cache/                              # Working cache directory
├── all_stations_combined.json      # Runtime combination (temporary)
├── all_lineups.jsonl               # Cached lineup data
├── api_search_results.tsv          # Direct API search results
├── search_results.tsv              # Local search results
├── dispatcharr_channels.json       # Dispatcharr channel cache
├── dispatcharr_matches.tsv         # Pending station ID matches
├── dispatcharr_tokens.json         # Authentication tokens
├── dispatcharr_logos.json          # Logo cache mapping
├── logos/                          # Cached station logos
└── stations/                       # Station cache files
```

## Contributing

This script is designed to be self-contained and user-friendly. For issues or suggestions find me on the dispatcharr discord.

## Version History

- **1.4.0** - Major modular architecture overhaul, enhanced stability, improved workflows
- **1.3.3** - Bug fixes and stability improvements
- **1.3.2** - Dispatcharr token refresh fixes, resume support
- **1.3.1** - Enhanced Dispatcharr workflows, improved parsing, better navigation
- **1.3.0** - Enhanced Dispatcharr integration, logo workflow, menu consistency
- **1.2.0** - Major base cache overhaul, better user cache handling  
- **1.1.0** - Added comprehensive local base cache
- **1.0.0** - Initial release with Dispatcharr integration