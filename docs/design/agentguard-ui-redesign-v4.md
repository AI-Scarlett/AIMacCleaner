# AgentGuard UI/UX Redesign V4

Status: design proposal for review, not implementation.

This version responds to the V3 feedback:

- V3 was too dark.
- The palette did not stay close enough to the app icon.
- Only one page was shown.
- The left tab bar needed a more complete redesign.

## V4 Direction

Use the original shield-eye icon as the design source:

- Bright cyan-green as the primary brand signal.
- Clean aqua-tinted surfaces instead of dark graphite panels.
- Light command-center feeling, not a heavy hacker dashboard.
- Consistent cards, buttons, tabs, and status chips across all pages.
- Brand icon shape must remain the original shield-eye mark.

## Pages Included

The HTML mockup includes eight page designs:

1. Command Center
2. Approvals
3. Sessions
4. Activity
5. Protected
6. Cleanup
7. Lab
8. Settings

Open:

`docs/design/agentguard-ui-redesign-v4.html`

## Palette

- App background: `#EAFBFB`
- Main canvas: `#F7FFFF`
- Sidebar tint: `#DDF8F5`
- Primary cyan: `#21C8D6`
- Primary green: `#34D990`
- Deep text: `#10252C`
- Soft text: `#55717A`
- Border: `rgba(16, 86, 96, .13)`
- Warning amber: `#F0A93A`
- Danger coral: `#F46565`

## Left Tab Redesign

The sidebar is now a light aqua rail instead of a dark rail.

Rules:

- Brand block uses the original shield-eye mark.
- Selected tab uses a white raised pill, cyan-green icon chip, and left cyan rail.
- Unselected tabs are calm and readable.
- Badges use soft colored capsules.
- Bottom status block shows monitoring state and active agents.

## Implementation Notes Later

If approved, the SwiftUI implementation should first create shared components:

- `BrandMarkView`
- `AppSidebar`
- `SidebarTabRow`
- `PageHeader`
- `MetricTile`
- `StatusChip`
- `ActionPillButton`
- `SurfacePanel`

Then each screen should migrate to these components. Do not restyle pages one by one independently.

