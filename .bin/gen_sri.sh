#!/bin/sh
set -eu

# ./gen_sri.sh
# Recompute the Subresource Integrity hashes in www/index.html for every
# local file it references with an integrity attribute.
main()
{
    html=www/index.html

    for file in $(get_subresources "$html"); do
        path="www/$file"
        [ -f "$path" ] || { printf -- 'Referenced file not found: %s\n' "$path" >&2; exit 1; }

        hash="$(get_hash "$path")"
        set_hash "$html" "$file" "$hash"
        printf -- '%s\t%s\n' "$file" "$hash"
    done
}

# get_subresources <html file>
# List local hrefs/srcs whose tag carries an integrity attribute
get_subresources()
{
    awk '
        /<(link|script)/       { tag = ""     }
        /(href|src)="[^":]*"/  { match($0, /(href|src)="[^":]*"/)
                                 tag = substr($0, RSTART, RLENGTH)
                                 sub(/^(href|src)="/, "", tag)
                                 sub(/"$/, "", tag) }
        /integrity="/ && tag   { print tag; tag = "" }
    ' "$1"
}

# get_hash <file>
get_hash()
{
    printf -- 'sha384-%s\n' "$(openssl dgst -sha384 -binary "$1" | openssl base64 -A)"
}

# set_hash <html file> <subresource> <hash>
# Replace the integrity value that follows this subresource's href/src
set_hash()
{
    awk -v want="$2" -v hash="$3" '
        /(href|src)="[^":]*"/ { match($0, /(href|src)="[^":]*"/)
                                cur = substr($0, RSTART, RLENGTH)
                                sub(/^(href|src)="/, "", cur)
                                sub(/"$/, "", cur) }
        /integrity="sha384-/ && cur == want { sub(/sha384-[^"]*/, hash) }
        { print }
    ' "$1" >"$1.tmp"

    mv -- "$1.tmp" "$1"
}

main "$@"
