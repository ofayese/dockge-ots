Infrastructure folder for HAProxy (canonical config: haproxy.cfg next to these dirs):
  certs/  — PEM files only (full chain + private key, one file per bundle, .pem names).
            HAProxy bind uses ssl crt …/certs/ and loads every non-hidden file there;
            do not put README or other text in certs/ (only *.pem). *.pem is gitignored.
  maps/   — host.map (Host header -> backend name)

If the NAS already has /volume1/docker/haproxy.cfg (sibling of dockge/), keep that file as
a thin include of this tree only, or change HAProxy to -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg.

This is not a Dockge compose stack. Traefik stacks (traefik-ots / traefik-mft) remain the TLS path for services that use them; HAProxy here is the optional edge for host-published ports.
