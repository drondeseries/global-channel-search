# Manual Lineup Processor Documentation

**Global Station Search - Manual Lineup Processing Tool**

A standalone utility for downloading stations from specific lineup IDs and creating all necessary files for base cache incorporation.

## Overview

The Manual Lineup Processor is designed for situations where you need to download stations from specific lineup codes that don't exist in any country/postal code combination. This is particularly useful for:

- Special streaming service lineups
- Satellite/cable provider-specific lineups
- Regional broadcast lineups not tied to geographic markets
- Custom or proprietary lineup configurations

## Features

- ✅ **Direct Lineup Processing** - Download stations from specific lineup IDs
- ✅ **Comprehensive Enhancement** - Enhances station data via TMS API calls
- ✅ **Automatic Deduplication** - Removes duplicate stations across lineups
- ✅ **State File Generation** - Creates all necessary files for base cache integration
- ✅ **Progress Tracking** - Real-time progress reporting with statistics
- ✅ **Error Resilience** - Continues processing even when some lineups fail
- ✅ **Integration Ready** - Outputs files ready for base cache merge

## Prerequisites

**Required Tools:**
- `jq` (JSON processor)
- `curl` (HTTP client)
- Bash shell (version 4.0+)
- Standard UNIX tools (awk, sort, wc, etc.)

**Required Access:**
- Channels DVR server with TMS API access
- Network connectivity to the Channels DVR server
- Write permissions in working directory

**File Inputs:**
- Text file containing lineup IDs (one per line)
- Comments supported (lines starting with #)

## Installation

1. **Download the script:**
   ```bash
   # Script should be provided as manual_lineup_processor.sh
   chmod +x manual_lineup_processor.sh
   ```

2. **Verify dependencies:**
   ```bash
   # Check required tools
   jq --version
   curl --version
   ```

3. **Test connectivity:**
   ```bash
   # Test your Channels DVR server
   curl -s http://your-server:8089 > /dev/null && echo "Server accessible" || echo "Server not accessible"
   ```

## Usage

### Basic Usage

```bash
# Process lineups from a file
./manual_lineup_processor.sh lineup_file.txt

# With custom server
./manual_lineup_processor.sh --server http://192.168.1.100:8089 lineup_file.txt

# With custom output directory
./manual_lineup_processor.sh --output my_results lineup_file.txt
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-s, --server URL` | Channels DVR server URL | `http://localhost:8089` |
| `-o, --output DIR` | Output directory | `manual_lineup_output` |
| `-h, --help` | Show help message | - |

### Input File Format

Create a text file with one lineup ID per line:

```text
# Example lineup file
# Lines starting with # are comments

# US Streaming Services
USA-STREAMING-001
USA-STREAMING-002

# Canadian Satellite
CAN-SATELLITE-999

# UK Digital
GBR-DIGITAL-ABC

# Add your actual lineup IDs below
YOUR-LINEUP-ID-1
YOUR-LINEUP-ID-2
```

**Input File Guidelines:**
- One lineup ID per line
- Comments supported (lines starting with #)
- Empty lines are ignored
- Whitespace is automatically trimmed
- Case-sensitive lineup IDs

## Processing Workflow

### Phase 1: Validation and Setup
1. **Dependency Check** - Verifies required tools are available
2. **Server Connectivity** - Tests connection to Channels DVR server
3. **Input Validation** - Validates lineup file format and content
4. **Directory Creation** - Sets up output directory structure

### Phase 2: Lineup Processing
1. **Download Stations** - Fetches station data for each lineup ID
2. **Data Validation** - Validates JSON response and station count
3. **Metadata Enhancement** - Adds lineup_id, source, and timestamp info
4. **Error Handling** - Logs failures but continues processing

### Phase 3: Deduplication and Enhancement
1. **File Combination** - Merges all individual lineup files
2. **Deduplication** - Removes duplicate stations by station ID
3. **Enhancement Loop** - Enhances stations missing names via TMS API
4. **Progress Tracking** - Shows real-time enhancement progress

### Phase 4: State File Creation
1. **Markets CSV** - Creates fake geographic entries for state tracking
2. **Cached Markets** - Generates market processing state (JSONL)
3. **Cached Lineups** - Generates lineup processing state (JSONL)
4. **Lineup Mapping** - Creates lineup-to-market mapping (JSON)

### Phase 5: Integration Preparation
1. **Instructions** - Generates step-by-step integration guide
2. **Validation** - Verifies all output files are valid JSON
3. **Statistics** - Provides comprehensive processing summary

## Output Files

The script creates the following files in the output directory:

### Primary Output Files

| File | Description | Purpose |
|------|-------------|---------|
| `all_stations_manual.json` | Enhanced station data | Ready for base cache merge |
| `sampled_markets_manual.csv` | Fake markets configuration | State tracking support |
| `cached_markets_manual.jsonl` | Market processing state | Integration with existing state |
| `cached_lineups_manual.jsonl` | Lineup processing state | Integration with existing state |
| `lineup_to_market_manual.json` | Lineup-to-market mapping | State tracking relationships |

### Supporting Files

| File | Description | Purpose |
|------|-------------|---------|
| `INTEGRATION_INSTRUCTIONS.txt` | Step-by-step integration guide | Base cache merge instructions |
| `stations/*.json` | Individual lineup station files | Debugging and verification |

### File Formats

**Enhanced Station Data** (`all_stations_manual.json`):
```json
[
  {
    "stationId": "12345",
    "name": "Example Channel",
    "callSign": "EXAM",
    "country": "MANUAL",
    "lineup_id": "USA-STREAMING-001",
    "source": "manual",
    "processed_timestamp": "20241231_143022",
    "videoQuality": {
      "videoType": "HDTV"
    },
    "preferredImage": {
      "uri": "https://example.com/logo.png"
    }
  }
]
```

**State Files** (JSONL format):
```json
{"country": "MANUAL", "zip": "MANUAL", "timestamp": "2024-12-31T14:30:22-05:00", "lineups_found": 1}
{"lineup_id": "USA-STREAMING-001", "timestamp": "2024-12-31T14:30:22-05:00", "stations_found": 15}
```

## Integration with Base Cache

### Automatic Integration

Follow the instructions in `INTEGRATION_INSTRUCTIONS.txt`:

1. **Backup Current Base Cache:**
   ```bash
   cp all_stations_base.json all_stations_base.json.backup_$(date +%Y%m%d_%H%M%S)
   cp all_stations_base_manifest.json all_stations_base_manifest.json.backup_$(date +%Y%m%d_%H%M%S)
   ```

2. **Merge Station Data:**
   ```bash
   jq -s '.[0] + .[1] | unique_by(.stationId) | sort_by(.name // "")' \
     all_stations_base.json manual_lineup_output/all_stations_manual.json > all_stations_base_new.json
   mv all_stations_base_new.json all_stations_base.json
   ```

3. **Merge State Files:** (Optional)
   ```bash
   tail -n +2 manual_lineup_output/sampled_markets_manual.csv >> sampled_markets.csv
   cat manual_lineup_output/cached_markets_manual.jsonl >> cache/cached_markets.jsonl
   cat manual_lineup_output/cached_lineups_manual.jsonl >> cache/cached_lineups.jsonl
   
   jq -s '.[0] * .[1]' cache/lineup_to_market.json manual_lineup_output/lineup_to_market_manual.json > temp_mapping.json
   mv temp_mapping.json cache/lineup_to_market.json
   ```

4. **Regenerate Manifest:**
   ```bash
   ./create_base_cache_manifest.sh -v -f
   ```

5. **Validate Results:**
   ```bash
   jq 'length' all_stations_base.json  # Should show increased count
   jq empty all_stations_base_manifest.json  # Should validate successfully
   ```

### Manual Integration

For more control, manually review and merge specific aspects:

1. **Review Station Data:**
   ```bash
   # Check quality of downloaded stations
   jq '.[] | {id: .stationId, name: .name, lineup: .lineup_id}' manual_lineup_output/all_stations_manual.json | head -10
   ```

2. **Selective Merge:**
   ```bash
   # Merge only specific lineups or filter by criteria
   jq '[.[] | select(.lineup_id | startswith("USA-STREAMING"))]' manual_lineup_output/all_stations_manual.json > streaming_only.json
   ```

## Error Handling and Troubleshooting

### Common Issues

**1. Server Connection Failures**
```bash
Error: Cannot connect to Channels DVR at http://localhost:8089
```
- **Cause:** Server is offline or incorrect URL
- **Solution:** Verify server is running and accessible
- **Check:** `curl -s http://your-server:8089`

**2. Invalid Lineup IDs**
```bash
❌ Download failed (network error or lineup not found)
```
- **Cause:** Lineup ID doesn't exist or is incorrect
- **Solution:** Verify lineup IDs with your provider
- **Note:** Script continues with other lineups

**3. Empty Lineups**
```bash
⚠️ Lineup exists but contains no stations
```
- **Cause:** Lineup is valid but has no stations
- **Solution:** Normal behavior, check if lineup should have stations
- **Note:** Script continues processing

**4. JSON Validation Errors**
```bash
❌ Invalid response or corrupted data
```
- **Cause:** Server returned malformed JSON
- **Solution:** Check server health, retry later
- **Debug:** Check individual station files in `stations/` directory

**5. Enhancement Failures**
```bash
API errors (non-fatal): 15
```
- **Cause:** TMS API timeouts or rate limiting
- **Solution:** Normal for large datasets, stations still processed
- **Note:** Enhancement improves data quality but isn't required

### Debug Mode

Enable verbose debugging by modifying the script:

```bash
# Add debug output
set -x  # Enable command tracing

# Check individual files
ls -la manual_lineup_output/stations/
jq '.' manual_lineup_output/stations/YOUR_LINEUP_ID.json
```

### Recovery Procedures

**Partial Processing Failure:**
```bash
# Continue from where it left off
# Script automatically skips successfully processed files
./manual_lineup_processor.sh --output same_directory lineup_file.txt
```

**Complete Failure Recovery:**
```bash
# Clean up and restart
rm -rf manual_lineup_output
./manual_lineup_processor.sh lineup_file.txt
```

## Performance Considerations

### Processing Time

**Factors Affecting Speed:**
- Number of lineup IDs (1-2 minutes per lineup)
- Station count per lineup (varies widely)
- Network latency to Channels DVR server
- Enhancement API call time (when stations missing names)

**Typical Performance:**
- **Small Dataset:** 5-10 lineups, 5-15 minutes
- **Medium Dataset:** 20-50 lineups, 30-60 minutes  
- **Large Dataset:** 100+ lineups, 2-4 hours

### Optimization Tips

1. **Process During Off-Peak Hours** - Less server load
2. **Stable Network Connection** - Reduces retry overhead
3. **Local Channels DVR Server** - Faster than remote access
4. **Batch Similar Lineups** - Group by provider/region

### Resource Usage

**Disk Space:**
- ~1MB per 100 stations (JSON storage)
- Temporary files cleaned up automatically
- Peak usage: ~2x final output size

**Memory:**
- Minimal memory usage (streaming processing)
- Large datasets may require more memory for deduplication

**Network:**
- 1-2 API calls per lineup ID
- Additional API calls for enhancement (as needed)
- Bandwidth: ~10KB per station

## Best Practices

### Before Running

1. **✅ Validate Lineup IDs** - Test a few manually first
2. **✅ Check Server Health** - Ensure Channels DVR is responsive
3. **✅ Plan Timing** - Run during low-usage periods
4. **✅ Backup Existing Data** - If integrating with existing base cache

### During Processing

1. **✅ Monitor Progress** - Watch for consistent failures
2. **✅ Check Output Directory** - Verify files are being created
3. **✅ Network Stability** - Ensure stable connection
4. **✅ Don't Interrupt** - Let process complete naturally

### After Completion

1. **✅ Review Statistics** - Check success/failure rates
2. **✅ Validate Output** - Verify JSON integrity
3. **✅ Test Integration** - Small test before full merge
4. **✅ Document Changes** - Record what was processed

## Advanced Usage

### Custom Server Configuration

```bash
# Multiple server fallback
./manual_lineup_processor.sh --server http://primary:8089 lineups.txt || \
./manual_lineup_processor.sh --server http://backup:8089 lineups.txt
```

### Batch Processing

```bash
# Process multiple lineup sets
for category in streaming satellite cable; do
    ./manual_lineup_processor.sh \
        --output "output_${category}" \
        "lineups_${category}.txt"
done
```

### Integration Scripting

```bash
#!/bin/bash
# Automated integration script
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Process lineups
./manual_lineup_processor.sh special_lineups.txt

# Auto-integrate if successful
if [ $? -eq 0 ]; then
    # Backup and merge automatically
    cp all_stations_base.json all_stations_base.json.backup_${TIMESTAMP}
    
    jq -s '.[0] + .[1] | unique_by(.stationId) | sort_by(.name // "")' \
        all_stations_base.json manual_lineup_output/all_stations_manual.json \
        > all_stations_base_new.json
    
    mv all_stations_base_new.json all_stations_base.json
    
    # Regenerate manifest
    ./create_base_cache_manifest.sh -v -f
    
    echo "✅ Integration complete"
else
    echo "❌ Processing failed, integration skipped"
fi
```

## Version History

- **v1.0.0** - Initial release with basic lineup processing
- **v1.1.0** - Added comprehensive enhancement loop
- **v1.2.0** - Improved error handling and resilience
- **v1.3.0** - Enhanced state file generation and integration support

## Related Documentation

- [Base Cache Update Process](BASE_CACHE_UPDATE_README.md) - Complete base cache merge workflow
- [Base Cache Manifest Creator](create_base_cache_manifest-readme.md) - Manifest generation tool
- [Global Station Search](README.md) - Main script documentation

---

**Script Location:** `manual_lineup_processor.sh`  
**Maintainer:** Global Station Search Project  
**Last Updated:** 2024-12-31  
**Document Version:** 1.3.0