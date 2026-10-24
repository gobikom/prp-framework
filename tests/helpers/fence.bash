# Shared fence extractor (prp-framework#151): every behaviour test extracts its bash fence
# through here, so the same extraction works for all 7 EXPECTED_FILES — including gemini's
# TOML wrapper, whose raw triple-quoted string diverges byte-for-byte from the canonical
# markdown text (string escaping) and must be decoded with tomllib first.

prompt_text() { # <file> -> the file's markdown prompt text on stdout
  case "$1" in
    *.toml)
      python3 -I -c 'import sys,tomllib; sys.stdout.write(tomllib.load(open(sys.argv[1],"rb"))["prompt"])' "$1"
      ;;
    *)
      cat "$1"
      ;;
  esac
}

fence() { # <file> <heading> -> the bash fence after <heading>, {NUMBER} filled in with 7
  local out
  out="$(prompt_text "$1" | awk -v want="$2" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' | sed 's/{NUMBER}/7/g')"
  if [ -z "$out" ]; then
    echo "fence: empty extraction for heading '$2' in $1" >&2
    return 1
  fi
  printf '%s\n' "$out"
}
