# Audit Project Documentation

Audit existing documentation and migrate to standardized structure.

## Purpose

Use this skill to:
- **Audit** existing documentation across the project
- **Identify** docs in wrong locations (root, random subdirectories)
- **Migrate** docs to standardized `docs/` structure
- **Add frontmatter** to existing docs that lack it
- **Generate router/catalog** to include all documentation
- **Report** on documentation health and compliance

---

## Usage

```
/audit-project-docs <project-path>
```

**Options:**
- `--dry-run` - Show what would be done without making changes
- `--migrate` - Actually move files and make changes
- `--report-only` - Generate report without any changes

**Examples:**
```bash
# Audit only (safe, read-only)
/audit-project-docs ~/projects/jl-engine

# Dry run (show what would be migrated)
/audit-project-docs ~/projects/portfolio-cms --dry-run

# Migrate (make changes)
/audit-project-docs ~/projects/jl-engine --migrate
```

---

## Documentation Rules

### Allowed Files (No Migration Needed)
- ✅ **README.md** - Anywhere (explains directory contents)
- ✅ **LICENSE** - Root only (standard file)
- ✅ **CHANGELOG.md** - Root or docs/ (standard file)
- ✅ **CONTRIBUTING.md** - Root or docs/ (standard file)
- ✅ **CODE_OF_CONDUCT.md** - Root or docs/ (standard file)

### Must Be in docs/
- ❌ **ARCHITECTURE.md** - System design documentation
- ❌ **DEPLOYMENT.md** - Deployment procedures
- ❌ **API.md, API_GUIDE.md** - API documentation
- ❌ **TROUBLESHOOTING.md** - Troubleshooting guide
- ❌ **implementation-*.md** - Implementation notes/summaries
- ❌ **audit-*.md, report-*.md** - Audit reports and analyses
- ❌ **notes.md, summary.md** - General documentation
- ❌ **Any other .md files** - Project documentation

### Examples
```
✅ CORRECT:
  README.md                          # Project overview
  LICENSE                            # License file
  CHANGELOG.md                       # Version history (optional)
  CONTRIBUTING.md                    # Contribution guidelines (optional)
  src/README.md                      # Explains src/ structure
  lib/components/README.md           # Explains components
  docs/ARCHITECTURE.md               # System design
  docs/security/audit-2026-02-08.md  # Security audit

❌ WRONG:
  ARCHITECTURE.md                    # Should be docs/ARCHITECTURE.md
  src/design-notes.md                # Should be docs/DESIGN_DECISIONS.md
  implementation-summary.md          # Should be docs/IMPLEMENTATION.md
  audit-report.md                    # Should be docs/security/audit-YYYY-MM-DD.md
  notes.md                           # Should be in docs/ or update existing doc
```

---

## What It Does

### Phase 1: Discovery & Audit
1. **Scan for documentation files:**
   ```bash
   # Find all markdown files (excluding node_modules, .git, etc.)
   find <project> -name "*.md" \
     -not -path "*/node_modules/*" \
     -not -path "*/.git/*" \
     -not -path "*/.venv/*" \
     -not -path "*/dist/*" \
     -not -path "*/build/*"
   ```

2. **Categorize findings:**
   - ✅ Docs in `docs/` directory (compliant)
   - ✅ README.md in any directory (allowed - explains folder contents)
   - ⚠️ Other .md files in root (should be in docs/)
   - ⚠️ Other .md files in subdirectories (should be in docs/)
   - ❌ Docs without frontmatter (docs/ only)
   - ❌ Orphaned docs (not in router)

3. **Check structure:**
   - [ ] `docs/` directory exists
   - [ ] `docs/00_ROUTER.md` exists
   - [ ] `docs/01_CATALOG.md` exists
   - [ ] `docs/scripts/generate_docs_index.py` exists
   - [ ] All docs have frontmatter
   - [ ] All docs registered in router

### Phase 2: Analysis & Report

Generate compliance report:

```markdown
# Documentation Audit Report
**Project:** <project-name>
**Date:** <current-date>
**Compliance Score:** X/10

## Summary

- **Total docs found:** X files
- **Compliant:** X files in docs/ with frontmatter
- **Non-compliant:** X files need migration/fixes
- **Missing structure:** [list missing components]

## Findings

### 1. Documentation Location Issues

#### Files in Root (should be in docs/)
- ✅ README.md (ALLOWED - project overview)
- ✅ LICENSE (ALLOWED - standard file)
- ✅ CHANGELOG.md (ALLOWED - standard file, but can also be in docs/)
- ✅ CONTRIBUTING.md (ALLOWED - standard file, but can also be in docs/)
- [ ] ARCHITECTURE.md → docs/ARCHITECTURE.md
- [ ] API_GUIDE.md → docs/API.md (merge/rename)
- [ ] implementation-summary.md → docs/IMPLEMENTATION.md or update existing doc
- [ ] audit-report.md → docs/security/audit-YYYY-MM-DD.md

#### Files in Wrong Subdirectories
- [ ] src/docs/architecture.md → docs/ARCHITECTURE.md
- [ ] src/design-notes.md → docs/DESIGN_DECISIONS.md
- ✅ src/README.md (ALLOWED - explains src/ directory)
- ✅ lib/components/README.md (ALLOWED - explains components/ directory)

#### Orphaned Documentation
- [ ] old_docs/legacy.md (consider archiving or removing)

### 2. Frontmatter Issues

#### Missing Frontmatter (X files)
- [ ] docs/existing-file.md - Add frontmatter
- [ ] README.md - Add frontmatter (keep in root)

#### Invalid Frontmatter (X files)
- [ ] docs/some-doc.md - Missing required fields (id, summary, tags)

### 3. Router/Catalog Issues

- [ ] docs/00_ROUTER.md - Missing or outdated
- [ ] docs/01_CATALOG.md - Missing or outdated
- [ ] X docs not registered in router

### 4. Content Quality Issues

- [ ] Duplicate docs on same topic
- [ ] Outdated docs (last modified > 1 year ago)
- [ ] Empty or stub files

## Recommendations

### Immediate Actions (Critical)
1. Move root-level docs to docs/
2. Add frontmatter to all docs
3. Initialize router/catalog if missing

### High Priority
1. Consolidate duplicate docs
2. Update/archive outdated docs
3. Register all docs in router

### Low Priority
1. Standardize naming conventions
2. Add cross-references
3. Improve doc organization

## Migration Plan

### Step 1: Initialize Structure (if needed)
```bash
/setup-project-docs <project-path>
```

### Step 2: Migrate Files
```bash
# Move docs to docs/ directory
mv CHANGELOG.md docs/
mv CONTRIBUTING.md docs/
mv src/docs/architecture.md docs/ARCHITECTURE.md
```

### Step 3: Add Frontmatter
[Generated frontmatter for each file]

### Step 4: Regenerate Router
```bash
cd docs/scripts
python3 generate_docs_index.py
```

### Step 5: Verify
```bash
/audit-project-docs <project-path>  # Should score higher now
```

## Compliance Score Breakdown

- **Structure (30%):** X/30 - [pass/fail checks]
- **Location (30%):** X/30 - [% of docs in docs/]
- **Frontmatter (25%):** X/25 - [% with valid frontmatter]
- **Registration (15%):** X/15 - [% in router/catalog]

**Total Score:** X/100 → Y/10
```

### Phase 3: Migration (if --migrate flag)

1. **Backup first:**
   ```bash
   git status  # Ensure clean working tree
   git checkout -b docs-migration-$(date +%Y%m%d)
   ```

2. **Initialize structure (if missing):**
   ```bash
   # Calls /setup-project-docs internally
   ```

3. **Move files to docs/:**
   ```bash
   # For each misplaced file:
   git mv <old-path> docs/<new-name>
   ```

4. **Add frontmatter to files without it:**
   ```markdown
   ---
   id: <auto-generated-id>
   summary: <extracted from first paragraph or heading>
   tags: [<inferred from filename/content>]
   related_files: []
   date: <file modification date or today>
   status: published
   ---

   <original content>
   ```

5. **Update router/catalog:**
   ```bash
   cd docs/scripts
   python3 generate_docs_index.py
   ```

6. **Create migration commit:**
   ```bash
   git add -A
   git commit -m "docs: migrate to standardized structure

   - Move docs to docs/ directory
   - Add frontmatter to existing docs
   - Generate router and catalog
   - Compliance score: X → Y/10

   Audit report: docs/audit-report-$(date +%Y%m%d).md"
   ```

---

## Implementation Steps

When the user invokes this skill:

### 1. Validate Project
```bash
if [ ! -d "<project-path>" ]; then
  echo "Error: Project directory not found"
  exit 1
fi

cd <project-path>

# Check if git repo
if [ ! -d ".git" ]; then
  echo "Warning: Not a git repository. Version control recommended."
fi
```

### 2. Discovery Phase
```bash
# Find all markdown files
find . -name "*.md" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/.venv/*" \
  -not -path "*/venv/*" \
  -not -path "*/.env/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/.cache/*" \
  -not -path "*/__pycache__/*" \
  -type f > /tmp/docs-audit-$$-all.txt

# Categorize by location
grep "^./docs/" /tmp/docs-audit-$$-all.txt > /tmp/docs-audit-$$-compliant.txt
grep -v "^./docs/" /tmp/docs-audit-$$-all.txt | grep -v "^./README.md" > /tmp/docs-audit-$$-misplaced.txt
```

### 3. Check Frontmatter
```bash
# For each doc, check if it has frontmatter
for doc in $(cat /tmp/docs-audit-$$-all.txt); do
  if ! head -n 5 "$doc" | grep -q "^---$"; then
    echo "$doc" >> /tmp/docs-audit-$$-no-frontmatter.txt
  fi
done
```

### 4. Check Structure
```bash
# Check for required files
[ -d "docs" ] && echo "✅ docs/ directory exists" || echo "❌ docs/ directory missing"
[ -f "docs/00_ROUTER.md" ] && echo "✅ Router exists" || echo "❌ Router missing"
[ -f "docs/01_CATALOG.md" ] && echo "✅ Catalog exists" || echo "❌ Catalog missing"
[ -f "docs/scripts/generate_docs_index.py" ] && echo "✅ Index generator exists" || echo "❌ Index generator missing"
```

### 5. Generate Report
```bash
# Create audit report
cat > docs/audit-report-$(date +%Y%m%d).md <<EOF
[Report template from above]
EOF

# Display summary
echo ""
echo "📊 Documentation Audit Summary"
echo "================================"
echo "Total docs: $(wc -l < /tmp/docs-audit-$$-all.txt)"
echo "Compliant: $(wc -l < /tmp/docs-audit-$$-compliant.txt)"
echo "Misplaced: $(wc -l < /tmp/docs-audit-$$-misplaced.txt)"
echo "Missing frontmatter: $(wc -l < /tmp/docs-audit-$$-no-frontmatter.txt)"
echo ""
echo "Compliance score: X/10"
echo ""
echo "Full report: docs/audit-report-$(date +%Y%m%d).md"
```

### 6. Migration Phase (if --migrate)
```bash
# Prompt for confirmation
echo "This will:"
echo "  - Move $(wc -l < /tmp/docs-audit-$$-misplaced.txt) files to docs/"
echo "  - Add frontmatter to $(wc -l < /tmp/docs-audit-$$-no-frontmatter.txt) files"
echo "  - Regenerate router and catalog"
echo ""
read -p "Proceed with migration? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Migration cancelled."
  exit 0
fi

# Create migration branch
git checkout -b "docs-migration-$(date +%Y%m%d)"

# Initialize structure if needed
if [ ! -d "docs" ]; then
  echo "Initializing docs structure..."
  /setup-project-docs $(pwd)
fi

# Move misplaced files
while IFS= read -r file; do
  # Determine new name
  filename=$(basename "$file")

  # Special cases
  case "$filename" in
    CHANGELOG.md|CONTRIBUTING.md|LICENSE.md)
      newpath="docs/$filename"
      ;;
    architecture.md|ARCHITECTURE.md)
      newpath="docs/ARCHITECTURE.md"
      ;;
    deployment.md|DEPLOYMENT.md|DEPLOY.md)
      newpath="docs/DEPLOYMENT.md"
      ;;
    api.md|API.md|api-guide.md)
      newpath="docs/API.md"
      ;;
    *)
      # Convert to title case, sanitize
      newname=$(echo "$filename" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1' | sed 's/ //g')
      newpath="docs/$newname"
      ;;
  esac

  echo "Moving: $file → $newpath"

  # Check if target exists
  if [ -f "$newpath" ]; then
    echo "  ⚠️  Target exists: $newpath"
    echo "  Creating: ${newpath%.md}-merged.md"
    newpath="${newpath%.md}-merged.md"
  fi

  git mv "$file" "$newpath" 2>/dev/null || mv "$file" "$newpath"
done < /tmp/docs-audit-$$-misplaced.txt

# Add frontmatter to files without it
while IFS= read -r file; do
  echo "Adding frontmatter to: $file"

  # Extract first heading as summary
  summary=$(grep -m1 "^#" "$file" | sed 's/^#* //' || echo "Documentation for $(basename $file .md)")

  # Generate ID from filename
  filename=$(basename "$file" .md)
  id=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-')

  # Infer tags from filename
  tags=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | tr ' ' ',' | tr '_' ',')

  # Get file modification date
  if [ "$(uname)" = "Darwin" ]; then
    date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file")
  else
    date=$(stat -c "%y" "$file" | cut -d' ' -f1)
  fi

  # Create temp file with frontmatter
  cat > /tmp/docs-audit-$$-temp.md <<FRONTMATTER
---
id: $id
summary: $summary
tags: [$tags]
related_files: []
date: $date
status: published
---

FRONTMATTER

  # Append original content
  cat "$file" >> /tmp/docs-audit-$$-temp.md

  # Replace original
  mv /tmp/docs-audit-$$-temp.md "$file"
done < /tmp/docs-audit-$$-no-frontmatter.txt

# Regenerate router and catalog
echo "Regenerating router and catalog..."
cd docs/scripts
python3 generate_docs_index.py
cd ../..

# Commit changes
git add -A
git commit -m "docs: migrate to standardized structure

- Moved $(wc -l < /tmp/docs-audit-$$-misplaced.txt) docs to docs/ directory
- Added frontmatter to $(wc -l < /tmp/docs-audit-$$-no-frontmatter.txt) docs
- Generated router and catalog
- Compliance improved to X/10

Audit report: docs/audit-report-$(date +%Y%m%d).md"

echo ""
echo "✅ Migration complete!"
echo "Branch: docs-migration-$(date +%Y%m%d)"
echo "Review changes and merge when ready."
```

---

## Compliance Scoring

### Structure (30 points)
- docs/ directory exists: 10 pts
- 00_ROUTER.md exists: 5 pts
- 01_CATALOG.md exists: 5 pts
- generate_docs_index.py exists: 5 pts
- Proper subdirectory structure: 5 pts

### Location (30 points)
- % of docs in docs/ directory (excluding README.md)
- 100% = 30 pts
- Deduct 3 pts per misplaced doc (max -30)

### Frontmatter (25 points)
- % of docs with valid frontmatter
- Valid = has all required fields (id, summary, tags, date, status)
- 100% = 25 pts
- Deduct 2.5 pts per doc without valid frontmatter

### Registration (15 points)
- % of docs registered in router
- 100% = 15 pts
- Deduct 1.5 pts per unregistered doc

### Score Interpretation
- **9-10:** Excellent - Fully compliant
- **7-8:** Good - Minor issues
- **5-6:** Fair - Needs attention
- **3-4:** Poor - Significant issues
- **0-2:** Critical - Major overhaul needed

---

## Safety Features

1. **Dry run by default** - No changes unless --migrate flag
2. **Git branch creation** - All changes in new branch
3. **Backup warnings** - Prompts if working tree not clean
4. **Conflict detection** - Warns if target file exists
5. **Reversible** - All changes via git, can rollback

---

## Output Example

```
📊 Documentation Audit Report
================================

Project: jl-engine
Date: 2026-02-08
Compliance Score: 4/10

Summary:
  Total docs: 8 files
  Compliant: 2 files (25%)
  Misplaced: 5 files (62%)
  Missing frontmatter: 6 files (75%)

Issues Found:
  ❌ docs/ directory missing
  ❌ Router missing
  ❌ Catalog missing
  ⚠️  5 docs in wrong locations
  ⚠️  6 docs missing frontmatter

Misplaced Documentation:
  📄 ./ARCHITECTURE.md → should be docs/ARCHITECTURE.md
  📄 ./USAGE.md → should be docs/USAGE.md
  📄 ./apps/web/README.md → should be docs/WEB_APP.md
  📄 ./docs-old/deployment.md → should be docs/DEPLOYMENT.md
  📄 ./schema/README.md → should be docs/SCHEMA.md

Recommendations:
  1. Run: /setup-project-docs ~/projects/jl-engine
  2. Run: /audit-project-docs ~/projects/jl-engine --migrate
  3. Review and commit changes

Full report saved to: docs/audit-report-20260208.md

Run with --dry-run to see migration preview
Run with --migrate to execute migration
```

---

## Related Skills

- `/setup-project-docs` - Initialize docs structure (call this first if structure missing)
- `/ports` - Port allocations (should be documented in docs/PORT_REGISTRY.md)
- `/deploy` - Deployment (should reference docs/DEPLOYMENT.md)

---

## Integration with Workflow

### Typical Usage Flow

**For projects without docs structure:**
```bash
1. /setup-project-docs ~/projects/my-project
2. /audit-project-docs ~/projects/my-project --dry-run
3. /audit-project-docs ~/projects/my-project --migrate
```

**For projects with existing docs/**
```bash
1. /audit-project-docs ~/projects/my-project
2. Fix issues manually or with --migrate
3. Verify: /audit-project-docs ~/projects/my-project
```

---

## Notes

- **Idempotent:** Safe to run multiple times
- **Git-aware:** Uses git mv when possible to preserve history
- **Non-destructive:** Creates branches, can rollback
- **Automatic frontmatter:** Infers metadata from content/filename
- **Conflict handling:** Warns when files would be overwritten
- **Comprehensive report:** Saved to docs/ for future reference

---

**Priority:** 🟡 High (pairs with setup-project-docs)
**Effort:** Medium-High (30-45 minutes per project with manual review)
**Dependencies:** Python 3, git, /setup-project-docs skill
