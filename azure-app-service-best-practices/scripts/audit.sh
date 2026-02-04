#!/bin/bash
# Azure App Service Best Practices Audit Script
# Usage: ./audit.sh <app-name> <resource-group>
#
# Audits an App Service configuration against best practices

set -e

APP_NAME="$1"
RESOURCE_GROUP="$2"

if [[ -z "$APP_NAME" || -z "$RESOURCE_GROUP" ]]; then
  echo "Usage: ./audit.sh <app-name> <resource-group>"
  exit 1
fi

echo "🔍 Auditing App Service: $APP_NAME"
echo "================================================"

PASSED=0
WARNINGS=0
FAILED=0

check() {
  local rule="$1"
  local status="$2"
  local message="$3"
  
  if [[ "$status" == "PASS" ]]; then
    echo "✅ [$rule] $message"
    ((PASSED++))
  elif [[ "$status" == "WARN" ]]; then
    echo "⚠️  [$rule] $message"
    ((WARNINGS++))
  else
    echo "❌ [$rule] $message"
    ((FAILED++))
  fi
}

# Get app configuration
CONFIG=$(az webapp config show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>/dev/null)
APP=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>/dev/null)

if [[ -z "$CONFIG" || -z "$APP" ]]; then
  echo "❌ Could not retrieve app configuration. Check app name and resource group."
  exit 1
fi

echo ""
echo "📋 SECURITY"
echo "--------------------------------------------"

# HTTPS Only
HTTPS_ONLY=$(echo "$APP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('httpsOnly', False))" 2>/dev/null)
if [[ "$HTTPS_ONLY" == "True" ]]; then
  check "security-https-only" "PASS" "HTTPS Only is enabled"
else
  check "security-https-only" "FAIL" "HTTPS Only is disabled - run: az webapp update --https-only true"
fi

# TLS Version
MIN_TLS=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('minTlsVersion', 'Unknown'))" 2>/dev/null)
if [[ "$MIN_TLS" == "1.2" || "$MIN_TLS" == "1.3" ]]; then
  check "security-min-tls" "PASS" "Minimum TLS version is $MIN_TLS"
else
  check "security-min-tls" "FAIL" "Minimum TLS is $MIN_TLS - should be 1.2+"
fi

# FTP State
FTPS_STATE=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ftpsState', 'Unknown'))" 2>/dev/null)
if [[ "$FTPS_STATE" == "Disabled" ]]; then
  check "security-disable-ftp" "PASS" "FTP is disabled"
elif [[ "$FTPS_STATE" == "FtpsOnly" ]]; then
  check "security-disable-ftp" "WARN" "FTPS only (consider disabling completely)"
else
  check "security-disable-ftp" "FAIL" "FTP is enabled - run: az webapp config set --ftps-state Disabled"
fi

# Managed Identity
IDENTITY=$(echo "$APP" | python3 -c "import sys,json; i=json.load(sys.stdin).get('identity'); print(i.get('type') if i else 'None')" 2>/dev/null)
if [[ "$IDENTITY" != "None" && -n "$IDENTITY" ]]; then
  check "security-managed-identity" "PASS" "Managed Identity is enabled ($IDENTITY)"
else
  check "security-managed-identity" "WARN" "Managed Identity not enabled"
fi

echo ""
echo "📋 RELIABILITY"
echo "--------------------------------------------"

# Always On
ALWAYS_ON=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('alwaysOn', False))" 2>/dev/null)
if [[ "$ALWAYS_ON" == "True" ]]; then
  check "reliability-always-on" "PASS" "Always On is enabled"
else
  check "reliability-always-on" "FAIL" "Always On is disabled - run: az webapp config set --always-on true"
fi

# Health Check
HEALTH_CHECK=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('healthCheckPath', ''))" 2>/dev/null)
if [[ -n "$HEALTH_CHECK" && "$HEALTH_CHECK" != "None" ]]; then
  check "reliability-health-check" "PASS" "Health check configured: $HEALTH_CHECK"
else
  check "reliability-health-check" "WARN" "No health check path configured"
fi

# Deployment Slots
SLOTS=$(az webapp deployment slot list --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [[ "$SLOTS" -gt 0 ]]; then
  check "reliability-deployment-slots" "PASS" "$SLOTS deployment slot(s) configured"
else
  check "reliability-deployment-slots" "WARN" "No deployment slots - consider adding staging slot"
fi

echo ""
echo "📋 PERFORMANCE"
echo "--------------------------------------------"

# HTTP/2
HTTP2=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('http20Enabled', False))" 2>/dev/null)
if [[ "$HTTP2" == "True" ]]; then
  check "perf-http2" "PASS" "HTTP/2 is enabled"
else
  check "perf-http2" "WARN" "HTTP/2 is disabled - run: az webapp config set --http20-enabled true"
fi

# ARR Affinity
ARR=$(echo "$APP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('clientAffinityEnabled', True))" 2>/dev/null)
if [[ "$ARR" == "False" ]]; then
  check "perf-arr-affinity" "PASS" "ARR affinity disabled (good for stateless apps)"
else
  check "perf-arr-affinity" "WARN" "ARR affinity enabled - disable for stateless apps"
fi

# Linux vs Windows
RUNTIME=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('linuxFxVersion', ''))" 2>/dev/null)
if [[ -n "$RUNTIME" && "$RUNTIME" != "None" ]]; then
  check "perf-linux-plans" "PASS" "Using Linux App Service plan"
else
  check "perf-linux-plans" "WARN" "Using Windows plan - Linux plans often have better performance"
fi

echo ""
echo "================================================"
echo "📊 SUMMARY"
echo "   ✅ Passed:   $PASSED"
echo "   ⚠️  Warnings: $WARNINGS"
echo "   ❌ Failed:   $FAILED"
echo "================================================"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
