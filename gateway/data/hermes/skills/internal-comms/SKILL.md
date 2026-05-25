---
name: internal-comms
description: A set of resources to help write all kinds of internal communications, using the formats that my company likes to use. Trigger when asked to write status reports, leadership updates, 3P updates, company newsletters, FAQs, incident reports, project updates, or any internal team communication.
license: Complete terms in LICENSE.txt
---

# Internal Communications

## When to use this skill

| Communication Type | Use Case | Example File |
|-------------------|----------|-------------|
| 3P Update | Weekly/biweekly team status (Progress, Plans, Problems) | `examples/3p-updates.md` |
| Company Newsletter | Company-wide announcements, monthly roundups | `examples/company-newsletter.md` |
| FAQ Response | Answering common/recurring questions | `examples/faq-answers.md` |
| Incident Report | Post-mortems, outage summaries | `examples/general-comms.md` |
| Leadership Update | Executive summaries, board prep | `examples/general-comms.md` |
| Project Update | Stakeholder progress reports | `examples/general-comms.md` |
| General / Uncategorized | Anything not listed above | `examples/general-comms.md` |

## Workflow

### Step 1: Identify Communication Type

Determine which type from the table above best matches the user's request.

**If ambiguous**: Ask the user: "Is this a 3P update, newsletter, FAQ, incident report, leadership update, or general announcement?"

### Step 2: Load the Guideline

Read the corresponding example file from `examples/`:

```bash
Read .claude/skills/internal-comms/examples/{filename}
```

**If the file is missing or unreadable**: Use the fallback templates in Step 4 of this skill.

### Step 3: Draft with Structure

Use the loaded guideline for formatting and tone. Apply these universal principles:

**Tone Rules by Audience:**
| Audience | Tone | Detail Level |
|----------|------|-------------|
| Executives | Concise, outcomes-focused | High-level, 3-5 bullets max |
| Peers/Team | Collaborative, transparent | Moderate, include blockers |
| Cross-functional | Explanatory, jargon-light | Moderate, include context |
| Company-wide | Positive, inclusive | Light, focus on impact |

**Content Checklist (verify before sharing draft):**
- [ ] Purpose is clear in the first sentence
- [ ] Key dates/deadlines are included (if applicable)
- [ ] Action items are explicitly called out
- [ ] Acronyms are spelled out on first use
- [ ] Sensitive information is removed or flagged
- [ ] Links/attachments are verified

**If no guideline file matches**: Use this universal structure:
1. **Header**: What this is about (one line)
2. **Context**: Why this matters now (1-2 sentences)
3. **Details**: The key information (bullets or short paragraphs)
4. **Actions**: What recipients need to do (if anything)
5. **Timeline/Next Steps**: When to expect more info

### Step 4: Review with User

Present the draft and ask: "Here's the draft. Does it cover everything? Any changes to tone, detail, or audience?"

Wait for confirmation before finalizing.

## Communication Types

### 3P Update (Progress, Plans, Problems)

Default format for recurring team updates:

```
**Progress** (what was accomplished)
- Item 1
- Item 2

**Plans** (what's next)
- Item 1
- Item 2

**Problems** (blockers / risks)
- Item 1 — [owner/eta if known]
```

### Incident Report

For production outages, bugs, or service disruptions:

```
**What happened**: [One-line summary]
**Impact**: [Who was affected, for how long, severity]
**Timeline**: [Key events with timestamps]
**Root cause**: [What caused it]
**Resolution**: [How it was fixed]
**Follow-up**: [Prevention steps, action items with owners]
```

### Leadership Update

For executive summaries:

```
**Bottom line up front**: [One sentence]
**Key metrics / highlights**: [2-3 bullets]
**Risks / Attention needed**: [Where you need help]
**Next milestone**: [Date + what]
```

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| Communication type unclear | Ask user to clarify (Step 1) |
| Example file not found | Use universal structure in Step 3 |
| User wants a format not listed | Use universal structure; adapt to described format |
| Multiple audiences | Draft main version, note sections that need per-audience tailoring |
| Sensitive content | Flag for user review; do not share externally |
| Very short request (e.g., "write a quick update") | Default to 3P format; confirm with user |
| User provides raw notes/bullets | Organize into structured format; don't invent additional content |
