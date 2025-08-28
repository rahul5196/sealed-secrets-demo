BEGIN {
  OFS=","
  get_colnames_command = "jq -c -S 'keys'"
  get_colvalues_command = "jq -c -S 'map(.)'"
  get_coltypes_command = sprintf("psql --quiet -c \"SET search_path to '%s'; select column_name, data_type from INFORMATION_SCHEMA.COLUMNS where table_name ='%s'\" | tail -n +3 | head -n -2 | tr -d '[:blank:]'", SCHEMA_NAME, TNAME)
  getcoltypes(coltypes)
#   for (type in coltypes) {
#     printf("%s -> %s\n", type, coltypes[type]) # DEBUG
#   }
}

function getcolnames(l_rec) {
  print l_rec |& get_colnames_command
  close(get_colnames_command, "to")

   while ((get_colnames_command |& getline colnames) > 0)
    gsub(/"/, "", colnames)
    gsub(/[[]/, "", colnames)
    gsub(/[]]/, "", colnames)
   close(get_colnames_command)

   return colnames
}

function removedoublequotes(somestr) {
  gsub("\"", "", somestr)
  return somestr
}

function getcolvalues(l_rec) {
  print l_rec |& get_colvalues_command
  close(get_colvalues_command, "to")

   while ((get_colvalues_command |& getline colvalues) > 0)
    # gsub(/"/, "", colvalues)
    gsub(/[[]/, "", colvalues)
    gsub(/[]]/, "", colvalues)
   close(get_colvalues_command)

   return colvalues
}

function getcoltypes(l_coltypes,   l_arr) {
    while ((get_coltypes_command | getline coltype) > 0) {
      split(coltype, l_arr, "|")
      key = l_arr[1]
      value = l_arr[2]
      l_coltypes[key] = value
    }
    close(get_coltypes_command)
}

function assert(condition, string)
{
    if (! condition) {
        printf("%s:%d: assertion failed: %s\n",
            FILENAME, FNR, string) > "/dev/stderr"
        _assert_exit = 1
        exit 1
    }
}

function get_col_name_val_assoc_array(l_col_name_val) {
  colnames = getcolnames($0)
  colvalues = getcolvalues($0)
  
  # printf("colnames = %s\n", colnames)
  # printf("colvalues = %s\n", colvalues)

  n = split(colnames, name_arr)
  m = split(colvalues, value_arr)

  assert(n == m, "length of col names and values must match") 

  for (i = 1; i <= n; ++i) {
    name = name_arr[i]
    value = value_arr[i]
    l_col_name_val[name] = value
  }
}

function join_keys(assocarr,  keystr) {
  keystr = ""
  for (k in assocarr) {
    k = "\"" k "\""
    if (keystr == "")
      keystr = k
    else 
      keystr = keystr "," k
  }
  return keystr
}

function join_vals(assocarr,  valstr) {
  valstr = ""
  for (k in assocarr) {
    # printf("k = %s, v = %s\n", k, assocarr[k]) # DEBUG
    if (valstr == "")
      valstr = assocarr[k]
    else 
      valstr = valstr "," assocarr[k]
  }
  return valstr
}

type == "insert" {
   get_col_name_val_assoc_array(col_name_val)
   for (i in coltypes) {
     if (coltypes[i] == "charactervarying" || coltypes[i] == "timestampwithouttimezone") {
       v = col_name_val[i]
       if (v != "null") {
         col_name_val[i] = "'" v "'"
       }
     }
   }

   keys = join_keys(col_name_val)
   vals = join_vals(col_name_val)

   printf("INSERT INTO %s (\n %s \n) VALUES (\n %s \n);\n", TNAME, keys, vals)
}

NF > 0 && type == "update" {
	# printf("Got fields to update -> %s\n\n", $0) # DEBUG
	rec = ""
	# printf("%s\n", $0)
	n = split($0, arr, ",")
	for (i = 1; i <= n; ++i) {
		# printf("arr[%d] = %s\n", i, arr[i]) # DEBUG
		fld = arr[i]
		st = index(fld, ":")
		fld_name = substr(fld, 1, st-1)
		fld_value = substr(fld, st+1)

		# printf("%s -> '%s'\n", fld_name, fld_value) # DEBUG
		gsub("^[ \t]*", "", fld_name)
		gsub("[ \t]*$", "", fld_name)
		gsub("\"", "", fld_name)

		gsub("^[ \t]*", "", fld_value)
		gsub("[ \t]*$", "", fld_value)
		if (coltypes[fld_name] == "charactervarying" || coltypes[fld_name] == "timestampwithouttimezone") {
			if (fld_value != "null") {
				gsub("\"", "'", fld_value)
			}
		}
		if (rec != "") {
			rec = rec ", "
		}
		rec = rec "\"" fld_name "\"" " = " fld_value
	}
	barekey = removedoublequotes(KEY)
	if (coltypes[barekey] == "charactervarying") {
		gsub("\"", "'", id)
	}

	# printf("rec = %s\n", rec) # DEBUG
	printf("UPDATE %s SET %s WHERE %s = %s;\n", TNAME, rec, KEY, id)
}

