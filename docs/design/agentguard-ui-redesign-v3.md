# AgentGuard UI/UX Redesign V3

Status: proposal for review, not implementation.

## Design Goal

Make AgentGuard feel like a focused AI security command center, not a default macOS settings utility.

The UI should be memorable because it is calm, sharp, coherent, and fast. The visual language should support trust and control rather than decorative novelty.

## Product Personality

- Professional: security and monitoring should feel reliable.
- Premium: use depth, spacing, and typography with restraint.
- Alive: interactions should respond with subtle motion and status changes.
- Familiar: keep the original shield-eye brand mark. Do not change the logo shape.

## Visual System

### Color

Primary palette:

- Graphite canvas: `#101317`
- Deep panel: `#171C22`
- Elevated panel: `#202731`
- Brand cyan: `#42D7E8`
- Trust green: `#4BE08A`
- Attention amber: `#F4B84A`
- Danger red: `#FF5E6C`

Use cyan as the brand signal, green for healthy/live state, amber for attention, red only for real risk.

Avoid:

- Random purple gradients.
- Too many independent card colors.
- Heavy macOS default gray surfaces.
- Multiple unrelated icon styles.

### Typography

- Product title: rounded, heavy, compact.
- Data labels: small uppercase or semibold caption.
- Body text: regular, high contrast, no oversized marketing copy inside operational screens.

### Shape

- Main surfaces: 18px radius.
- Sidebar tabs: 14px radius.
- Small chips/buttons: 999px capsule.
- Avoid nested cards. Use one clear surface layer plus separators.

### Icon Rule

Use the existing shield-eye menu bar mark for the brand.

System icons can be used for navigation and row actions, but they should sit inside the same visual treatment: fixed-size icon slots, consistent stroke weight, and consistent color behavior.

## App Layout

### Shell

The app should use a three-zone command-center layout:

1. Left navigation rail.
2. Main dashboard or working page.
3. Optional right insight panel for context, not always visible.

The first screen should be useful immediately. No marketing landing page.

### Left Tab Bar

The left tab bar needs to become the product anchor.

Structure:

- Brand block at top: shield-eye mark + AgentGuard + live status.
- Primary workspace group:
  - Command
  - Approvals
  - Sessions
  - Activity
  - Protected
- Secondary group:
  - Cleanup
  - Lab
  - Settings
- Bottom status capsule:
  - "Monitoring Live"
  - active agents count

Selected tab:

- Uses a cyan-to-green edge glow.
- Has a left accent rail.
- Background is elevated but not glassy-noisy.
- Label becomes bright white.
- Icon uses brand cyan.

Unselected tab:

- Low contrast but readable.
- No heavy borders.
- Hover raises contrast and reveals a soft background.

### Main Dashboard

Top section:

- Compact title: "Command Center"
- One-line health summary.
- Right-side action cluster: Refresh, Authorize, Export.

Hero status band:

- Not a marketing hero.
- It should feel like a live console: current protection state, active AI tools, approvals waiting, recent operations.

Below:

- Four metric cards in one visual family.
- A live activity stream with grouped rows.
- A risk/approval panel with clear next action.

### Cards

All cards share:

- Same corner radius.
- Same border opacity.
- Same background model.
- Same title/data rhythm.

Card hierarchy:

- Level 1: page sections.
- Level 2: repeated metric cards.
- Level 3: row hover states.

No card should look like a different product.

## Interaction

Motion should be subtle and useful.

- Sidebar tab hover: 120ms background fade + 1px x movement.
- Tab selection: 180ms spring, accent rail slides in.
- Card hover: 120ms lift, tiny shadow change.
- Button press: scale to 0.98 and return.
- Live status pulse: slow opacity pulse only for active monitoring.
- Empty state: do not use big illustrations; use a calm icon, explanation, and one action.

## Proposed Screens

The HTML mockup contains:

- Main command center layout.
- Redesigned left tab bar.
- Unified card system.
- Brand mark treatment based on the original shield-eye symbol.
- Right-side "Today" insight panel.

Open:

`docs/design/agentguard-ui-redesign-v3.html`

