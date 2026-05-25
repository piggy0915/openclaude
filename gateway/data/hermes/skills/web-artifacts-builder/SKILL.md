---
name: web-artifacts-builder
description: Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts. Trigger when user asks to build a Claude artifact, web app artifact, React artifact, or multi-component interactive HTML bundle.
license: Complete terms in LICENSE.txt
---

# Web Artifacts Builder

Build complex claude.ai HTML artifacts with React 18 + TypeScript + Vite + Tailwind CSS + shadcn/ui, bundled to a single HTML file via Parcel.

## Workflow

### Step 1: Initialize Project

```bash
bash scripts/init-artifact.sh <project-name>
cd <project-name>
```

This creates:
- React 18 + TypeScript (via Vite)
- Tailwind CSS 3.4.1 with shadcn/ui theming
- Path aliases (`@/`) configured
- 40+ shadcn/ui components pre-installed
- Parcel bundling configured (`.parcelrc`)
- Node 18+ compatibility (auto-detects Vite version)

**If init fails**:
- Check Node.js version (`node --version`): requires 18+
- Check disk space and write permissions
- If `scripts/init-artifact.sh` not found, verify working directory is project root

### Step 2: Develop the Artifact

Edit files in the generated project. Key locations:

| What to change | Where |
|---------------|-------|
| Main app component | `src/App.tsx` |
| Page layouts | `src/pages/` or `src/App.tsx` |
| Reusable components | `src/components/` |
| Tailwind config | `tailwind.config.js` |
| Global styles | `src/index.css` |

**Development tips**:
- Use shadcn/ui components directly (they're pre-installed): `import { Button } from "@/components/ui/button"`
- For new shadcn components, use `npx shadcn-ui@latest add <component-name>`
- Keep all logic in one or few files for easier bundling
- Use Tailwind classes for styling — they inline well during bundling

**Design guideline**: Avoid generic AI aesthetics (centered layouts, purple gradients, Inter font, uniform rounded corners). Apply distinctive design choices.

**Checkpoint**: After initial development, verify the dev server works (`npm run dev`). Present a summary of what was built before bundling.

### Step 3: Bundle to Single HTML

```bash
bash scripts/bundle-artifact.sh
```

This produces `bundle.html` — a self-contained file with all JS, CSS, and dependencies inlined.

**Requirements**: `index.html` must exist in project root.

**If bundle fails**:
- Ensure `index.html` exists in project root
- Run `npm install` to restore missing dependencies
- Check for import errors or TypeScript compilation failures (`npx tsc --noEmit`)
- If Parcel errors persist, try `npx parcel build index.html --no-source-maps` directly

### Step 4: Deliver Artifact

Share `bundle.html` with the user as a Claude artifact.

### Step 5: Test (Optional)

Only test if the user requests it or if issues arise. Use Playwright/Puppeteer or the webapp-testing skill. Skip testing by default to minimize latency.

## Reference

- **shadcn/ui components**: https://ui.shadcn.com/docs/components

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| `init-artifact.sh` missing | Verify in `.claude/skills/web-artifacts-builder/scripts/`; if absent, report to user |
| Node.js < 18 | Tell user to upgrade Node; suggest `nvm install 18` |
| Port already in use during dev | Use `--port 3000` or kill existing process |
| `bundle-artifact.sh` fails with Parcel errors | Run `npx tsc --noEmit` to find TypeScript errors first |
| User wants simple single-file artifact | This skill is overkill; suggest writing a plain HTML file instead |
| `npm install` fails | Check network; try `npm install --legacy-peer-deps` |
| Project already exists | Ask user: "Overwrite, merge, or use a different project name?" |
