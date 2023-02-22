# ESnet Notes

# Branch Updates

## To update the `main` branch:
- git clone git@gitlab.es.net:ht/open-nic-shell
  or just use an existing clone if you have one available
- cd open-nic-shell
- git remote add upstream https://github.com/xilinx/open-nic-shell
- git remote update
- git checkout main
- git branch --set-upstream-to=upstream/main
- git pull --ff-only
- git push -nv origin

***** REVIEW THE OUTPUT TO ENSURE THAT IT WILL PUSH WHAT IS WANTED
- git push -v origin

## To backup the `esnet-patches` branch:
- git push -v origin origin/esnet-patches:refs/heads/attic/esnet-patches-\<yyyy-mm-dd\>

## To update the `esnet-patches` branch:
- git checkout -b esnet-patches-dev origin/esnet-patches
- git rebase upstream/main
- git push -v origin esnet-patches-dev:esnet-patches-dev

***** REVIEW origin/esnet-patches-dev TO ENSURE THAT IT WILL PUSH WHAT IS WANTED

- git push --force origin origin/esnet-patches-dev:esnet-patches
