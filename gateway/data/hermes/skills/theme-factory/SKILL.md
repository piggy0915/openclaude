---
name: theme-factory
description: Toolkit for styling artifacts with a theme. These artifacts can be slides, docs, reports, HTML landing pages, etc. There are 10 pre-set themes with colors/fonts that you can apply to any artifact that has been created, or can generate a new theme on-the-fly. Trigger when user asks to apply a theme, style a deck/document, pick a color scheme, or create a custom theme.
license: Complete terms in LICENSE.txt
---

# Theme Factory Skill

This skill provides a curated collection of professional font and color themes, each with carefully selected color palettes and font pairings. Once a theme is chosen, it can be applied to any artifact.

## Workflow

### Step 1: Determine Approach

| Situation | Action |
|-----------|--------|
| User has a specific theme in mind | Skip to Step 3 (Apply) |
| User wants to browse themes | Go to Step 2 (Showcase) |
| No existing theme fits the context | Go to Step 4 (Custom Theme) |

**Checkpoint**: If unclear, ask: "Do you have a theme in mind, want to browse the 10 presets, or need a custom theme?"

### Step 2: Show Themes

Display the theme showcase for visual browsing:

```bash
# Show the theme showcase PDF (read-only, do not modify)
Read .claude/skills/theme-factory/theme-showcase.pdf
```

If `theme-showcase.pdf` is not found or cannot be read, list the themes by name with descriptions:

| # | Theme | Vibe |
|---|-------|------|
| 1 | Ocean Depths | Professional, calming maritime |
| 2 | Sunset Boulevard | Warm, vibrant sunset colors |
| 3 | Forest Canopy | Natural, grounded earth tones |
| 4 | Modern Minimalist | Clean, contemporary grayscale |
| 5 | Golden Hour | Rich, warm autumnal palette |
| 6 | Arctic Frost | Cool, crisp winter-inspired |
| 7 | Desert Rose | Soft, sophisticated dusty tones |
| 8 | Tech Innovation | Bold, modern tech aesthetic |
| 9 | Botanical Garden | Fresh, organic garden colors |
| 10 | Midnight Galaxy | Dramatic, cosmic deep tones |

**Checkpoint**: Ask "Which theme would you like?" Wait for explicit selection.

### Step 3: Apply Theme

1. **Read the theme file**: `Read .claude/skills/theme-factory/themes/{theme-name}.md`
2. **Extract specifications**: Identify the color palette (hex codes) and font pairings from the theme file
3. **Apply to artifact**, following these rules:

**Color Application:**
- **Background**: Use the theme's primary/lightest color for page/slide backgrounds
- **Text**: Use the theme's darkest color for body text; accent color for headings
- **Shapes/Accents**: Use the theme's secondary/accent color(s) for borders, shapes, icons
- **Data visualizations**: Preserve original data colors; theme only the surrounding elements

**Typography Application:**
- **Headings**: Use the theme's header font (or system fallback if unavailable)
- **Body text**: Use the theme's body font (or system fallback if unavailable)
- **Size hierarchy**: Maintain original font sizes; only change font family and color

**Consistency Check:**
- Verify contrast ratios are readable (dark text on light bg, or light text on dark bg)
- Ensure the same colors and fonts appear consistently across all pages/slides
- If a theme element doesn't suit a particular slide (e.g., dark text on a dark image), use the theme's lightest color for text on that slide

### Step 4: Custom Theme (Optional)

When no preset theme fits:

1. **Gather context**: Ask the user about the artifact's purpose, audience, and desired tone
2. **Generate theme**: Create a new theme with:
   - A descriptive name (e.g., "Healthcare Horizon", "Industrial Edge")
   - 3-5 cohesive hex colors (primary, background, text, 1-2 accents)
   - A font pairing (header + body) — use system-available fonts
3. **Show for review**: Present the generated theme spec for user approval before applying
4. **Apply**: Once approved, follow Step 3

## Available Themes

| # | Theme | Primary Colors | Best For |
|---|-------|---------------|----------|
| 1 | Ocean Depths | Deep blues, teal, white | Corporate, finance, consulting |
| 2 | Sunset Boulevard | Warm orange, coral, cream | Creative, marketing, lifestyle |
| 3 | Forest Canopy | Forest green, brown, beige | Sustainability, outdoors, wellness |
| 4 | Modern Minimalist | Black, white, gray | Tech, architecture, luxury |
| 5 | Golden Hour | Gold, amber, dark brown | Premium, hospitality, autumn events |
| 6 | Arctic Frost | Ice blue, white, silver | Healthcare, tech, winter themes |
| 7 | Desert Rose | Dusty rose, terracotta, cream | Fashion, beauty, feminine brands |
| 8 | Tech Innovation | Electric blue, dark navy, cyan | SaaS, AI, startup pitches |
| 9 | Botanical Garden | Sage green, floral pink, cream | Organic products, gardening, spring |
| 10 | Midnight Galaxy | Deep purple, black, gold | Gaming, space, premium night events |

Full specifications in `themes/` directory. Read the theme file for exact hex codes and font names.

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| `theme-showcase.pdf` unreadable | Use the text table in Step 2 as fallback |
| Theme file not found in `themes/` | List available themes via `Glob .claude/skills/theme-factory/themes/*.md`; if still missing, offer to create a custom theme |
| User picks a theme, then changes mind | Restart from Step 2; do not mix themes |
| Artifact type unsupported by theme | Apply only colors and fonts that make sense; skip elements the artifact type doesn't support |
| Multiple artifacts need theming | Apply the same theme consistently across all; note any per-artifact adjustments |
| System fonts unavailable | Document which fonts couldn't be applied; use fallback fonts from the theme file or system defaults |
| User wants to modify an existing theme | Treat as custom theme (Step 4) using the existing theme as a starting point |
