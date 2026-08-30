#!/usr/bin/env sh
# Create a minimal, uncompressed PDF used for local pdfgrep smoke tests.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:-"$script_dir/pdfgrep-smoke.pdf"}
output_dir=$(dirname -- "$output")
tmp_file="$output_dir/.pdfgrep-smoke.pdf.tmp"

mkdir -p -- "$output_dir"
trap 'rm -f -- "$tmp_file"' EXIT HUP INT TERM

content='BT
/F1 24 Tf
100 700 Td
(hello pdfgrep) Tj
ET'

offset() {
  wc -c < "$tmp_file" | tr -d '[:space:]'
}

printf '%%PDF-1.4\n' > "$tmp_file"

object_1=$(offset)
printf '%s\n' \
  '1 0 obj' \
  '<< /Type /Catalog /Pages 2 0 R >>' \
  'endobj' >> "$tmp_file"

object_2=$(offset)
printf '%s\n' \
  '2 0 obj' \
  '<< /Type /Pages /Kids [3 0 R] /Count 1 >>' \
  'endobj' >> "$tmp_file"

object_3=$(offset)
printf '%s\n' \
  '3 0 obj' \
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]' \
  '   /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>' \
  'endobj' >> "$tmp_file"

object_4=$(offset)
content_length=$(printf '%s\n' "$content" | wc -c | tr -d '[:space:]')
printf '4 0 obj\n<< /Length %s >>\nstream\n%s\nendstream\nendobj\n' \
  "$content_length" "$content" >> "$tmp_file"

object_5=$(offset)
printf '%s\n' \
  '5 0 obj' \
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica' \
  '   /Encoding /WinAnsiEncoding >>' \
  'endobj' >> "$tmp_file"

xref=$(offset)
printf 'xref\n0 6\n0000000000 65535 f \n' >> "$tmp_file"
for object in "$object_1" "$object_2" "$object_3" "$object_4" "$object_5"; do
  printf '%010d 00000 n \n' "$object" >> "$tmp_file"
done
printf 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%s\n%%%%EOF\n' "$xref" >> "$tmp_file"

mv -f -- "$tmp_file" "$output"
