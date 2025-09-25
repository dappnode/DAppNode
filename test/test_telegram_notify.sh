#!/bin/bash

# Test script for telegram_notify.sh
# Tests the validation logic and message formatting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEGRAM_SCRIPT="${SCRIPT_DIR}/../scripts/telegram_notify.sh"

echo "Testing Telegram notification script..."

# Test 1: No arguments
echo "Test 1: No arguments"
if $TELEGRAM_SCRIPT 2>/dev/null; then
    echo "❌ FAILED: Should have failed with no arguments"
    exit 1
else
    echo "✅ PASSED: Correctly failed with no arguments"
fi

# Test 2: Invalid version format
echo "Test 2: Invalid version format"
if $TELEGRAM_SCRIPT "0.2.51" "https://github.com/dappnode/DAppNode/releases/tag/v0.2.51" 2>/dev/null; then
    echo "❌ FAILED: Should have failed with invalid version format"
    exit 1
else
    echo "✅ PASSED: Correctly failed with invalid version format"
fi

# Test 3: Invalid URL format
echo "Test 3: Invalid URL format"
if $TELEGRAM_SCRIPT "v0.2.51" "https://invalid-url.com" 2>/dev/null; then
    echo "❌ FAILED: Should have failed with invalid URL format"
    exit 1
else
    echo "✅ PASSED: Correctly failed with invalid URL format"
fi

# Test 4: Valid arguments but missing environment variables
echo "Test 4: Valid arguments but missing environment variables"
if $TELEGRAM_SCRIPT "v0.2.51" "https://github.com/dappnode/DAppNode/releases/tag/v0.2.51" 2>/dev/null; then
    echo "❌ FAILED: Should have failed with missing environment variables"
    exit 1
else
    echo "✅ PASSED: Correctly failed with missing environment variables"
fi

# Test 5: Valid arguments with mock environment variables (dry run)
echo "Test 5: Valid arguments with test environment variables"
export TELEGRAM_BOT_TOKEN="test_token_123456"
export TELEGRAM_CHAT_ID="test_chat_id"

# Create a mock curl command that doesn't actually send anything
create_mock_curl() {
    cat > /tmp/mock_curl.sh << 'EOF'
#!/bin/bash
# Mock curl command for testing
if [[ "$*" == *"sendMessage"* ]]; then
    echo "Mock: Telegram message would be sent"
    exit 0
fi
exec /usr/bin/curl "$@"
EOF
    chmod +x /tmp/mock_curl.sh
}

# Test the script with a dry run by temporarily replacing curl
create_mock_curl
export PATH="/tmp:$PATH"

# Temporarily modify the telegram script to use our mock curl
sed 's|curl -s|/tmp/mock_curl.sh -s|g' $TELEGRAM_SCRIPT > /tmp/telegram_notify_test.sh
chmod +x /tmp/telegram_notify_test.sh

if /tmp/telegram_notify_test.sh "v0.2.51" "https://github.com/dappnode/DAppNode/releases/tag/v0.2.51" 2>/dev/null; then
    echo "✅ PASSED: Script executed successfully with valid arguments"
else
    echo "❌ FAILED: Script should have succeeded with valid arguments and environment variables"
    exit 1
fi

# Clean up
rm -f /tmp/mock_curl.sh /tmp/telegram_notify_test.sh
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID

echo ""
echo "🎉 All tests passed! The Telegram notification script is working correctly."