---
name: launchR
description: A calm, precise, hand-drawn honeycomb that turns into a working R package.
colors:
  ember-background: "#0d1117"
  ember-surface: "#171d27"
  ember-ink: "#f4f1ec"
  ember-soft: "#b7bcc6"
  ember-accent: "#f6ab85"
  ember-success: "#86d3a8"
  ember-problem: "#ff8f7e"
  paper-background: "#f5f1ea"
  paper-surface: "#ffffff"
  paper-ink: "#1c1b22"
  paper-soft: "#4b4a56"
  paper-accent: "#a3411a"
  paper-success: "#2a7050"
  paper-problem: "#b3261e"
  plan-cran: "#c2552a"
  plan-public: "#3b5bb0"
  plan-private-later: "#9a3f8f"
typography:
  display:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "clamp(2.15rem, 4.5vw, 4rem)"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.03em"
  group-heading:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 500
  subsection:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "14.5px"
    fontWeight: 500
  body:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  option:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "14.5px"
    fontWeight: 400
  note:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
  code:
    fontFamily: "ui-monospace, SF Mono, Menlo, Consolas, monospace"
    fontSize: "13px"
rounded:
  control: "8px"
  input: "10px"
  card: "12px"
  pill: "99px"
spacing:
  group: "14px"
  gutter-min: "16px"
  gutter-max: "56px"
components:
  button-primary:
    backgroundColor: "{colors.paper-accent}"
    textColor: "{colors.paper-background}"
    rounded: "{rounded.pill}"
    padding: "13px 22px"
  pill-on:
    textColor: "{colors.paper-accent}"
    rounded: "{rounded.pill}"
    height: "34px"
---

# Design System: launchR

## Overview

**Creative North Star: "The Hand-Drawn Workbench"**

A package is built from small, honest parts, and the page shows them. Hexagons made of dots start as a honeycomb with gaps, grow into a file tree, become checks and paths, and close into one package. The scene carries the story, so the words beside it stay short and calm.

The form is a workbench: plain, ordered and quiet. The first screen asks four things, and everything else waits under Modify, in closed groups with a one-line summary. Explanations sit behind an info mark, not on the page.

**Key Characteristics:**
- One typeface, two themes, one accent per theme
- Dotted, slightly unsteady line work, never clean vector icons on the animation
- Small hexagons that stay small, with no bigger versions on the plan or package screens
- Pills for choices, a matrix only where two dimensions are real
- Every control that can't work yet is hidden or marked Coming soon

## Colors

Warm neutrals with a single burnt accent, in a dark Ember and a light Paper theme. The theme follows the system until the visitor chooses.

### Primary
- **Ember Peach and Paper Rust:** the only accent. Links, selected pills, focus, the lit row and lit hexagon.

### Tertiary
- **Plan hues:** a small hexagon chip beside each plan, and the package hexagon in the summary card. Never used for text or state.

### Neutral
- **Background, Surface, Ink, Soft, Line:** page, cards and inputs, main text, secondary text, hairlines.

### Named Rules
**The Colour-Is-Never-Alone Rule.** On, off, error and disabled always have a second signal: a tick, a message, a position or a grey.

**The Green Means Done Rule.** Success and problem colours appear only on ticks, crosses and messages.

## Typography

**Display Font:** Space Grotesk, self-hosted
**Label/Mono Font:** the system monospace, only for file names, check names and commands

**Character:** engineered and friendly, with monospace reserved for things a person would type.

### Hierarchy
- **Display:** the page headings.
- **Group heading:** the five Modify groups.
- **Subsection and field label:** headings inside a group, and labels above inputs.
- **Option:** pills, switches, rows and inputs.
- **Note:** field errors and small notes.
- **Code:** file and check names.

### Named Rules
**The One Scale Rule.** Inside the form, text is one of the sizes above. A new size means a new role, and needs a reason.

## Layout

Seven scroll-snapped screens, with the picture and text side by side on a laptop and stacked below 860px, where a screen taller than the phone holds the picture until its text has passed. The form is a full-screen dialog that grows from the control that opened it. It widens for Modify, and narrows to one column for the next steps and for existing packages. Inside a group, children sit 14px apart. A label sits beside its control, never across the page from it.

## Elevation & Depth

Flat by default. Depth comes from hairlines and the surface colour. The only soft shadows are on the privacy notice and on hovering the primary button, and both have an offset.

### Named Rules
**The Lit Outline Rule.** A hovered hexagon keeps its size and gains one thin glowing outline around it. Nothing else glows.

## Shapes

The hexagon is the form language. Controls are soft: 8px, 10px and 12px corners, and full pills for choices and primary buttons.

## Components

### Buttons
- **Primary:** accent background, full pill. Hover adds a soft offset shadow. Disabled is faded.
- **Quiet:** outline only, accent on hover.

### Pills
- **Off:** hairline outline and soft text.
- **On:** accent outline, light accent tint, accent text and a tick.
- **Disabled:** grey, with a not-allowed cursor.

### Inputs
- **Style:** surface fill, hairline border, 10px corners.
- **Focus:** accent border with a soft ring.
- **Error:** problem border with a plain message below, naming the fix.

### Lit rows
Lists that pair with the picture light up both ways. The row gains a light tint with rounded corners, its text grows slightly, and its divider lines disappear.

### Tooltips
One info mark per group, holding bullets for every option in it. They open on hover, keyboard focus or tap, and close on Escape or a tap elsewhere.

## Do's and Don'ts

### Do:
- **Do** keep touch controls at least 44px on phones.
- **Do** say what will happen before it happens, in plain sentences beside the control.
- **Do** read defaults from the kit's lists, so an untouched form matches the command line tool.

### Don't:
- **Don't** put text on the animation, apart from the Start control.
- **Don't** add a ripple, a second hexagon on hover, or a glow on the dots.
- **Don't** use an R logo.
- **Don't** show an option the kit can't honour.
