#!/bin/bash

set -o errexit

GOFILES=$(find . -path './vendor' -prune -o -name '*.go' -print)

for file in $GOFILES; do
	if ! grep -q License "$file"; then
		echo "Bumping $file"
            	sed -i '1s/^/\/\/ SPDX-License-Identifier:Apache-2.0\n\n/' $file
	fi
done
