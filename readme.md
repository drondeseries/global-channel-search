# Global Station Search

A comprehensive television station search tool that integrates with Channels DVR API and Dispatcharr to provide enhanced station discovery, automated field population, and logo management capabilities.

## Version 1.3.1

**New in 1.3.1:**
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

### 🚀 **Instant Ready** - No Setup Required
- **Comprehensive Base Cache** - Thousands of pre-loaded stations from USA, Canada, and UK, including streaming channels
- **Search Immediately** - Works out of the box without any initial caching
- **Optional Expansion** - Add custom markets only if you need additional coverage

### 🔍 **Powerful Search**
- **Local Database Search** - Searching happens locally, without API calls
- **Direct API Search** - Real-time queries to Channels DVR server (requires Channels DVR integration)
- **Smart Filtering** - Filter by resolution (SDTV, HDTV, UHDTV) and country
- **Logo Display** - Visual station logos (requires viu and a compatible terminal)

### 🔧 **Dispatcharr Integration**
- **Automated Station ID Matching** - Interactive matching for channels missing station IDs
- **Complete Field Population** - Automatically populate channel name, TVG-ID, station ID, and logos
- **Visual Comparison** - See current vs. proposed logos side-by-side

### 🌍 **Market Management**
- **Granular Control** - Add specific ZIP codes/postal codes for any country
- **Smart Caching** - Incremental updates only process new markets
- **Base Cache Awareness** - Automatically skips markets already covered
- **Force Refresh** - Override base cache when you need specific market processing

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

## Usage Guide

### 🔍 **Local Database Search**
The fastest and most feature-rich option:
- **Instant Access** - No configuration needed
- **Unlimited Results** - Browse all matching stations

### 🔧 **Dispatcharr Integration**
Automated channel field population:

1. **Scan for Missing Station IDs** - Find channels that need station IDs
2. **Interactive Matching** - Match channels to stations with visual feedback
3. **Populate Additional Fields** - Populate channel name, station ID, logo, and tvg-id [from callsign] using cached Gracenote data

**Logo Workflow:**
- Shows current Dispatcharr logo vs. potential replacement
- Displays both logos side-by-side (if viu installed)
- Uploads new logo to Dispatcharr automatically
- Updates channel with new logo ID
- Comprehensive success feedback

### 🌍 **Custom Market Expansion**
Add markets beyond the base cache:

1. **Manage Television Markets** - Configure additional Countries/ZIP codes
2. **Run User Caching** - Process your custom markets
3. **Incremental Updates** - Add more markets anytime

**Supported Countries:** Any country with 3-letter ISO codes
**Postal Code Tips:**
- **USA:** 5-digit ZIP codes (90210, 10001)
- **UK:** Short format (G1, SW1A, EH1)
- **Canada:** Short format (M5V, K1A)
- Script will auto normalize international postal codes if necessary

### ⚙️ **Settings & Configuration**
Fine-tune the tool's behavior:
- **Server Configuration** - Connect to Channels DVR and Dispatcharr
- **Filter Settings** - Configure default resolution and country filters
- **Logo Display** - Enable/disable logo previews
- **Cache Management** - View statistics and manage cache files

## Advanced Features

### Two-File Cache System
- **Base Cache** (`all_stations_base.json`) - Distributed with the script
- **User Cache** (`cache/all_stations_user.json`) - Your custom additions
- **Automatic Merging** - Combines both for comprehensive coverage

### Smart Market Processing
- **Base Cache Manifest** - Knows what markets are already covered
- **Automatic Skipping** - Avoids redundant API calls
- **Force Refresh** - Override when you need specific processing

### State Tracking
- **Incremental Processing** - Only new markets are processed
- **Recovery Support** - Resume interrupted caching operations
- **Detailed Logging** - Track all operations for troubleshooting

## Integration Details

### Channels DVR
- **Base URL:** `http://IP:PORT` (typically port 8089)
- **Used For:** Direct API search, user cache building
- **Optional:** All core features work without Channels DVR connection

### Dispatcharr
- **Base URL:** `http://IP:PORT` (typically port 9191)
- **Authentication:** Username/password with JWT token management
- **Features:** Dispatcharr channel field population
- **Optional:** Only needed for Dispatcharr channel field population

## File Structure

```
globalstationsearch.sh              # Main script
all_stations_base.json              # Pre-loaded station database
all_stations_base_manifest.json     # Base cache coverage manifest
globalstationsearch.env             # Configuration file
sampled_markets.csv                 # Your custom markets (optional)

cache/                              # Cache directory
├── all_stations_user.json          # Your custom stations
├── cached_markets.jsonl            # Processing state
├── dispatcharr_*.json              # Dispatcharr integration cache
└── logos/                          # Cached station logos
```

## Troubleshooting

### Common Issues

**"Local Search Not Available"**
- Ensure `all_stations_base.json` is in the script directory
- Try running user caching to build a custom database

**"Cannot connect to Dispatcharr"**
- Verify server URL and port (typically 9191)
- Check username/password credentials
- Ensure Dispatcharr is running and accessible

**"No results found"**
- Try different search terms
- Disable filters in Settings if results seem limited
- Use Direct API Search as alternative

### Command Line Diagnostics
```bash
./globalstationsearch.sh --version-info    # System information
# Then use Settings > Developer Information for detailed diagnostics
```

## Contributing

This script is designed to be self-contained and user-friendly. For issues or suggestions:

1. Check the built-in diagnostics (Settings > Developer Information)
2. Review the comprehensive logging in `cache/` directory
3. Use the export functions to share configuration safely

## Version History

- **1.3.0** - Enhanced Dispatcharr integration, logo workflow, menu consistency
- **1.2.0** - Major base cache overhaul, better user cache handling  
- **1.1.0** - Added comprehensive local base cache
- **1.0.0** - Initial release with Dispatcharr integration