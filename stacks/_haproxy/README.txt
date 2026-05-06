Infrastructure folder for HAProxy (canonical config: haproxy.cfg next to these dirs):
  certs/  — PEM files only (full chain + private key, one file per bundle, .pem names).
            HAProxy bind uses ssl crt …/certs/ and loads every non-hidden file there;
            do not put README or other text in certs/ (only *.pem). *.pem is gitignored.
  maps/   — host.map (Host header -> backend name)

If the NAS already has /volume1/docker/haproxy.cfg (sibling of dockge/), keep that file as
a thin include of this tree only, or change HAProxy to -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg.

This is not a Dockge compose stack. Traefik stacks (traefik-ots / traefik-mft) remain the TLS path for services that use them; HAProxy here is the optional edge for host-published ports.

TLS — fixing “cannot open …/certs/ots.olutechsys.com.pem” (or any missing PEM)
  HAProxy refuses to start until every certificate path referenced on bind ssl crt … is readable.
  - Repo bind line uses a directory: ssl crt …/stacks/_haproxy/certs/  (trailing slash). HAProxy loads
    every *.pem in that directory for SNI. You need at least one valid bundle whose SANs cover the
    Host names you expose (often a wildcard under *.ots.olutechsys.com plus other zones as separate PEMs).
  - If your Synology copy under /volume1/@appdata/haproxy/haproxy.cfg still points at a single file
    …/certs/ots.olutechsys.com.pem, that file must exist OR change line 59 to match the repo directory form
    after git pull, then reload.
  - Build a HAProxy PEM (full chain + private key, concatenated in that order) from acme.sh output. Use one
    shell line — do not break inside the single-quoted sh -c '…' string (newlines become bogus cat args):
      sudo sh -c 'cat /volume1/certs/acme/ots-sub/fullchain.pem /volume1/certs/acme/ots-sub/privkey.pem > /volume1/docker/dockge/stacks/_haproxy/certs/ots.olutechsys.com.pem'
    (Or ots-sub.pem if you prefer; any *.pem name is fine when bind uses the certs/ directory.)
    Adjust paths if your acme layout differs (see stacks/acme-sh/SETUP.md). Then: chmod 640 that PEM.
  - Validate before reload (use the same -f path your package actually loads):
      sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg
    or: … -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg
