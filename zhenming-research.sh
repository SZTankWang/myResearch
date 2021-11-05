#!/usr/bin/env bash
#
# ------------------------------------------------------------------------------
# This script performs fault-localization on a Java project using the GZoltar
# command line interface either using instrumentation 'at runtime' or 'offline'.
#
# Usage:
# ./run.sh
#     --instrumentation <online|offline>
#     [--help]
#
# Requirements:
# - `java` and `javac` needs to be set and must point to the Java installation.
#
# ------------------------------------------------------------------------------

SCRIPT_DIR=$(cd `dirname ${BASH_SOURCE[0]}` && pwd)

source "/home/zhenming/research/getAllClasses.sh"
#
# Print error message and exit
#
die() {
  echo "$@" >&2
  exit 1
}

# ------------------------------------------------------------------ Envs & Args

GZOLTAR_VERSION="1.7.3-SNAPSHOT"
PID="Lang"
BID=4
STAR="*******************"

#use a consistent dir for holding different version of the project
UNI_DIR="/home/zhenming/research/${PID}/project" 
RES_BASE_DIR="/home/zhenming/research"

# read option
USAGE="Usage: ${BASH_SOURCE[0]} --instrumentation <online|offline> [--help]"
if [ "$#" -eq "0" ]; then
  die "$USAGE"
fi
mod_of_two=$(expr $# % 2)
if [ "$#" -ne "1" ] && [ "$mod_of_two" -ne "0" ]; then
  die "$USAGE"
fi

INSTRUMENTATION=""

while [[ "$1" = --* ]]; do
  OPTION=$1; shift
  case $OPTION in
    (--instrumentation)
      INSTRUMENTATION=$1;
      shift;;
    (--help)
      echo "$USAGE";
      exit 0;;
    (*)
      die "$USAGE";;
  esac
done

[ "$INSTRUMENTATION" != "" ] || die "$USAGE"
if [ "$INSTRUMENTATION" != "online" ] && [ "$INSTRUMENTATION" != "offline" ]; then
  die "$USAGE"
fi



while [ $BID -le 4 ]
do 
# return to the root dir
cd $RES_BASE_DIR
if [ $BID -ne 2 ];
then
echo "$STAR"
echo "running on buggy version $BID"

#make project dir
rm -rf "$UNI_DIR"
mkdir -p "$UNI_DIR"
[ -d "$UNI_DIR" ] || die "$UNI_DIR does not exist!"



#defects4j checkout
defects4j checkout -p $PID -v ${BID}b -w $UNI_DIR

## copy .starts folder if it exists
if [ -d ".starts" ]; then
  echo ".starts exist, copy to the project dir"
  mv ".starts" $UNI_DIR
else
  echo ".starts artifact does not exist, likely the first run!"
fi


#make lib dir
LIB_DIR="$RES_BASE_DIR/lib" 
if [ ! -d $LIB_DIR ]
then 
  pwd "LIB DIR not exist, creating!"
  mkdir -p "$LIB_DIR" || die "Failed to create $LIB_DIR!"
fi
[ -d "$LIB_DIR" ] || die "$LIB_DIR does not exist!"


cd $UNI_DIR

#change java version in pom.xml
echo "skipping pom-editing script in working dir ${SCRIPT_DIR}/project"

# python3 ../../script_modify_pom.py "${SCRIPT_DIR}/${PID}/project"

#
# Compile
#

echo "Compile project using STARTS"

#mvn starts: select will output all the affected test classes
#write those tests to an output file to be used by Gzoltar suite
#create selected-test beforehand
SELECTED_TEST="${RES_BASE_DIR}/test-selected.txt"
if [ -e $SELECTED_TEST ]
then
  pwd
  echo "removing test-selected.txt"
  rm ${SELECTED_TEST}
fi
touch "${RES_BASE_DIR}/test-selected.txt"

# compile using defects4j compile
echo "$STAR compiling using d4j $STAR"
defects4j compile
echo "$STAR running STARTS $STAR"


mvn edu.illinois:starts-maven-plugin:1.4-SNAPSHOT:select -Dmaven.test.skip=true -X -DtestClassesDir=$(pwd)/target/tests -DupdateSelectChecksums=true
#now, we got a list of test to run from STARTS, simply give it to GZoltar


SRC_DIR=${UNI_DIR}/target/classes
TEST_DIR=${UNI_DIR}/target/tests


# # Check whether GZOLTAR_CLI_JAR is set
export GZOLTAR_CLI_JAR="/home/zhenming/gzoltar/com.gzoltar.cli/target/com.gzoltar.cli-$GZOLTAR_VERSION-jar-with-dependencies.jar"
echo $SCRIPT_DIR
[ "$GZOLTAR_CLI_JAR" != "" ] || die "GZOLTAR_CLI is not set!"
[ -s "$GZOLTAR_CLI_JAR" ] || die "$GZOLTAR_CLI_JAR does not exist or it is empty! Please go to '$SCRIPT_DIR/..' and run 'mvn clean install'."

# # Check whether GZOLTAR_AGENT_RT_JAR is set
export GZOLTAR_AGENT_RT_JAR="/home/zhenming/gzoltar/com.gzoltar.agent.rt/target/com.gzoltar.agent.rt-$GZOLTAR_VERSION-all.jar"
[ "$GZOLTAR_AGENT_RT_JAR" != "" ] || die "GZOLTAR_AGENT_RT_JAR is not set!"
[ -s "$GZOLTAR_AGENT_RT_JAR" ] || die "$GZOLTAR_AGENT_RT_JAR does not exist or it is empty! Please go to '$SCRIPT_DIR/..' and run 'mvn clean install'."




# #
# # Prepare runtime dependencies
# #


JUNIT_JAR="$LIB_DIR/junit.jar"
if [ ! -s "$JUNIT_JAR" ]; then
  wget "https://repo1.maven.org/maven2/junit/junit/4.12/junit-4.12.jar" -O "$JUNIT_JAR" || die "Failed to get junit-4.12.jar from https://repo1.maven.org!"
fi
[ -s "$JUNIT_JAR" ] || die "$JUNIT_JAR does not exist or it is empty!"

HAMCREST_JAR="$LIB_DIR/hamcrest-core.jar"
if [ ! -s "$HAMCREST_JAR" ]; then
  wget -np -nv "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar" -O "$HAMCREST_JAR" || die "Failed to get hamcrest-core-1.3.jar from https://repo1.maven.org!"
fi
[ -s "$HAMCREST_JAR" ] || die "$HAMCREST_JAR does not exist or it is empty!"

BUILD_DIR="$UNI_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" || die "Failed to create $BUILD_DIR!"

##create classes file, make sure it exists
INCLUDE_CLASSES="/home/zhenming/research/$PID/allClasses.txt"
if [ -e $INCLUDE_CLASSES ];  then
  rm $INCLUDE_CLASSES
fi
touch  "/home/zhenming/research/$PID/allClasses.txt"

[ -e $INCLUDE_CLASSES ] || die "Failed to create allClasses.txt!"

#call get all classes function
getAllClasses $PID

#export cp.test from defects4j && maven compiled target path
cd $UNI_DIR
TEST_CP_DIR="$(defects4j export -p cp.test)"


#EXPORT relevant test file from test_selected.txt
# RELEVANT_TEST_FILE="/home/zhenming/research/test-selected.txt"
RELEVANT_TESTS=$(cat ${SELECTED_TEST} |  sed 's/$/#*/' | sed ':a;N;$!ba;s/\n/:/g')
# # ------------------------------------------------------------------------- Main




# #
# # Collect list of unit test cases to run
# #

echo "Collect list of unit test cases to run ..."

UNIT_TESTS_FILE="$BUILD_DIR/tests.txt"

java -cp "${TEST_CP_DIR}:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_CLI_JAR" \
  com.gzoltar.cli.Main listTestMethods ${TEST_DIR} \
    --outputFile "$UNIT_TESTS_FILE" \
    --includes ${RELEVANT_TESTS} || die "Collection of unit test cases has failed!"
[ -s "$UNIT_TESTS_FILE" ] || die "$UNIT_TESTS_FILE does not exist or it is empty!"

# #
# # Collect coverage
# #

SER_FILE="$BUILD_DIR/gzoltar.ser"

LOADED_CLASSES_FILE="/home/zhenming/research/$PID/allClasses.txt"
NORMAL_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/:/' | sed ':a;N;$!ba;s/\n//g')
INNER_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/$*:/' | sed ':a;N;$!ba;s/\n//g')
LOADED_CLASSES="$NORMAL_CLASSES$INNER_CLASSES"


if [ "$INSTRUMENTATION" == "online" ]; then
  echo "Perform instrumentation at runtime and run each unit test case in isolation ..."

  # Perform instrumentation at runtime and run each unit test case in isolation
  # switch to java 7
  export JAVA_HOME="/usr/lib/jvm/jdk1.7.0_80"
  echo "CHECK JAVA VERSION: $JAVA_HOME AND $(javac -version)"

  java -javaagent:$GZOLTAR_AGENT_RT_JAR=destfile=$SER_FILE,buildlocation="${SRC_DIR}",includes=${LOADED_CLASSES},excludes="",inclnolocationclasses=false,output="file" \
    -cp $TEST_CP_DIR:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_CLI_JAR \
    com.gzoltar.cli.Main runTestMethods \
      --testMethods "$UNIT_TESTS_FILE" \
      --collectCoverage || die "Coverage collection has failed!"
fi
# #offline mode is not ready --Zhenming
# elif [ "$INSTRUMENTATION" == "offline" ]; then
#   echo "Perform offline instrumentation ..."

#   # Backup original classes
#   BUILD_BACKUP_DIR="$SCRIPT_DIR/.build"
#   mv "$BUILD_DIR" "$BUILD_BACKUP_DIR" || die "Backup of original classes has failed!"
#   mkdir -p "$BUILD_DIR"

#   # Perform offline instrumentation
#   java -cp $BUILD_BACKUP_DIR:$GZOLTAR_AGENT_RT_JAR:$GZOLTAR_CLI_JAR \
#     com.gzoltar.cli.Main instrument \
#     --outputDirectory "$BUILD_DIR" \
#     $BUILD_BACKUP_DIR || die "Offline instrumentation has failed!"

#   echo "Run each unit test case in isolation ..."

#   # Run each unit test case in isolation
#   java -cp $BUILD_DIR:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_AGENT_RT_JAR:$GZOLTAR_CLI_JAR \
#     -Dgzoltar-agent.destfile=$SER_FILE \
#     -Dgzoltar-agent.output="file" \
#     com.gzoltar.cli.Main runTestMethods \
#       --testMethods "$UNIT_TESTS_FILE" \
#       --offline \
#       --collectCoverage || die "Coverage collection has failed!"

#   # Restore original classes
#   cp -R $BUILD_BACKUP_DIR/* "$BUILD_DIR" || die "Restore of original classes has failed!"
#   rm -rf "$BUILD_BACKUP_DIR"
# fi

# [ -s "$SER_FILE" ] || die "$SER_FILE does not exist or it is empty!"

# #
# # Create fault localization report
# #

echo "Create fault localization report ..."

SPECTRA_FILE="$BUILD_DIR/sfl/txt/spectra.csv"
MATRIX_FILE="$BUILD_DIR/sfl/txt/matrix.txt"
TESTS_FILE="$BUILD_DIR/sfl/txt/tests.csv"

java -cp $TEST_CP_DIR:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_CLI_JAR \
  com.gzoltar.cli.Main faultLocalizationReport \
    --buildLocation "${SRC_DIR}" \
    --granularity "line" \
    --inclPublicMethods \
    --inclStaticConstructors \
    --inclDeprecatedMethods \
    --dataFile "$SER_FILE" \
    --outputDirectory "$BUILD_DIR" \
    --family "sfl" \
    --formula "tarantula" \
    --metric "entropy" \
    --formatter "txt" || die "Generation of fault-localization report has failed!"

[ -s "$SPECTRA_FILE" ] || die "$SPECTRA_FILE does not exist or it is empty!"
[ -s "$MATRIX_FILE" ] || die "$MATRIX_FILE does not exist or it is empty!"
[ -s "$TESTS_FILE" ] || die "$TESTS_FILE does not exist or it is empty!"

echo "DONE!"
echo "Copying STARTS artifact to temporary location"
cd $UNI_DIR
cp -R ".starts" $RES_BASE_DIR

echo "DONE!"

echo "switch back to java 8"
export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
echo "CHECK JAVA VERSION: $JAVA_HOME AND $(javac -version)"

fi
# increment buggy version
BID=$(( BID+1 ))

done

exit 0


# run sbfl
# ./do-sbfl-analysis Lang 3 Lang/project/build/sfl/txt/matrix.txt Lang/project/build/sfl/txt/spectra.csv 