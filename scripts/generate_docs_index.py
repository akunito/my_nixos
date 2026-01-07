#!/usr/bin/env python3
"""
Hierarchical Documentation Index Generator for NixOS Flake Configuration

This script scans the project structure and generates docs/00_INDEX.md to optimize
AI context retrieval by providing a hierarchical navigation tree.

CRITICAL: This file is auto-generated. Do not edit manually.
Regenerate with: python3 scripts/generate_docs_index.py
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Directories to strictly ignore
IGNORE_DIRS = {'.git', 'node_modules', 'result'}

# Directories to scan
SCAN_DIRS = ['docs', 'system', 'user', 'profiles', 'lib']

# Project root (assume script is in scripts/ subdirectory)
PROJECT_ROOT = Path(__file__).parent.parent


def should_ignore_path(path: Path) -> bool:
    """Check if a path should be ignored."""
    parts = path.parts
    return any(part in IGNORE_DIRS for part in parts)


def extract_first_comment_block(content: str) -> Optional[str]:
    """Extract the first comment block from a Nix file."""
    lines = content.split('\n')
    comments = []
    in_comment_block = False
    
    for line in lines:
        stripped = line.strip()
        # Skip empty lines and imports at the start
        if not stripped or stripped.startswith('imports'):
            continue
        
        # Check for comment
        if stripped.startswith('#'):
            comment = stripped[1:].strip()
            if comment:  # Non-empty comment
                comments.append(comment)
                in_comment_block = True
        elif in_comment_block and not stripped.startswith('#'):
            # End of comment block
            break
    
    if comments:
        # Return first meaningful comment (skip pure separators)
        for comment in comments:
            if len(comment) > 10 and not comment.startswith('---'):
                return comment
        return comments[0] if comments else None
    return None


def extract_lib_mkif_conditions(content: str) -> List[str]:
    """
    Robustly extract lib.mkIf conditions using a parenthesis counter.
    Handles nested parentheses: lib.mkIf (a && (b || c))
    """
    conditions = []
    search_str = "lib.mkIf"
    start_idx = 0
    
    while True:
        idx = content.find(search_str, start_idx)
        if idx == -1:
            break
            
        # Move past "lib.mkIf" to find the opening parenthesis
        open_paren = content.find('(', idx)
        if open_paren == -1:
            start_idx = idx + len(search_str)
            continue
            
        # Extract balanced parenthesis content
        count = 1
        current_pos = open_paren + 1
        condition_chars = []
        
        while count > 0 and current_pos < len(content):
            char = content[current_pos]
            if char == '(':
                count += 1
            elif char == ')':
                count -= 1
            
            if count > 0:
                condition_chars.append(char)
            current_pos += 1
            
        if count == 0:
            raw_cond = "".join(condition_chars).strip()
            # Clean up whitespace (convert newlines/tabs to single spaces)
            clean_cond = " ".join(raw_cond.split())
            if clean_cond and clean_cond not in conditions:
                conditions.append(clean_cond)
        
        start_idx = current_pos

    return conditions


def parse_nix_file(file_path: Path) -> Tuple[Optional[str], List[str]]:
    """Parse a Nix file to extract module purpose and lib.mkIf conditions."""
    try:
        content = file_path.read_text(encoding='utf-8')
        purpose = extract_first_comment_block(content)
        conditions = extract_lib_mkif_conditions(content)
        return purpose, conditions
    except Exception as e:
        print(f"Warning: Could not parse {file_path}: {e}", file=sys.stderr)
        return None, []


def extract_markdown_summary(file_path: Path) -> Optional[str]:
    """Extract the first non-header line as summary, skipping YAML frontmatter."""
    try:
        content = file_path.read_text(encoding='utf-8')
        lines = content.split('\n')
        
        in_frontmatter = False
        # Check if file starts with YAML frontmatter
        if lines and lines[0].strip() == '---':
            in_frontmatter = True
            lines = lines[1:]  # Skip the opening marker

        for line in lines:
            stripped = line.strip()
            
            # Handle closing frontmatter marker
            if in_frontmatter:
                if stripped == '---':
                    in_frontmatter = False
                continue
            
            # Skip headers, empty lines, and code blocks
            if (stripped and 
                not stripped.startswith('#') and 
                not stripped.startswith('---') and
                not stripped.startswith('```') and
                not stripped.startswith('<!-') and
                len(stripped) > 10):  # Meaningful content
                # Truncate if too long
                if len(stripped) > 200:
                    stripped = stripped[:197] + '...'
                return stripped
        
        return None
    except Exception as e:
        print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        return None


def detect_doc_structure(file_path: Path) -> Tuple[int, str]:
    """
    Detect documentation structure level (3 or 4).
    Returns (level, category).
    """
    parts = file_path.parts
    # Find docs/ in path
    try:
        docs_idx = parts.index('docs')
        relative_parts = parts[docs_idx + 1:]
        
        if len(relative_parts) == 1:
            # docs/file.md - Level 2
            return 2, 'root'
        elif len(relative_parts) == 2:
            # docs/category/file.md - Level 3
            return 3, relative_parts[0]
        elif len(relative_parts) >= 3:
            # docs/category/subcategory/file.md - Level 4
            return 4, f"{relative_parts[0]}/{relative_parts[1]}"
    except ValueError:
        pass
    
    return 0, 'unknown'


def scan_directory(directory: Path, base_path: Path = None) -> Dict:
    """Recursively scan a directory and collect file information."""
    if base_path is None:
        base_path = directory
    
    results = {
        'nix_files': [],
        'markdown_files': [],
        'directories': {}
    }
    
    if not directory.exists():
        return results
    
    try:
        for item in directory.iterdir():
            if should_ignore_path(item):
                continue
            
            if item.is_dir():
                sub_results = scan_directory(item, base_path)
                # Merge results
                results['nix_files'].extend(sub_results['nix_files'])
                results['markdown_files'].extend(sub_results['markdown_files'])
                results['directories'].update(sub_results['directories'])
            elif item.is_file():
                rel_path = item.relative_to(PROJECT_ROOT)
                
                if item.suffix == '.nix':
                    purpose, conditions = parse_nix_file(item)
                    results['nix_files'].append({
                        'path': rel_path,
                        'purpose': purpose,
                        'conditions': conditions
                    })
                elif item.suffix == '.md' and 'docs' in item.parts:
                    summary = extract_markdown_summary(item)
                    level, category = detect_doc_structure(item)
                    results['markdown_files'].append({
                        'path': rel_path,
                        'summary': summary,
                        'level': level,
                        'category': category
                    })
    except PermissionError:
        print(f"Warning: Permission denied for {directory}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Error scanning {directory}: {e}", file=sys.stderr)
    
    return results


def format_conditions(conditions: List[str]) -> str:
    """Format lib.mkIf conditions for display."""
    if not conditions:
        return ""
    
    if len(conditions) == 1:
        return f" *Enabled when:* `{conditions[0]}`"
    else:
        formatted = "\n   - " + "\n   - ".join(f"`{c}`" for c in conditions)
        return f" *Enabled when:*{formatted}"


def generate_index(data: Dict) -> str:
    """Generate the index Markdown content."""
    lines = []
    
    # Header
    lines.append("⚠️ **AUTO-GENERATED**: Do not edit manually. Regenerate with `python3 scripts/generate_docs_index.py`")
    lines.append("")
    lines.append("# Documentation Index")
    lines.append("")
    lines.append("This index provides a hierarchical navigation tree for AI context retrieval.")
    lines.append("Before answering architectural questions, read this index to identify relevant branches.")
    lines.append("")
    
    # Flake Architecture
    lines.append("## Flake Architecture")
    lines.append("")
    flake_files = [
        ('flake.nix', 'Main flake entry point defining inputs and outputs'),
        ('lib/flake-base.nix', 'Base flake module shared by all profiles'),
        ('lib/defaults.nix', 'Default system and user settings'),
    ]
    
    # Find profile flakes
    for nix_file in data['nix_files']:
        path_str = str(nix_file['path'])
        if path_str.startswith('flake.') and path_str.endswith('.nix'):
            flake_files.append((path_str, 'Profile-specific flake configuration'))
    
    for file_path, desc in flake_files:
        lines.append(f"- **{file_path}**: {desc}")
    lines.append("")
    
    # Profiles
    lines.append("## Profiles")
    lines.append("")
    profile_files = [f for f in data['nix_files'] if 'profiles' in f['path'].parts and f['path'].name.endswith('-config.nix')]
    profile_files.sort(key=lambda x: str(x['path']))
    
    for profile_file in profile_files:
        path_str = str(profile_file['path'])
        purpose = profile_file['purpose'] or "Profile configuration"
        conditions = format_conditions(profile_file['conditions'])
        lines.append(f"- **{path_str}**: {purpose}{conditions}")
    lines.append("")
    
    # System Modules
    lines.append("## System Modules")
    lines.append("")
    system_files = [f for f in data['nix_files'] if 'system' in f['path'].parts and 'profiles' not in f['path'].parts]
    system_files.sort(key=lambda x: str(x['path']))
    
    # Group by category
    system_by_category = {}
    for sys_file in system_files:
        parts = sys_file['path'].parts
        try:
            sys_idx = parts.index('system')
            if sys_idx + 1 < len(parts):
                category = parts[sys_idx + 1]
            else:
                category = 'root'
        except ValueError:
            category = 'root'
        
        if category not in system_by_category:
            system_by_category[category] = []
        system_by_category[category].append(sys_file)
    
    for category in sorted(system_by_category.keys()):
        if category != 'root':
            lines.append(f"### {category.title()}")
            lines.append("")
        for sys_file in system_by_category[category]:
            path_str = str(sys_file['path'])
            purpose = sys_file['purpose'] or f"System module: {sys_file['path'].name}"
            conditions = format_conditions(sys_file['conditions'])
            lines.append(f"- **{path_str}**: {purpose}{conditions}")
        lines.append("")
    
    # User Modules
    lines.append("## User Modules")
    lines.append("")
    user_files = [f for f in data['nix_files'] if 'user' in f['path'].parts and 'profiles' not in f['path'].parts]
    user_files.sort(key=lambda x: str(x['path']))
    
    # Group by category
    user_by_category = {}
    for usr_file in user_files:
        parts = usr_file['path'].parts
        try:
            usr_idx = parts.index('user')
            if usr_idx + 1 < len(parts):
                category = parts[usr_idx + 1]
            else:
                category = 'root'
        except ValueError:
            category = 'root'
        
        if category not in user_by_category:
            user_by_category[category] = []
        user_by_category[category].append(usr_file)
    
    for category in sorted(user_by_category.keys()):
        if category != 'root':
            lines.append(f"### {category.title()}")
            lines.append("")
        for usr_file in user_by_category[category]:
            path_str = str(usr_file['path'])
            purpose = usr_file['purpose'] or f"User module: {usr_file['path'].name}"
            conditions = format_conditions(usr_file['conditions'])
            lines.append(f"- **{path_str}**: {purpose}{conditions}")
        lines.append("")
    
    # Documentation
    lines.append("## Documentation")
    lines.append("")
    doc_files = data['markdown_files']
    doc_files.sort(key=lambda x: str(x['path']))
    
    # Group by level and category
    docs_by_category = {}
    for doc_file in doc_files:
        category = doc_file['category']
        if category not in docs_by_category:
            docs_by_category[category] = []
        docs_by_category[category].append(doc_file)
    
    for category in sorted(docs_by_category.keys()):
        if category != 'root' and category != 'unknown':
            lines.append(f"### {category.replace('/', ' / ').title()}")
            lines.append("")
        for doc_file in docs_by_category[category]:
            path_str = str(doc_file['path'])
            summary = doc_file['summary'] or "Documentation file"
            lines.append(f"- **{path_str}**: {summary}")
        lines.append("")
    
    return '\n'.join(lines)


def main():
    """Main entry point."""
    # Check Python version
    if sys.version_info < (3, 6):
        print("Error: Python 3.6 or higher is required", file=sys.stderr)
        sys.exit(1)
    
    print("Scanning project structure...")
    
    # Scan all directories
    all_data = {
        'nix_files': [],
        'markdown_files': [],
        'directories': {}
    }
    
    for scan_dir in SCAN_DIRS:
        dir_path = PROJECT_ROOT / scan_dir
        if dir_path.exists():
            print(f"  Scanning {scan_dir}/...")
            results = scan_directory(dir_path)
            all_data['nix_files'].extend(results['nix_files'])
            all_data['markdown_files'].extend(results['markdown_files'])
        else:
            print(f"  Warning: {scan_dir}/ does not exist, skipping...", file=sys.stderr)
    
    # Also scan root for flake files
    print("  Scanning root for flake files...")
    for item in PROJECT_ROOT.iterdir():
        if item.is_file() and item.suffix == '.nix' and 'flake' in item.name.lower():
            purpose, conditions = parse_nix_file(item)
            all_data['nix_files'].append({
                'path': item.relative_to(PROJECT_ROOT),
                'purpose': purpose,
                'conditions': conditions
            })
    
    print(f"Found {len(all_data['nix_files'])} Nix files and {len(all_data['markdown_files'])} Markdown files")
    
    # Generate index
    print("Generating index...")
    index_content = generate_index(all_data)
    
    # Write index file
    index_path = PROJECT_ROOT / 'docs' / '00_INDEX.md'
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(index_content, encoding='utf-8')
    
    print(f"Index generated successfully at {index_path}")
    print(f"  - {len(all_data['nix_files'])} Nix modules indexed")
    print(f"  - {len(all_data['markdown_files'])} documentation files indexed")


if __name__ == '__main__':
    main()

