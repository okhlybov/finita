# GIT operations refcard

## Local working repository setup

git clone git@github.com:okhlybov/finita.git

cd finita

git config --local push.recurseSubmodules on-demand 

git config --local submodule.recurse true

git checkout next

git submodule update --init --force --remote