#!/bin/sh
set -eu

# ./gen_securitytxt.sh <e-mail address>
main()
{
    key_filename="$(get_key_filename "$1")"
    key_fingerprint="$(get_key_fingerprint "$key_filename")"

    rm -f www/.well-known/security.txt

    {
        printf -- 'Contact: mailto:%s\n' "$1"
        printf -- 'Expires: %s\n' "$(date -d '-9 month ago' +'%Y-%m-%dT%H:%M:%SZ')"
        printf -- 'Encryption: https://www.karlsen.fr/.well-known/openpgpkey/hu/%s\n' "$key_filename"
        printf -- 'Preferred-Languages: en, no, fr\n'
        printf -- 'Canonical: https://www.karlsen.fr/.well-known/security.txt\n'
    } >/tmp/security.unsigned.txt

    gpg --clearsign \
        --local-user "$key_fingerprint" \
        --output www/.well-known/security.txt \
        /tmp/security.unsigned.txt

    rm /tmp/security.unsigned.txt
}

# get_key_filename <e-mail address>
get_key_filename()
{
    gpg-wks-client --print-wkd-hash "$1" \
        | cut -d' ' -f1 \
        | grep . \
            || { printf -- 'Could not compute WKD hash for %s\n' "$1" >&2; exit 1; }
}

# get_key_fingerprint <key file>
get_key_fingerprint()
{
    gpg --show-keys --with-colons "www/.well-known/openpgpkey/hu/$1" \
        | awk -F: '/^pub:/ { pub = 1 } pub && /^fpr:/ { print $10; exit }' \
        | grep . \
            || { printf -- 'Could not read fingerprint from %s\n' "$1" >&2; exit 1; }
}

main "$@"
