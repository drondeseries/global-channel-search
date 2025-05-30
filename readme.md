# Channels DVR Global Station Search

A comprehensive television station search tool that integrates with Channels DVR API to provide enhanced station discovery capabilities.

## Features

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
