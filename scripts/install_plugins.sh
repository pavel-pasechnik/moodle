#!/bin/bash
set -Eeo pipefail
trap 'echo "❌ Error at line $LINENO: command [$BASH_COMMAND]"' ERR

# Determine plugin list path: prefer /var/www/html/scripts/plugins.list, fallback to /scripts/plugins.list
if [ -z "${PLUGIN_LIST:-}" ]; then
  if [ -f "/var/www/html/scripts/plugins.list" ]; then
    PLUGIN_LIST="/var/www/html/scripts/plugins.list"
  elif [ -f "/scripts/plugins.list" ]; then
    PLUGIN_LIST="/scripts/plugins.list"
  else
    echo "⚠️ Plugin list file not found (checked /var/www/html/scripts/plugins.list and /scripts/plugins.list)"
    exit 0
  fi
fi

echo "=== Installing Moodle plugins ==="

command -v curl >/dev/null 2>&1 || { echo "❌ curl is not available in the image"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "❌ unzip is not available in the image"; exit 1; }

while IFS= read -r repo || [[ -n "$repo" ]]; do
  [[ "$repo" =~ ^#.*$ || -z "$repo" ]] && continue
  repo_url=$(echo "$repo" | awk '{print $1}')
  echo "-----------------------------------------------"
  echo "🔧 Installing plugin from $repo_url ..."
  tmpdir=$(mktemp -d)

  # Transform release URL to archive URL
  archive_url="${repo_url/releases\/tag\//archive\/refs\/tags\/}.zip"

  # Download the zip archive
  curl -fsSL -o /tmp/plugin.zip "$archive_url" || { echo "❌ Failed to download $archive_url"; continue; }

  # Unzip the archive into tmpdir
  unzip -q /tmp/plugin.zip -d "$tmpdir"

  # Find version.php and derive plugin root directory
  version_file=$(find "$tmpdir" -type f -name version.php | head -n1)
  if [ -n "$version_file" ]; then
    plugin_dir=$(dirname "$version_file")
  else
    plugin_dir=""
  fi

  if [ -z "$plugin_dir" ]; then
    echo "⚠️ version.php not found in the archive — skipping."
    rm -rf "$tmpdir"
    rm -f /tmp/plugin.zip
    continue
  fi

  component=$(grep "\$plugin->component" "$plugin_dir/version.php" | sed -E "s/.*'([^']+)'.*/\1/" | head -n1)

  if [ -z "$component" ]; then
    echo "⚠️ Failed to determine plugin type (component is empty)"
    rm -rf "$tmpdir"
    rm -f /tmp/plugin.zip
    continue
  fi

  if [[ "$component" == mod_* ]]; then
      dest="/var/www/html/mod/${component#mod_}"
  elif [[ "$component" == local_* ]]; then
      dest="/var/www/html/local/${component#local_}"
  elif [[ "$component" == tool_* ]]; then
      dest="/var/www/html/admin/tool/${component#tool_}"
  elif [[ "$component" == block_* ]]; then
      dest="/var/www/html/blocks/${component#block_}"
  elif [[ "$component" == theme_* ]]; then
      dest="/var/www/html/theme/${component#theme_}"
  elif [[ "$component" == certificateelement_* ]]; then
      # Custom certificate element subplugins live under mod/customcert/element
      dest="/var/www/html/admin/tool/certificate/element/${component#certificateelement_}"
  else
      echo "⚠️ Не удалось определить тип плагина ($component)"
      rm -rf "$tmpdir"
      rm -f /tmp/plugin.zip
      continue
  fi

  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest" ]; then
    if mount | grep -q " $dest "; then
      echo "✅ Plugin at $dest already exists and is bind-mounted — skipping."
    else
      echo "ℹ️ Plugin directory $dest exists — leaving as-is."
    fi
  else
    mv "$plugin_dir" "$dest"
    echo "→ Installed $component to $dest"
  fi

  rm -rf "$tmpdir"
  rm -f /tmp/plugin.zip
done < "$PLUGIN_LIST"

echo "🧩 Handing over to Moodle for plugin installation..."
/usr/local/bin/php /var/www/html/admin/cli/purge_caches.php || echo "⚠️ Cache purge failed."

echo "-----------------------------------------------"
echo
echo "=== Plugins installation complete ==="


if [ $? -eq 0 ]; then
  echo "✅ All plugins processed successfully."
else
  echo "⚠️ Some plugins failed to install. Check logs above."
fi

echo "✅ Plugin installation script finished. Review logs above for errors."
