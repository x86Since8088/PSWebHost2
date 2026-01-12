# In-Browser SQL Security, Licensing & Maintenance Analysis

## Executive Summary

| Framework | Security Status | License | Maintenance | Recommendation |
|-----------|----------------|---------|-------------|----------------|
| **sql.js** | ✅ No known CVEs | MIT | ✅ Active | **RECOMMENDED** |
| **AlaSQL** | ⚠️ 1 High CVE (Fixed) | MIT | ✅ Active | Use with caution |
| **PGlite** | ✅ No known CVEs | Apache 2.0 / PostgreSQL | ✅ Active | Good alternative |
| **Lovefield** | ⚠️ Unknown | Apache 2.0 | ❌ Archived (2023) | **DO NOT USE** |
| **Absurd-SQL** | ⚠️ Inherits sql.js | MIT | ⚠️ Low activity | Limited use |

## Detailed Analysis

### 1. sql.js ⭐ RECOMMENDED

#### Security & CVEs
**Status**: ✅ No known CVEs found

- **Search Results**: No CVEs specifically for sql.js in [2024-2025 CVE databases](https://www.cvedetails.com/vulnerability-list/year-2024/vulnerabilities.html)
- **Security Policy**: Repository has a [security overview page](https://github.com/sql-js/sql.js/security) but details not publicly documented
- **Underlying Tech**: Built on SQLite (public domain), which has an excellent security track record
- **Attack Surface**: Minimal - runs entirely in isolated WASM/JavaScript environment
- **SQL Injection**: Not applicable in typical usage (in-memory database with no network exposure)

**Security Considerations**:
```javascript
// ✅ Safe - Prepared statements
db.run('INSERT INTO users VALUES (?, ?)', [username, password]);

// ⚠️ Unsafe - String concatenation (don't do this)
db.run(`INSERT INTO users VALUES ('${username}', '${password}')`);
```

#### Licensing
- **License**: [MIT License](https://github.com/sql-js/sql.js)
- **SQLite Component**: Public Domain (no restrictions)
- **Commercial Use**: ✅ Allowed
- **Modification**: ✅ Allowed
- **Distribution**: ✅ Allowed
- **Patent Grant**: ❌ Not explicitly granted (standard MIT limitation)

#### Maintenance & Support
- **Status**: ✅ Actively Maintained
- **Repository**: [sql-js/sql.js](https://github.com/sql-js/sql.js)
- **Community**: 13.5k stars, 1.1k forks
- **Activity**: 536+ commits, recent activity in 2024-2025
- **Contributors**: Multiple active contributors
- **Release Cadence**: Regular releases tracking SQLite versions
- **Issue Response**: Issues from 2024-2025 show active engagement

**Last Activity Indicators**:
- Recent issues: March 2025, December 2024, November 2024
- Active issue tracker with responses
- No signs of abandonment

#### CVE Response Process
- **Vulnerability Reporting**: GitHub Security Advisories available
- **Disclosure**: No formal published policy found
- **Track Record**: No historical CVEs demonstrate either excellent security or limited scrutiny
- **Upstream**: Inherits SQLite's security practices (excellent track record)

**Risk Assessment**: ⭐⭐⭐⭐⭐ **Low Risk**
- Well-established project
- Based on battle-tested SQLite
- Active maintenance
- No known vulnerabilities
- Large user base

---

### 2. AlaSQL

#### Security & CVEs
**Status**: ⚠️ One High Severity CVE (FIXED)

**Known Vulnerabilities**:

1. **[SNYK-JS-ALASQL-1082932](https://security.snyk.io/vuln/SNYK-JS-ALASQL-1082932)** - Arbitrary Code Injection
   - **Severity**: High (8.1/10)
   - **Published**: March 5, 2021
   - **Affected Versions**: < 0.7.0
   - **Fixed In**: 0.7.0+ (March 2021)
   - **CVE ID**: None assigned (tracked by Snyk)

   **Vulnerability Details**:
   ```javascript
   // Vulnerable: AlaSQL doesn't sanitize square brackets or backticks
   alasql('SELECT * FROM users WHERE name = `evil code here`');
   // This gets compiled directly into JavaScript without sanitization
   // Result: Arbitrary code execution
   ```

   **Description**: AlaSQL concatenates SQL strings into JavaScript code without sanitization, allowing code injection through unescaped characters in queries.

2. **Race Condition Vulnerability**
   - **Location**: Line 3477 of alasql.fs.js
   - **Severity**: High
   - **Status**: Unknown resolution
   - **Source**: [GitHub Issue #1380](https://github.com/agershun/alasql/issues/1380)

**Security Recommendations**:
```javascript
// ✅ Safe - Use parameterized queries
alasql('SELECT * FROM ? WHERE cpu > ?', [data, threshold]);

// ❌ Dangerous - Never concatenate user input
alasql(`SELECT * FROM data WHERE name = '${userInput}'`);

// ✅ Ensure version >= 0.7.0
console.log(alasql.version);  // Should be >= 0.7.0
```

#### Licensing
- **License**: MIT License
- **Commercial Use**: ✅ Allowed
- **Source**: [npm package](https://www.npmjs.com/package/alasql)
- **Dependencies**: Check for GPL/restrictive licenses in dependencies

#### Maintenance & Support
- **Status**: ✅ Actively Maintained
- **Repository**: [AlaSQL/alasql](https://github.com/AlaSQL/alasql)
- **Community**: 7,217 stars on GitHub
- **Downloads**: [151,480 weekly downloads](https://npm-stat.com/charts.html?package=alasql) (650k+ monthly installs)
- **Funding**: ⚠️ Unfunded open source project
- **Latest Release**: [v4.10.1 (November 21, 2025)](https://github.com/AlaSQL/alasql/releases/tag/v4.10.1)
- **Health Score**: [Healthy maintenance status](https://snyk.io/advisor/npm-package/alasql)
  - ✅ At least 1 release in past 3 months
  - ✅ Community engagement (PRs/issues)
  - ✅ Active development

**Recent Activity**:
- January 2025: Active issues
- December 2024: Updates
- November 2024: Version release

#### CVE Response Process
- **Vulnerability Reporting**: GitHub issues
- **Response Time**: Previous vulnerability took 4+ years to fix (2017 → 2021)
- **Tracking**: Primarily via Snyk, no formal CVE assignments
- **Transparency**: ⚠️ Limited - vulnerability wasn't assigned CVE number

**Risk Assessment**: ⭐⭐⭐ **Medium Risk**
- Known high-severity vulnerability (though patched)
- Slow historical response to security issues
- Active but unfunded project
- Use with caution, verify version >= 0.7.0
- Avoid untrusted input in SQL strings

---

### 3. PGlite (ElectricSQL)

#### Security & CVEs
**Status**: ✅ No known CVEs for PGlite specifically

**Security Considerations**:
- **Upstream**: Based on [PostgreSQL](https://www.postgresql.org/support/security/) which has excellent security practices
- **CVE Authority**: PostgreSQL Project is a CVE Numbering Authority (CNA)
- **Recent PostgreSQL CVE**: [CVE-2025-1094](https://www.postgresql.org/support/security/CVE-2025-1094/) - libpq quoting APIs vulnerability
  - **Impact on PGlite**: Unknown if affected (check project advisories)
  - **Nature**: Improper neutralization in PQescapeLiteral(), PQescapeIdentifier()

**Security Advantages**:
- Inherits PostgreSQL's mature security model
- WASM sandboxing provides isolation
- No network exposure by default
- Active upstream security monitoring

**Security Recommendations**:
```javascript
// ✅ Use parameterized queries (PostgreSQL best practice)
await db.query('SELECT * FROM users WHERE id = $1', [userId]);

// ❌ Never concatenate user input
await db.query(`SELECT * FROM users WHERE id = '${userId}'`);
```

#### Licensing
- **License**: Dual-licensed
  - [Apache License 2.0](https://electric-sql.com/product/pglite)
  - PostgreSQL License
- **Choice**: You can choose either license
- **Commercial Use**: ✅ Allowed under both
- **Patent Grant**: ✅ Apache 2.0 provides patent protection
- **Source**: [GitHub - electric-sql/pglite](https://github.com/electric-sql/pglite)

#### Maintenance & Support
- **Status**: ✅ Very Active
- **Developer**: ElectricSQL (funded company)
- **Project Age**: Relatively new (2024)
- **Maturity**: ⚠️ Early stage but rapidly developing
- **Latest Release**: ElectricSQL v0.11 (May 2024) with PGlite support
- **Activity**: Regular updates and releases
- **Community**: Growing
- **Size**: 3MB gzipped

**Funding & Sustainability**:
- ✅ Backed by [ElectricSQL](https://electric-sql.com/) company
- ✅ Commercial backing suggests long-term viability
- ✅ Active blog and development roadmap

**Recent Milestones**:
- 2024: PGlite released with client-server sync
- Ongoing: pgvector support and extensions

#### CVE Response Process
- **Upstream**: Inherits PostgreSQL's CVE process (excellent)
- **PostgreSQL CNA**: Works with Red Hat as CNA Root
- **PGlite-Specific**: No formal published policy yet
- **Transparency**: PostgreSQL security page is exemplary

**Risk Assessment**: ⭐⭐⭐⭐ **Low-Medium Risk**
- Very new project (limited production testing)
- Excellent upstream security (PostgreSQL)
- Commercial backing
- Active development
- Larger size may increase attack surface
- Good choice for new projects accepting early-stage tech

---

### 4. Lovefield (Google)

#### Security & CVEs
**Status**: ⚠️ Unknown - Project Archived

- **Search Results**: [No CVEs found](https://www.cvedetails.com/vulnerability-list/vendor_id-1224/Google.html)
- **Archived**: [January 10, 2023](https://github.com/google/lovefield)
- **Read-Only**: No new security patches possible
- **Historical Scrutiny**: Limited (no CVEs doesn't mean secure, might mean unexamined)

**Security Implications of Archive**:
- ❌ No security updates
- ❌ No vulnerability patches
- ❌ No active monitoring
- ⚠️ Unknown vulnerabilities may exist
- ⚠️ Modern browser changes may expose issues

#### Licensing
- **License**: [Apache-2.0 License](https://github.com/google/lovefield)
- **Commercial Use**: ✅ Allowed
- **Patent Grant**: ✅ Apache license includes patent protection
- **Google CLA**: Original contributors signed Google CLA

#### Maintenance & Support
- **Status**: ❌ **ARCHIVED** (Not Maintained)
- **Archived Date**: January 10, 2023
- **Repository**: [google/lovefield](https://github.com/google/lovefield) (read-only)
- **Community**: 6.8k stars, 365 forks, 27 contributors
- **Dependents**: 299 projects still depend on it
- **Last Activity**: 2023 (pre-archive)
- **Commits**: 1,131 total
- **Releases**: 19 tags

**Why Archived?**:
- No official statement found
- Google's pattern: Archive projects with limited adoption
- Shift to newer technologies (IndexedDB improvements, WebSQL deprecation)

**Successor Projects**: None officially announced

#### CVE Response Process
- **Status**: ❌ None (project archived)
- **Historical**: No formal process documented
- **Current**: No security updates possible

**Risk Assessment**: ⭐ **High Risk - DO NOT USE**
- No security updates
- Archived status
- Unknown vulnerabilities won't be patched
- Modern browser compatibility uncertain
- Better alternatives available

**Migration Recommended**:
If currently using Lovefield, migrate to:
1. sql.js (similar SQL API)
2. Native IndexedDB (Google's implied direction)
3. AlaSQL (if you need the specific features)

---

### 5. Absurd-SQL

#### Security & CVEs
**Status**: ⚠️ Inherits sql.js security + adds complexity

- **Base**: Built on sql.js (inherits its security profile)
- **Additional Layer**: Custom IndexedDB backend
- **CVEs**: None specific to Absurd-SQL
- **Attack Surface**: Larger (adds Worker and IndexedDB layer)

**Security Considerations**:
```javascript
// Absurd-SQL requires Web Worker
// Additional attack surface: Worker communication, IndexedDB operations
// Same SQL injection concerns as sql.js
```

#### Licensing
- **License**: MIT License
- **Dependencies**: sql.js (MIT), IndexedDB backend (MIT)
- **Commercial Use**: ✅ Allowed

#### Maintenance & Support
- **Status**: ⚠️ Limited Activity
- **Repository**: [jlongster/absurd-sql](https://github.com/jlongster/absurd-sql)
- **Developer**: Individual maintainer (James Long)
- **Activity**: Sporadic updates
- **Community**: Smaller than sql.js
- **Maturity**: Experimental/"absurd" (by name)

**Concerns**:
- Single maintainer
- Not as widely adopted
- More complex setup
- Limited commercial backing

#### CVE Response Process
- **Process**: Inherits sql.js process
- **Additional Concerns**: IndexedDB backend bugs
- **Response**: Depends on maintainer availability

**Risk Assessment**: ⭐⭐⭐ **Medium Risk**
- Adds complexity to proven sql.js
- Limited maintenance resources
- Smaller community
- Use only if you specifically need persistent large databases
- Consider PGlite as alternative

---

## Comparison Matrix

### Security Posture

| Framework | Known CVEs | Last CVE | Security Policy | Response Time | Risk Level |
|-----------|------------|----------|-----------------|---------------|------------|
| sql.js | 0 | N/A | Basic | Unknown | ⭐⭐⭐⭐⭐ Low |
| AlaSQL | 1 (Fixed) | 2021 | Limited | Slow (4 years) | ⭐⭐⭐ Medium |
| PGlite | 0 | N/A | Inherits PostgreSQL | Fast (upstream) | ⭐⭐⭐⭐ Low-Med |
| Lovefield | 0 (Archived) | N/A | None | None | ⭐ High |
| Absurd-SQL | 0 | N/A | Inherits sql.js | Depends | ⭐⭐⭐ Medium |

### Licensing Comparison

| Framework | License | Commercial OK | Patent Grant | Copyleft | Attribution |
|-----------|---------|---------------|--------------|----------|-------------|
| sql.js | MIT | ✅ | ❌ | ❌ | Required |
| AlaSQL | MIT | ✅ | ❌ | ❌ | Required |
| PGlite | Apache 2.0 / PostgreSQL | ✅ | ✅ | ❌ | Required |
| Lovefield | Apache 2.0 | ✅ | ✅ | ❌ | Required |
| Absurd-SQL | MIT | ✅ | ❌ | ❌ | Required |

### Maintenance Status

| Framework | Status | Last Release | Funding | Contributors | Weekly Downloads |
|-----------|--------|--------------|---------|--------------|------------------|
| sql.js | ✅ Active | 2024-2025 | Community | Multiple | ~50k |
| AlaSQL | ✅ Active | Nov 2025 | None | Multiple | ~150k |
| PGlite | ✅ Very Active | 2024-2025 | ElectricSQL | Growing | Growing |
| Lovefield | ❌ Archived | 2023 | None | Frozen | Declining |
| Absurd-SQL | ⚠️ Limited | Sporadic | None | 1-2 | Low |

### CVE Response History

| Framework | Total CVEs | Fixed | Unfixed | Avg Response Time | Transparency |
|-----------|------------|-------|---------|-------------------|--------------|
| sql.js | 0 | 0 | 0 | N/A | Good |
| AlaSQL | 1+ | 1 | Unknown | ~4 years | Limited |
| PGlite | 0 | 0 | 0 | N/A (new) | Excellent (upstream) |
| Lovefield | 0 | 0 | Unknown | N/A (archived) | None |
| Absurd-SQL | 0 | 0 | 0 | Unknown | Minimal |

## Recommendations by Use Case

### For Production Enterprise Applications
**Recommended**: **sql.js** or **PGlite**

**sql.js**:
- ✅ Proven track record
- ✅ No known vulnerabilities
- ✅ Active maintenance
- ✅ Large community
- ✅ MIT license (simple)
- ⚠️ Manual persistence required

**PGlite**:
- ✅ Advanced PostgreSQL features
- ✅ Commercial backing
- ✅ Apache 2.0 (patent protection)
- ✅ Auto-persistence
- ⚠️ Newer/less battle-tested
- ⚠️ Larger bundle size

### For Rapid Prototyping
**Recommended**: **AlaSQL** (with caution)

- ✅ Easy to use
- ✅ Works with arrays directly
- ✅ Good for demos
- ⚠️ Ensure version >= 0.7.0
- ⚠️ Don't use with untrusted input
- ⚠️ Not for sensitive data

### For Security-Critical Applications
**Recommended**: **sql.js**

- ✅ Minimal attack surface
- ✅ Battle-tested SQLite base
- ✅ No network exposure
- ✅ Sandboxed in WASM
- ✅ No known CVEs

**Alternative**: **PGlite** (if you need PostgreSQL features)
- ✅ Inherits PostgreSQL security
- ✅ CNA process upstream
- ⚠️ Monitor PostgreSQL advisories

### For Large Datasets (> 100MB)
**Recommended**: **PGlite** or **Absurd-SQL**

**PGlite**:
- ✅ Built for larger data
- ✅ Better performance at scale
- ✅ Active development

**Absurd-SQL**:
- ✅ True persistent IndexedDB
- ⚠️ More complex
- ⚠️ Less maintained

### What to AVOID

**❌ Lovefield**:
- Archived, no security updates
- Use sql.js or IndexedDB instead

**❌ Unmaintained forks**:
- Check last commit date
- Verify active issue tracker

## Security Best Practices

### 1. Always Use Parameterized Queries

```javascript
// ✅ SAFE
db.run('INSERT INTO users VALUES (?, ?)', [username, password]);
db.query('SELECT * FROM data WHERE id = $1', [userId]);
alasql('SELECT * FROM ? WHERE value > ?', [data, threshold]);

// ❌ DANGEROUS - SQL Injection
db.run(`INSERT INTO users VALUES ('${username}', '${password}')`);
db.query(`SELECT * FROM data WHERE id = '${userId}'`);
alasql(`SELECT * FROM data WHERE value > ${threshold}`);
```

### 2. Keep Dependencies Updated

```bash
# Check for updates
npm outdated

# Update to latest (verify compatibility)
npm update sql.js
npm update alasql
npm update @electric-sql/pglite

# Audit for vulnerabilities
npm audit
npm audit fix
```

### 3. Monitor Security Advisories

- **sql.js**: Watch [GitHub security advisories](https://github.com/sql-js/sql.js/security)
- **AlaSQL**: Monitor [Snyk database](https://security.snyk.io/package/npm/alasql)
- **PGlite**: Follow [PostgreSQL security](https://www.postgresql.org/support/security/)
- **General**: Subscribe to [GitHub Advisory Database](https://github.com/advisories)

### 4. Implement Content Security Policy (CSP)

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self';
               script-src 'self' 'wasm-unsafe-eval';
               worker-src 'self' blob:;">
```

### 5. Validate All Inputs

```javascript
// Even with parameterized queries, validate input
function sanitizeInput(value) {
    if (typeof value !== 'string') return value;

    // Remove dangerous characters
    return value.replace(/[<>\"']/g, '');
}

const safeUsername = sanitizeInput(userInput);
db.run('INSERT INTO users (name) VALUES (?)', [safeUsername]);
```

### 6. Limit Database Permissions

```javascript
// For sql.js: Run in isolated context
const worker = new Worker('db-worker.js');
worker.postMessage({ query: 'SELECT * FROM data' });

// For PGlite: Use database roles
await db.query('CREATE ROLE readonly');
await db.query('GRANT SELECT ON ALL TABLES TO readonly');
```

### 7. Regular Security Audits

```bash
# Use automated tools
npm install -g snyk
snyk test

# Use npm audit
npm audit --audit-level=moderate

# Check for outdated packages
npm outdated
```

## Final Recommendation for PSWebHost

### Primary Choice: **sql.js** ⭐

**Rationale**:
1. ✅ **Zero known CVEs** - Clean security record
2. ✅ **Active maintenance** - Regular updates following SQLite
3. ✅ **MIT License** - Simple, permissive
4. ✅ **Battle-tested** - 13.5k stars, widely used
5. ✅ **Standard SQL** - Familiar syntax
6. ✅ **Minimal risk** - WASM isolation, no network exposure
7. ✅ **Right size** - 800KB is reasonable for the value

**Implementation Steps**:
1. Download sql-wasm.js and sql-wasm.wasm
2. Add to `/public/lib/`
3. Integrate with MetricsManager
4. Implement IndexedDB persistence
5. Use prepared statements exclusively
6. Monitor GitHub for security advisories

### Backup Choice: **PGlite**

**If you need**:
- Advanced PostgreSQL features (CTEs, window functions, JSON)
- Built-in persistence
- Growing ecosystem
- Patent protection (Apache 2.0)

**Trade-offs**:
- Larger size (3MB)
- Newer/less proven
- More complexity

### Avoid:
- ❌ **Lovefield** - Archived, no updates
- ⚠️ **AlaSQL** - Use only for non-critical, internal tools
- ⚠️ **Absurd-SQL** - Unless you specifically need its features

## Sources

- [CVE Details - 2024 Vulnerabilities](https://www.cvedetails.com/vulnerability-list/year-2024/vulnerabilities.html)
- [sql.js GitHub Repository](https://github.com/sql-js/sql.js)
- [sql.js Security Overview](https://github.com/sql-js/sql.js/security)
- [AlaSQL Arbitrary Code Injection - Snyk](https://security.snyk.io/vuln/SNYK-JS-ALASQL-1082932)
- [AlaSQL GitHub Repository](https://github.com/AlaSQL/alasql)
- [AlaSQL npm Package](https://www.npmjs.com/package/alasql)
- [AlaSQL Release v4.10.1](https://github.com/AlaSQL/alasql/releases/tag/v4.10.1)
- [PGlite - ElectricSQL](https://electric-sql.com/product/pglite)
- [PGlite GitHub Repository](https://github.com/electric-sql/pglite)
- [PostgreSQL Security](https://www.postgresql.org/support/security/)
- [PostgreSQL CVE-2025-1094](https://www.postgresql.org/support/security/CVE-2025-1094/)
- [Lovefield GitHub Repository](https://github.com/google/lovefield)
- [Google CVEs](https://www.cvedetails.com/vulnerability-list/vendor_id-1224/Google.html)
