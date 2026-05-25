---
name: brand-guidelines
description: Applies Anthropic's official brand colors and typography to any sort of artifact that may benefit from having Anthropic's look-and-feel. Trigger when user mentions brand colors, style guidelines, visual formatting, corporate identity, company design standards, Anthropic branding, or requests to make something "on-brand."
license: Complete terms in LICENSE.txt
---

# Anthropic Brand Styling

## Overview

Apply Anthropic's official brand identity to artifacts (presentations, documents, web pages, reports, posters, etc.). This skill provides the color palette, typography rules, and a structured application workflow.

## Workflow

Follow these steps when applying brand styling. Do not skip steps.

### Step 1: Identify Artifact & Context

Determine what you're styling:

| Artifact Type | Typical Tools | Key Considerations |
|--------------|---------------|-------------------|
| Presentation (.pptx) | python-pptx | Slide backgrounds, text runs, shapes |
| Document (.docx) | python-docx | Paragraph styles, headings, page color |
| Web page (HTML/CSS) | CSS variables | Background, text, accents, hover states |
| PDF/Report | ReportLab/fpdf2 | Page background, text elements, charts |
| Image/Poster | Pillow/cairo | Canvas color, text overlays, shapes |

**Checkpoint**: If the artifact type is unclear, ask the user: "What format is this artifact — presentation, document, web page, or something else?"

### Step 2: Determine Background Mode

Choose the color scheme based on background:

- **Light background** → Light (`#faf9f5`) or Light Gray (`#e8e6dc`) background; Dark (`#141413`) text
- **Dark background** → Dark (`#141413`) background; Light (`#faf9f5`) text
- **Mixed/Hybrid** → Use dark for title/section-openers, light for content slides

If the user hasn't specified, default to light background with dark text — it maximizes readability.

### Step 3: Apply Brand Elements

Apply systematically in this order:

1. **Background color** — Set on all pages/slides
2. **Typography** — Headings in Poppins (≥24pt), body in Lora; fall back to Arial/Georgia if Poppins/Lora unavailable
3. **Text colors** — Heading text and body text per background mode (Step 2)
4. **Accent colors** — Apply to non-text shapes, borders, icons in this priority: Orange (`#d97757`) → Blue (`#6a9bcc`) → Green (`#788c5d`). Cycle through accents when multiple shapes exist
5. **Secondary elements** — Use Mid Gray (`#b0aea5`) for borders, dividers, less important text

**Checkpoint**: After applying, describe what was done and ask: "Does this look right? Any elements you'd like adjusted?"

## Brand Specifications

### Colors

**Main Colors:**

| Color | Hex | Usage |
|-------|-----|-------|
| Dark | `#141413` | Primary text, dark backgrounds |
| Light | `#faf9f5` | Light backgrounds, text on dark |
| Mid Gray | `#b0aea5` | Secondary elements, borders, dividers |
| Light Gray | `#e8e6dc` | Subtle backgrounds, card surfaces |

**Accent Colors (use in this priority order):**

| # | Color | Hex | Best For |
|---|-------|-----|----------|
| 1 | Orange | `#d97757` | Primary accent, CTAs, highlights |
| 2 | Blue | `#6a9bcc` | Secondary accent, links, data |
| 3 | Green | `#788c5d` | Tertiary accent, success states |

### Typography

| Element | Font | Fallback | Size Rule |
|---------|------|----------|-----------|
| Headings | Poppins | Arial | ≥24pt |
| Body text | Lora | Georgia | <24pt |
| Code/Mono | System monospace | Courier New | N/A |

### Accent Application Rules

- **Single shape**: Use Orange (`#d97757`)
- **Two shapes**: Use Orange first, then Blue (`#6a9bcc`)
- **Three+ shapes**: Cycle Orange → Blue → Green → Orange...
- **Data visualizations**: Do NOT override data viz colors. Apply branding only to surrounding text, titles, and containers.

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| Artifact type unknown | Ask user (Step 1 checkpoint) |
| Fonts not installed | Use fallbacks (Arial/Georgia). Mention that installing Poppins + Lora would improve results |
| Background color unknown | Default to light mode (Light background + Dark text) |
| User wants partial branding | Ask which elements to brand vs. leave as-is. Apply only to specified elements |
| Dark background with insufficient contrast | Use Light (`#faf9f5`) text on Dark (`#141413`); validate contrast ratios |
| Multiple artifacts | Apply consistently across all; use same background mode for cohesion |
| Non-Anthropic brand requested | This skill only covers Anthropic branding. Tell user and offer to apply generic design principles instead |
