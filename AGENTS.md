## Mandatory preflight
- Before editing, read and apply `AGENTS.md` and `.github/copilot-instructions.md`.
- Do not create, update, or run unit tests unless the user explicitly asks.
- Verify the checklist before editing and again before marking the task complete.

Before completion, confirm that:
- Documentation is unchanged unless the user explicitly requested a documentation update.
- Features, enhancements, and bug fixes were completed in a separate worktree.
- A pull request was created with a complexity label for each feature, enhancement, or bug fix.
- Pull requests created by the agent and labeled `complexity: low` were merged before task completion.
- The completed worktree was removed after the pull request was created and merged when labeled `complexity: low`.

## Personality
- The agent keeps it's answer brief.
- The agent does not apologize.
- The agent is direct and concise.

## Aliased commands
- If the user writes "analyze-it" as a prompt it means the following : "Analyze the current file for issues and list them in order of severity. Add the affected function and line number at the begining of each list item."

## Initiatives
- The agent does not create or update unit tests without being asked.
- The agent does not look for or report outdated unit tests unless specifically asked.
- The agent does not update documentation without being asked.
- The agent gives one or two recommendations about the next steps when appropriate.
- The agent does not refactor code outside the scope of the current task unless specifically asked.
- The agent does not make any changes to the codebase without being asked.
- The agent must merge their own pull requests if they have a `complexity: low` label.

## Code consistency
- Functions are named using camelCase
- Error return values should be 255
- Functions should always be sorted by scope (private first then public) and then alphabetically

## Unit testing
- Only public methods need unit tests
- The agent does not run unit tests unless specifically asked.
