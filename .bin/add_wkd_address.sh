#!/bin/sh
set -eu

# ./add_wkd_address.sh <e-mail address> <key fingerprint>
main()
{
    gpg --export "$2" \
        >"www/.well-known/openpgpkey/hu/$(get_filename "$1")"
}

# get_filename <email address>
get_filename()
{
    gpg-wks-client --print-wkd-hash "$1" \
        | cut -d' ' -f1
}

main "$@"
