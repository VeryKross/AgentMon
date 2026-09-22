# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The primary user is a developer working on a Mac with a dedicated 1280x720 secondary display. They need an ambient, glance-only view of machine health and active GitHub Copilot project sessions while concentrating on their main screen.

## Product Purpose

AgentMon turns a novelty secondary display into an always-on system and work-status companion. It should make CPU, memory, storage, agent activity, active projects, time, and weather understandable within a glance, without requiring interaction during normal use.

## Positioning

Unlike a generic system monitor or agent dashboard, AgentMon combines local Mac telemetry with GitHub Copilot project-session awareness in a display designed specifically for a small, permanently visible companion screen.

## Operating Context

AgentMon runs full-screen on a 1280x720 monitor housed in a case reminiscent of the original Macintosh. The main display remains the user's working surface; AgentMon is peripheral awareness. A native-feeling macOS menu-bar presence provides access to settings and the dedicated display window.

## Capabilities and Constraints

- Show glanceable CPU, memory, and storage state.
- Show GitHub Copilot project sessions, their current state, and the projects being worked on.
- Include current weather as secondary ambient information.
- Default weather to Marietta, Georgia 30066 while keeping the location configurable.
- Optimize the primary surface for 1280x720 and continuous, unattended viewing.
- Normal operation is passive; configuration and window management may be interactive outside the full-screen display.
- The implementation approach for macOS packaging and access to Copilot session data remains open.

## Brand Commitments

The interface must feel fun and meaningfully connected to the original Macintosh era. The retro character should serve legibility and ambient monitoring rather than becoming a superficial skin or obstructive simulation.

## Evidence on Hand

No existing implementation, visual assets, telemetry integration, or agent-status integration is present yet. Future work must not fabricate live system, agent, project, or weather data without clearly identifying it as demonstration data.

## Product Principles

- Make important state readable in one glance from a peripheral display.
- Let system health and agent activity share one coherent operational picture.
- Reward prolonged ambient presence with character, not distraction.
- Preserve the little monitor's physical Macintosh illusion.
- Keep setup and configuration out of the primary display experience.
