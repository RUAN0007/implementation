#!/usr/bin/env bash
set -o errexit
# set -o pipefail
# set -o nounset
# set -o xtrace

#Before executing this script, be ensure to set up PG and config OrpheusDB. 

is_verbose=false
if [ -z "${VERBOSE}" ]; then 
  is_verbose=false
else
  is_verbose=true
  echo "In Verbose Mode"
fi

PG_DB=machine_db2
PG_USER=machine


DATASET_NAME=wl
BASE_FILE="$1"
QUERY_FILE="$2"
SCHEMA_FILE=lq_schema.csv

rm -rf benchmark_log.txt
touch benchmark_log.txt
# Drop the dataset if exists
echo "y" | orpheus drop $DATASET_NAME >> benchmark_log.txt


DB_SIZE_MB=$(($(psql -U ${PG_USER} -d ${PG_DB} -c " SELECT pg_database_size('${PG_DB}');" | sed 's/[^0-9]//g' | sed "3q;d") / 1048576))

DB_SIZE_KB=$(($(psql -U ${PG_USER} -d ${PG_DB} -c " SELECT pg_database_size('${PG_DB}');" | sed 's/[^0-9]//g' | sed "3q;d") / 1024))

if [ "${is_verbose}" = true ]; then
  echo "Before DB SIZE: ${DB_SIZE_KB} KB"
fi

# Measure the Init Time
if [ "${is_verbose}" = true ]; then
  echo "===================Initing The Dataset======================"
fi

BEFORE_MS=$(($(date +%s%N)/1000000))
orpheus init ${BASE_FILE} ${DATASET_NAME} -s test/${SCHEMA_FILE} >> benchmark_log.txt
if [ $? -ne 0 ]; then
  echo "Fail to Init."
  return 1
fi
END_MS=$(($(date +%s%N)/1000000))

DURATION_MS=$((${END_MS} - ${BEFORE_MS}))
if [ "${is_verbose}" = true ]; then
  echo "Initing Elapsed Ms: " ${DURATION_MS}
else
  echo ${DURATION_MS}
fi

INIT_DB_SIZE_MB=$(($(psql -U ${PG_USER} -d ${PG_DB} -c " SELECT pg_database_size('${PG_DB}');" | sed 's/[^0-9]//g' | sed "3q;d") / 1048576))
INIT_DB_SIZE_KB=$(($(psql -U ${PG_USER} -d ${PG_DB} -c " SELECT pg_database_size('${PG_DB}');" | sed 's/[^0-9]//g' | sed "3q;d") / 1024))
if [ "${is_verbose}" = true ]; then
  echo "DB SIZE After Init: ${INIT_DB_SIZE_KB} KB"
else
  echo ${INIT_DB_SIZE_MB}
fi


# Measure the aggregation Time
# Count the number of records with Departure_Num=01
if [ "${is_verbose}" = true ]; then
  echo "=============================Measure Aggregate============================"
fi
BEFORE_MS=$(($(date +%s%N)/1000000))
RESULT=$(echo "SELECT COUNT(*) FROM VERSION 1 OF CVD wl WHERE AggregateBy='01';" | orpheus run)
echo ${RESULT} >> benchmark_log.txt
COUNT=$(echo ${RESULT} | sed 's/[^0-9]//g' | sed "3q;d")
END_MS=$(($(date +%s%N)/1000000))
if [ $? -ne 0 ]; then
  echo "Fail to Perform Aggregation Query"
  return 1
fi
DURATION_MS=`expr ${END_MS} - ${BEFORE_MS}`
if [ "${is_verbose}" = true ]; then
  echo "Number of Filtered Records: $COUNT with Elapsed Ms: ${DURATION_MS}"
else
  echo "${DURATION_MS}"
fi

CHECKOUT_TABLE=wlv
psql -U ${PG_USER} -d ${PG_DB} -c "DROP TABLE IF EXISTS $CHECKOUT_TABLE;" &>> benchmark_log.txt
if [ $? -ne 0 ]; then
  echo "Drop Table wl ." ${CHECKOUT_TABLE}  " fails. "
  return 1
fi

ALL_LATENCY=()
ALL_STORAGE=()
# Edit the records with given age and region based on specified version
function Checkout_Edit_Commit() {
  VERSION=${1}
  UPDATE_BY=${2}
  NEXT_VER=$(($VERSION + 1))
	
  TOTAL_DURATION=0
  if [ "${is_verbose}" = true ]; then
    echo "===================Checkout V$VERSION and Commit V$NEXT_VER======================"
  fi
  ## Measure Checkout Time
  ### NOTE: Further filter out the dumping to fs time
  BEFORE_MS=$(($(date +%s%N)/1000000))
  orpheus checkout ${DATASET_NAME} -v ${VERSION} -t ${CHECKOUT_TABLE} >> benchmark_log.txt
  END_MS=$(($(date +%s%N)/1000000))
  if [ $? -ne 0 ]; then
    echo "Fail to Checkout Version $VERSION."
    return 1
  fi
  CHECKOUT_DURATION_MS=$(($END_MS - $BEFORE_MS))
  TOTAL_DURATION=$(($TOTAL_DUATION + $CHECKOUT_DURATION_MS))
  if [ "${is_verbose}" = true ]; then
    echo "Checkout V1 Elapsed Ms: " ${CHECKOUT_DURATION_MS}
  fi
  ## Apply the Edition
  ## Random string with 100 chars
  PROFILE="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $(shuf -i 10-100 -n 1) | head -n 1)"

  BEFORE_MS=$(($(date +%s%N)/1000000))

  NUM_EDITION="$(psql -U ${PG_USER} -d ${PG_DB} -c "UPDATE  ${CHECKOUT_TABLE}  SET UpdateOn='${PROFILE}' WHERE UpdateBy='${UPDATE_BY}';" | sed 's/[^0-9]//g')"

  END_MS=$(($(date +%s%N)/1000000))
  if [ $? -ne 0 ]; then
    echo "Fail to Edit Version $VERSION."
    return 1
  fi
  EDIT_DURATION_MS=$(($END_MS - $BEFORE_MS))
  TOTAL_DURATION=$(($TOTAL_DUATION + $EDIT_DURATION_MS))

  if [ "${is_verbose}" = true ]; then
    echo "Number of Edition: ${NUM_EDITION} with Elapsed Ms: ${EDIT_DURATION_MS}"
  fi

  ## Commit the Edited to Next Version
  BEFORE_MS=$(($(date +%s%N)/1000000))
  orpheus commit -t $CHECKOUT_TABLE -m 'V${NEXT_VER}' >> benchmark_log.txt
  END_MS=$(($(date +%s%N)/1000000))
  if [ $? -ne 0 ]; then
    echo "Fail to Commit Version ${NEXT_VER}."
    return 1
  fi
  COMMIT_DURATION_MS=$(($END_MS - $BEFORE_MS))
  TOTAL_DURATION=$(($TOTAL_DUATION + $COMMIT_DURATION_MS))

  if [ "${is_verbose}" = true ]; then
    echo "Commit V${NEXT_VER} Elapsed Ms: " ${COMMIT_DURATION_MS}
  fi

  CHECKOUT_TABLE=wlv
  psql -U ${PG_USER} -d ${PG_DB} -c "DROP TABLE IF EXISTS ${CHECKOUT_TABLE};" >> benchmark_log.txt
  if [ $? -ne 0 ]; then
    echo "Drop Table " ${CHECKOUT_TABLE}  " fails. "
    return 1
  fi

  DB_SIZE_MB=$(($(psql -U ${PG_USER} -d ${PG_DB} -c " SELECT pg_database_size('${PG_DB}');" | sed 's/[^0-9]//g' | sed "3q;d") / 1048576))
  if [ "${is_verbose}" = true ]; then
    echo "DB SIZE After Commit ${NEXT_VER} ${DB_SIZE_MB} MB"
  fi
  echo "${CHECKOUT_DURATION_MS}; ${EDIT_DURATION_MS}; ${COMMIT_DURATION_MS}"
  ALL_STORAGE+=("${DB_SIZE_MB}")
}

edition_counter=1
while IFS='' read -r line || [[ -n "$line" ]]; do
  Checkout_Edit_Commit ${edition_counter} $line
  edition_counter=$((${edition_counter}+1))
done < ${QUERY_FILE}

if [ "${is_verbose}" = false ]; then
  # echo $(($edition_counter-1))
  # for LATENCY in "${ALL_LATENCY[@]}"
  # do
   # echo "${LATENCY}"
  # done  
  
  PRE_STORAGE=${INIT_DB_SIZE_KB}
  for STORAGE in "${ALL_STORAGE[@]}"
  do
    INCREASE=$((${STORAGE}-${PRE_STORAGE}))
    echo "$INCREASE"
    PRE_STORAGE=${STORAGE}
  done  
fi

function Diff() {

  DURATION_MS=$(echo "EXPLAIN ANALYZE SELECT * FROM (SELECT unnest((SELECT rlist FROM wl_indextable where vid = ${1})) as tmp_rid except SELECT unnest((SELECT rlist FROM wl_indextable where vid = ${2}))) AS tmp, wl_datatable WHERE wl_datatable.rid = tmp.tmp_rid;" | orpheus run | sed 's/[^0-9\.]//g' | sed '4q;d')
  if [ "${is_verbose}" = true ]; then
    echo "Diff V${1} and V${2} Elapsed Ms: ${DURATION_MS}"
  else
    echo "${DURATION_MS}"
  fi
}

if [ "${is_verbose}" = true ]; then
  echo "==============Measure Diff==================="
fi

for i in $(seq 1 ${edition_counter});
do
  Diff 1 $i
done

