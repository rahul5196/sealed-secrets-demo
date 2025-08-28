#!/bin/bash

# Database credentials
DB_USER="ifrm"
DB_PASSWORD="ifrm"
DB_HOST="10.71.21.16"
DB_NAME="ifrm_pulse"
SCRIPT_DIR="/home/dev/field/customer/scripts"
LOG_DIR="${SCRIPT_DIR}/logs"

# Ensure the logs directory exists
mkdir -p "$LOG_DIR"

# Log file for this execution
LOG_FILE="${LOG_DIR}/script_$(date +"%Y%m%d%H%M%S").log"

# Redirect all output (stdout and stderr) to the log file
exec >> "$LOG_FILE" 2>&1

# Export password for non-interactive psql use
export PGPASSWORD=$DB_PASSWORD

# Setup path explicitly

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin



# Optional: Log current env (good for debugging)

env >> /home/dev/field/customer/scripts/logs/env_from_cron.log


# Function to log messages with timestamps
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

{
    log "Execution started"

    # Step 1: Generate the SQL file with a timestamp
    SQL_FILE="${SCRIPT_DIR}/customer_stage_$(date +"%Y%m%d%H%M%S").sql"
    log "Generating SQL file: $SQL_FILE"
    time ${SCRIPT_DIR}/process.sh '"CUSTOMER_STAGE"' '"CUSTOMER_STAGE_MIGRATION"' '"CUST_CIF"' '"IFRM_UDS"' > "$SQL_FILE" 2>>"$LOG_FILE"

    # Step 2: Execute the latest SQL file
    LATEST_FILE=$(ls -t ${SCRIPT_DIR}/customer_stage_*.sql | head -n 1)
    log "Executing latest SQL file: $LATEST_FILE"
    psql -U $DB_USER -d $DB_NAME -h $DB_HOST -c "SET search_path TO 'IFRM_UDS';" -f "$LATEST_FILE" >>"$LOG_FILE" 2>&1

    # Step 3: Remove all cust_stage_*.sql files
    log "Removing all customer_stage_*.sql files from $SCRIPT_DIR"
    rm -f ${SCRIPT_DIR}/customer_stage_*.sql

    # Step 4: Truncate the table
    log "Truncating table \"IFRM_UDS\".\"CUSTOMER_STAGE_MIGRATION\""
    psql -U $DB_USER -d $DB_NAME -h $DB_HOST -c "TRUNCATE TABLE \"IFRM_UDS\".\"CUSTOMER_STAGE_MIGRATION\";" >>"$LOG_FILE" 2>&1

    log "Execution completed"
} | tee -a "$LOG_FILE"

# Unset password for security
unset PGPASSWORD