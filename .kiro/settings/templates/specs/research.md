---
type: Research
title: "{{TITLE}}"
description: "{{DESCRIPTION}}"
status: draft
sources: []
kiro:
  depends_on: []
---

# 調査と設計判断のテンプレート

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

**Usage**:
- Log research activities and outcomes during the discovery phase.
- Document design decision trade-offs that are too detailed for `design.md`.
- Provide references and evidence for future audits or reuse.
---

## 更新時の規則

現行の Summary と Design Decisions は新しい根拠に合わせて更新する。
旧判断は Change Log で失効理由と置換先を示し、現行の指示として併記しない。
変更記録には確認日、参照元、変更理由、影響先、未解決事項を必要な範囲で残す。
機密情報や会話の全文は転記しない。

## Summary
- **Feature**: `<feature-name>`
- **Discovery Scope**: New Feature / Extension / Simple Addition / Complex Integration
- **Key Findings**:
  - Finding 1
  - Finding 2
  - Finding 3

## Research Log
Document notable investigation steps and their outcomes. Group entries by topic for readability.

### [Topic or Question]
- **Context**: What triggered this investigation?
- **Sources Consulted**: Links, documentation, API references, benchmarks
- **Findings**: Concise bullet points summarizing the insights
- **Implications**: How this affects architecture, contracts, or implementation

_Repeat the subsection for each major topic._

## Architecture Pattern Evaluation
List candidate patterns or approaches that were considered. Use the table format where helpful.

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Hexagonal | Ports & adapters abstraction around core domain | Clear boundaries, testable core | Requires adapter layer build-out | Aligns with existing steering principle X |

## Design Decisions
Record major decisions that influence `design.md`. Focus on choices with significant trade-offs.

### Decision: `<Title>`
- **Context**: Problem or requirement driving the decision
- **Alternatives Considered**:
  1. Option A — short description
  2. Option B — short description
- **Selected Approach**: What was chosen and how it works
- **Rationale**: Why this approach fits the current project context
- **Trade-offs**: Benefits vs. compromises
- **Follow-up**: Items to verify during implementation or testing

_Repeat the subsection for each decision._

## Risks & Mitigations
- Risk 1 — Proposed mitigation
- Risk 2 — Proposed mitigation
- Risk 3 — Proposed mitigation

## References
Provide canonical links and citations (official docs, standards, ADRs, internal guidelines).
- [Title](https://example.com) — brief note on relevance
- ...

## Change Log

意味のある変更ごとに、日付、変更元の根拠、旧判断からの変更、影響する文書と承認、残件を短く追記する。
古い調査ログは履歴として維持し、現行結論への参照を付ける。
