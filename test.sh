#!/usr/bin/env bash

LOADED_CLASSES_FILE="$D4J_HOME/framework/projects/Lang/loaded_classes/3.src"
NORMAL_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/:/' | sed ':a;N;$!ba;s/\n//g')
INNER_CLASSES=$(cat "$LOADED_CLASSES_FILE" | sed 's/$/$*:/' | sed ':a;N;$!ba;s/\n//g')
LOADED_CLASSES="$NORMAL_CLASSES$INNER_CLASSES"
echo $LOADED_CLASSES
