#!/bin/sh
set -eu

main()
{
    readonly contact='sebastian@karlsen.fr'
    readonly key_filename="$(get_key_filename "$contact")"

    rm -f www/.well-known/security.txt

    {
        printf -- 'Contact: mailto:%s\n' "$contact"
        printf -- 'Expires: %s\n' "$(date -d '-9 month ago' +'%Y-%m-%dT%H:%M:%SZ')"
        printf -- 'Encryption: https://www.karlsen.fr/.well-known/openpgpkey/hu/%s\n' "$key_filename"
        printf -- 'Preferred-Languages: en, no, fr\n'
        printf -- 'Canonical: https://www.karlsen.fr/.well-known/security.txt\n'
    } >/tmp/security.unsigned.txt

    gpg --clearsign \
        --local-user 94863C7F986D65E8 \
        --output www/.well-known/security.txt \
        /tmp/security.unsigned.txt

    rm /tmp/security.unsigned.txt
}

# get_key_filename <email address>
get_key_filename()
{
    gpg-wks-client --print-wkd-hash "$1" \
        | cut -d' ' -f1
}

main
