document.addEventListener("DOMContentLoaded", async function(event) {
    var content = await fetch('karlsen.fr.ascii')
        .then((response) => response.text())
        .then((data) => {
            return data;
        }
    );

    document.getElementById('hostname-pre').innerHTML = content;
});

/* PGP key dialog
 *
 * The published key is a binary OpenPGP transferable public key, so the
 * fingerprint and the armoured form are both derived from it in the browser.
 * Nothing is hard-coded: whatever is served is what gets shown.
 */
document.addEventListener('DOMContentLoaded', function() {
    const link = document.getElementById('pgp-link');
    const dialog = document.getElementById('pgp-dialog');

    if (!link || !dialog || !window.crypto?.subtle || typeof HTMLDialogElement === 'undefined')
        return;     // leave the plain download link alone

    let loaded = null;

    link.addEventListener('click', async function(event) {
        event.preventDefault();
        dialog.showModal();

        if (loaded === null) {
            loaded = render(link.getAttribute('href')).catch(function(err) {
                loaded = null;  // allow a retry on the next click
                document.getElementById('pgp-error').textContent =
                    'Could not load the key: ' + err.message;
            });
        }
    });

    document.getElementById('pgp-close').addEventListener('click', () => dialog.close());

    // Click outside the content closes the dialog
    dialog.addEventListener('click', function(event) {
        if (event.target === dialog) dialog.close();
    });

    document.querySelectorAll('#pgp-dialog button.copy').forEach(function(button) {
        button.addEventListener('click', async function() {
            const source = document.getElementById(button.dataset.copy);
            const icon = button.querySelector('use');

            try {
                // Prefer the ungrouped value where the display is spaced out
                await navigator.clipboard.writeText(source.dataset.raw || source.textContent);
                icon.setAttribute('href', '#icon-check');
            } catch {
                button.classList.add('failed');
            }

            setTimeout(function() {
                icon.setAttribute('href', '#icon-copy');
                button.classList.remove('failed');
            }, 1500);
        });
    });

    async function render(url) {
        const response = await fetch(url);
        if (!response.ok) throw new Error('HTTP ' + response.status);
        const key = new Uint8Array(await response.arrayBuffer());

        const packets = parse(key);
        const pub = packets.find((p) => p.tag === 6);
        if (!pub) throw new Error('no public-key packet');

        const fpr = await fingerprint(pub.body);
        const uids = packets.filter((p) => p.tag === 13)
            .map((p) => new TextDecoder().decode(p.body));

        const fprNode = document.getElementById('pgp-fpr');
        fprNode.textContent = group(fpr);
        fprNode.dataset.raw = fpr;
        document.getElementById('pgp-keyid').textContent = fpr.slice(-16);
        document.getElementById('pgp-uid').textContent = uids.join('\n') || '(none)';
        document.getElementById('pgp-created').textContent = date(keyCreated(pub.body));
        document.getElementById('pgp-expires').textContent = expiry(pub.body, packets);
        document.getElementById('pgp-armor').textContent = armor(key);

        /* Name the download after the key's own user ID, so the address does
         * not have to sit in the page source for scrapers to harvest. */
        const address = (uids[0] || '').match(/<([^>]+)>/);
        if (address) document.getElementById('pgp-download').download = address[1] + '.pgp';
    }

    /* Split a packet stream into {tag, body}. Handles both the old and the
     * new header format; partial body lengths are not used by key files. */
    function parse(buf) {
        const out = [];
        let i = 0;

        while (i < buf.length) {
            const ctb = buf[i++];
            if (!(ctb & 0x80)) throw new Error('malformed packet stream');
            let tag, len;

            if (ctb & 0x40) {
                tag = ctb & 0x3f;
                const o = buf[i++];
                if (o < 192) len = o;
                else if (o < 224) len = ((o - 192) << 8) + buf[i++] + 192;
                else if (o === 255) { len = read32(buf, i); i += 4; }
                else throw new Error('partial body length');
            } else {
                tag = (ctb >> 2) & 0x0f;
                const lt = ctb & 0x03;
                if (lt === 0) len = buf[i++];
                else if (lt === 1) { len = (buf[i] << 8) | buf[i + 1]; i += 2; }
                else if (lt === 2) { len = read32(buf, i); i += 4; }
                else throw new Error('indeterminate length');
            }

            out.push({tag: tag, body: buf.subarray(i, i + len)});
            i += len;
        }

        return out;
    }

    function read32(buf, i) {
        return ((buf[i] << 24) | (buf[i + 1] << 16) | (buf[i + 2] << 8) | buf[i + 3]) >>> 0;
    }

    /* RFC 4880: a v4 fingerprint is SHA-1 over 0x99, a two-octet length,
     * and the public-key packet body. */
    async function fingerprint(body) {
        const pre = new Uint8Array(3 + body.length);
        pre[0] = 0x99;
        pre[1] = body.length >> 8;
        pre[2] = body.length & 0xff;
        pre.set(body, 3);

        const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', pre));
        return [...digest].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    }

    function keyCreated(body) {
        return read32(body, 1);             // body[0] is the version octet
    }

    function date(seconds) {
        return new Date(seconds * 1000).toISOString().slice(0, 10);
    }

    /* The key expiration time (subpacket 9) lives in the hashed area of the
     * primary key's own self-signature, and is a count of seconds from the
     * key's creation. Subkey bindings (0x18) carry their own, narrower
     * expiry, so those signatures are skipped. */
    function expiry(body, packets) {
        for (const packet of packets) {
            if (packet.tag !== 2) continue;

            const sig = packet.body;
            if (sig[0] !== 4) continue;         // v4 signatures only

            const type = sig[1];
            if (!((type >= 0x10 && type <= 0x13) || type === 0x1f)) continue;

            const seconds = subpacket9(sig);
            if (seconds === null) continue;

            const at = keyCreated(body) + seconds;
            return date(at) + (at * 1000 < Date.now() ? ' (expired)' : '');
        }

        return 'never';
    }

    function subpacket9(sig) {
        const end = 6 + ((sig[4] << 8) | sig[5]);   // hashed subpacket area
        let i = 6;

        while (i < end) {
            let len;
            const o = sig[i++];
            if (o < 192) len = o;
            else if (o < 255) len = ((o - 192) << 8) + sig[i++] + 192;
            else { len = read32(sig, i); i += 4; }

            if ((sig[i] & 0x7f) === 9) return read32(sig, i + 1);
            i += len;                                // len counts the type octet
        }

        return null;
    }

    function group(fpr) {
        return (fpr.match(/.{1,4}/g) || []).join(' ');
    }

    function base64(buf) {
        let s = '';
        for (const b of buf) s += String.fromCharCode(b);
        return btoa(s);
    }

    function crc24(buf) {
        let crc = 0xb704ce;

        for (const b of buf) {
            crc ^= b << 16;
            for (let k = 0; k < 8; k++) {
                crc <<= 1;
                if (crc & 0x1000000) crc ^= 0x1864cfb;
            }
        }

        return crc & 0xffffff;
    }

    function armor(buf) {
        const c = crc24(buf);
        const check = base64(new Uint8Array([(c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff]));

        return '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n'
            + (base64(buf).match(/.{1,64}/g) || []).join('\n')
            + '\n=' + check + '\n'
            + '-----END PGP PUBLIC KEY BLOCK-----';
    }
});
