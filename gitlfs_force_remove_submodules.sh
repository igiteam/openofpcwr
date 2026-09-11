#!/bin/bash

# Script: git-remove-submodules.sh
# Description: Automatically identify and remove all Git submodules from a repository
# Usage: ./git-remove-submodules.sh [dry-run]

set -e

DRY_RUN=false
if [ "$1" = "dry-run" ] || [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ==="
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not a git repository"
    exit 1
fi

# Check if .gitmodules file exists
if [ ! -f .gitmodules ]; then
    echo "No .gitmodules file found. No submodules to remove."
    exit 0
fi

# Function to remove a submodule
remove_submodule() {
    local submodule_path="$1"
    local submodule_name="$2"
    
    echo "Removing submodule: $submodule_name ($submodule_path)"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would execute:"
        echo "    git submodule deinit -f \"$submodule_path\""
        echo "    rm -rf .git/modules/\"$submodule_path\""
        echo "    git rm -f \"$submodule_path\""
        return 0
    fi
    
    # Remove the submodule entry from .git/config
    echo "  Deinitializing submodule..."
    git submodule deinit -f "$submodule_path"
    
    # Remove the submodule directory from the superproject's .git/modules directory
    echo "  Removing from .git/modules..."
    rm -rf ".git/modules/$submodule_path"
    
    # Remove the entry in .gitmodules and remove the submodule directory
    echo "  Removing from git index and working directory..."
    git rm -f "$submodule_path"
    
    echo "  ✓ Successfully removed submodule: $submodule_name"
}

# Function to get submodule names and paths
get_submodules() {
    # Extract submodule paths from .gitmodules
    grep -E '^\s*path\s*=' .gitmodules | sed 's/^.*=\s*//' | tr -d ' '
}

# Function to get submodule name for a given path
get_submodule_name() {
    local path="$1"
    # Find the section for this path and extract the name
    awk -v path="$path" '
    /^\[submodule/ { 
        submodule_name = $2
        gsub(/"/, "", submodule_name)
        found = 0
    }
    /^\s*path\s*=/ {
        current_path = $0
        gsub(/^.*=\s*/, "", current_path)
        gsub(/\s*$/, "", current_path)
        if (current_path == path) {
            print submodule_name
            exit
        }
    }
    ' .gitmodules
}

echo "=== Git Submodule Removal Script ==="
echo "Repository: $(pwd)"
echo

# Get list of submodule paths
submodule_paths=$(get_submodules)

if [ -z "$submodule_paths" ]; then
    echo "No submodules found in .gitmodules"
    exit 0
fi

echo "Found submodules:"
echo "$submodule_paths" | while read -r path; do
    name=$(get_submodule_name "$path")
    echo "  - $name: $path"
done
echo

# Confirm removal
if [ "$DRY_RUN" = false ]; then
    echo "WARNING: This will permanently remove all submodules from the repository."
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Remove each submodule
echo "$submodule_paths" | while read -r path; do
    if [ -n "$path" ]; then
        name=$(get_submodule_name "$path")
        remove_submodule "$path" "$name"
        echo
    fi
done

# Final steps
if [ "$DRY_RUN" = false ]; then
    echo "=== Final Steps ==="
    echo "1. Review the changes:"
    echo "   git status"
    echo
    echo "2. Commit the removal:"
    echo "   git commit -m \"Remove submodules\""
    echo
    echo "3. If you also want to remove the .gitmodules file (if all submodules are removed):"
    echo "   git rm .gitmodules"
    echo
    echo "Submodule removal completed!"
else
    echo "=== DRY RUN COMPLETED ==="
    echo "No changes were made to the repository."
fi