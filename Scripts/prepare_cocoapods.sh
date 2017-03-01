SCHEME=$1
if [ -z "$SCHEME" ]
then
  echo "\nUsage: ${0} <Scheme name: \"CBL ObjC\" or \"CBL Swift\">\n\n" 
  exit 1
fi

echo "Preparing CouchbaseLite framework ..."

rm -rf frameworks
sh Scripts/build_framework.sh -s "$SCHEME" -p ios -o frameworks > ios-build.log
sh Scripts/build_framework.sh -s "$SCHEME" -p tvos -o frameworks > tvos-build.log
sh Scripts/build_framework.sh -s "$SCHEME" -p macos -o frameworks > macos-build.log
