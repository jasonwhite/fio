#!/bin/bash
if [ "$TRAVIS_REPO_SLUG" == "jasonwhite/io" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]; then
	git clone --recursive --branch=gh-pages https://github.com/${TRAVIS_REPO_SLUG}.git gh-pages

	cd gh-pages
	git config credential.helper "store --file=.git/credentials"
	echo "https://${GH_TOKEN}:@github.com" > .git/credentials
	git config --global user.name "travis-ci"
	git config --global user.email "travis@travis-ci.org"
	git config --global push.default simple

	echo -e "Generating DDoc...\n"
	sh ./generate.sh
	git add .
    git commit -m "Auto update docs from travis-ci build #$TRAVIS_BUILD_NUMBER"
	git push
	echo -e "Published DDoc to gh-pages.\n"
fi
