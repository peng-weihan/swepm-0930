#!/bin/bash
set -euo pipefail
cd /testbed
git apply --whitespace=nowarn /solution/gold.patch
git apply --check /solution/reference-correction.patch
git apply --whitespace=nowarn /solution/reference-correction.patch
