#!/bin/bash
# Azure App Service Health Check Script
# Usage: ./health-check.sh <app-name> <resource-group>
#
# Checks app status, configuration, and recent logs

set -e

APP_NAME="$1"
RESOURCE_GROUP="$2"

if [[ -z "$APP_NAME" || -z "$RESOURCE_GROUP" ]]; then
  echo "Usage: ./health-check.sh <app-name> <resource-group>"
  exit 1
fi

echo "🔍 Health Check: $APP_NAME"
echo "================================================"

# 1. App State
echo ""
echo "📊 App State:"
STATE=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query state -o tsv 2>/dev/null || echo "Not Found")
echo "   Status: $STATE"

if [[ "$STATE" == "Not Found" ]]; then
  echo "   ❌ App not found. Check app name and resource group."
  exit 1
fi

# 2. URL Check
URL="https://${APP_NAME}.azurewebsites.net"
echo ""
echo "🌐 URL Check: $URL"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" --max-time 10 2>/dev/null || echo "timeout")
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "   ✅ HTTP $HTTP_STATUS - OK"
elif [[ "$HTTP_STATUS" == "timeout" ]]; then
  echo "   ⚠️  Request timed out"
else
  echo "   ⚠️  HTTP $HTTP_STATUS"
fi

# 3. Configuration
echo ""
echo "⚙️  Configuration:"
CONFIG=$(az webapp config show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "{runtime:linuxFxVersion,alwaysOn:alwaysOn,http20:http20Enabled}" -o json 2>/dev/null)
echo "$CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'   Runtime: {d.get(\"runtime\", \"N/A\")}'); print(f'   Always On: {d.get(\"alwaysOn\", False)}'); print(f'   HTTP/2: {d.get(\"http20\", False)}')" 2>/dev/null || echo "   Could not parse config"

# 4. App Service Plan
echo ""
echo "📦 App Service Plan:"
PLAN_INFO=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "appServicePlanId" -o tsv 2>/dev/null)
PLAN_NAME=$(echo "$PLAN_INFO" | rev | cut -d'/' -f1 | rev)
echo "   Plan: $PLAN_NAME"

# 5. Recent issues check
echo ""
echo "🔧 Quick Recommendations:"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "   • Check logs: az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
fi

CONFIG_JSON=$(az webapp config show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" -o json 2>/dev/null)
ALWAYS_ON=$(echo "$CONFIG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('alwaysOn', False))" 2>/dev/null || echo "False")

if [[ "$ALWAYS_ON" == "False" ]]; then
  echo "   • Consider enabling Always On to prevent cold starts"
fi

echo ""
echo "================================================"
echo "✅ Health check complete"
