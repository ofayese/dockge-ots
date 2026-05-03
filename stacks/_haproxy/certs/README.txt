Place PEM files here (full certificate chain + private key in one file per hostname or SNI bundle).
HAProxy bind uses: crt /volume1/docker/dockge/stacks/_haproxy/certs/
Do not commit real keys; this path is gitignored for *.pem except .gitkeep.
