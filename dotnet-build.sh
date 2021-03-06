#!/bin/bash
# return failing exit code if any command fails
set -e

# enable nullglob - allows filename patterns which match no files to expand to a null string, rather than themselves
shopt -s nullglob

ROOTDIRECTORY="/api"

# go to the workdir
if [ -n "$BITBUCKET_CLONE_DIR" ]
then
    cd "$BITBUCKET_CLONE_DIR" || return
    ROOTDIRECTORY="$BITBUCKET_CLONE_DIR"
else
    cd /api || return
fi

# Add nuget source if access token is set
if [ -n "$MYGET_ACCESS_TOKEN" ]
then
    echo "Adding private myget source"
    SOURCE="https://www.myget.org/F/inforit/auth/$MYGET_ACCESS_TOKEN/api/v3/index.json"
    VAR=$(sed "/<\/packageSources>/i <add key=\"inforit.org\" value=\"$SOURCE\" protocolVersion=\"3\" />" ~/.nuget/NuGet/NuGet.Config)
    echo "$VAR" > ~/.nuget/NuGet/NuGet.Config
fi

CS_PROJECT_FILE="Api/Api.csproj"
CS_PROJECT_NAME="Api"
DIST="./dist"
RELEASE="Release"

# change project name from default "Api"
if [ -n "$PROJECT_NAME" ]
then
  CS_PROJECT_NAME="$PROJECT_NAME"
fi

# change project file location from default "Api.csproj" if specified
if [ -n "$PROJECT_FILE" ]
then
  CS_PROJECT_FILE="$PROJECT_FILE"
fi

PROJECT_DIST="$DIST/$CS_PROJECT_NAME"
ARTIFACTS_DIST="$DIST/artifacts"``

rm -rf ./**/bin
rm -rf ./**/obj
rm -rf "$DIST"

# create artifacts dir
mkdir -p "$ARTIFACTS_DIST"

# clean dependencies
echo "cleaning $CS_PROJECT_FILE"
dotnet clean $CS_PROJECT_FILE

# restore dependencies
echo "restoring $CS_PROJECT_FILE"
dotnet restore $CS_PROJECT_FILE

# build project
echo "building $CS_PROJECT_FILE"
dotnet build -c $RELEASE --no-restore $CS_PROJECT_FILE

# run tests
echo "running tests"
for f in *.Test/*.csproj
do
  echo "Processing $f file..."
  dotnet test "$f" -c $RELEASE -r "$DIST/test-results" /p:CollectCoverage=true /p:CoverletOutputFormat="opencover" /p:CoverletOutput="$DIST/test-coverlet" 
done

# collect codecoverage files and generate report for sonarcloud (warning is for backwards compatability)
reportgenerator -reports:"**/*.opencover*.xml" -targetdir:"$DIST/coverage" -reporttypes:"Cobertura;HTMLInline;HTMLChart;SonarQube" || echo -e "\033[33mWARNING: codecoverage not succesfull\033[0m"

# publish
echo "publishing $CS_PROJECT_FILE"
dotnet publish -c $RELEASE -o "$PROJECT_DIST" $CS_PROJECT_FILE

# copy deployment files over
echo "copying deployment files $CS_PROJECT_FILE"
cp -r deployment/ $PROJECT_DIST

# generate artifacts dir
echo "generating artifacts"
cd "$PROJECT_DIST"

zip -r "$ROOTDIRECTORY/$ARTIFACTS_DIST/$CS_PROJECT_NAME.zip" "."
