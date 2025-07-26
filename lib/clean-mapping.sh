#!/bin/bash
# Clean tool mapping by removing self-mappings and filtering packages
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Configuration
TEMP_DIR="/tmp/aurgen-mapping"
CLEAN_MAPPING_FILE="$TEMP_DIR/clean-mapping.txt"
BACKUP_FILE="$TEMP_DIR/tool-mapping.sh.backup.clean"

# Clean the tool mapping
clean_tool_mapping() {
    local tool_mapping_file
    tool_mapping_file="$(dirname "${BASH_SOURCE[0]}")/tool-mapping.sh"
    
    echo "Cleaning tool mapping..."
    
    # Create backup
    cp "$tool_mapping_file" "$BACKUP_FILE"
    echo "Backup created: $BACKUP_FILE"
    
    # Extract mappings and filter
    local clean_mappings=()
    
    while IFS= read -r line; do
        # Extract tool and package using grep and sed
        if echo "$line" | grep -q '^[[:space:]]*[a-zA-Z0-9_-]\+)[[:space:]]*echo[[:space:]]*"[^"]*"[[:space:]]*;;'; then
            local tool
            tool=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\1/p')
            local package
            package=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]\+\))[[:space:]]*echo[[:space:]]*"\([^"]*\)"[[:space:]]*;;/\2/p')
            
            if [[ -n "$tool" && -n "$package" ]]; then
                # Skip self-mappings (tool name = package name)
                if [[ "$tool" != "$package" ]]; then
                    # Skip Android-specific packages
                    if [[ ! "$tool" =~ ^android- ]] && [[ ! "$package" =~ ^android- ]]; then
                        # Skip some other unnecessary packages
                        if [[ ! "$tool" =~ ^(alsa-lib|boca|boca-git|chrpath|electron30|electron35|epics-base|expat|faac|faad2|fluxbox|freetype2|fuse2|gcc-libs|gendesk|glew)$ ]]; then
                            clean_mappings+=("$tool:$package")
                        fi
                    fi
                fi
            fi
        fi
    done < "$tool_mapping_file"
    
    # Sort mappings by tool name
    mapfile -t clean_mappings < <(printf '%s\n' "${clean_mappings[@]}" | sort)
    
    # Write clean mappings to file
    printf '%s\n' "${clean_mappings[@]}" > "$CLEAN_MAPPING_FILE"
    
    # Generate new tool-mapping.sh
    cat > "$tool_mapping_file" << 'EOF'
#!/bin/bash
# Tool to package mapping for Arch Linux
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of aurgen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

# Map tool names to their containing packages
# Usage: map_tool_to_package <tool_name>
# Returns: package name that contains the tool
map_tool_to_package() {
    local tool="$1"
    
    # Tool to package mapping for Arch Linux
    case "$tool" in
EOF
    
    # Add clean mappings
    for mapping in "${clean_mappings[@]}"; do
        local tool="${mapping%:*}"
        local package="${mapping#*:}"
        echo "        $tool) echo \"$package\" ;;" >> "$tool_mapping_file"
    done
    
    # Add default case
    cat >> "$tool_mapping_file" << 'EOF'
        
        # Default: return the tool name as-is if no mapping exists
        *) echo "$tool" ;;
    esac
}
EOF
    
    # Show statistics
    local original_count
    original_count=$(grep -c '^[[:space:]]*[a-zA-Z0-9_-]\+)[[:space:]]*echo[[:space:]]*"[^"]*"[[:space:]]*;;' "$BACKUP_FILE" || echo "0")
    local clean_count=${#clean_mappings[@]}
    local removed_count=$((original_count - clean_count))
    
    echo "Cleaning statistics:"
    echo "  Original mappings: $original_count"
    echo "  Clean mappings: $clean_count"
    echo "  Removed mappings: $removed_count"
    echo
    echo "Clean mapping saved to: $CLEAN_MAPPING_FILE"
    echo "Backup of original: $BACKUP_FILE"
    echo
    echo "Tool mapping has been cleaned and updated."
}

# Main function
clean_mapping() {
    echo "Cleaning tool mapping..."
    clean_tool_mapping
    echo "Done! Tool mapping has been cleaned."
} 