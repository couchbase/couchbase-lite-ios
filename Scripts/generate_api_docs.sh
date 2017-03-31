#!/bin/bash

set -e

function usage 
{
  echo "\nUsage: ${0} -o <Output Directory>\n" 
}

if ! gem query -i -n jazzy 1>/dev/null;
then
		echo "jazzy is required, please run [sudo] gem install jazzy to install."
    exit 3
fi

while [[ $# -gt 1 ]]
do
  key=${1}
  case $key in
      -o)
      OUTPUT_DIR=${2}
      shift
      ;;
      *)
      usage
      exit 3
      ;;
  esac
  shift
done

if [ -z "$OUTPUT_DIR" ]
then
  usage
  exit 4
fi

jazzy --clean --xcodebuild-arguments "-scheme,CBL Swift" --module CouchbaseLiteSwift --theme Scripts/Support/Theme --output ${OUTPUT_DIR}/CouchbaseLiteSwift 
jazzy --clean --objc --umbrella-header Objective-C/CouchbaseLite.h --framework-root . -m CouchbaseLite --theme Scripts/Support/Theme --output ${OUTPUT_DIR}/CouchbaseLite
