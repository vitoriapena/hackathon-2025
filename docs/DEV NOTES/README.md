DEV NOTES

This folder contains informal developer notes, scratch files, and local experimentation documents.

Purpose:
- Provide a place for team members to record quick notes and local run instructions.

Guidelines:
- Files in this folder are ignored by `.gitignore` to avoid committing ephemeral or sensitive local information.
- If a note becomes important for the project, move it to `docs/` (not `docs/DEV NOTES/`) and create a proper PR describing the change.
- Keep content non-sensitive; never add secrets or credentials here.

If you prefer this folder to be tracked instead, replace `docs/DEV NOTES/README.md` with a `.gitkeep` and remove the folder pattern from `.gitignore`.
