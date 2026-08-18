# shellcheck shell=bash
#
# changelog.sh — prepend a release section to CHANGELOG.md from git log.
#
# Sourced by deploy/deploy.sh. One component ("site") — this repository
# builds and ships a single artefact.
#
#   ## site 0.4 — 2026-08-17 (a1b2c3d)
#
# Kept in sync by hand with the copies in voxivium-mvp and
# voxivium-mvp-client. Three repositories, no shared module between them;
# the duplication is deliberate and small.
#
# The "commits since last release" range is derived from the changelog
# itself — the SHA in the most recent heading for the same component.
# No side-car state file and no git tags to keep in sync: the file that
# records history is the file that defines where history left off. If
# someone hand-edits an entry, keeping the (sha) intact is the only rule.

# changelog_prepend <component> <tag> <sha> [changelog_path]
#
# Writes a new section at the top of the entry list. Safe to call when
# CHANGELOG.md does not exist yet — it is created with a preamble.
# NOTE: no local variable here may be named `path`. In zsh `path` is tied
# to `PATH`, so `local path=CHANGELOG.md` empties the command search path
# and every subsequent `cat`/`sed`/`date` fails with "command not found".
# These scripts declare bash, but this file is sourceable and zsh is the
# shell people actually have open.
changelog_prepend() {
    local component="$1" tag="$2" sha="$3"
    local changelog_path="${4:-CHANGELOG.md}"
    local marker="<!-- releases below -->"

    if [[ ! -f "$changelog_path" ]]; then
        cat > "$changelog_path" <<EOF
# Changelog

Release history for the Voxivium marketing site, newest first. Sections
are written by \`deploy/deploy.sh\` from the git log, so an entry appears
when the site is actually deployed rather than when someone remembers to
write it down.

The version comes from the \`VERSION\` file at the repository root and
advances by one on every deploy. The short SHA in each heading is the
commit that was deployed, and is what the next deploy uses to work out
which commits are new — leave it in place when editing an entry by hand.

$marker
EOF
    fi

    # Where the previous release for THIS component left off. Empty on the
    # first run for a component, which is not an error — it just means the
    # range below is open-ended and gets capped.
    local last_sha
    last_sha=$(grep -m1 -E "^## ${component} " "$changelog_path" 2>/dev/null \
                 | sed -E 's/.*\(([0-9a-f]+)\).*/\1/' || true)

    local range_desc body
    if [[ -n "$last_sha" ]] && git cat-file -e "${last_sha}^{commit}" 2>/dev/null; then
        body=$(git log --no-merges --pretty=format:'- %s' "${last_sha}..HEAD" -- . 2>/dev/null || true)
        range_desc="since ${last_sha}"
    else
        # First entry for this component, or the recorded SHA is no longer
        # reachable (rebased/squashed history). Cap the list rather than
        # dumping the entire repository history into one section.
        body=$(git log --no-merges --pretty=format:'- %s' -n 20 2>/dev/null || true)
        range_desc="most recent 20 commits — no prior ${component} entry to measure from"
    fi

    if [[ -z "$body" ]]; then
        # Expected: deploys bump the version unconditionally, so a redeploy
        # with no new commits produces an empty range. Say so explicitly —
        # a heading with nothing under it reads like the generator broke.
        body="- No code changes since the previous ${component} release."
    fi

    local heading="## ${component} ${tag} — $(date -u +%Y-%m-%d) (${sha})"
    local tmp
    tmp=$(mktemp)

    # Splice with head/tail rather than awk: the body is multi-line, and
    # `awk -v body="$body"` rejects a value containing newlines on BSD awk
    # ("newline in string"), which is the awk on every Mac this runs on.
    local marker_line
    marker_line=$(grep -n -F -m1 "$marker" "$changelog_path" | cut -d: -f1)
    if [[ -z "$marker_line" ]]; then
        # Marker removed by hand. Put entries at the end rather than
        # guessing where the preamble stops.
        marker_line=$(wc -l < "$changelog_path" | tr -d ' ')
    fi

    {
        head -n "$marker_line" "$changelog_path"
        printf '\n%s\n\n%s\n\n<sub>%s</sub>\n' "$heading" "$body" "$range_desc"
        tail -n +$((marker_line + 1)) "$changelog_path"
    } > "$tmp" && mv "$tmp" "$changelog_path"
}
