<!--
Small fixes don't need a linked issue. For anything larger, link the issue
where the approach was agreed.
-->

## What changed

<!-- One or two sentences. What does this do that the previous behavior didn't? -->

## Why

<!-- The problem this solves. If it fixes an issue, "Fixes #N". -->

## How it was verified

<!--
Which tests you ran and what they showed. If you added a test, say what it
would catch. If a change is hard to test, say why.
-->

- [ ] `bats tests/*.bats`
- [ ] `pytest tests/ -q`

## Checklist

- [ ] `CHANGELOG.md` entry appended at the end (never edit existing lines)
- [ ] `TD_VERSION` bumped in **both** `scripts/token-diet` and `scripts/token-diet.ps1`, if this ships a user-visible change
- [ ] No hardcoded home paths or usernames (the path-leak guard checks this)
- [ ] Pinned submodules in `forks/` left alone, unless bumping them is the point of this PR
