# Developer agent learnings

## F90

- Hermetic bash tests should build their world in a `mktemp -d` sandbox and
  clean it up on EXIT so they never touch the live repo.
