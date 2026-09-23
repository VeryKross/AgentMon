---
version: 1
slug: "sources-agentmon-dashboardview-swift"
primary_target: "Sources/AgentMon/DashboardView.swift"
related_targets: []
---

## Scope and mode

Operate-mode ambient dashboard for the dedicated 1280x720 secondary display. The surface is glance-only during normal use; configuration lives in the menu-bar settings window.

## Audience, job, and content

A developer working on the main display needs peripheral awareness of Mac health and GitHub Copilot project sessions across the Mac and paired computers. Show CPU, memory, storage, uptime, active projects, source host, session state, current time, and Marietta weather. Live system data remains local; relays expose only normalized session metadata; mock data is never presented as live.

## Direction and memorable moment

Macintosh Mission Control: a coherent System 6 desktop rather than modern dashboard cards with nostalgic decoration. Agent Desk owns the broad right field; This Macintosh and Weather stack on the left. Event-driven status glyphs make working, ready, and needs-attention states readable at a glance. Approved composition: `/Users/kenross/.copilot/session-state/0ffbf08a-4ccd-4fa8-bd6f-0746036b78d3/files/agentmon-mockup.html`.

## Implementation fidelity

| Ingredient | Medium |
|---|---|
| Dithered desktop and window chrome | SwiftUI Canvas and shapes |
| Macintosh and status glyphs | Semantic SwiftUI Canvas drawing |
| System meters and history | Native data rendered with SwiftUI shapes |
| Agent rows and state labels | Native text and accessibility labels |
| Detailed one-bit weather artwork | SwiftUI Canvas paths and stipple marks |
| Menu-bar controls and settings | Native SwiftUI scenes |

## Constraints and open decisions

Preserve the fixed 1280x720 composition, one-bit palette, hard shadows, crisp rules, low-motion behavior, and 150% dashboard type scale approved for the physically small display. Scale the complete canvas proportionally on other window sizes. The local Copilot event format is not a public API and must remain isolated behind an adapter. Launch-at-login is outside the first build.
