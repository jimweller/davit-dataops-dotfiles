---
name: worktree
description: Git worktree management for parallel branch development. Use for creating, merging, rebasing, and removing worktrees.
user-invocable: true
argument-hint: "[create|list|merge|rebase|remove] [branch-name]"
---

STARTER_CHARACTER = 🎋

# Git Worktree Management

Manage git worktrees for parallel branch development. Each operation runs standard git commands.

Arguments: $ARGUMENTS

- First argument is the operation. Second argument is the branch name (required for create, merge, rebase, remove).
- If $ARGUMENTS is empty, default to `list`.

## Path Calculation

All operations derive paths from git:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
PARENT_DIR=$(dirname "$REPO_ROOT")
WORKTREE_DIR="$PARENT_DIR/$BRANCH_NAME"
```

## Operations

### create <branch>

Create a new worktree as a sibling directory with a new branch.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
git worktree add "$(dirname "$REPO_ROOT")/<branch>" -b <branch>
```

After creation, remind the user:
- Run `/worktree-secrets` in the new worktree to copy `.envrc` and GPG keys
- Open a new terminal in the worktree directory

### list

Show all worktrees.

```bash
git worktree list
```

### merge

Merge the current worktree's branch into main. Run from the feature worktree.

**Pre-check:** Verify the current branch is NOT main. If on main, refuse — there's nothing to merge.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
MAIN_DIR="$(dirname "$REPO_ROOT")/main"

git -C "$MAIN_DIR" fetch origin && git -C "$MAIN_DIR" pull
git -C "$MAIN_DIR" merge "$BRANCH"
git -C "$MAIN_DIR" push origin main
```

If there are conflicts, help the user resolve them before pushing.

### rebase <branch>

Rebase a branch onto the latest main. Must be run from within the branch's worktree.

**Pre-check:** Verify the current branch matches `<branch>`. If not, refuse and instruct the user to switch to the correct worktree.

```bash
git fetch origin
git rebase origin/main
```

If there are conflicts, help the user resolve them. After successful rebase, remind the user that force-push is required if the branch was previously pushed (but only with explicit permission per safety rules).

### remove <branch>

Remove a worktree and delete its branch. Must be run from the main worktree.

**Pre-checks:**
1. Verify the current worktree is the main branch. If not, refuse.
2. Verify the branch is merged into main using `git branch --merged`. If not merged, refuse and instruct the user to merge first.

```bash
git worktree remove "$(dirname "$REPO_ROOT")/<branch>"
git branch -d <branch>
```

If `git branch -d` fails with "not fully merged", stop and tell the user to merge first. Never use `git branch -D`.

## Safety Rules

- Local merges only. Do not create pull requests.
- If the worktree has unstaged or uncommited work during remove operation, ask the user about merging or forcing delete
- Never delete a worktree branch manually. Only use `git worktree remove`
- Never delete a worktree directory manually. Always use `git worktree remove`.
- Never force push without explicit user permission.
- Derive paths from `git rev-parse --show-toplevel` and `dirname`. Never hardcode paths.
