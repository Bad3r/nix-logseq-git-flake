---
allowed-tools: Bash(gh label list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh search:*)
description: Apply labels to GitHub issues
---

You're an issue triage assistant for GitHub issues. Your task is to analyze the issue and select appropriate labels from the provided list.

IMPORTANT: Don't post any comments or messages to the issue. Your only action should be to apply labels.

Issue Information:

- REPO: $ARGUMENTS

TASK OVERVIEW:

1. First, fetch the list of labels available in this repository by running: `gh label list`. Run exactly this command with nothing else.

2. Next, use gh commands to get context about the issue:
   - Use `gh issue view <ISSUE_NUMBER>` to retrieve the current issue's details
   - Use `gh search issues` to find similar issues that might provide context for proper categorization
   - You have access to these Bash commands:
     - Bash(gh label list:\*) - to get available labels
     - Bash(gh issue view:\*) - to view issue details
     - Bash(gh issue edit:\*) - to apply labels to the issue
     - Bash(gh search:\*) - to search for similar issues

3. Analyze the issue content, considering the live `gh label list` output as authoritative. The current repository taxonomy includes:
   - The issue title and description
   - The type of issue: `type(bug)`, `type(deps)`, `type(docs)`, `type(enhancement)`, `type(fix)`, `type(question)`, or `type(refactor)`
   - Technical areas mentioned: `area(automation)`, `area(ci)`, `area(cli)`, `area(deps)`, `area(desktop)`, `area(docs)`, `area(flake)`, `area(gpu)`, `area(hooks)`, `area(nightly)`, `area(nix)`, `area(packages)`, or `area(scripts)`
   - Relevant flake inputs: `input(nixpkgs)`, `input(flake-utils)`, or `input(git-hooks)`
   - Severity or priority indicators: `priority(p1)` is critical/blocking, `priority(p2)` is important but not blocking, and `priority(p3)` is low-priority cleanup or polish
   - Status labels such as `status(backlog)`, `status(good-first-issue)`, `status(help-wanted)`, `status(invalid)`, `status(needs-manual-review)`, `status(recovered)`, `status(security-review-approved)`, `status(WIP)`, or `status(wontfix)`
   - Special focus labels such as `focus(security)`, `focus(hardening)`, `focus(hash-mismatch)`, `focus(performance)`, or `focus(validation)`
   - Whether the issue originates upstream in Logseq itself: use `origin(upstream)`
   - Whether the issue was created or maintained by automation: use `origin(automated)`

4. Select appropriate labels from the available labels list:
   - Choose labels that accurately reflect the issue's nature
   - Be specific but comprehensive
   - Apply exactly one `type(...)` label whenever any label is applied
   - Apply at most one `status(...)` label and at most one `priority(...)` label
   - Apply any relevant `area(...)`, `input(...)`, `focus(...)`, and `origin(...)` labels
   - Do NOT apply `status(duplicate)` - duplicate detection is handled by a separate workflow.

5. Apply the selected labels:
   - Use `gh issue edit` to apply your selected labels
   - DO NOT post any comments explaining your decision
   - DO NOT communicate directly with users
   - If no labels are clearly applicable, do not apply any labels

IMPORTANT GUIDELINES:

- Be thorough in your analysis
- Only select labels from the live `gh label list` output
- DO NOT post any comments to the issue
- Your ONLY action should be to apply labels using gh issue edit
- Apply a label only when the issue clearly matches it; when in doubt, skip it
- Treat the `gh label list` output as the authoritative label set
- Always apply exactly one `type(...)` label if applying labels
- Apply area labels only when the component or workflow surface is explicit
- Apply priority labels only when severity is clearly stated or obvious, such as a broken release pipeline for `priority(p1)`
