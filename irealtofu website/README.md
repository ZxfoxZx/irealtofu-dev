# IRealtofu.dev starter website

A responsive, static personal portfolio site built with HTML, CSS, and vanilla JavaScript.

## Files
- `index.html` — page content
- `styles.css` — layout, responsive styling, and warm color palette
- `script.js` — mobile navigation, reveal animations, and current year

## Before publishing
In `index.html`, replace the placeholder `href="#"` values for CurseForge, GitHub, and Discord with your real profile/project URLs.

## Deploying with Cloudflare Workers static assets
Upload these files to the root of your `irealtofu-dev` GitHub repository. The deploy command configured in Cloudflare should be:
`npx wrangler deploy --assets .`

The repository root should contain `index.html`, `styles.css`, and `script.js`.

// N/A