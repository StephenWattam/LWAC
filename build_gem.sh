#!/bin/sh
# 
# echo " Building user documentation..."
# cd user_docs
# rm -rf docs
# ruby compile.rb
# cd ..
#
#
cp doc/*.md .

echo "Building gem..."
gem build lwac.gemspec

mv README.md README.backup
rm *.md
mv README.backup README.md

