#!/usr/bin/env bash
# Install the review agents and the /pre-pr skill into a project's .claude/ directory.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [--link] [--force] [--review-template] <project-dir>

Copies agents/*.md into <project-dir>/.claude/agents/ and each skills/<name>/
into <project-dir>/.claude/skills/<name>/. Run it again to update the copies.

  --link             symlink to this repo instead of copying (local use only:
                     CI and other contributors will see broken links)
  --force            replace installed files that differ from this repo's versions
  --review-template  also copy templates/REVIEW.md into the project if it has
                     no REVIEW.md, .github/REVIEW.md or docs/REVIEW.md
  -h, --help         show this help
EOF
}

src_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
mode=copy force=0 template=0 project=
while [ $# -gt 0 ]; do
  case $1 in
    --link) mode=link ;;
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

echo "Installing review-agents into $project/.claude ($mode)"
mkdir -p "$project/.claude/agents" "$project/.claude/skills"
for f in "$src_root"/agents/*.md; do
  install_one "$f" "$project/.claude/agents/$(basename "$f")"
done
for d in "$src_root"/skills/*/; do
  d=${d%/}
  install_one "$d" "$project/.claude/skills/$(basename "$d")"
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
