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
BID="1"
PROJECT_DIR="/home/zhenming/research/${PID}/${BID}_buggy"

#make project dir
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
[ -d "$PROJECT_DIR" ] || die "$PROJECT_DIR does not exist!"

#defects4j checkout
defects4j checkout -p $PID -v ${BID}b -w $PROJECT_DIR

cd $PROJECT_DIR

#
# Compile
#

echo "Compile source and test cases using defects4j compile..."
defects4j compile

SRC_DIR=${PROJECT_DIR}/$(defects4j export -p dir.bin.classes)
TEST_DIR=${PROJECT_DIR}/$(defects4j export -p dir.bin.tests)


# Check whether GZOLTAR_CLI_JAR is set
export GZOLTAR_CLI_JAR="/home/zhenming/gzoltar/com.gzoltar.cli/target/com.gzoltar.cli-$GZOLTAR_VERSION-jar-with-dependencies.jar"
echo $SCRIPT_DIR
[ "$GZOLTAR_CLI_JAR" != "" ] || die "GZOLTAR_CLI is not set!"
[ -s "$GZOLTAR_CLI_JAR" ] || die "$GZOLTAR_CLI_JAR does not exist or it is empty! Please go to '$SCRIPT_DIR/..' and run 'mvn clean install'."

# Check whether GZOLTAR_AGENT_RT_JAR is set
export GZOLTAR_AGENT_RT_JAR="/home/zhenming/gzoltar/com.gzoltar.agent.rt/target/com.gzoltar.agent.rt-$GZOLTAR_VERSION-all.jar"
[ "$GZOLTAR_AGENT_RT_JAR" != "" ] || die "GZOLTAR_AGENT_RT_JAR is not set!"
[ -s "$GZOLTAR_AGENT_RT_JAR" ] || die "$GZOLTAR_AGENT_RT_JAR does not exist or it is empty! Please go to '$SCRIPT_DIR/..' and run 'mvn clean install'."

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

#
# Prepare runtime dependencies
#
LIB_DIR="$PROJECT_DIR/lib" 
rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR" || die "Failed to create $LIB_DIR!"
[ -d "$LIB_DIR" ] || die "$LIB_DIR does not exist!"

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

BUILD_DIR="$PROJECT_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" || die "Failed to create $BUILD_DIR!"

#export cp.test from defects4j
TEST_CP_DIR=$(defects4j export -p cp.test)

#EXPORT relevant test file from defects4j
RELEVANT_TEST_FILE="${D4J_HOME}/framework/projects/${PID}/relevant_tests/${BID}"
RELEVANT_TESTS=$(cat ${RELEVANT_TEST_FILE} |  sed 's/$/#*/' | sed ':a;N;$!ba;s/\n/:/g')
# ------------------------------------------------------------------------- Main




#
# Collect list of unit test cases to run
#

echo "Collect list of unit test cases to run ..."

UNIT_TESTS_FILE="$BUILD_DIR/tests.txt"

java -cp "${TEST_CP_DIR}:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_CLI_JAR" \
  com.gzoltar.cli.Main listTestMethods ${TEST_DIR} \
    --outputFile "$UNIT_TESTS_FILE" \
    --includes ${RELEVANT_TESTS} || die "Collection of unit test cases has failed!"
[ -s "$UNIT_TESTS_FILE" ] || die "$UNIT_TESTS_FILE does not exist or it is empty!"

#
# Collect coverage
#

SER_FILE="$BUILD_DIR/gzoltar.ser"

LOADED_CLASSES_FILE="${D4J_HOME}/framework/projects/${PID}/loaded_classes/${BID}.src"
NORMAL_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/:/' | sed ':a;N;$!ba;s/\n//g')
INNER_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/$*:/' | sed ':a;N;$!ba;s/\n//g')
LOADED_CLASSES="$NORMAL_CLASSES$INNER_CLASSES"


if [ "$INSTRUMENTATION" == "online" ]; then
  echo "Perform instrumentation at runtime and run each unit test case in isolation ..."

  # Perform instrumentation at runtime and run each unit test case in isolation
  java -javaagent:$GZOLTAR_AGENT_RT_JAR=destfile=$SER_FILE,buildlocation="${SRC_DIR}",includes=${LOADED_CLASSES},excludes="",inclnolocationclasses=false,output="file" \
    -cp $TEST_CP_DIR:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_CLI_JAR \
    com.gzoltar.cli.Main runTestMethods \
      --testMethods "$UNIT_TESTS_FILE" \
      --collectCoverage || die "Coverage collection has failed!"

#offline mode is not ready --Zhenming
elif [ "$INSTRUMENTATION" == "offline" ]; then
  echo "Perform offline instrumentation ..."

  # Backup original classes
  BUILD_BACKUP_DIR="$SCRIPT_DIR/.build"
  mv "$BUILD_DIR" "$BUILD_BACKUP_DIR" || die "Backup of original classes has failed!"
  mkdir -p "$BUILD_DIR"

  # Perform offline instrumentation
  java -cp $BUILD_BACKUP_DIR:$GZOLTAR_AGENT_RT_JAR:$GZOLTAR_CLI_JAR \
    com.gzoltar.cli.Main instrument \
    --outputDirectory "$BUILD_DIR" \
    $BUILD_BACKUP_DIR || die "Offline instrumentation has failed!"

  echo "Run each unit test case in isolation ..."

  # Run each unit test case in isolation
  java -cp $BUILD_DIR:$JUNIT_JAR:$HAMCREST_JAR:$GZOLTAR_AGENT_RT_JAR:$GZOLTAR_CLI_JAR \
    -Dgzoltar-agent.destfile=$SER_FILE \
    -Dgzoltar-agent.output="file" \
    com.gzoltar.cli.Main runTestMethods \
      --testMethods "$UNIT_TESTS_FILE" \
      --offline \
      --collectCoverage || die "Coverage collection has failed!"

  # Restore original classes
  cp -R $BUILD_BACKUP_DIR/* "$BUILD_DIR" || die "Restore of original classes has failed!"
  rm -rf "$BUILD_BACKUP_DIR"
fi

[ -s "$SER_FILE" ] || die "$SER_FILE does not exist or it is empty!"

#
# Create fault localization report
#

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


exit 0
