---
name: perspectives
description: "Character perspective/role-playing skills — adopt a notable person's thinking framework, mental models, decision heuristics, and expression style. Trigger when user asks to 'use X's perspective', 'what would X think', 'think like X', or mentions any character name matching a reference file in this skill. Each character has its own reference file under references/ with full framework. Do NOT activate just for general explanation requests — only when role-playing a specific person's thinking style is requested."
license: Proprietary. LICENSE.txt has complete terms
---

# Perspectives — Character Thinking Frameworks

## Overview

This umbrella skill provides a library of character perspective/role-playing frameworks. Each character's full framework (identity card, mental models, decision heuristics, expression DNA, values, honesty boundaries) lives in a reference file under `references/`.

**How it works:** When the user asks to adopt a specific person's perspective, load THIS skill (perspectives), then read the relevant `references/<character-name>.md` file. Apply that character's framework for the duration of the conversation. The umbrella SKILL.md provides the common activation protocol shared by all characters.

## Common Structure (All Characters)

Every perspective skill in this library follows the same structure:

```
Identity Card — who this person is, their origin story, core beliefs
Role-Playing Rules — how to adopt their voice (first-person, disclaimer rules, exit protocol)
Answer Workflow — agentic protocol for research-before-reply
Core Mental Models — 5-6 thinking frameworks (the cognitive engine)
Decision Heuristics — ~8 practical rules of thumb
Expression DNA — voice, syntax, vocabulary, rhythm, humor, certainty levels
Values & Anti-Patterns — what they pursue, what they reject, internal tensions
Intellectual Pedigree — who influenced them, who they influenced
Honesty Boundaries — limitations of the reproduction, known blind spots
```

## Activation Protocol

1. Load this skill (`perspectives`)
2. Read `references/<character-name>.md` for the full framework
3. Adopt first-person voice per that character's rules
4. Deliver one disclaimer on first activation, then stay in character
5. User says "exit" or "exit character" to return to normal mode

## Available Characters

| Character | File | Domain |
|-----------|------|--------|
| Andrej Karpathy | `references/andrej-karpathy-perspective.md` | AI research, engineering, technical education |
| Chen Sicheng (陈思诚) | `references/chensicheng-perspective.md` | Chinese cinema, commercial filmmaking |
| Elon Musk | `references/elon-musk-perspective.md` | Technology, entrepreneurship, engineering |
| Feynman (Richard) | `references/feynman-perspective.md` | Physics, science, learning, critical thinking |
| Hai Yan (海岩) | `references/haiyan-perspective.md` | Chinese TV drama, screenwriting |
| Hongguo Editor (红果编辑) | `references/hongguo-editor-perspective.md` | Short drama content editing, platform review |
| Ilya Sutskever | `references/ilya-sutskever-perspective.md` | AI research, deep learning, alignment |
| Liu Heping (刘和平) | `references/liuheping-perspective.md` | Chinese historical drama, screenwriting |
| MrBeast | `references/mrbeast-perspective.md` | Content creation, YouTube, virality |
| Munger (Charlie) | `references/munger-perspective.md` | Investing, mental models, rationality |
| Naval Ravikant | `references/naval-perspective.md` | Philosophy, startups, wealth, happiness |
| Ning Hao (宁浩) | `references/ninghao-perspective.md` | Chinese cinema, absurdist realism |
| Paul Graham | `references/paul-graham-perspective.md` | Startups, writing, technology trends |
| Steve Jobs | `references/steve-jobs-perspective.md` | Product design, innovation, leadership |
| Sun Yuchen (孙宇晨) | `references/sun-yuchen-perspective.md` | Crypto marketing, attention economy |
| Taleb (Nassim) | `references/taleb-perspective.md` | Risk, uncertainty, antifragility |
| Tian Liangliang (田良良) | `references/tianliangliang-perspective.md` | IP adaptation, Chinese screenwriting |
| Trump (Donald) | `references/trump-perspective.md` | Politics, media, negotiation |
| Wang Haoyu (王浩宇) | `references/wanghaoyu-perspective.md` | Short drama screenwriting |
| Wang Jing (王晶) | `references/wangjing-perspective.md` | Hong Kong cinema, commercial filmmaking |
| Wang Juan (王倦) | `references/wangjuan-perspective.md` | Chinese TV drama, adaptation |
| Wang Xiaoping (王小平) | `references/wangxiaoping-perspective.md` | Chinese TV drama, Zhen Huan |
| Xiaojixiangtian | `references/xiaojixiangtian-perspective.md` | Content creation, entrepreneurship |
| Zhang Yiming (张一鸣) | `references/zhang-yiming-perspective.md` | Technology, product, business strategy |
| Zhang Xuefeng (张雪峰) | `references/zhangxuefeng-perspective.md` | Education, career advice |
| Zhang Yimou (张艺谋) | `references/zhangyimou-perspective.md` | Chinese cinema, visual aesthetics |

## Skill Generator (Nuwa)

The file `references/huashu-nuwa.md` contains the **Nuwa** (女娲) skill-generation framework — an automated pipeline for distilling any person's thinking framework into a new perspective character for this library. Use it when the user wants to create a NEW perspective character not yet in the library. It covers:
- Multi-agent parallel research (6 information dimensions)
- Mental model extraction with triple-verification
- Expression DNA analysis
- Quality validation with test prompts

Read `references/huashu-nuwa.md` and its research materials under `references/huashu-nuwa/` for the full pipeline.

## Persistence

- Each character's content is preserved in its reference file under this umbrella
- Archived originals remain recoverable in `~/.hermes/skills/.archive/`
