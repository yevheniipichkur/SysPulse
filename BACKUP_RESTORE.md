# Design backup restore

Before the design overhaul (2026-05-30), the project was saved at:

- **Branch:** `backup/pre-design-2026-05-30`
- **Tag:** `backup-pre-design-2026-05-30`
- **Commit:** `a8b7b4a` (same as `main` at backup time)

## Restore locally

```bash
git fetch origin
git checkout backup/pre-design-2026-05-30
```

Or reset `main` to the tag (destructive for newer commits):

```bash
git checkout main
git reset --hard backup-pre-design-2026-05-30
```

## Restore from tag only

```bash
git checkout backup-pre-design-2026-05-30
```
