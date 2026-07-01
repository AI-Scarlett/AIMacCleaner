# Mole-Inspired Maintenance

AgentGuard studies Mole's maintenance workflow and reimplements the useful
product behaviors in native Swift. No Mole source code is copied into this
repository.

## Adopted Behaviors

- Discover regenerable project artifacts such as `node_modules`, `target`,
  `.build`, and common framework caches.
- Discover large downloaded installers for review.
- Keep every discovered maintenance item review-first.
- Route confirmed cleanup through the existing Trash-based removal flow.
- Surface project artifacts in Dependency Management and installers in Other
  Tools, so maintenance inventory is not hidden in a single cleanup screen.

## Safety Boundaries

- Only scan authorized or common user workspace roots.
- Skip protected and noisy directories, packages, and symbolic links.
- Require project markers near a build artifact before listing it.
- Do not include maintenance candidates in automatic smart cleanup.
- Keep uninstall and destructive app-management actions disabled in the App
  Store build.
