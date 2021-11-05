#!/usr/bin/env bash


#$1: pid
getAllClasses () {
	CG_PATH="/home/zhenming/.m2/repository/io/github/classgraph/classgraph/4.8.104/classgraph-4.8.104.jar"
	cd "/home/zhenming/research"
	rm "getAllClasses.class"
	javac -cp $CG_PATH "getAllClasses.java"

	local target_path="/home/zhenming/research/$1/project/target/classes"
	

	if [ -s "$target_path/getAllClasses.class" ]; then
		rm "$target_path/getAllClasses.class"
		
	fi
	
	cp getAllClasses.class "/home/zhenming/research/$1/project/target/classes"

	cd "$target_path"
	CURR_DIR=$(pwd)
	ls
	java -cp $CG_PATH:$CURR_DIR getAllClasses
	cd -
	pwd
	echo "bash : finished!"
}
