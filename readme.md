# Channels DVR Global Station Search

A comprehensive television station search tool that integrates with Channels DVR API to provide enhanced station discovery capabilities.

## Features

- **New in 1.1.0-RC - Channels DVR server is now optional, as the script is distributed withe a comprehensive local base cache including all major television markets in the US, Canada, and the UK.
- **User Cache** - Users can add to the base cache incrementally by adding country and postal codes using the Televeion Market Management function in the Main Menu.
- **Script is now Instantly Usable** - There is no longer a need to build a local cache prior to using the script.

- **New in 1.0-RC - Dispatcharr Integration** - automatically find channels in dispatcharr missing stationID and populate with an interactive channel matching function

- **Station Search**: Search by name, call sign with partial/exact matching
- **Resolution Filtering**: Filter results by SDTV, HDTV, UHDTV
- **Logo Display**: Visual station logos with caching
- **Market Management**: Add/remove television markets
- **Local Caching**: Efficient data caching making searching more robust
- **Direct API search**: Directly search API without locally caching, though search and results may be less useful
- **Settings Management**: Comprehensive configuration options

## Requirements

- **Required**: `jq`, `curl`
- **Optional**: `viu` (for logo previews), `bc` (for progress calculations)
- **System**: Bash 4.0+, Channels DVR server

## Installation

1. Clone the repository:
```bash
git clone https://github.com/egyptiangio/channelsdvr-global-search
cd channelsdvr-global-search
```
2. Make the script executable
```
chmod +x globalstationsearch.sh
```
4. Run
```
./globalstationsearch.sh
```
5. Follow Prompts in Script
