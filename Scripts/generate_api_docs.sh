#!/bin/bash

set -e

function usage 
{
  echo "\nUsage: ${0} -o <Output Directory> [--EE]\n" 
}

if ! gem query -i -n jazzy 1>/dev/null;
then
		echo "jazzy is required, please run [sudo] gem install jazzy to install."
    exit 3
fi

while [[ $# -gt 0 ]]
do
  key=${1}
  case $key in
      -o)
      OUTPUT_DIR=${2}
      shift
      ;;
      --EE)
      EE="Y"
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

if [ -z "$EE" ]
then
  SCHEME="CBL Swift"
else
  SCHEME="CBL-EE Swift"
fi

jazzy --clean --xcodebuild-arguments "-scheme,$SCHEME,-sdk,iphonesimulator" --module CouchbaseLiteSwift --theme Scripts/Support/Theme --output ${OUTPUT_DIR}/CouchbaseLiteSwift 
jazzy --clean --objc --xcodebuild-arguments --objc,Objective-C/CouchbaseLite.h,--,-x,objective-c,-isysroot,$(xcrun --show-sdk-path --sdk iphonesimulator),-I,$(pwd) --module CouchbaseLite --theme Scripts/Support/Theme --output ${OUTPUT_DIR}/CouchbaseLite
