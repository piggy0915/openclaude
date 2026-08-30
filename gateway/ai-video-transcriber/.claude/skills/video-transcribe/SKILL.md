---
name: video-transcribe
description: Transcribe and summarize a video or podcast from a URL (YouTube, TikTok, Bilibili, Apple Podcasts, SoundCloud, 30+ platforms) or from a local media/.txt file. Use when the user shares a video/podcast link or media file and wants a transcript, summary, translation, or the original video downloaded. Triggers on "transcribe", "summarize this video", "what does this video say", "get the transcript", "转录", "视频摘要".
---

# Video Transcribe

Runs this repo's pipeline headlessly: platform subtitles when available (seconds),
local Whisper as fallback, then optimize → translate → summarize.

## Before running

The command needs the project's virtualenv and `ffmpeg`. Verify once per session:

```bash
ls venv/bin/python && command -v ffmpeg
```

- **No venv** → `./install.sh` (or `python3 -m venv venv && venv/bin/pip install -r requirements.txt`)
- **No ffmpeg** → `brew install ffmpeg` (macOS) / `sudo apt install ffmpeg` (Debian/Ubuntu). Do not proceed without it; audio extraction will fail.

## Run it

```bash
venv/bin/python transcribe.py "<URL or file path>" --json
```

Always pass `--json` — it puts machine-readable output on stdout and keeps progress
chatter on stderr. Parse the JSON rather than scraping the log lines.

Useful flags:

| Flag | When to use |
|------|-------------|
| `-l, --summary-language <code>` | Summary language: `en`, `zh`, `es`, `fr`, `de`, `it`, `pt`, `ru`, `ja`, `ko`, `ar`. Default `en` |
| `--no-llm` | **No API key available**, or the user only wants the raw transcript. Skips optimize/translate/summarize |
| `--no-video` | User doesn't want the source video kept (faster, less disk) |
| `--whisper-model small` | Accuracy matters more than speed. `tiny`→`large`, default `base` |
| `-o <dir>` | Write the Markdown somewhere other than `./temp` |

The LLM steps need an OpenAI-compatible key via `OPENAI_API_KEY` (and optionally
`OPENAI_BASE_URL`). Without one the pipeline still transcribes but falls back to
basic formatting — prefer `--no-llm` in that case and summarize the transcript
yourself, which is usually better anyway since you have the full context.

Provider settings:

```bash
export OPENAI_API_KEY="your_api_key_here"
export OPENAI_BASE_URL="https://openrouter.ai/api/v1"
export OPENAI_TRANSLATION_MODEL="gpt-4o"  # optional
```

For a one-off run, `transcribe.py` also accepts `--api-key`, `--base-url`, and
`--model`. Prefer environment variables when possible so API keys are not written
to shell history.

## Reading the result

```json
{
  "title": "...",
  "no_speech": false,
  "detected_language": "en",
  "files": { "raw": "...", "transcript": "...", "summary": "...", "translation": "..." },
  "media": { "path": "...", "kind": "video", "size_bytes": 2243691 }
}
```

Read the `transcript` / `summary` paths to get the content. `translation` is present
only when the source language differs from the summary language.

## Critical: `no_speech`

When `"no_speech": true` the source contains **no speech at all**. There is no
transcript, no summary, no translation — the pipeline deliberately skips the LLM so
that nothing gets invented.

If you see this, tell the user the video has no speech. **Do not** guess at the
content, infer it from the title, or describe what the video "probably" says. This
guard exists because feeding an empty transcript to an LLM previously produced a
confident, entirely fabricated conversation.

## Failure modes

- Exit `2` — bad input (missing file, unsupported extension, empty text file). The message says which; fix the argument.
- Exit `1` — download/transcode failure. Usually an unreachable URL, a region-blocked or private video, or missing ffmpeg. Report the actual error; don't retry blindly.
- First run downloads Whisper weights (~150 MB for `base`), so it can look stalled for a minute.
- Long videos are slow in Whisper mode (a 30-min audio-only podcast can take 15–60 min). Warn the user before starting; subtitle mode is seconds.
