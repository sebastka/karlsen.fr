#!/bin/sh
set -eu

# ./gen_sri.sh
# For every local subresource www/index.html references with an integrity
# attribute: recompute its SRI hash, point the reference at a content-hashed
# symlink (style.css -> style.<version>.css) and drop the previous symlink.
#
# The symlink means the URL changes whenever the file does, so the asset can be
# served immutable without a build step, and a stale cache can never be paired
# with a fresh index.html.
main()
{
    html=www/index.html

    for ref in $(get_subresources "$html"); do
        file="$(strip_version "$ref")"
        path="www/$file"
        [ -f "$path" ] || { printf -- 'Referenced file not found: %s\n' "$path" >&2; exit 1; }

        hash="$(get_hash "$path")"
        versioned="$(add_version "$file" "$(get_version "$path")")"

        link_asset www "$file" "$versioned"
        set_ref "$html" "$ref" "$versioned" "$hash"

        printf -- '%s\t%s\n' "$versioned" "$hash"
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

# strip_version <reference>       style.1a2b3c4d.css -> style.css
strip_version()
{
    printf -- '%s\n' "$1" | sed -E 's/\.[0-9a-f]{8}\.([^.]+)$/.\1/'
}

# add_version <file> <version>    style.css 1a2b3c4d -> style.1a2b3c4d.css
add_version()
{
    printf -- '%s.%s.%s\n' "${1%.*}" "$2" "${1##*.}"
}

# get_hash <file>                 the SRI digest
get_hash()
{
    printf -- 'sha384-%s\n' "$(openssl dgst -sha384 -binary "$1" | openssl base64 -A)"
}

# get_version <file>              short digest used in the filename
get_version()
{
    openssl dgst -sha256 -hex "$1" | sed -E 's/^.* //' | cut -c1-8
}

# link_asset <dir> <file> <versioned>
# Point <versioned> at <file> and remove any earlier version of it
link_asset()
{
    name="${2%.*}"
    ext="${2##*.}"

    for old in "$1/$name".*."$ext"; do
        [ -L "$old" ] || continue                   # never touch real files
        [ "${old##*/}" = "$3" ] && continue
        rm -- "$old"
    done

    ln -sf -- "$2" "$1/$3"
}

# set_ref <html file> <old reference> <new reference> <hash>
# Rewrite the href/src and the integrity that belongs to it
set_ref()
{
    awk -v want="$2" -v ref="$3" -v hash="$4" '
        /(href|src)="[^":]*"/ {
            match($0, /(href|src)="[^":]*"/)
            cur = substr($0, RSTART, RLENGTH)
            sub(/^(href|src)="/, "", cur)
            sub(/"$/, "", cur)

            if (cur == want) {
                attr = substr($0, RSTART, index(substr($0, RSTART, RLENGTH), "=") - 1)
                $0 = substr($0, 1, RSTART - 1) attr "=\"" ref "\"" substr($0, RSTART + RLENGTH)
                active = 1
            } else
                active = 0
        }

        /integrity="sha384-/ && active { sub(/sha384-[^"]*/, hash); active = 0 }
        { print }
    ' "$1" >"$1.tmp"

    mv -- "$1.tmp" "$1"
}

main "$@"
