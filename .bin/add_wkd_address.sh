#!/bin/sh
set -eu

# ./add_wkd_address.sh <email address>
main()
{
    readonly address="$1"
    readonly filename="$(get_filename "$address")"

    gpg --export "$address" \
        >"www/.well-known/openpgpkey/hu/${filename}"
}

# get_filename <email address>
get_filename()
{
    gpg-wks-client --print-wkd-hash "$1" \
        | cut -d' ' -f1
}

main "$@"
