# Deterministic Markdown chunker used by the narrow Bash driver action. It
# writes chunk bodies as files and a tab-separated metadata manifest; Bash owns
# the JSON output shape and hashing. A chunk never crosses a heading boundary.

function flush_chunk(    path) {
  if (chunk_words == 0) {
    return
  }
  chunk_count++
  path = sprintf("%s/chunk-%04d.txt", out_dir, chunk_count)
  printf "%s", chunk_text > path
  close(path)
  gsub(/\t/, " ", chunk_section)
  printf "%d\t%d\t%d\t%d\t%d\t%d\t%s\n", \
    chunk_count, chunk_start, chunk_end, chunk_page_start, chunk_page_end, \
    chunk_words, chunk_section >> manifest
  close(manifest)
  chunk_text = ""
  chunk_words = 0
  chunk_start = 0
  chunk_end = 0
  chunk_page_start = current_page
  chunk_page_end = current_page
  chunk_section = current_section
}

function begin_chunk() {
  if (chunk_words == 0) {
    chunk_start = body_offset
    chunk_page_start = current_page
    chunk_page_end = current_page
    chunk_section = current_section
  }
}

function add_words(line,    words, count, word_index, candidate) {
  count = split(line, words, /[[:space:]]+/)
  for (word_index = 1; word_index <= count; word_index++) {
    if (words[word_index] == "") {
      continue
    }
    if (chunk_words >= target_words) {
      flush_chunk()
    }
    begin_chunk()
    candidate = chunk_words == 0 ? words[word_index] : " " words[word_index]
    chunk_text = chunk_text candidate
    chunk_words++
    chunk_end = body_offset + length(line)
    chunk_page_end = current_page
  }
  chunk_text = chunk_text "\n"
}

BEGIN {
  manifest = out_dir "/manifest.tsv"
  current_page = 1
  current_section = ""
  in_frontmatter = 0
  body_offset = 0
}

{
  line = $0
  if (NR == 1 && line == "---") {
    in_frontmatter = 1
    next
  }
  if (in_frontmatter) {
    if (line == "---") {
      in_frontmatter = 0
    }
    next
  }

  if (match(line, /^<!--[[:space:]]*page:([0-9][0-9][0-9])[[:space:]]*-->$/, page_match)) {
    current_page = page_match[1] + 0
    body_offset += length(line) + 1
    next
  }

  if (match(line, /^#{1,4}[[:space:]]+(.+)$/, heading_match)) {
    flush_chunk()
    current_section = heading_match[1]
    add_words(line)
    body_offset += length(line) + 1
    next
  }

  if (line == "") {
    if (chunk_words > 0) {
      chunk_text = chunk_text "\n"
      chunk_end = body_offset
    }
    body_offset++
    next
  }

  line_words = split(line, scratch, /[[:space:]]+/)
  if (chunk_words > 0 && chunk_words + line_words > target_words) {
    flush_chunk()
  }
  add_words(line)
  body_offset += length(line) + 1
}

END {
  flush_chunk()
}
