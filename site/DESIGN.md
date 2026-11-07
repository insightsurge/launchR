---
name: launchR
description: A calm, precise, hand-drawn honeycomb that turns into a working R package.
colors:
  ember-background: "#0d1117"
  ember-surface: "#171d27"
  ember-ink: "#f4f1ec"
  ember-soft: "#b7bcc6"
  ember-hint: "#808795"
  ember-accent: "#f6ab85"
  ember-hex-fill: "#2a2533"
  ember-success: "#86d3a8"
  ember-problem: "#ff8f7e"
  ember-plan-public: "#8fa4e8"
  ember-plan-private-later: "#c58bd0"
  ember-plan-private: "#7fd0b4"
  paper-background: "#f5f1ea"
  paper-surface: "#ffffff"
  paper-ink: "#1c1b22"
  paper-soft: "#4b4a56"
  paper-hint: "#73737e"
  paper-accent: "#a3411a"
  paper-hex-fill: "#fbe4d4"
  paper-success: "#2a7050"
  paper-problem: "#b3261e"
  paper-plan-cran: "#c2552a"
  paper-plan-public: "#3b5bb0"
  paper-plan-private-later: "#9a3f8f"
  paper-plan-private: "#1f8a6a"
typography:
  display:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "clamp(2.15rem, 4.5vw, 4rem)"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.03em"
  body:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  question:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 500
  answer:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
  placeholder:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  note:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
  label:
    fontFamily: "Space Grotesk, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
    letterSpacing: "0.06em"
  code:
    fontFamily: "ui-monospace, SF Mono, Menlo, Consolas, monospace"
    fontSize: "13px"
rounded:
  control: "8px"
  input: "10px"
  card: "12px"
  summary-card: "18px"
  pill: "99px"
spacing:
  child: "14px"
  question-to-answer: "8px"
  question-to-question: "20px"
  gutter-min: "16px"
  gutter-max: "56px"
components:
  button-primary:
    backgroundColor: "{colors.paper-accent}"
    textColor: "{colors.paper-background}"
    rounded: "{rounded.pill}"
    padding: "13px 22px"
  button-quiet:
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.pill}"
    padding: "12px 20px"
  pill-on:
    textColor: "{colors.paper-accent}"
    rounded: "{rounded.pill}"
    height: "34px"
  input:
    backgroundColor: "{colors.paper-surface}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.input}"
  plan-card:
    backgroundColor: "{colors.paper-surface}"
    rounded: "{rounded.card}"
  summary-card:
    backgroundColor: "{colors.paper-surface}"
    rounded: "{rounded.summary-card}"
    padding: "22px"
---

# Design System: launchR

## Overview

**Creative North Star: "The Hand-Drawn Workbench"**

A package is built from small, honest parts, and the page shows them. Hexagons drawn in dots start as a honeycomb with gaps, grow into a file tree, become checks and paths, and close into one package. The scene carries the story, so the words beside it stay short.

The mood is calm and precise. The form is the workbench: plain, ordered and quiet. The first screen asks a few questions and a plan; everything else waits behind one choice, Customise a plan, in four steps. Explanations sit behind an info mark, not on the page. Components feel quiet and sure: soft corners, pills for choices and one strong primary button per screen.

**Key Characteristics:**
- One typeface, two themes (dark Ember, light Paper), one accent per theme
- Dotted, slightly unsteady line work on the animation, never clean vector icons there
- Small hexagons that stay small
- Pills for choices, a matrix only where two dimensions are real
- Flat surfaces separated by hairlines
- A summary card that stays put while the steps change beside it
- Every control that can't work yet is hidden or marked Coming soon

## Colors

Warm neutrals with a single burnt accent, in a dark Ember theme and a light Paper theme. The theme follows the system until the visitor chooses.

### Primary
- **Ember** (peach in the dark theme, rust in the light one): the only accent. Links, the primary button, selected pills, focus rings, the lit row and the lit hexagon.

### Tertiary
- **Plan hues** (CRAN, public, private for now, private for good): a small hexagon chip beside each plan and the package hexagon in the summary card. Never used for text or state.

### Neutral
- **Background and Surface:** the page, and cards, inputs and the summary card on it.
- **Ink:** main text and typed answers.
- **Soft:** secondary text, notes and help.
- **Hint:** example text in empty fields, lighter than typed text (about 4.7:1), so a field never looks filled in.
- **Line:** hairlines and dividers (white at 16% on Ember, ink at 22% on Paper).
- **Success and Problem:** ticks, crosses and messages only.

### Named Rules
**The Colour-Is-Never-Alone Rule.** On, off, error and disabled always have a second signal: a tick, a message, a position or a grey.

**The One Accent Rule.** Ember is the only colour that means "this is the choice" or "act here". Plan hues identify plans; they never mark state.

**The Green Means Done Rule.** Success and problem colours appear only on ticks, crosses and messages.

## Typography

**Display Font:** Space Grotesk (self-hosted, with the system sans serif as fallback)
**Label/Mono Font:** the system monospace, only for file names, check names and commands

**Character:** engineered and friendly; monospace is kept for things a person would type.

### Hierarchy
- **Display** (500, clamp(2.15rem, 4.5vw, 4rem), 1.04): the page headings on the landing page.
- **Body** (400, 17px, 1.55): the landing page's paragraphs.
- **Question** (500, 15px): form labels, legends and step headings inside the form.
- **Answer** (400, 15px): typed text, pills, switches and plan names.
- **Placeholder** (400, 14px, Hint): example text in empty fields.
- **Note** (400, 13.5px, Soft): field notes, errors and help.
- **Label** (400, 12.5px, 0.06em, uppercase): row labels in the summary card.
- **Code** (13px, monospace): file names, check names and commands.

### Named Rules
**The One Scale Rule.** Inside the form, text is one of the sizes above. A new size means a new role, and needs a reason.

## Layout

The landing page is seven scroll-snapped screens, picture and text side by side on a laptop and stacked below 860px. The form is a full-screen dialog that grows from the control that opened it: two columns on a laptop (the questions, and the summary card), one column below 860px. It widens for the settings steps and narrows to one column for the next steps and for an existing package.

The summary card's top sits level with the end of the view's subtitle on every view and the card grows down from there, so it never moves when Next changes the step. A step bar above the form keeps its room on every view, so the form never jumps.

Spacing inside the form: question to answer 8px, one question to the next 20px, children of a group 14px. The page gutter runs from 16px to 56px with the window. A label sits beside its control, never across the page from it.

### Named Rules
**The Still Card Rule.** Moving between steps changes the left column only. The step bar and the summary card stay where they are.

## Elevation & Depth

Flat by default. Depth comes from hairlines and the surface colour. Three shadows exist, each with a job: the hovered primary button gains a soft accent shadow below it; the privacy notice floats on a soft dark shadow; focus is a 3px accent ring around the field.

### Named Rules
**The Lit Outline Rule.** A hovered hexagon keeps its size and gains one thin glowing outline around it. Nothing else glows.

## Shapes

The hexagon is the form language: the logo, the plan chips, the package in the summary card and the scene. Controls are soft: 8px for small controls, 10px for inputs, 12px for cards, 18px for the summary card, and full pills for choices and buttons.

## Components

### Buttons
Quiet and sure: one primary button per screen.
- **Primary:** Ember background, full pill (13px 22px), 16px semibold. Hover adds a soft accent shadow; pressing moves it down 1px. Until the form is complete it stays readable at 72% opacity (at least 3:1), with a note beside it saying what is missing.
- **Quiet:** a 1.5px Soft outline on a full pill; the outline and text turn Ember on hover.

### Pills
- **Off:** hairline outline and Soft text.
- **On:** Ember outline, a light Ember tint, Ember text and a tick.
- **Disabled:** grey, with a not-allowed cursor and a reason nearby.

### Inputs
- **Style:** Surface fill, hairline border, 10px corners, Hint placeholder.
- **Focus:** Ember border with a 3px soft Ember ring.
- **Error:** Problem border with a plain message below that names the fix; focus moves to the field.

### Plan cards
A Surface card with a 1.5px hairline and 12px corners, the plan's hexagon chip and a one-line note. The chosen card takes the Ember outline.

### Summary card
The package as a hexagon with its initials, the zip name, the plan, and rows (checks, systems, website, checklists) under small uppercase labels. Surface fill, hairline, 18px corners, 22px padding. It updates as the visitor types and sits still while the steps change.

### Step bar
Five numbered pills in one centred row above the form. The current step has the Ember outline and tint; finished steps turn Ink.

### Tooltips
One info mark (15px) per group, holding bullets for every option in it, so the page itself stays minimal. They open on hover, keyboard focus or tap, close on Escape or a tap elsewhere, and become a bottom sheet on a phone.

### Lit rows
Lists that pair with the picture light up both ways. The row gains a light tint with rounded corners, its text grows slightly, and its divider lines disappear.

## Do's and Don'ts

### Do:
- **Do** keep touch controls at least 44px on phones.
- **Do** say what will happen before it happens, in plain sentences beside the control.
- **Do** keep details in tooltips and the page itself minimal: chips show the check's name, the info mark explains it.
- **Do** read defaults from the kit's lists, so an untouched form matches the command line.
- **Do** keep the summary card level with the subtitle's end on every view.

### Don't:
- **Don't** put text on the animation, apart from the Start control.
- **Don't** add a ripple, a second hexagon on hover, or a glow on the dots.
- **Don't** use an R logo.
- **Don't** show an option the kit can't honour.
- **Don't** fold a short list behind a disclosure when it fits as its own section.
