#!/bin/sh
set -eu

# ./add_wkd_address.sh <email address>
main()
{
    readonly address="$1"

    gpg --export "$address" \
        >"www/.well-known/openpgpkey/hu/$(get_filename "$address")"
}

# get_filename <email address>
get_filename()
{
    gpg-wks-client --print-wkd-hash "$1" \
        | cut -d' ' -f1
}

main "$@"
