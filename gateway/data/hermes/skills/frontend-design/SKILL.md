---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications (examples include websites, landing pages, dashboards, React components, HTML/CSS layouts, or when styling/beautifying any web UI). Generates creative, polished code and UI design that avoids generic AI aesthetics.
license: Complete terms in LICENSE.txt
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

## Workflow

### Step 1: Understand Context

Extract from the user's request:
- **What** are they building? (landing page, dashboard, component, full app?)
- **Who** is it for? (audience, brand, industry)
- **Constraints**? (framework, mobile, accessibility, performance)

If any of these are unclear, ask before proceeding.

### Step 2: Design Direction (present before coding)

Commit to a BOLD aesthetic and present a brief direction card:

```
**Aesthetic**: [e.g., "Brutalist Editorial" / "Organic Minimalism" / "Retro-Futuristic"]
**Color Direction**: [dominant color + 1-2 accents, e.g., "Raw concrete grays with neon amber accents"]
**Typography**: [display font + body font, e.g., "DM Serif Display + JetBrains Mono"]
**Key Visual**: [the ONE thing people will remember, e.g., "Massive bleeding typography that breaks the grid"]
**Motion Strategy**: [e.g., "Staggered reveals on scroll" / "Subtle hover micro-interactions" / "No motion"]
```

**Checkpoint**: Present this to the user. Ask: "Does this direction feel right? Any adjustments?"

### Step 3: Determine Technical Approach

| User Specified | Action |
|---------------|--------|
| Framework specified (React, Vue, etc.) | Use it |
| No framework | Default: single HTML file with inline CSS/JS (fastest to deliver) |
| "Artifact" or "claude.ai artifact" | Single HTML file |
| Needs routing/state management | Offer React + simple router or keep single-page |
| Mobile-first required | Add responsive breakpoints; test at 375px and 1440px |

### Step 4: Implement

Build working code following these design principles:

**Typography:**
- Choose distinctive, beautiful fonts (Google Fonts CDN for HTML; @import or npm for frameworks)
- Avoid: Inter, Roboto, Arial, system fonts, Space Grotesk
- Pair a characterful display font with a refined body font
- Use `font-display: swap` for performance

**Color & Theme:**
- Commit to a cohesive palette. Dominant colors with sharp accents outperform timid palettes
- Use CSS variables for consistency
- Avoid: purple gradients on white, evenly-distributed palettes

**Motion:**
- CSS-only animations for HTML files. Motion library (framer-motion) for React
- Focus on high-impact moments: staggered reveals, scroll-triggered entrances
- Use `prefers-reduced-motion` for accessibility
- One well-orchestrated page load > scattered micro-interactions

**Spatial Composition:**
- Asymmetry, overlap, diagonal flow, grid-breaking elements
- Generous negative space OR controlled density — pick one
- Avoid centered everything

**Backgrounds & Texture:**
- Gradient meshes, noise textures, geometric patterns, grain overlays
- No flat solid-color backgrounds without purpose

### Step 5: Verify

Before delivering:
- [ ] Code runs without errors (check console)
- [ ] Design matches the direction card from Step 2
- [ ] No generic fonts or cliched colors crept in
- [ ] Responsive at specified breakpoints (if applicable)
- [ ] Animations work and don't cause layout shift

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| No framework specified | Default to single HTML file |
| User wants brand colors applied | Integrate brand colors into the aesthetic direction; don't force-fit |
| Accessibility required (WCAG) | Maintain 4.5:1 contrast ratio; add aria labels; respect prefers-reduced-motion |
| Dark/light mode needed | Implement both using CSS custom properties + prefers-color-scheme |
| Existing codebase | Match existing patterns for consistency; apply creative direction only to new components |
| Very short request (e.g., "make a button") | Still apply distinct styling; even a button can be memorable |
| User rejects design direction | Return to Step 2 with feedback; present new direction |

## Anti-Patterns

NEVER use:
- Inter, Roboto, Arial, Space Grotesk, or system fonts as primary choices
- Purple gradients on white backgrounds
- Centered hero with rounded corners and soft shadows
- Cookie-cutter layouts that could be any SaaS landing page
- The same design twice — vary between light/dark, serif/sans, minimal/maximal
