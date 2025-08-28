#!/usr/bin/zsh -f

# Import PostgreSQL connection details
export PGUSER="ifrm"
export PGPASSWORD="ifrm"
export PGHOST="10.71.21.16"
export PGDATABASE="ifrm_pulse"
export UPDATED_TABLENAME='"CUSTOMER_ACCOUNT_STAGE_MIGRATION"'
# Validate arguments
if [[ "$#" -ne 4 ]]; then
   echo "Usage: $0 tablename updated_rows_tablename key schemaname" >&2
   exit 1
fi

TABLENAME="$1"
UPDATED_TABLENAME="$2"
KEY="$3"
SCHEMA_NAME="$4"

# Function to lookup row in PostgreSQL
function lookup_row_in_postgres() {
  local value=$(echo "$1" | tr '"' "'")
  local query="SET search_path TO $SCHEMA_NAME; SELECT row_to_json($TABLENAME) FROM $TABLENAME WHERE $KEY = $value;"
  psql --quiet -c "$query" | awk 'NR > 2' | head -n -2 | jq -S .
}

# Function to check if it is an insert
function is_it_an_insert() {
  local value=$(echo "$1" | tr '"' "'")
  local query="SET search_path TO $SCHEMA_NAME; SELECT 1 FROM $TABLENAME WHERE $KEY = $value;"
  psql --quiet -c "$query" | egrep '(0 rows)' > /dev/null
}

# Generate updated_rows_orig.json
query="SET search_path TO $SCHEMA_NAME; SELECT row_to_json($UPDATED_TABLENAME) FROM $UPDATED_TABLENAME;"
time psql -U $PGUSER -d $PGDATABASE -h $PGHOST --quiet -c "$query" | awk 'NR > 2' | head -n -2 > updated_rows_orig.json

if [[ $? -ne 0 ]]; then
  echo "Error generating updated_rows_orig.json. Exiting." >&2
  exit 1
fi

# Process each row
while IFS= read -ru3 raw_line; do
  line=$(printf "%s\n" "$raw_line" | jq -S .)
  key=$(printf "%s\n" "$line" | jq -r ".$KEY") # Use -r to remove quotes for SQL

  if $(is_it_an_insert "$key"); then
    ((insert_count++))
    printf "%s\n" "$line" | jq -c -S . | awk --csv -f generate_ins_or_upd.awk -vTNAME=$TABLENAME -vtype=insert -vKEY=$KEY
  else
    ((update_count++))
    r1=$(lookup_row_in_postgres "$key" | jq -S .)

    # Generate valid SQL UPDATE statements
    diff --unchanged-line-format= --old-line-format= --new-line-format='%L' <(echo "$r1") <(echo "$line") | \
      jq -r 'to_entries | map("\(.key) = \(.value|tostring)") | join(", ")' | \
      awk --csv -vid="$key" -f generate_ins_or_upd.awk -vTNAME=$TABLENAME -vtype=update -vKEY=$KEY -vSCHEMA_NAME=$SCHEMA_NAME
  fi
done 3< updated_rows_orig.json

