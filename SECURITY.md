# Security Policy

Primary project documentation is maintained at **https://docs.sonicverse.eu**. This file covers only security reporting expectations for this repository.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please use [GitHub's private vulnerability reporting](https://github.com/sonicverse-eu/audiostreaming-stack/security/advisories/new) to disclose issues confidentially.

Include the following in your report:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fix or mitigation

We will acknowledge your report within 48 hours and aim to release a patch within 14 days for critical issues.

## Scope

**In scope:**
- Command injection via the status panel API
- Authentication bypass in the Appwrite integration
- Container escape via Docker socket exposure
- Secrets leakage through API responses
- CORS misconfigurations that allow unauthorised cross-origin access

**Out of scope:**
- Issues requiring physical access to the server
- Denial of service attacks against a specific deployment
- Social engineering
- Vulnerabilities in third-party dependencies (report those upstream)
