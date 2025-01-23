#!/bin/bash

# Check if a post name was provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide a post name"
    echo "Usage: ./create_post.sh <name_of_post> [blog_category]"
    echo "blog_category is optional and defaults to 'blog'"
    exit 1
fi

# Check if more than 2 arguments were provided
if [ $# -gt 2 ]; then
    echo "Error: Too many arguments"
    echo "Usage: ./create_post.sh name_of_post [blog_category]"
    exit 1
fi

# Set category to second argument or default to "blog"
category="${2:-blog}"

# Get current date in YYYY-MM-DD format
current_date=$(date +%Y-%m-%d)

# Create post name by combining date and provided name
post_name="${current_date}-${1}"
echo "Post name: ${post_name}"

# Get the absolute path of the script directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
echo "Script directory: ${script_dir}"

# Get the project root directory (parent of script directory)
project_root="$(dirname "$script_dir")"
echo "Project root: ${project_root}"

# Set posts directory path
posts_dir="${project_root}/_posts"
echo "Posts directory: ${posts_dir}"

# Check if _posts directory exists, if not create it
if [ ! -d "$posts_dir" ]; then
    mkdir -p "$posts_dir"
fi

# Create the post file
post_file="${posts_dir}/${post_name}.markdown"
if [ -f "$post_file" ]; then
    echo "Error: Post file already exists: ${post_file}"
    exit 1
fi

# Create file with basic Jekyll front matter
cat > "$post_file" << EOF
---
layout: post
title: "${1//_/ }"
date: "$(date '+%Y-%m-%d %H:%M:%S %z')"
categories: "${category}"
---

EOF

echo "Created new post: ${post_file}"