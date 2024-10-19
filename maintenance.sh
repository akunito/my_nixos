#!/usr/bin/env bash

# Set the number of generations to keep
SystemGenerationsToKeep=8
HomeManagerGenerationsToKeep=8

# Clean up old system generations
echo "=============================================================================="
echo "===================== Listing System Generations ============================="
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
echo "===================== Keeping only last $SystemGenerationsToKeep system generations =============================="
sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +$SystemGenerationsToKeep
echo "===================== Collecting garbage ====================================="
sudo nix-collect-garbage

# Clean up Home Manager generations
echo "=============================================================================="
echo "===================== Listing Home Manager Generations ======================="

# Fetch all generations with 'home-manager generations' command
home-manager generations
gen_list=$(home-manager generations)

# Fetch the currently active generation (marked as 'current' in nix-env)
current_gen=$(nix-env --list-generations | grep '(current)' | awk '{print $1}')

# Extract the IDs from the home-manager generations output (assuming the format is consistent)
# Using 'awk' to grab the ID after the word 'id' in each line
ids=($(echo "$gen_list" | awk -F'id ' '{print $2}' | awk '{print $1}'))

# Reverse the IDs to have the most recent ones first (bigger number = newer)
ids=($(echo "${ids[@]}" | tr ' ' '\n' | sort -nr))

# Calculate the total number of generations
total_gen=${#ids[@]}

# Check if there are more than $HomeManagerGenerationsToKeep generations to delete
if [ $total_gen -le $HomeManagerGenerationsToKeep ]; then
    echo "There are only $total_gen generations. No need to delete."
    exit 0
fi

echo "ids found are: ${ids[@]}"
echo "current generation is: $current_gen"

echo "===================== Calculate HM Gens to remove ============================"
# Calculate how many generations we need to delete (total_gen - HomeManagerGenerationsToKeep)
delete_count=$((total_gen - HomeManagerGenerationsToKeep))

# Get the list of IDs to delete (all except the last $HomeManagerGenerationsToKeep)
delete_ids=(${ids[@]:$HomeManagerGenerationsToKeep})

# Exclude the current generation from the delete list
delete_ids=(${delete_ids[@]/$current_gen/})

# Print the IDs to be deleted
echo "Deleting generations: ${delete_ids[@]}"

# Delete the old generations using nix-env, if there are any to delete
if [ ${#delete_ids[@]} -gt 0 ]; then
    nix-env --delete-generations "${delete_ids[@]}"
else
    echo "No generations to delete."
fi

# Optional: Run garbage collection to free space
nix-collect-garbage
