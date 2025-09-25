#!/bin/bash

# Telegram notification script for DAppNode releases
# This script sends a notification to a Telegram chat when a new release is created

set -e

# Function to display usage
show_usage() {
    echo "Usage: $0 <release_version> <release_url>"
    echo "Example: $0 v0.2.51 https://github.com/dappnode/DAppNode/releases/tag/v0.2.51"
    exit 1
}

# Function to send telegram message
send_telegram_message() {
    local message="$1"
    local bot_token="$TELEGRAM_BOT_TOKEN"
    local chat_id="$TELEGRAM_CHAT_ID"
    
    if [ -z "$bot_token" ]; then
        echo "Error: TELEGRAM_BOT_TOKEN environment variable is not set"
        exit 1
    fi
    
    if [ -z "$chat_id" ]; then
        echo "Error: TELEGRAM_CHAT_ID environment variable is not set"
        exit 1
    fi
    
    # Send the message using curl
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"text\": \"${message}\",
            \"parse_mode\": \"Markdown\",
            \"disable_web_page_preview\": false
        }" > /dev/null
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Telegram notification sent successfully"
    else
        echo "Failed to send Telegram notification (exit code: $exit_code)"
        exit 1
    fi
}

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    echo "Error: Missing required arguments"
    show_usage
fi

RELEASE_VERSION="$1"
RELEASE_URL="$2"

# Validate release version format
if [[ ! $RELEASE_VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Release version must be in format vX.Y.Z (e.g., v0.2.51)"
    exit 1
fi

# Validate release URL
if [[ ! $RELEASE_URL =~ ^https://github\.com/dappnode/DAppNode/releases/tag/.+ ]]; then
    echo "Error: Invalid release URL format"
    exit 1
fi

# Create the message
MESSAGE="🚀 *New DAppNode Release Available!*

📦 **Version:** \`${RELEASE_VERSION}\`
🔗 **Download:** [${RELEASE_VERSION}](${RELEASE_URL})

The latest DAppNode release is now available with updated core packages and improvements. Visit the release page to download the installation ISOs and view the complete changelog.

#DAppNode #Release #Decentralized"

# Send the notification
echo "Sending Telegram notification for release ${RELEASE_VERSION}..."
send_telegram_message "$MESSAGE"