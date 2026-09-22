---
name: AgentMon
description: A one-bit Macintosh mission-control system for ambient developer operations.
colors:
  carbon-ink: "#0B0D0B"
  crt-paper: "#E8E6D6"
  desktop-gray: "#ABAB9C"
  graphite-copy: "#52544D"
typography:
  display:
    fontFamily: "Monaco, monospace"
    fontSize: "36px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.5px"
  body:
    fontFamily: "Monaco, monospace"
    fontSize: "19.5px"
    fontWeight: 400
    lineHeight: 1.3
  label:
    fontFamily: "Monaco, monospace"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "0"
rounded:
  square: "0px"
  hardware: "4px"
spacing:
  hairline: "1px"
  compact: "7px"
  standard: "18px"
  generous: "21px"
components:
  window:
    backgroundColor: "{colors.crt-paper}"
    textColor: "{colors.carbon-ink}"
    rounded: "{rounded.square}"
    padding: "{spacing.standard}"
  status-inverted:
    backgroundColor: "{colors.carbon-ink}"
    textColor: "{colors.crt-paper}"
    rounded: "{rounded.square}"
    padding: "3px 6px"
---

# Design System: AgentMon

## Overview

**Creative North Star: "Macintosh Mission Control"**

AgentMon behaves like a working System 6 desktop embedded in its Macintosh-inspired enclosure. It is an ambient instrument, not a modern dashboard wearing nostalgic decoration: hierarchy comes from window geometry, ink density, typography, and state inversion.

The surface is compact, orderly, and lightly playful. Its one-bit discipline makes live system and agent state readable from the edge of the user's vision, while small drawn details reward a closer look.

**Key Characteristics:**

- Fixed, purposeful desktop composition
- One-bit rendering with warm CRT neutrals
- Crisp rules, stipple, and structural offset depth
- Event-driven animation rather than constant motion
- Native information rendered without decorative cards

## Colors

The palette simulates dark ink on a softly aged monochrome CRT, with no ornamental color accents.

### Primary

- **Carbon Ink** (`#0B0D0B`): Primary text, borders, filled meter segments, icons, and inverted alerts.

### Neutral

- **CRT Paper** (`#E8E6D6`): Window surfaces and reversed text.
- **Desktop Gray** (`#ABAB9C`): The dithered desktop field surrounding windows.
- **Graphite Copy** (`#52544D`): Secondary descriptions and quiet metadata.

### Named Rules

**The One-Bit Rule.** State must remain understandable through shape, wording, pattern, and inversion. Do not introduce semantic color as a shortcut.

## Typography

**Display Font:** Monaco, with the macOS monospaced system face as fallback  
**Body Font:** Monaco, with the macOS monospaced system face as fallback  
**Label Font:** Monaco

**Character:** Monaco preserves the compact Macintosh lineage while rendering cleanly on modern Retina and low-density auxiliary displays. Size, weight, case, and placement establish hierarchy.

### Hierarchy

- **Display** (bold, 36px, 1.1): Agent Desk summary and major ambient readings.
- **Headline** (bold, 25.5–27px, 1.15): Project names and system messages.
- **Body** (regular, 18–19.5px, 1.3): Assignments, host details, and weather location.
- **Label** (bold, 13.5–16.5px, uppercase): State stamps, column labels, and sampling metadata.

### Named Rules

**The Clean Strike Rule.** Never apply a SwiftUI shadow to a composed text container; shadows belong to backing geometry so glyphs remain single and crisp.

## Layout

The canonical canvas is exactly 1280×720. A 34px desktop menu strip sits above a two-column workspace: a 376px system rail and an 850px Agent Desk separated by 18px. The system rail stacks a 452px health window and a 190px weather window. On other window sizes, scale the complete canvas proportionally instead of reflowing its topology.

Agent Desk is the focal field and accommodates four 104px session rows before summarizing overflow in its footer. System health and weather are supporting instruments. Dashboard typography renders at 150% of the original scale for legibility on the physically small display.

## Elevation & Depth

Depth is structural and binary. Windows receive one hard 5px offset Carbon Ink backing silhouette with no blur. The silhouette sits behind the window only; it must never shadow or duplicate child text, icons, or meters.

### Shadow Vocabulary

- **Desktop Window:** A separate `#0B0D0B` rectangle at `5px 5px`, 78% opacity, zero blur.

## Shapes

Most geometry is square and ruled with 1–3px strokes. Four-pixel rounding is reserved for illustrated hardware such as the Macintosh body and weather forms. Meter segments, state stamps, list rows, and windows remain rectangular.

## Components

### Buttons

- **Shape:** Square or 4px hardware corners.
- **Primary:** Carbon Ink fill with CRT Paper text.
- **Hover / Focus:** Invert foreground and background or add a crisp inset rule; never glow.
- **Secondary:** CRT Paper with a 1–2px Carbon Ink outline.

### Chips

- **Style:** Compact uppercase state stamps with a 1px Carbon Ink rule.
- **State:** Normal states remain outlined; attention states invert completely.

### Cards / Containers

- **Corner Style:** Square.
- **Background:** CRT Paper.
- **Shadow Strategy:** Separate hard offset backing silhouette.
- **Border:** 3px Carbon Ink outer rule, with 1–2px internal dividers.
- **Internal Padding:** 14–21px according to density.

### Inputs / Fields

- **Style:** Native macOS fields belong only in settings, not on the ambient dashboard.
- **Focus:** Preserve the native keyboard focus ring in settings.
- **Error / Disabled:** State the problem and recovery in text; never rely on color.

### Navigation

The dashboard has no navigation. Its top strip establishes place and time using desktop-menu grammar. Window management and settings live in the native menu-bar item.

### Retro Window

Every instrument is a fixed window with striped title chrome, centered title, close and zoom furniture, strong outer rule, and isolated hard-offset depth. Emphasized states replace stripes with solid Carbon Ink.

### Weather Artwork

Weather uses a complete one-bit scene vocabulary rather than one generic icon. Cloud mass increases visibly from mostly sunny through overcast; clear, mostly clear, partly cloudy, and mostly cloudy receive day/night celestial variants. Fog uses horizontal visibility bands, drizzle uses sparse dots, rain uses long diagonal strokes, snow uses asterisk flakes, and thunderstorms combine a heavy cloud, rain, and a bold lightning bolt.

## Do's and Don'ts

### Do:

- **Do** preserve the one-bit palette and communicate state redundantly.
- **Do** draw distinctive icons with crisp paths and stipple marks.
- **Do** preserve a unique silhouette and precipitation grammar for every weather family.
- **Do** keep motion low-frequency, brief, and tied to live state.
- **Do** maintain the approved 1280×720 hierarchy.

### Don't:

- **Don't** introduce modern rounded metric cards, glass, gradients, or glow.
- **Don't** apply shadows to composed views containing text.
- **Don't** use animation as ambient decoration.
- **Don't** fabricate live system, agent, project, or weather information.
