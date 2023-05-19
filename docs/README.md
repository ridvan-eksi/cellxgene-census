# API Documentation

The documentation website is currently hosted on https://chanzuckerberg.github.io/cellxgene-census/.

The documentation site is rebuilt each time a tag is created on the repo, which happens on release. This will include the Sphinx website (for the Python API) and the `pkgdown` website (for the R API).

A full rebuild can also be triggered manually as the workflow supports `workflow_dispatch`. This should be done if a bug in the documentation is found and a release is not necessary.