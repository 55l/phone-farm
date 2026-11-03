#!/bin/bash
set -e
cd "$(dirname "$0")"
# node@24 is keg-only in Homebrew, so its bin directory is listed explicitly.
export PATH="/opt/homebrew/opt/node@24/bin:/usr/local/opt/node@24/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
npm run local:stop
