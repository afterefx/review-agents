#!/usr/bin/env bash
# Install the review agents and the /pre-pr skill into a project's .claude/ directory,
# or with --copilot into its .github/ directory for GitHub Copilot.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [--link | --copilot] [--force] [--review-template] <project-dir>

Copies agents/*.md into <project-dir>/.claude/agents/ and each skills/<name>/
into <project-dir>/.claude/skills/<name>/. Run it again to update the copies.

  --link             symlink to this repo instead of copying (local use only:
                     CI and other contributors will see broken links)
  --copilot          install for GitHub Copilot instead: agents go to
                     .github/agents/<name>.agent.md with Copilot frontmatter,
                     skills to .github/skills/<name>/
  --force            replace installed files that differ from this repo's versions
  --review-template  also copy templates/REVIEW.md into the project if it has
                     no REVIEW.md, .github/REVIEW.md or docs/REVIEW.md
  -h, --help         show this help
EOF
}

src_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mode=copy force=0 template=0 copilot=0 project=
while [ $# -gt 0 ]; do
  case $1 in
    --link) mode=link ;;
    --copilot) copilot=1 ;;
    --force) force=1 ;;
    --review-template) template=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "install.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$project" ] || { echo "install.sh: only one project directory allowed" >&2; exit 2; }
      project=$1 ;;
  esac
  shift
done
[ -n "$project" ] || { usage >&2; exit 2; }
# Copilot agents are rewritten on install, so there is nothing in this repo to link to.
[ "$copilot" -eq 0 ] || [ "$mode" = copy ] || { echo "install.sh: --link and --copilot can't be combined" >&2; exit 2; }
[ -d "$project" ] || { echo "install.sh: $project is not a directory" >&2; exit 1; }
project=$(cd "$project" && pwd -P)
[ "$project" != "$src_root" ] || { echo "install.sh: refusing to install into review-agents itself" >&2; exit 1; }

skipped=0

# True when <dest> already holds <src>'s content, either as a copy or as a link to it.
same() {
  [ "$1" -ef "$2" ] && return 0
  [ -e "$2" ] || return 1
  if [ -d "$1" ]; then diff -rq "$1" "$2" >/dev/null 2>&1; else cmp -s "$1" "$2"; fi
}

install_one() {
  local src=$1 dest=$2 rel=${2#"$project"/} verb
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    # Already installed the way this run would install it.
    if [ "$mode" = link ] && [ -L "$dest" ] && [ "$dest" -ef "$src" ]; then echo "  ok       $rel"; return; fi
    if [ "$mode" = copy ] && [ ! -L "$dest" ] && same "$src" "$dest"; then echo "  ok       $rel"; return; fi
    # Never discard local edits without --force. A broken symlink holds nothing to lose.
    if [ -e "$dest" ] && ! same "$src" "$dest" && [ "$force" -eq 0 ]; then
      echo "  SKIPPED  $rel (differs from review-agents; rerun with --force to replace)"
      skipped=$((skipped + 1))
      return
    fi
    rm -rf "$dest"
    verb=updated
  else
    verb=added
  fi
  if [ "$mode" = link ]; then ln -s "$src" "$dest"; else cp -R "$src" "$dest"; fi
  printf '  %-8s %s\n' "$verb" "$rel"
}

# Print a Claude Code agent file with its frontmatter rewritten for Copilot:
# tool names become Copilot's aliases, and `model: inherit` is dropped because
# Copilot reads `model` as a model name and inherits the default when it's unset.
copilot_agent() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0; print; next }
    fm && /^model:[ \t]*inherit[ \t]*$/ { next }
    fm && /^tools:/ {
      n = split(substr($0, 7), t, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        x = t[i]; gsub(/^[ \t]+|[ \t]+$/, "", x)
        if (x == "Read") x = "read"
        else if (x == "Grep" || x == "Glob") x = "search"
        else if (x == "Bash") x = "execute"
        else if (x == "Edit" || x == "Write") x = "edit"
        if (x == "" || x in seen) continue
        seen[x] = 1; out = out (out == "" ? "" : ", ") x
      }
      print "tools: " out; next
    }
    { print }
  ' "$1"
}

if [ "$copilot" -eq 1 ]; then
  root=.github
  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT
else
  root=.claude
fi

echo "Installing review-agents into $project/$root ($mode)"
mkdir -p "$project/$root/agents" "$project/$root/skills"
for f in "$src_root"/agents/*.md; do
  name=$(basename "$f" .md)
  if [ "$copilot" -eq 1 ]; then
    copilot_agent "$f" >"$stage/$name.agent.md"
    install_one "$stage/$name.agent.md" "$project/.github/agents/$name.agent.md"
  else
    install_one "$f" "$project/.claude/agents/$name.md"
  fi
done
for d in "$src_root"/skills/*/; do
  d=${d%/}
  install_one "$d" "$project/$root/skills/$(basename "$d")"
done

if [ "$template" -eq 1 ]; then
  if [ -e "$project/REVIEW.md" ] || [ -e "$project/.github/REVIEW.md" ] || [ -e "$project/docs/REVIEW.md" ]; then
    echo "  ok       REVIEW.md already exists, template not copied"
  else
    cp "$src_root/templates/REVIEW.md" "$project/REVIEW.md"
    echo "  added    REVIEW.md (fill in the <placeholders>)"
  fi
fi

if [ "$skipped" -gt 0 ]; then
  echo "$skipped item(s) skipped." >&2
  exit 1
fi
