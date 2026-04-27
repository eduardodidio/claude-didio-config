# F99-T01-edit — F15 fixture: create and edit a slash-command file

**Wave:** 99
**Type:** fixture (used by F15 smoke test only)
**Status:** fixture

## Objective

Create `templates/commands/_f15-fixture.md` with the exact content
`F15 fixture marker` (one line). Then append a second line
`appended by F15 smoke`. Use the Write tool first, then Edit.

## Instructions

1. Use the Write tool to create `templates/commands/_f15-fixture.md`
   with this exact content (one line):

   ```
   F15 fixture marker
   ```

2. Use the Edit tool to append a second line to that same file so the final
   content is exactly:

   ```
   F15 fixture marker
   appended by F15 smoke
   ```

3. Print `DIDIO_DONE: f15-fixture wrote 2 lines`.

Do not create any other files. Do not modify any other files.
