#!/usr/bin/zsh -f
function lookup_updated_row() {
  jq -S "select (."$KEY" == $1)" updated_rows_orig.json 
}

function is_it_an_insert() {
  value=$(echo "$1" | tr '"' "'")
  query="SET search_path to '$SCHEMA_NAME'; SELECT row_to_json($TABLENAME) FROM $TABLENAME where $KEY = $value"
  psql --quiet -c "$query" | egrep '(0 rows)' > /dev/null
}

function get_updated_rows_as_json() {
  query="SET search_path to '$SCHEMA_NAME'; SELECT row_to_json($UPDATED_TABLENAME) FROM $UPDATED_TABLENAME" 
  psql --quiet -c "$query" | awk 'NR > 2' | head -n -2 > updated_rows_orig.json
}

if [[ "$#" -ne 4 ]]; then
   echo "Usage: $0 tablename updated_rows_tablename key schemaname" >&2
   exit 1
fi

TABLENAME="$1"
UPDATED_TABLENAME="$2"
KEY="$3"
SCHEMA_NAME="$4"

get_updated_rows_as_json

printf "" > insert.json
printf "" > update.json

IFS=$'\n'
for row in $(jq ".$KEY" updated_rows_orig.json)
do
  updated_row=$(lookup_updated_row "$row")
  if $(is_it_an_insert "$row")
  then
    printf "%s\n" "$updated_row" | jq -c -S . >> insert.json
  else 
    printf "%s\n" "$updated_row" | jq -c -S . | { printf "%s\n" "$row"; cat -; printf "\n" }  # >> update.json
  fi
done
