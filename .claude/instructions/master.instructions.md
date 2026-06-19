---
name: master
description: 'Define orchestration rules for R repository modernization.'
---

## Purpose
Coordinate all R repository operational modes and enforce deterministic, technical standards.

## Key Rules
- Deterministic modifications only.
- Preserve public function signatures, return types, exported API.
- Avoid and eliminate backward compatibility; fix legacy patterns whenever found.
- Function-level documentation only (`roxygen2` inside scripts).
- Strict technical tone; no marketing or conversational filler.