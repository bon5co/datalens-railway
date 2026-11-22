# datalens-railway

Wrapper images that let [DataLens](https://github.com/datalens-tech/datalens) 2.9.0 (Apache-2.0, open-source BI and dashboards) run as a
Railway template. One `Dockerfile`, one build target per component (`db`, `temporal`, `control-api`, `data-api`, `us`, `ui-api`,
`meta-manager`, `auth`, `ui`), each published as `ghcr.io/bon5co/datalens-railway-<role>`.

DataLens runs nine containers that share RSA key pairs and master tokens, and its compose file ships the same public defaults for all of
them. The `db` image generates a fresh key set on first boot (kept on its volume), and serves it on the private network behind a secret
path; every other image fetches the keys it needs before starting the upstream entrypoint. Public sign-up is turned off.
