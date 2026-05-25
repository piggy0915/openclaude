---
name: webapp-testing
description: Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs. Trigger when user asks to test a web app, check if a page works, debug UI behavior, capture screenshots of a local site, or write browser automation.
license: Complete terms in LICENSE.txt
---

# Web Application Testing

Test local web applications with native Python Playwright scripts.

## Workflow

### Step 1: Determine Approach

Use the decision tree:

```
User task → Is it static HTML?
    ├─ Yes → Read HTML file directly to identify selectors
    │         ├─ Success → Write Playwright script using selectors
    │         └─ Fails/Incomplete → Treat as dynamic (below)
    │
    └─ No (dynamic webapp) → Is the server already running?
        ├─ No → Run: python scripts/with_server.py --help
        │        Then use the helper + write simplified Playwright script
        │
        └─ Yes → Reconnaissance-then-action:
            1. Navigate and wait for networkidle
            2. Take screenshot or inspect DOM
            3. Identify selectors from rendered state
            4. Execute actions with discovered selectors
```

**Checkpoint**: If unclear whether the app is static or dynamic, ask the user: "Is this a static HTML file, or does it need a running server?"

### Step 2: Set Up Server (if needed)

**Single server:**
```bash
python scripts/with_server.py --server "npm run dev" --port 5173 -- python your_automation.py
```

**Multiple servers (e.g., backend + frontend):**
```bash
python scripts/with_server.py \
  --server "cd backend && python server.py" --port 3000 \
  --server "cd frontend && npm run dev" --port 5173 \
  -- python your_automation.py
```

Always run `--help` first to see usage. Treat scripts as black boxes — don't read their source.

### Step 3: Write and Run Test Script

Use this template:
```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('http://localhost:5173')
    page.wait_for_load_state('networkidle')  # CRITICAL for dynamic apps
    # ... your automation logic
    browser.close()
```

### Step 4: Present Results

Share findings: screenshots, console logs, or test pass/fail summary.

## Reconnaissance-Then-Action Pattern

For dynamic apps with unknown selectors:

1. **Inspect**:
   ```python
   page.screenshot(path='/tmp/inspect.png', full_page=True)
   content = page.content()
   page.locator('button').all()
   ```
2. **Identify selectors** from inspection
3. **Execute** using discovered selectors

## Best Practices

- Use `sync_playwright()` for synchronous scripts
- Always close the browser when done
- Always launch headless (`headless=True`)
- Use descriptive selectors: `text=`, `role=`, CSS selectors, IDs
- Add waits: `page.wait_for_selector()` or `page.wait_for_timeout()`
- ❌ Don't inspect DOM before `networkidle` on dynamic apps
- ✅ Do wait for `page.wait_for_load_state('networkidle')` before inspection

## Reference Files

- `examples/element_discovery.py` — Discovering buttons, links, inputs
- `examples/static_html_automation.py` — Using file:// URLs for local HTML
- `examples/console_logging.py` — Capturing console logs

## Boundary Conditions

| Situation | Action |
|-----------|--------|
| Server won't start | Check port availability; try different port with `--port` flag |
| `with_server.py` not found | Verify path: `.claude/skills/webapp-testing/scripts/with_server.py` |
| Playwright not installed | Run `pip install playwright && playwright install chromium` |
| Selector not found at runtime | Use reconnaissance pattern: screenshot → inspect → retry |
| Timeout on `networkidle` | Increase timeout: `page.wait_for_load_state('networkidle', timeout=30000)` |
| Server takes too long to start | `with_server.py` has built-in retry; if persistent, manually start server |
| Element not interactive | Wait for it: `page.wait_for_selector('button', state='visible')` |
| User wants to test on non-localhost | Ask for the URL; use it directly in `page.goto()` |
