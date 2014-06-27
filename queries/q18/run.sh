#!/usr/bin/env bash

query_run_main_method () {
	HIVE1_SCRIPT="$QUERY_DIR/hive1.sql"
	if [ ! -r "$HIVE1_SCRIPT" ]
	then
		echo "SQL file $HIVE1_SCRIPT can not be read."
		exit 1
	fi

	HIVE2_SCRIPT="$QUERY_DIR/hive2.sql"
	if [ ! -r "$HIVE2_SCRIPT" ]
	then
		echo "SQL file $HIVE2_SCRIPT can not be read."
		exit 1
	fi

	HIVE3_SCRIPT="$QUERY_DIR/hive3.sql"
	if [ ! -r "$HIVE3_SCRIPT" ]
	then
		echo "SQL file $HIVE3_SCRIPT can not be read."
		exit 1
	fi

	#EXECUTION Plan:
	#step 1.	prepare		:	Copying LinearRegression jar to HDFS etc
	#step 2.	hive1.sql	:	Settting up intermediate views and tables
	#step 3.	hadoop m/r	:	Running LinearRegression on tables
	#step 4.	hive2.sql	:	Combining output into 1 table
	#step 5.	hive3.sql	:	Combine output with sentiment analysis
	#step 6. 	hadoop fs	: 	Cleaning up

	MATRIX_MAX=12

	MR_JAR="${BIG_BENCH_QUERIES_DIR}/Resources/bigbenchqueriesmr.jar"
	MR_CLASS="de.bankmark.bigbench.queries.${QUERY_NAME}.MRlinearRegression"
	MR_JARCLASS="${MR_JAR} ${MR_CLASS}"

	#Step 1. Hadoop Part 0-----------------------------------------------------------------------
	# Copying jar to hdfs
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 1 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 1/6: Prepare required resources"
		echo "========================="
		hadoop fs -rm -r -skipTrash "${TEMP_DIR}"/*
		hadoop fs -mkdir -p "${TEMP_DIR}"
		hadoop fs -chmod uga+rw "${TEMP_DIR}"
		hadoop fs -copyFromLocal "${MR_JAR}" "${TEMP_DIR}/"
	fi

	#Step 2. Hive Part 1-----------------------------------------------------------------------
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 2 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 2/6: exec hive query(s) part 1 (create matrix)"
		echo "========================="
		hive $HIVE_PARAMS -i "$COMBINED_PARAMS_FILE" -f "$HIVE1_SCRIPT"
	fi

	#Step 3. Hadoop Part 1---- MRlinearRegression--------------------------------------------------------------
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 3 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 3/6: prepare M/R job environment"
		echo "========================="

		hadoop fs -rm -r -skipTrash "${TEMP_DIR}"/output*

		echo "========================="
		echo "$QUERY_NAME Step 3/6: exec M/R job linear regression analysis"
		echo "========================="
		for (( i=1; i <= $MATRIX_MAX; i++ ))
		do
			echo "-------------------------"
			echo "$QUERY_NAME Step 3: linear regression analysis Matrix ${i}/12"
			echo "in: ${TEMP_DIR}/q18_matrix${i}"
			echo "out: ${TEMP_DIR}/output${i}"
			echo "Exec: hadoop jar ${MR_JARCLASS} ${TEMP_DIR}/q18_matrix${i} ${TEMP_DIR}/output${i} "
			echo "-------------------------"
			hadoop jar "${MR_JAR}" "${MR_CLASS}" "${TEMP_DIR}/q18_matrix${i}" "${TEMP_DIR}/output${i}"  
		done
	fi

	#Step 4. Hive 2-----------------------------------------------------------------------
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 4 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 4/6: exec hive query(s) part 2, aggregate linear regression"
		echo "========================="
		hive $HIVE_PARAMS -i "$COMBINED_PARAMS_FILE" -f "$HIVE2_SCRIPT"
	fi

	#Step 5. Hive 3-----------------------------------------------------------------------
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 5 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 5/6: exec hive query(s) part 3, combine with sentiment analysis"
		echo "========================="
		echo "hive --auxpath \"$BIG_BENCH_QUERIES_DIR/Resources/opennlp-maxent-3.0.3.jar:$BIG_BENCH_QUERIES_DIR/Resources/opennlp-tools-1.5.3.jar\" -f \"${QUERY_DIR}/hive3.sql\""
		hive --auxpath "$BIG_BENCH_QUERIES_DIR/Resources/opennlp-maxent-3.0.3.jar:$BIG_BENCH_QUERIES_DIR/Resources/opennlp-tools-1.5.3.jar" $HIVE_PARAMS -i "$COMBINED_PARAMS_FILE" -f "$HIVE3_SCRIPT"
	fi

	#Step 6. Hadoop  3-----------------------------------------------------------------------
	# Cleaning up
	if [[ -z "$DEBUG_QUERY_PART" || $DEBUG_QUERY_PART -eq 6 ]] ; then
		echo "========================="
		echo "$QUERY_NAME Step 6/6: cleaning up temporary files"
		echo "========================="
		hive -f "${QUERY_DIR}/cleanup.sql"
		hadoop fs -rm -r -skipTrash "${TEMP_DIR}"/*
	fi
}
