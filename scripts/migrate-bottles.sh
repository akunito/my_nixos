#!/usr/bin/env bash

# Migration script for Bottles data from Flatpak to Native
# Source: ~/.var/app/com.usebottles.bottles/data/bottles
# Dest: ~/.local/share/bottles/bottles

SOURCE_DIR="$HOME/.var/app/com.usebottles.bottles/data/bottles"
DEST_DIR="$HOME/.local/share/bottles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Starting Bottles Migration..."

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Flatpak Bottles data directory not found at $SOURCE_DIR"
    exit 1
fi

echo "Source found: $SOURCE_DIR"

# Create destination if it doesn't exist
mkdir -p "$DEST_DIR"

# Backup existing native configuration if valid
if [ -d "$DEST_DIR/bottles" ] && [ "$(ls -A $DEST_DIR/bottles)" ]; then
    echo "Existing native bottles found. Backing up to ${DEST_DIR}_backup_${TIMESTAMP}..."
    cp -r "$DEST_DIR" "${DEST_DIR}_backup_${TIMESTAMP}"
fi

echo "Copying data..."

# Copy bottles (prefixes)
# Note: Flatpak structure might be slightly different.
# Check if "bottles" exists inside source
if [ -d "$SOURCE_DIR/bottles" ]; then
    echo "Copying bottles..."
    rsync -av --progress "$SOURCE_DIR/bottles/" "$DEST_DIR/bottles/"
fi

# Copy other config files if they exist and are newer
CONF_FILES=("temp" "templates" "runners" "dxvk" "vkd3d" "nvapi" "latencyflex" "data.yml" "library.yml")

for file in "${CONF_FILES[@]}"; do
    if [ -e "$SOURCE_DIR/$file" ]; then
        echo "Copying $file..."
        rsync -av --update "$SOURCE_DIR/$file" "$DEST_DIR/"
    fi
done

echo "Migration data copy complete."
echo "Please verify your bottles in the native application."
echo "Note: Some runners might need to be re-downloaded if paths are hardcoded, but data/prefixes should be intact."
