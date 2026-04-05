# Short URL Setup Guide

This document explains how to set up and maintain the short installation link for Sonicverse (`https://sonicverse.short.gy/install-audiostack` or similar).

## Overview

The short URL system allows users to quickly install the Sonicverse stack with a single command:

```bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack)
```

Instead of memorizing or copying long GitHub URLs, users only need the memorable short link.

## Setup Options

Choose one of the following approaches based on your infrastructure:

### Option 1: GitHub Pages (Recommended - Free & Simple)

**Pros:**
- Free hosting
- Automatic updates via GitHub Actions
- No additional infrastructure needed
- Works with custom domain (with CNAME)

**Setup:**

1. Create a GitHub Pages repository (or use existing `sonicverse.github.io` if you have it):
   ```bash
   # If creating new:
   git clone https://github.com/sonicverse-eu/sonicverse.github.io.git
   ```

2. Copy the redirect file:
   ```bash
   cp install-redirect.html sonicverse.github.io/install.html
   ```

3. Configure GitHub Pages in the repository settings:
   - Go to Settings → Pages
   - Source: Deploy from a branch
   - Branch: main, folder: root

4. Access via: `https://sonicverse.github.io/install.html`

5. **For custom domain** (`sonicverse.short.gy`):
   - Register/manage the domain (`short.gy`)
   - Add CNAME records to point to `sonicverse.github.io`:
     ```
     install.sonicverse.short.gy CNAME sonicverse.github.io
     ```
   - Update GitHub Pages custom domain setting
   - Enable HTTPS

### Option 2: Netlify Redirects (Free & Flexible)

**Pros:**
- Excellent redirect management
- Better analytics
- Easy configuration

**Setup:**

1. Create `_redirects` file in repository root:
   ```
   /install-audiostack https://raw.githubusercontent.com/sonicverse-eu/audiostreaming-stack/main/install.sh 200
   ```

2. Deploy to Netlify:
   ```bash
   npm install -g netlify-cli
   netlify deploy
   ```

3. Configure custom domain in Netlify dashboard

### Option 3: Cloudflare Workers (Free & Powerful)

**Pros:**
- Ultra-fast global CDN
- Advanced routing
- Analytics and logging
- Free tier available

**Setup:**

1. Create a Cloudflare Worker:
   ```javascript
   export default {
     async fetch(request) {
       // Redirect short links to the install script
       if (request.url.includes('/install-audiostack')) {
         return Response.redirect(
           'https://raw.githubusercontent.com/sonicverse-eu/audiostreaming-stack/main/install.sh',
           301
         );
       }
       return new Response('Not found', { status: 404 });
     }
   };
   ```

2. Bind to your domain
3. Enable caching for maximum performance

### Option 4: Self-Hosted Redirect Service (Max Control)

For complete control, run your own redirect service:

**Using Docker:**

```dockerfile
FROM nginx:alpine

RUN echo '
server {
  listen 80;
  server_name _;
  
  location /install-audiostack {
    return 301 https://raw.githubusercontent.com/sonicverse-eu/audiostreaming-stack/main/install.sh;
  }
}
' > /etc/nginx/conf.d/default.conf

EXPOSE 80
```

Deploy as a containerized service behind your reverse proxy.

### Option 5: Third-Party URL Shortener

Use services like:
- **bit.ly** - Analytics, branded links
- **short.link** - Custom domains
- **TinyURL** - Simple, privacy-focused
- **is.gd** - Free, no tracking

Simply create a shortened link and document it.

## Maintenance & Testing

### Verify the Short Link Works

```bash
# Test HTTP redirect
curl -I https://sonicverse.short.gy/install-audiostack

# Test curl piping (local test)
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack) --help
```

### Update the Target Script

When `install.sh` is updated in the repository:

- **GitHub Pages/Netlify/Cloudflare:** Automatically updates (points to `main` branch)
- **Self-hosted:** Redeploy with the latest redirect logic
- **Third-party shortener:** URLs are stable; no action needed

### Monitor Link Usage

Enable optional analytics with:
- **Cloudflare Analytics:** Built-in for Workers
- **Netlify Analytics:** Included in Pro plan
- **bit.ly API:** Track clicks and geographic data
- **Server logs:** Self-hosted solutions provide full control

## Documentation

Once configured, update:

1. **README.md** - Add quick install section
2. **docs.sonicverse.eu** - Link to short URL
3. **Presentation slides** - Use memorable short link
4. **Chat/forums** - Easier sharing

## Example Documentation Section

Add this to the README after "Quick Start":

```markdown
### ⚡ One-liner Installation

For the fastest setup on systems with Docker already installed:

\`\`\`bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack)
\`\`\`

Or with development dependencies:

\`\`\`bash
bash <(curl -fsSL https://sonicverse.short.gy/install-audiostack) --dev
\`\`\`
```

## Troubleshooting

### "Command not found: bash" or "command not found: curl"

- Ensure bash and curl are installed on the target system
- Some minimal container images may require installation first

### Redirect loops or timeouts

- Verify the target URL is correct and accessible
- Check that the redirect isn't pointing back to itself
- Test with: `curl -I -L https://sonicverse.short.gy/install-audiostack`

### HTTPS/Certificate errors

- Ensure both your short URL and target are HTTPS
- For GitHub Pages, wait for SSL certificate provisioning (5-10 minutes)
- For custom domains, ensure DNS and CNAME records are correct

## Security Considerations

1. **Always HTTPS:** The short link and target must be HTTPS
2. **Verify Repository:** Users should verify they're running from `sonicverse-eu/audiostreaming-stack`
3. **Audit Script Updates:** Review changes before they're linked from short URLs
4. **Monitor for Abuse:** Watch for unexpected redirect traffic patterns

## GitHub Actions Automation

To automatically publish updates to GitHub Pages when install.sh changes:

```yaml
name: Deploy Install Redirect

on:
  push:
    branches: [main]
    paths:
      - install-redirect.html
      - .github/workflows/deploy-redirect.yml

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: .
          include_files: |
            install-redirect.html
```

## Support

- For domain issues: Check DNS records with `nslookup sonicverse.short.gy`
- For service status: Monitor your chosen host platform
- For script issues: File issues on the [main repository](https://github.com/sonicverse-eu/audiostreaming-stack)
