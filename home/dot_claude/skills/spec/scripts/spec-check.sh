#!/bin/sh
# spec-check.sh — lint a light-format SPEC.md against the house claim grammar
# (dotfiles skill `spec`, §4.4 of the 2026-09-30 projects-board sweep).
#
# Usage: spec-check.sh SPEC.md
# Exit 0: clean. Exit 1: one or more violations, one per line:
#   SPEC.md:<line>: <rule>
# Exit 2: usage error (bad args, file not found).
set -eu

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
	echo "usage: spec-check.sh SPEC.md" >&2
	exit 2
fi

DIR=$(dirname "$FILE")
PROVE="$DIR/PROVE.md"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# report() both prints and marks the log, so it works even when called
# from inside a `cmd | while read` pipeline subshell (POSIX sh forks one
# there; a shell counter would not survive it, a file write does).
report() {
	printf '%s:%s: %s\n' "$FILE" "$1" "$2"
	echo x >>"$LOG"
}

total=$(wc -l <"$FILE")
headings=$(grep -n '^## ' "$FILE" || true)

# --- Consumers: non-empty ---------------------------------------------------
cline=$(grep -n '^Consumers:' "$FILE" | head -1 || true)
if [ -z "$cline" ]; then
	report 0 "missing 'Consumers:' header"
else
	cln=${cline%%:*}
	cval=$(printf '%s\n' "$cline" | sed -E 's/^[0-9]+:Consumers:[[:space:]]*//')
	[ -z "$cval" ] && report "$cln" "Consumers: must be non-empty"
fi

# --- Fixed section order: Outcome, Rulings, Claims, Open questions, -------
# --- Out of scope (last); an optional append-only Tasks may follow. -------
want="## Outcome ## Rulings ## Claims ## Open questions ## Out of scope"
got=$(printf '%s\n' "$headings" | sed -E 's/^[0-9]+://; s/[[:space:]]+$//')
got_core=$(printf '%s\n' "$got" | grep -v '^## Tasks$' || true)
got_joined=$(printf '%s' "$got_core" | tr '\n' ' ' | sed 's/ $//')
if [ "$got_joined" != "$want" ]; then
	first_ln=$(printf '%s\n' "$headings" | head -1 | sed -E 's/:.*//')
	report "${first_ln:-0}" "section order must be exactly: Outcome, Rulings, Claims, Open questions, Out of scope (Tasks may follow, append-only)"
fi

# --- Empty sections only as 'Omitted: <reason>.' ----------------------------
printf '%s\n' "$headings" | while IFS=: read -r hln htext; do
	next_ln=$(printf '%s\n' "$headings" | awk -F: -v cur="$hln" '$1>cur{print $1; exit}')
	[ -z "$next_ln" ] && next_ln=$((total + 1))
	body=$(sed -n "$((hln + 1)),$((next_ln - 1))p" "$FILE" | sed '/^[[:space:]]*$/d')
	if [ -z "$body" ]; then
		report "$hln" "'$htext' is empty; write 'Omitted: <reason>.' instead of leaving it blank"
	fi
done

# --- Claims section body -----------------------------------------------
claims_start=$(printf '%s\n' "$headings" | grep '## Claims$' | head -1 | sed -E 's/:.*//' || true)
claims_end=$(printf '%s\n' "$headings" | awk -F: -v cur="${claims_start:-0}" '$1>cur{print $1; exit}')
[ -z "$claims_end" ] && claims_end=$((total + 1))

if [ -n "$claims_start" ]; then
	body=$(sed -n "$((claims_start + 1)),$((claims_end - 1))p" "$FILE" | awk -v off="$claims_start" '{print off+NR"\t"$0}')

	# Claim-id lines: full grammar, and exactly one prove/human binding.
	printf '%s\n' "$body" | grep -E '^[0-9]+	C[0-9]' | while IFS='	' read -r ln text; do
		bindings=$(printf '%s' "$text" | grep -oE '\[prove: P[0-9]+\.[0-9]+\]|\[human: H[0-9]+\]' | wc -l | tr -d ' ')
		if ! printf '%s' "$text" | grep -qE '^C[0-9]+\.[0-9]+ (\(tree\) )?.*→.*(\[prove: P[0-9]+\.[0-9]+\]|\[human: H[0-9]+\])'; then
			report "$ln" "malformed claim line (need 'C<n>.<n> [(tree)] <cond> → <observable>. [prove:|human: ...]')"
		fi
		[ "$bindings" -eq 0 ] && report "$ln" "claim has no [prove: Px]/[human: Hx] binding" || true
		[ "$bindings" -gt 1 ] && report "$ln" "claim has more than one [prove:]/[human:] binding" || true
	done

	# Lexicon ban.
	printf '%s\n' "$body" | while IFS='	' read -r ln text; do
		word=$(printf '%s' "$text" | grep -oiE '\<(should|ideally|robust|gracefully|properly)\>|as needed|e\.g\.|etc\.' | head -1)
		[ -n "$word" ] && report "$ln" "banned lexicon word '$word' in Claims" || true
	done

	# Model-name ban (runtimes belong only in the Tasks table).
	printf '%s\n' "$body" | while IFS='	' read -r ln text; do
		word=$(printf '%s' "$text" | grep -oiE '\<(opus|sonnet|haiku|fable|gpt|qwen)\>' | head -1)
		[ -n "$word" ] && report "$ln" "model name '$word' in Claims" || true
	done

	# Numerals need (given)/(GUESS) unless id, pinned version, or path.
	printf '%s\n' "$body" | grep -E '^[0-9]+	C[0-9]' | while IFS='	' read -r ln text; do
		stripped=$(printf '%s' "$text" |
			sed -E 's/^C[0-9]+\.[0-9]+[[:space:]]*//' |
			sed -E 's/\(tree\)//g' |
			sed -E 's/\[(prove|human): [^]]*\]//g' |
			sed -E 's#[A-Za-z0-9_.-]*/[A-Za-z0-9_./-]*##g' |
			sed -E 's/[0-9]+(\.[0-9]+)+/ /g')
		if printf '%s' "$stripped" | grep -qE '[0-9]' && ! printf '%s' "$text" | grep -qE '\((given|GUESS)\)'; then
			report "$ln" "numeral in claim needs '(given)' or '(GUESS)' (unless id, pinned version, or path)"
		fi
	done
fi

# --- Status ratified refuses (GUESS)/[BLOCKING] -----------------------------
if grep -qE '^Status: ratified' "$FILE"; then
	grep -noE '\(GUESS\)|\[BLOCKING\]' "$FILE" | while IFS=: read -r ln tag; do
		report "$ln" "Status: ratified but '$tag' still present"
	done
fi

# --- Every [prove: Px] has a row in PROVE.md --------------------------------
ids=$(grep -oE '\[prove: P[0-9]+\.[0-9]+\]' "$FILE" | sed -E 's/\[prove: (P[0-9]+\.[0-9]+)\]/\1/' | sort -u)
if [ -n "$ids" ]; then
	if [ ! -f "$PROVE" ]; then
		report 0 "PROVE.md not found beside $FILE; every [prove: Px] needs a row there"
	else
		for pid in $ids; do
			grep -qE "^\| *${pid} *\|" "$PROVE" || report 0 "prove id $pid has no row in $PROVE"
		done
	fi
fi

if [ -s "$LOG" ]; then
	exit 1
fi
exit 0
