#!/bin/bash

set -e

function usage 
{
  echo "Usage: ${0} [delete-all]"
}

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
    --delete-all)
    DELETE_ALL="Y"
    ;;
    *)
    usage
    exit 1
    ;;
  esac
  shift
done

if [ -z "$DELETE_ALL" ]
then
  shopt -s nullglob
  i=0
  for fname in ~/Library/Logs/DiagnosticReports/xctest*.crash ; do
     i=$((i+1))
     echo -e ">> Crash Log #$i : $fname\n"
     cat $fname
  done
  if [[ $i = 0 ]]; then
    echo "No crash logs found"
  fi
else
  echo "Delete all xctest crash logs ..."
  rm -f ~/Library/Logs/DiagnosticReports/xctest*.crash
fi
