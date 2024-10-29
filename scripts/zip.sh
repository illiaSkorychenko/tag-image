#!/bin/bash

for dir in ./dist/*; do
  if [ -d "$dir" ]; then
    zip -j "$dir.zip" "$dir/index.js"
  fi
done
