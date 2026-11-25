---
name: generative_ui
description: Generate offline, runnable, visually rich FlowOS HTML applications and compact widgets.
---
# FlowOS Generative UI Skill

## Output contract
Return one complete HTML document, with meaningful title, inline CSS and JavaScript, and fully implemented interactions. No Markdown or JSON-only app definition. The harness extracts the document, performs static checks, runs an isolated WebKit startup check, and saves successful results as runnable artifacts. One repair pass is permitted per build approval. Failed or interrupted source stays a draft, never marked runnable.

## Visual system
Use semantic host CSS variables for all colors, typography of at least 12px, accessible contrast, 44px touch targets, responsive mobile layouts, CSS spring-like transitions, and reduced-motion support. Use inline SVG and Canvas for charts; redraw on themechange. Compact previews target 450px, transparent and flush, with no viewport-relative top-level height. Larger experiences use scrolling standalone pages and grouped panels. No external dependencies, including CDN Tailwind. Use equivalent inline CSS and native browser primitives.

## Runtime
FlowOS uses a WKWebView with a nonpersistent website data store, a sandboxed iframe without same-origin permissions, content security policy, blocked network resource rules and restricted navigation. Generated code receives no device-control bridge, API credentials or access to other applications. Only app-scoped JSON state is allowed (64 KiB) through FlowOS.load() and FlowOS.save(value); state is stored separately for each artifact revision. Use textContent for user data, not HTML interpolation. Avoid modal JS dialogs, external resources, eval and uncontrolled loops. Exported HTML receives the same theme and runtime; localStorage support depends on the browser. Define window.flowSelfTest returning a meaningful boolean for pure core-logic tests. Preview and test actual interaction before relying on results.

## Agent workflow
1. Interpret user request and implement a focused complete app.
2. Stream HTML generation in Labs.
3. Validate document structure, size, offline constraints.
4. Launch sandbox smoke test and capture startup errors and supplied self-test.
5. Repair once on a failed validation; preserve failed drafts.
6. Publish runnable artifact with app, code, tests and revision tabs.
7. Open immediately, optionally install in library, export or edit source.
8. Revisions use previous source with user approval and save a separate copy.

## Host differences from original skill
FlowOS uses its native artifact store and WKWebView, not an external agent-embed tag, ArtifactMetadata, host-specific variables, or a CDN. Standalone is the default; compact preview is in Labs rather than mixing app creation into Chat. Existing native trackers remain available. App logic and layout are not guaranteed by startup tests; user verification is required.
