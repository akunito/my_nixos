# Audit Project Security

Comprehensive security audit with automated remediation including git-crypt setup.

## Purpose

Use this skill to:
- **Audit** project security posture (secrets, Docker, dependencies, etc.)
- **Detect** plaintext credentials, API keys, and sensitive data
- **Setup git-crypt** for secrets encryption (if needed)
- **Scan** for security vulnerabilities
- **Generate** compliance report with remediation steps
- **Remediate** issues automatically (with --fix flag)

---

## Usage

```
/audit-project-security <project-path>
```

**Options:**
- *(default)* - Audit only, generate report
- `--fix` - Apply automatic remediations
- `--setup-gitcrypt` - Initialize git-crypt only
- `--report-only` - Skip scans, just summarize existing findings

**Examples:**
```bash
# Audit only (safe, read-only)
/audit-project-security ~/projects/jl-engine

# Setup git-crypt and encrypt secrets
/audit-project-security ~/projects/jl-engine --setup-gitcrypt

# Full audit with automatic fixes
/audit-project-security ~/projects/portfolio-cms --fix
```

---

## What It Audits

### 1. Secrets Management (CRITICAL)
- [ ] Git-crypt initialized
- [ ] `.env*` files encrypted
- [ ] `.gitattributes` configured
- [ ] Git-crypt key accessible (`~/.git-crypt/dotfiles-key`)
- [ ] No plaintext secrets in git history
- [ ] `.env.example` template exists

### 2. Environment Files
- [ ] `.env` files present
- [ ] `.env.example` exists (public template)
- [ ] Sensitive keys identified (API keys, passwords, tokens)
- [ ] No hardcoded secrets in code
- [ ] No secrets in docker-compose.yml

### 3. Docker Security
- [ ] Non-root user configured
- [ ] Health checks enabled
- [ ] No secrets in Dockerfile
- [ ] `.dockerignore` exists
- [ ] Image scanning (if applicable)

### 4. Dependencies
- [ ] Known vulnerabilities (npm audit, pip check, etc.)
- [ ] Outdated packages with security issues
- [ ] Dependency lock files exist

### 5. Git Repository
- [ ] No committed secrets (gitleaks/trufflehog scan)
- [ ] `.gitignore` properly configured
- [ ] No sensitive files tracked

### 6. API Keys & Credentials
Scans for patterns:
- API keys (OpenAI, Anthropic, AWS, etc.)
- Database credentials
- JWT secrets
- OAuth tokens
- Private keys (RSA, SSH)
- Passwords

---

## Security Scoring

### Score Breakdown (0-10)

| Category | Weight | Checks |
|----------|--------|--------|
| **Secrets Encryption** | 35% | Git-crypt, .env encryption |
| **Git Hygiene** | 25% | No committed secrets, proper .gitignore |
| **Docker Security** | 20% | Non-root, health checks, no secrets |
| **Dependencies** | 15% | No known vulnerabilities |
| **Best Practices** | 5% | Documentation, .env.example |

**Score Interpretation:**
- **9-10:** Excellent - Production-ready security ✅
- **7-8:** Good - Minor issues 🟡
- **5-6:** Fair - Needs attention ⚠️
- **3-4:** Poor - Significant risks 🔴
- **0-2:** Critical - Immediate action required 🚨

---

## Implementation Steps

### Phase 1: Discovery & Scanning

#### 1. Project Detection
```bash
cd <project-path>

# Detect project type
if [ -f "package.json" ]; then
  PROJECT_TYPE="node"
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  PROJECT_TYPE="python"
elif [ -f "Gemfile" ]; then
  PROJECT_TYPE="ruby"
elif [ -f "go.mod" ]; then
  PROJECT_TYPE="go"
else
  PROJECT_TYPE="unknown"
fi

echo "Detected project type: $PROJECT_TYPE"
```

#### 2. Check Git-crypt Status
```bash
# Check if git-crypt is initialized
if [ -d ".git-crypt" ]; then
  echo "✅ Git-crypt initialized"

  # Check if unlocked
  if git-crypt status | grep -q "not encrypted"; then
    echo "⚠️  Git-crypt initialized but files not encrypted"
    GITCRYPT_STATUS="initialized-not-encrypted"
  else
    echo "✅ Git-crypt unlocked and files encrypted"
    GITCRYPT_STATUS="enabled"
  fi
else
  echo "❌ Git-crypt not initialized"
  GITCRYPT_STATUS="not-initialized"
fi

# Check for git-crypt key
if [ -f ~/.git-crypt/dotfiles-key ]; then
  echo "✅ Shared git-crypt key found"
else
  echo "⚠️  Shared git-crypt key not found (expected: ~/.git-crypt/dotfiles-key)"
fi
```

#### 3. Scan for Environment Files
```bash
# Find all .env files
find . -maxdepth 2 -name ".env*" -not -name ".env.example" -type f > /tmp/security-audit-$$-envfiles.txt

echo "Found $(wc -l < /tmp/security-audit-$$-envfiles.txt) environment files:"
cat /tmp/security-audit-$$-envfiles.txt

# Check if encrypted
for envfile in $(cat /tmp/security-audit-$$-envfiles.txt); do
  if git-crypt status "$envfile" 2>/dev/null | grep -q "encrypted"; then
    echo "  ✅ $envfile - encrypted"
  else
    echo "  ❌ $envfile - NOT encrypted"
  fi
done
```

#### 4. Scan for Secrets in Code
```bash
# Common secret patterns
echo "Scanning for potential secrets in code..."

# API Keys
grep -r -n -E "(api_key|apikey|api-key|API_KEY|APIKEY)" \
  --include="*.js" --include="*.ts" --include="*.py" --include="*.rb" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  . > /tmp/security-audit-$$-apikeys.txt

# Passwords
grep -r -n -E "(password|PASSWORD|passwd|PASSWD).*=.*['\"]" \
  --include="*.js" --include="*.ts" --include="*.py" --include="*.rb" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  . > /tmp/security-audit-$$-passwords.txt

# Private keys
find . -name "*.pem" -o -name "*.key" -o -name "id_rsa" \
  -not -path "*/.git/*" -not -path "*/node_modules/*" \
  > /tmp/security-audit-$$-privatekeys.txt

# JWT secrets
grep -r -n -E "(jwt_secret|JWT_SECRET|jwtSecret)" \
  --include="*.js" --include="*.ts" --include="*.py" --include="*.rb" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  . > /tmp/security-audit-$$-jwt.txt

# Report findings
if [ -s /tmp/security-audit-$$-apikeys.txt ]; then
  echo "⚠️  Found $(wc -l < /tmp/security-audit-$$-apikeys.txt) potential API key references"
fi
if [ -s /tmp/security-audit-$$-passwords.txt ]; then
  echo "⚠️  Found $(wc -l < /tmp/security-audit-$$-passwords.txt) potential password references"
fi
if [ -s /tmp/security-audit-$$-privatekeys.txt ]; then
  echo "🔴 Found $(wc -l < /tmp/security-audit-$$-privatekeys.txt) private key files"
fi
if [ -s /tmp/security-audit-$$-jwt.txt ]; then
  echo "⚠️  Found $(wc -l < /tmp/security-audit-$$-jwt.txt) JWT secret references"
fi
```

#### 5. Check Git History for Secrets
```bash
# Check if gitleaks is available
if command -v gitleaks &> /dev/null; then
  echo "Running gitleaks scan..."
  gitleaks detect --source . --report-path /tmp/security-audit-$$-gitleaks.json

  if [ -s /tmp/security-audit-$$-gitleaks.json ]; then
    echo "🔴 CRITICAL: Secrets found in git history!"
  else
    echo "✅ No secrets found in git history"
  fi
else
  echo "⚠️  gitleaks not installed (recommended: brew install gitleaks)"

  # Fallback: basic git log search
  echo "Running basic git history scan..."
  git log --all --full-history --source --pretty=format:"%H" \
    | while read commit; do
        git show $commit | grep -E "(password|api_key|secret|token)" \
          && echo "⚠️  Potential secret in commit $commit"
      done | head -20 > /tmp/security-audit-$$-git-secrets.txt

  if [ -s /tmp/security-audit-$$-git-secrets.txt ]; then
    echo "⚠️  Potential secrets in git history ($(wc -l < /tmp/security-audit-$$-git-secrets.txt) matches)"
  fi
fi
```

#### 6. Docker Security Check
```bash
if [ -f "Dockerfile" ]; then
  echo "Checking Docker security..."

  # Check for non-root user
  if grep -q "^USER " Dockerfile; then
    echo "  ✅ Non-root user configured"
  else
    echo "  ⚠️  No USER directive (running as root)"
  fi

  # Check for secrets in Dockerfile
  if grep -E "(password|secret|token|api_key)" Dockerfile; then
    echo "  🔴 Potential secrets in Dockerfile!"
  else
    echo "  ✅ No obvious secrets in Dockerfile"
  fi

  # Check for .dockerignore
  if [ -f ".dockerignore" ]; then
    echo "  ✅ .dockerignore exists"

    # Check if .env is ignored
    if grep -q "\.env" .dockerignore; then
      echo "  ✅ .env files ignored in Docker builds"
    else
      echo "  ⚠️  .env not in .dockerignore"
    fi
  else
    echo "  ⚠️  .dockerignore missing"
  fi
fi

# Check docker-compose for secrets
if ls docker-compose*.yml &> /dev/null; then
  echo "Checking docker-compose files..."

  if grep -h -E "(password|secret|token|api_key):" docker-compose*.yml | grep -v "file:"; then
    echo "  🔴 Potential hardcoded secrets in docker-compose!"
  else
    echo "  ✅ No hardcoded secrets in docker-compose"
  fi

  # Check if using .env files
  if grep -q "env_file:" docker-compose*.yml; then
    echo "  ✅ Using env_file for secrets"
  else
    echo "  ⚠️  Not using env_file (consider for secret management)"
  fi
fi
```

#### 7. Dependency Vulnerabilities
```bash
echo "Checking for dependency vulnerabilities..."

case $PROJECT_TYPE in
  node)
    if [ -f "package-lock.json" ] || [ -f "yarn.lock" ] || [ -f "pnpm-lock.yaml" ]; then
      echo "  Running npm audit..."
      npm audit --json > /tmp/security-audit-$$-npm.json 2>&1

      vulnerabilities=$(jq '.metadata.vulnerabilities.total' /tmp/security-audit-$$-npm.json 2>/dev/null || echo "0")
      if [ "$vulnerabilities" -gt 0 ]; then
        echo "  ⚠️  Found $vulnerabilities npm vulnerabilities"
      else
        echo "  ✅ No npm vulnerabilities"
      fi
    else
      echo "  ⚠️  No lock file (run npm install)"
    fi
    ;;

  python)
    if command -v pip &> /dev/null; then
      echo "  Running pip check..."
      pip check > /tmp/security-audit-$$-pip.txt 2>&1

      if grep -q "No broken requirements" /tmp/security-audit-$$-pip.txt; then
        echo "  ✅ No broken Python dependencies"
      else
        echo "  ⚠️  Python dependency issues found"
      fi

      # Safety check (if available)
      if command -v safety &> /dev/null; then
        echo "  Running safety check..."
        safety check --json > /tmp/security-audit-$$-safety.json 2>&1
        # Parse results
      else
        echo "  ⚠️  safety not installed (recommended: pip install safety)"
      fi
    fi
    ;;
esac
```

---

### Phase 2: Generate Security Report

```markdown
# Security Audit Report
**Project:** <project-name>
**Path:** <project-path>
**Date:** <current-date>
**Security Score:** X/10

---

## Executive Summary

- **Overall Risk Level:** [CRITICAL | HIGH | MEDIUM | LOW]
- **Critical Issues:** X
- **High Priority Issues:** X
- **Medium Priority Issues:** X
- **Low Priority Issues:** X

---

## 1. Secrets Management (Score: X/35)

### Git-crypt Status
- [ ] Git-crypt initialized
- [ ] .env files encrypted
- [ ] .gitattributes configured
- [ ] Shared key accessible

**Findings:**
- ❌ Git-crypt NOT initialized
- ❌ 3 .env files contain plaintext secrets:
  - `.env` (8 sensitive keys)
  - `.env.dev` (8 sensitive keys)
  - `.env.prod` (10 sensitive keys including DB password)

**Remediation:**
```bash
/audit-project-security <project> --setup-gitcrypt
```

---

## 2. Plaintext Secrets (Score: X/25)

### Detected Secrets

#### Critical (Immediate Action Required)
- 🔴 **OPENAI_API_KEY** in `.env` (sk-...)
- 🔴 **ANTHROPIC_API_KEY** in `.env` (sk-ant-...)
- 🔴 **DATABASE_PASSWORD** in `.env.prod`
- 🔴 **JWT_SECRET** in `.env.prod`

#### High Priority
- ⚠️ **STRAPI_ADMIN_JWT_SECRET** in `.env`
- ⚠️ **S3_ACCESS_KEY** in `.env`
- ⚠️ **S3_SECRET_KEY** in `.env`

#### Git History
- 🔴 **CRITICAL:** API key found in commit abc1234 (2024-11-15)
- 🔴 **CRITICAL:** Database password in commit def5678 (2024-10-20)

**Remediation:**
1. Setup git-crypt (see above)
2. Rotate compromised credentials
3. Clean git history:
   ```bash
   # Use BFG or git-filter-repo
   git filter-repo --invert-paths --path .env
   git push origin --force --all
   ```

---

## 3. Docker Security (Score: X/20)

### Dockerfile Analysis
- ✅ Multi-stage build used
- ⚠️ Running as root (no USER directive)
- ⚠️ .dockerignore missing

### docker-compose Analysis
- ✅ Using env_file for secrets
- ✅ No hardcoded secrets
- ✅ Health checks configured

**Recommendations:**
1. Add USER directive to Dockerfile:
   ```dockerfile
   USER appuser:appgroup
   ```
2. Create .dockerignore:
   ```
   .env*
   .git
   node_modules
   *.log
   ```

---

## 4. Dependencies (Score: X/15)

### npm audit Results
- ⚠️ 12 vulnerabilities found:
  - 0 critical
  - 2 high
  - 5 moderate
  - 5 low

**Affected Packages:**
- `lodash@4.17.19` (high) - Prototype Pollution
- `axios@0.21.1` (moderate) - SSRF

**Remediation:**
```bash
npm audit fix
```

---

## 5. Best Practices (Score: X/5)

- ✅ .gitignore exists and configured
- ❌ .env.example missing
- ⚠️ No security documentation

**Recommendations:**
1. Create .env.example template
2. Add docs/SECURITY.md with security procedures

---

## Compliance Score Breakdown

| Category | Weight | Score | Status |
|----------|--------|-------|--------|
| Secrets Encryption | 35% | 0/35 | 🔴 CRITICAL |
| Git Hygiene | 25% | 10/25 | ⚠️ HIGH RISK |
| Docker Security | 20% | 15/20 | 🟡 GOOD |
| Dependencies | 15% | 10/15 | 🟡 GOOD |
| Best Practices | 5% | 2/5 | ⚠️ FAIR |

**Total Score:** 37/100 → 3.7/10 (🔴 POOR - Immediate Action Required)

---

## Immediate Actions Required

### Critical (Do Today)
1. ✅ **Setup git-crypt:**
   ```bash
   /audit-project-security ~/projects/jl-engine --setup-gitcrypt
   ```

2. ✅ **Rotate compromised API keys:**
   - OpenAI API key (found in git history)
   - Anthropic API key (found in git history)

3. ✅ **Clean git history:**
   ```bash
   # Backup first!
   git clone --mirror <repo-url> backup.git

   # Remove .env from history
   git filter-repo --invert-paths --path .env
   git push origin --force --all
   ```

### High Priority (This Week)
4. Add non-root user to Dockerfile
5. Create .dockerignore
6. Fix npm vulnerabilities (npm audit fix)
7. Create .env.example template

### Medium Priority (This Month)
8. Add docs/SECURITY.md
9. Setup dependency scanning in CI/CD
10. Add secret scanning pre-commit hook

---

## Remediation Commands

```bash
# 1. Setup git-crypt
/audit-project-security ~/projects/jl-engine --setup-gitcrypt

# 2. Fix dependencies
npm audit fix

# 3. Add .dockerignore
cat > .dockerignore <<EOF
.env*
.git
node_modules
*.log
EOF

# 4. Create .env.example
cp .env .env.example
# Manually remove sensitive values

# 5. Commit security improvements
git add .gitattributes .dockerignore .env.example
git commit -m "security: setup git-crypt and improve Docker security"
```

---

## Next Audit

Re-run audit after remediation:
```bash
/audit-project-security ~/projects/jl-engine
```

Expected improvements:
- Secrets Encryption: 0/35 → 35/35
- Git Hygiene: 10/25 → 25/25
- Total Score: 3.7/10 → 8.5/10

---

**Report saved to:** `docs/security/audit-YYYYMMDD.md`
```

---

### Phase 3: Git-crypt Setup (--setup-gitcrypt or --fix)

When user runs with `--setup-gitcrypt` or `--fix` flag:

#### 1. Initialize Git-crypt
```bash
echo "Setting up git-crypt for <project-name>..."

# Check if already initialized
if [ -d ".git-crypt" ]; then
  echo "✅ Git-crypt already initialized"
else
  # Check for shared key
  if [ ! -f ~/.git-crypt/dotfiles-key ]; then
    echo "❌ Error: Shared git-crypt key not found"
    echo "Expected location: ~/.git-crypt/dotfiles-key"
    echo ""
    echo "Options:"
    echo "  1. Copy key from another machine:"
    echo "     scp user@other-machine:~/.git-crypt/dotfiles-key ~/.git-crypt/"
    echo "  2. Generate new key:"
    echo "     mkdir -p ~/.git-crypt"
    echo "     git-crypt export-key ~/.git-crypt/dotfiles-key"
    exit 1
  fi

  # Initialize with shared key
  git-crypt init
  git-crypt unlock ~/.git-crypt/dotfiles-key

  echo "✅ Git-crypt initialized with shared key"
fi
```

#### 2. Create .gitattributes
```bash
# Check if .gitattributes exists
if [ ! -f ".gitattributes" ]; then
  echo "Creating .gitattributes..."

  cat > .gitattributes <<'EOF'
# Git-crypt configuration
# Encrypt all .env files except .env.example

.env filter=git-crypt diff=git-crypt
.env.* filter=git-crypt diff=git-crypt
!.env.example

# Encrypt other sensitive files
secrets/** filter=git-crypt diff=git-crypt
*.key filter=git-crypt diff=git-crypt
*.pem filter=git-crypt diff=git-crypt

# Don't encrypt these
.env.example !filter !diff
*.md !filter !diff
EOF

  echo "✅ Created .gitattributes"
else
  echo "⚠️  .gitattributes exists, checking configuration..."

  if ! grep -q "filter=git-crypt" .gitattributes; then
    echo "Adding git-crypt rules to existing .gitattributes..."

    cat >> .gitattributes <<'EOF'

# Git-crypt configuration
.env filter=git-crypt diff=git-crypt
.env.* filter=git-crypt diff=git-crypt
!.env.example
EOF

    echo "✅ Updated .gitattributes"
  else
    echo "✅ .gitattributes already configured"
  fi
fi
```

#### 3. Create .env.example
```bash
# Find all .env files
for envfile in .env .env.dev .env.test .env.prod; do
  if [ -f "$envfile" ] && [ ! -f "${envfile}.example" ]; then
    echo "Creating ${envfile}.example template..."

    # Replace values with placeholders
    sed -E 's/(=).+$/\1REPLACE_ME/g' "$envfile" > "${envfile}.example"

    echo "✅ Created ${envfile}.example"
  fi
done

# If no .env files, create basic template
if [ ! -f ".env.example" ]; then
  cat > .env.example <<'EOF'
# Environment Configuration Template
# Copy to .env and fill in actual values

# API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/dbname

# Application
NODE_ENV=development
PORT=3000

# Secrets
JWT_SECRET=your-jwt-secret-here
EOF

  echo "✅ Created .env.example template"
fi
```

#### 4. Encrypt Existing .env Files
```bash
echo "Encrypting .env files..."

# Stage .gitattributes first
git add .gitattributes

# Stage .env files - this triggers git-crypt encryption
for envfile in .env .env.dev .env.test .env.prod; do
  if [ -f "$envfile" ]; then
    git add "$envfile"
    echo "  ✅ Staged $envfile (will be encrypted on commit)"
  fi
done

# Verify encryption will happen
echo ""
echo "Verifying encryption status..."
git-crypt status | grep ".env"
```

#### 5. Update .gitignore
```bash
if [ -f ".gitignore" ]; then
  echo "Updating .gitignore..."

  # Check if .env is already ignored
  if grep -q "^\.env$" .gitignore; then
    echo "  ⚠️  .env is in .gitignore - removing (now tracked via git-crypt)"
    sed -i.bak '/^\.env$/d' .gitignore
    sed -i.bak '/^\.env\.\*/d' .gitignore
  fi

  # Add .env.example exception
  if ! grep -q "!\.env\.example" .gitignore; then
    echo "!.env.example" >> .gitignore
    echo "  ✅ Added !.env.example to .gitignore"
  fi

  # Ensure .env.local is ignored (local development only)
  if ! grep -q "^\.env\.local$" .gitignore; then
    echo ".env.local" >> .gitignore
    echo "  ✅ Added .env.local to .gitignore"
  fi
else
  echo "⚠️  No .gitignore found - creating one..."

  cat > .gitignore <<'EOF'
# Environment files (local only)
.env.local

# Allow encrypted .env files (tracked via git-crypt)
!.env
!.env.*

# Allow .env.example template
!.env.example

# Dependencies
node_modules/
.venv/
venv/

# Build outputs
dist/
build/
*.log
EOF

  echo "✅ Created .gitignore"
fi
```

#### 6. Commit Changes
```bash
echo ""
echo "Changes ready to commit:"
echo "  - .gitattributes (git-crypt rules)"
echo "  - .env* files (encrypted)"
echo "  - .env.example (template)"
echo "  - .gitignore (updated)"
echo ""

# Create commit
git add .gitattributes .env* .gitignore
git commit -m "security: setup git-crypt for secrets encryption

- Initialize git-crypt with shared key
- Configure .gitattributes for .env file encryption
- Create .env.example templates
- Update .gitignore for encrypted files

All .env files are now encrypted at rest in git.
Use 'git-crypt unlock ~/.git-crypt/dotfiles-key' after cloning."

echo "✅ Git-crypt setup complete!"
echo ""
echo "Next steps:"
echo "  1. Push changes: git push origin main"
echo "  2. On other machines: git-crypt unlock ~/.git-crypt/dotfiles-key"
echo "  3. Rotate any compromised credentials"
```

---

## Output Example

```
🔒 Security Audit: jl-engine
============================

Scanning project...
  Project type: node
  Git repository: ✅

1. Git-crypt Status
  ❌ Not initialized
  ✅ Shared key available (~/.git-crypt/dotfiles-key)

2. Environment Files
  Found 2 files:
    ❌ .env (NOT encrypted)
    ❌ .env.dev (NOT encrypted)

3. Secrets Detection
  ⚠️  Found 2 API keys in .env:
    - OPENAI_API_KEY
    - ANTHROPIC_API_KEY
  ⚠️  No .env.example template

4. Git History Scan
  🔴 CRITICAL: API key found in commit abc1234

5. Docker Security
  ✅ Multi-stage Dockerfile
  ⚠️  No USER directive (running as root)
  ⚠️  .dockerignore missing

6. Dependencies
  ⚠️  5 npm vulnerabilities (0 critical, 1 high)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Security Score: 4/10 (🔴 POOR)

Critical Issues: 2
  - API keys in git history
  - No secrets encryption

High Priority: 3
  - Plaintext .env files
  - No .env.example
  - Docker running as root

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Full report saved to: docs/security/audit-20260208.md

🔧 Remediation available:

  Setup git-crypt:
    /audit-project-security ~/projects/jl-engine --setup-gitcrypt

  Or fix all issues:
    /audit-project-security ~/projects/jl-engine --fix
```

---

## Related Skills

- `/audit-project-docs` - Audit documentation (often references security docs)
- `/setup-project-docs` - Create docs/ structure (for SECURITY.md)
- `/audit-infrastructure` - Infrastructure-level security audit

---

## Notes

- **Read-only by default** - Audit without changes
- **--setup-gitcrypt** - Setup encryption only
- **--fix** - Apply all automatic remediations
- **Shared key pattern** - Uses `~/.git-crypt/dotfiles-key` from dotfiles repo
- **Reference implementation** - Based on lefty_workout's git-crypt pattern
- **Preserves git history** - Uses git-crypt (transparent encryption)

---

**Priority:** 🔴 Critical (Phase 1 in project audit)
**Effort:** Medium (20-30 minutes first run, 5 minutes subsequent)
**Dependencies:** git-crypt, gitleaks (optional but recommended)
**Reference:** lefty_workout (see PROJECT_AUDIT.md)
