#!/bin/bash
set -euo pipefail
cd /testbed
git apply --whitespace=nowarn /solution/gold.patch
