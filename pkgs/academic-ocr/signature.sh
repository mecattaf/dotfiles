set -euo pipefail

usage() {
  printf 'usage: academic-ocr-signature <text-file|->\n' >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
input=$1
if [[ $input != "-" ]]; then
  [[ -f $input ]] || {
    printf 'academic-ocr-signature: input is not a file: %s\n' "$input" >&2
    exit 2
  }
fi

# Text is normalized before shingling so line-wrap hyphenation, punctuation,
# case, and whitespace do not turn ordinary OCR jitter into disagreement.
# Thirty-two seeded MinHash components make the flow's positional mismatch
# score approximate trigram Jaccard distance while staying inside uint16.
sed ':join;$!{N;b join};s/-\n[[:space:]]*//g' "$input" \
  | iconv -c -f UTF-8 -t ASCII//TRANSLIT \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs '[:alnum:]' '\n' \
  | gawk '
      NF { token[++count] = $0 }
      END {
        if (count == 0) {
          print "academic-ocr-signature: normalized text is empty" > "/dev/stderr"
          exit 20
        }

        alphabet = " abcdefghijklmnopqrstuvwxyz0123456789"
        modulus = 65521
        for (slot = 1; slot <= 32; slot++) {
          a[slot] = ((slot * 2003 + 12345) % (modulus - 1)) + 1
          b[slot] = (slot * 7919 + 54321) % modulus
          minimum[slot] = modulus
        }

        shingle_count = count < 3 ? count : count - 2
        for (item = 1; item <= shingle_count; item++) {
          if (count < 3) {
            shingle = token[item]
          } else {
            shingle = token[item] " " token[item + 1] " " token[item + 2]
          }
          hash = 0
          for (character = 1; character <= length(shingle); character++) {
            code = index(alphabet, substr(shingle, character, 1))
            hash = (hash * 257 + code) % modulus
          }
          for (slot = 1; slot <= 32; slot++) {
            value = (a[slot] * hash + b[slot]) % modulus
            if (value < minimum[slot]) {
              minimum[slot] = value
            }
          }
        }

        printf "["
        for (slot = 1; slot <= 32; slot++) {
          printf "%s%d", slot == 1 ? "" : ",", minimum[slot]
        }
        print "]"
      }
    '
