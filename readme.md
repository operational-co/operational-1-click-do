This repo is the base for the Operational 1-Click Installer for Digital Ocean

This guide is primarily for the maintainer of the Operational project(Shash)

## How to update Operational version

First, drop this repo inside a fresh DO Droplet. Location is irrelevant - we use absolute paths

In the 010-setup.sh, git pull a newer version of Operational via tag

Then run the following scripts in this order:

scripts/010-setup.sh
scripts/prompt.sh

Then check and see if everything is working correctly. If yes, build a packer image via

`export DIGITALOCEAN_TOKEN=your_do_token_here`
`packer build operational-image.json`

This will automatically build and upload a built image to DO

## Gotchas

If the DO API key is expired, create a new one from DO's api section.
Only set full scopes for droplet and ssh. Set expiry to max 1 month.

operational-image.json is for building a file based image. Not needed but kept around for testing.

scripts/prompt.sh and files/usr/local/bin/prompt.sh are the same. Only difference is, scripts/prompt.sh is kept there for testing.