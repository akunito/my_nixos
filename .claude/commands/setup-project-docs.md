# Setup Project Documentation

Initialize standardized documentation structure for a project.

## Purpose

Use this skill to:
- Create consistent documentation structure across all projects
- Set up router/catalog system for Claude navigation
- Generate documentation templates with proper frontmatter
- Prevent ad-hoc documentation in root or random locations

---

## Usage

```
/setup-project-docs <project-path>
```

**Example:**
```
/setup-project-docs ~/projects/jl-engine
```

---

## What Gets Created

### Directory Structure
```
<project>/docs/
├── 00_ROUTER.md          # Claude routing table (navigation index)
├── 01_CATALOG.md         # Full documentation catalog (metadata)
├── ARCHITECTURE.md       # System design and patterns
├── ENVIRONMENT_SETUP.md  # Local development setup
├── DEPLOYMENT.md         # Deployment procedures
├── API.md                # API reference (if applicable)
├── TROUBLESHOOTING.md    # Common issues and solutions
└── scripts/
    └── generate_docs_index.py  # Auto-generate router/catalog
```

### Frontmatter Template
Each documentation file includes:
```yaml
---
id: category.subcategory.identifier
summary: One-line description of the document
tags: [tag1, tag2, tag3]
related_files: [path/pattern/**]
date: YYYY-MM-DD
status: draft | published
---
```

---

## Implementation Steps

When the user invokes this skill:

1. **Verify project directory exists:**
   ```bash
   if [ ! -d "<project-path>" ]; then
     echo "Error: Project directory not found"
     exit 1
   fi
   ```

2. **Create docs/ directory:**
   ```bash
   mkdir -p <project-path>/docs/scripts
   ```

3. **Generate 00_ROUTER.md:**
   ```markdown
   # Router Index

   **Documentation for <project-name>**

   Use this file to select the best node ID(s), then read the referenced docs/files.

   ## How to Use This Router

   1. **Scan the table** below for relevant IDs by topic or tags
   2. **Select the ID(s)** that match your question or task
   3. **Read the referenced docs** (Primary Path column)
   4. **Follow related links** as needed

   ---

   | ID | Summary | Tags | Primary Path |
   |---|---|---|---|
   | architecture | System architecture and design patterns | architecture, design | docs/ARCHITECTURE.md |
   | environment | Local development environment setup | setup, dev, environment | docs/ENVIRONMENT_SETUP.md |
   | deployment | Deployment procedures and workflows | deployment, production | docs/DEPLOYMENT.md |
   | api | API reference and endpoints | api, reference | docs/API.md |
   | troubleshooting | Common issues and solutions | troubleshooting, debugging | docs/TROUBLESHOOTING.md |

   ---

   **Last updated:** <current-date>
   **Entry count:** 5 documents
   ```

4. **Generate 01_CATALOG.md:**
   ```markdown
   # Documentation Catalog

   **Full metadata for all documentation in <project-name>**

   ## Overview

   This catalog provides detailed metadata for all documentation files.
   The router (00_ROUTER.md) provides a quick navigation table.

   ---

   ## Documents

   ### architecture
   - **Path:** docs/ARCHITECTURE.md
   - **Summary:** System architecture and design patterns
   - **Tags:** architecture, design
   - **Status:** draft
   - **Last Updated:** <current-date>

   ### environment
   - **Path:** docs/ENVIRONMENT_SETUP.md
   - **Summary:** Local development environment setup
   - **Tags:** setup, dev, environment
   - **Status:** draft
   - **Last Updated:** <current-date>

   ### deployment
   - **Path:** docs/DEPLOYMENT.md
   - **Summary:** Deployment procedures and workflows
   - **Tags:** deployment, production
   - **Status:** draft
   - **Last Updated:** <current-date>

   ### api
   - **Path:** docs/API.md
   - **Summary:** API reference and endpoints
   - **Tags:** api, reference
   - **Status:** draft
   - **Last Updated:** <current-date>

   ### troubleshooting
   - **Path:** docs/TROUBLESHOOTING.md
   - **Summary:** Common issues and solutions
   - **Tags:** troubleshooting, debugging
   - **Status:** draft
   - **Last Updated:** <current-date>
   ```

5. **Generate ARCHITECTURE.md stub:**
   ```markdown
   ---
   id: architecture
   summary: System architecture and design patterns
   tags: [architecture, design]
   related_files: [src/**, lib/**]
   date: <current-date>
   status: draft
   ---

   # Architecture

   ## Overview

   [Brief description of the system architecture]

   ## Components

   ### [Component Name]

   **Purpose:** [What this component does]
   **Location:** [Path to component]
   **Dependencies:** [Key dependencies]

   ## Design Patterns

   ### [Pattern Name]

   **Usage:** [Where and how this pattern is used]
   **Rationale:** [Why this pattern was chosen]

   ## Data Flow

   [Describe data flow through the system]

   ## Technology Stack

   - **Backend:** [Technologies]
   - **Frontend:** [Technologies]
   - **Database:** [Technologies]
   - **Infrastructure:** [Technologies]

   ## Related Documentation

   - [ENVIRONMENT_SETUP.md](./ENVIRONMENT_SETUP.md)
   - [DEPLOYMENT.md](./DEPLOYMENT.md)
   ```

6. **Generate ENVIRONMENT_SETUP.md stub:**
   ```markdown
   ---
   id: environment
   summary: Local development environment setup
   tags: [setup, dev, environment]
   related_files: [docker-compose*.yml, .env.example]
   date: <current-date>
   status: draft
   ---

   # Environment Setup

   ## Prerequisites

   - [List required software and versions]

   ## Initial Setup

   1. **Clone the repository:**
      ```bash
      git clone <repo-url>
      cd <project-name>
      ```

   2. **Install dependencies:**
      ```bash
      # Add project-specific commands
      ```

   3. **Configure environment:**
      ```bash
      cp .env.example .env
      # Edit .env with your settings
      ```

   ## Development Workflow

   ### Start Development Environment
   ```bash
   # Add project-specific commands
   ```

   ### Run Tests
   ```bash
   # Add test commands
   ```

   ## Troubleshooting

   See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues.

   ## Related Documentation

   - [ARCHITECTURE.md](./ARCHITECTURE.md)
   - [DEPLOYMENT.md](./DEPLOYMENT.md)
   ```

7. **Generate DEPLOYMENT.md stub:**
   ```markdown
   ---
   id: deployment
   summary: Deployment procedures and workflows
   tags: [deployment, production]
   related_files: [deploy.sh, docker-compose*.yml]
   date: <current-date>
   status: draft
   ---

   # Deployment

   ## Environments

   - **Development:** [Description]
   - **Test:** [Description]
   - **Production:** [Description]

   ## Deployment Process

   ### Development
   ```bash
   # Add deployment commands
   ```

   ### Production
   ```bash
   # Add deployment commands
   ```

   ## Health Checks

   After deployment, verify:
   - [ ] Services are running
   - [ ] Health endpoints respond
   - [ ] Database connectivity
   - [ ] API functionality

   ## Rollback Procedure

   If deployment fails:
   ```bash
   # Add rollback commands
   ```

   ## Related Documentation

   - [ARCHITECTURE.md](./ARCHITECTURE.md)
   - [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
   ```

8. **Generate API.md stub (if applicable):**
   ```markdown
   ---
   id: api
   summary: API reference and endpoints
   tags: [api, reference]
   related_files: [src/api/**, src/routes/**]
   date: <current-date>
   status: draft
   ---

   # API Reference

   ## Base URL

   - Development: `http://localhost:<port>`
   - Production: `https://<domain>`

   ## Authentication

   [Describe authentication method]

   ## Endpoints

   ### GET /endpoint

   **Description:** [What this endpoint does]

   **Parameters:**
   - `param1` (type): Description

   **Response:**
   ```json
   {
     "example": "response"
   }
   ```

   **Status Codes:**
   - 200: Success
   - 400: Bad Request
   - 401: Unauthorized

   ## Rate Limiting

   [Describe rate limiting if applicable]

   ## Error Handling

   [Describe error response format]
   ```

9. **Generate TROUBLESHOOTING.md stub:**
   ```markdown
   ---
   id: troubleshooting
   summary: Common issues and solutions
   tags: [troubleshooting, debugging]
   related_files: [docs/**]
   date: <current-date>
   status: draft
   ---

   # Troubleshooting

   ## Common Issues

   ### Issue: [Problem description]

   **Symptoms:**
   - [Symptom 1]
   - [Symptom 2]

   **Solution:**
   ```bash
   # Commands to fix
   ```

   **Prevention:**
   [How to avoid this issue]

   ## Debugging Tips

   ### Check Logs
   ```bash
   # Log viewing commands
   ```

   ### Verify Configuration
   ```bash
   # Configuration check commands
   ```

   ## Getting Help

   If you can't resolve the issue:
   1. Check the [ARCHITECTURE.md](./ARCHITECTURE.md) for system design
   2. Review [ENVIRONMENT_SETUP.md](./ENVIRONMENT_SETUP.md) for setup steps
   3. Search existing issues in the repository
   ```

10. **Copy generate_docs_index.py from dotfiles:**
    ```bash
    cp ~/.dotfiles/scripts/generate_docs_index.py <project-path>/docs/scripts/
    ```

11. **Create README.md in docs/ (optional):**
    ```markdown
    # Documentation

    This directory contains all documentation for <project-name>.

    ## Navigation

    - Start with [00_ROUTER.md](./00_ROUTER.md) to find relevant documentation
    - See [01_CATALOG.md](./01_CATALOG.md) for full document metadata

    ## Key Documents

    - [ARCHITECTURE.md](./ARCHITECTURE.md) - System design
    - [ENVIRONMENT_SETUP.md](./ENVIRONMENT_SETUP.md) - Local development
    - [DEPLOYMENT.md](./DEPLOYMENT.md) - Deployment procedures
    - [API.md](./API.md) - API reference
    - [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues

    ## Updating Documentation

    After adding or modifying documentation:
    ```bash
    cd docs/scripts
    python3 generate_docs_index.py
    ```
    ```

12. **Summary output:**
    ```
    ✅ Documentation structure created for <project-name>

    Created files:
    - docs/00_ROUTER.md (navigation index)
    - docs/01_CATALOG.md (metadata catalog)
    - docs/ARCHITECTURE.md (stub)
    - docs/ENVIRONMENT_SETUP.md (stub)
    - docs/DEPLOYMENT.md (stub)
    - docs/API.md (stub)
    - docs/TROUBLESHOOTING.md (stub)
    - docs/scripts/generate_docs_index.py (from dotfiles)

    Next steps:
    1. Fill in the stub files with project-specific content
    2. Add frontmatter to existing docs (if any)
    3. Run: cd docs/scripts && python3 generate_docs_index.py
    4. Commit changes: git add docs/ && git commit -m "docs: initialize documentation structure"

    IMPORTANT: All documentation MUST go in docs/ directory.
    Never create documentation in root or random locations.
    ```

---

## Verification After Setup

```bash
# Check structure
tree docs/

# Verify frontmatter in files
head -n 10 docs/ARCHITECTURE.md

# Test index generation
cd docs/scripts
python3 generate_docs_index.py
```

---

## Documentation Standards

### Location Rules (CRITICAL)
1. **ALL documentation goes in `docs/` directory** - Never in root
2. **Router system required** - 00_ROUTER.md + 01_CATALOG.md
3. **Frontmatter mandatory** - All docs must have YAML frontmatter
4. **Incremental updates** - Update existing docs, don't create duplicates
5. **Stable IDs** - Once assigned, document IDs never change

### Frontmatter Requirements
```yaml
---
id: category.subcategory.identifier  # Stable, unique ID
summary: One-line description         # Required, concise
tags: [tag1, tag2]                   # Required, lowercase
related_files: [path/**]             # Optional, globs OK
date: YYYY-MM-DD                     # Required, ISO format
status: draft | published            # Required
---
```

### When to Update vs Create
- **Update existing doc** if topic already exists
- **Create new doc** only if truly new topic
- **Never create duplicate docs** on same topic
- **Always regenerate router** after changes

---

## Integration with CLAUDE.md

After running this skill, add to project's CLAUDE.md (if exists):

```markdown
## Documentation

This project uses the router/catalog documentation system.

### Reading Documentation
1. Start with `docs/00_ROUTER.md` to find relevant docs
2. Use document IDs to navigate efficiently
3. Follow related links for deeper understanding

### Adding Documentation
1. Create/update file in `docs/` directory
2. Add proper frontmatter (see docs/README.md)
3. Regenerate router: `cd docs/scripts && python3 generate_docs_index.py`
4. Commit changes

### Rules
- **ALL documentation goes in docs/** - Never in root or random locations
- **Update existing docs** - Don't create duplicates
- **Use frontmatter** - Required for router inclusion
- **Stable IDs** - Never change document IDs
```

---

## Related Skills

- `/audit-project-security` - Audit project security posture
- `/standardize-docker` - Apply Docker patterns (includes deployment docs)
- `/init-ci-pipeline` - Add CI/CD (requires docs/DEPLOYMENT.md)

---

## Notes

- This skill is **idempotent** - safe to run multiple times
- Existing docs are preserved - only missing files are created
- Router/catalog can be regenerated anytime with `generate_docs_index.py`
- Based on reference implementation from `lefty_workout` project
- Follows the same pattern as `~/.dotfiles/docs/` structure

---

**Priority:** 🟡 High (Phase 3 in project audit)
**Effort:** Medium (15-20 minutes per project)
**Dependencies:** Python 3 (for generate_docs_index.py)
