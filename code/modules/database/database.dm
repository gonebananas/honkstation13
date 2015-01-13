var/Database/DB = new

/Database/var
	use_mysql    = 0
	mysql_host   = ""
	mysql_port   = 3306
	mysql_user   = ""
	mysql_pass   = ""
	mysql_dbname = ""
	DBConnection/mysql
	database/sqlite
	uniqueid     = ""

/Database/proc/init()
	processUpgradeDocument('code/modules/client/db-changelog.xml')

/Database/proc/generateUniqueID()
	if (uniqueid) uniqueid = query("SELECT CAST(? + 1 AS CHAR)", uniqueid)
	else          uniqueid = query("SELECT UNIX_TIMESTAMP_FULL()")

	return uniqueid

/Database/proc/processUpgradeDocument(file)
	if (!tableExists("databasechangelog"))
		executeUpdate("CREATE TABLE databasechangelog (id character varying(10) NOT NULL, author character varying(30) NOT NULL, filename character varying(255) NOT NULL, dateexecuted timestamp with time zone NOT NULL, md5sum character varying(32), CONSTRAINT databasechangelog_pkey PRIMARY KEY (id, author, filename))")

	var
		XML/Element/root = xmlRootFromFile(file)
		filename         = root.Attribute("logicalFilePath")

	for (var/XML/Element/changeset in root.Descendants("changeset"))
		processChangeset(filename, changeset)

/Database/proc/processChangeset(filename, var/XML/Element/changeset)
	var
		id       = changeset.Attribute("id")
		author   = changeset.Attribute("author")
		sql      = ""

	for (var/XML/Element/element in changeset.Descendants("sql"))
		if (sql) sql = sql + "; "
		sql      = sql + element.Text()

	var/hash     = md5(sql)
	var/rhash    = query("SELECT md5sum FROM databasechangelog WHERE id = ? AND author = ? AND filename = ?", id, author, filename)

	if (rhash == null)
		var/database/query/q = getQuery(0, sql) // /DBQuery is compatible with /database/query

		if (!q.ErrorMsg())
			executeUpdate("INSERT INTO databasechangelog (id, author, filename, dateexecuted, md5sum) VALUES(?, ?, ?, NOW(), ?)", id, author, filename, hash)
	else if (rhash != hash) log_debug("#SQL: ERROR: Hash mismatch for changeset [id] by [author] in file [filename]! New hash: [hash] Old hash: [rhash]")

/Database/proc/checkConnection()
	src.use_mysql = config.sql_enabled

	world.log << "SQL: [use_mysql ? "mysql" : "sqlite"]"

	if (use_mysql)
		src.mysql_host = sqladdress
		src.mysql_port = sqlport
		src.mysql_dbname = sqldb
		src.mysql_user = sqllogin
		src.mysql_pass = sqlpass

		if (!mysql)  mysql = new/DBConnection("dbi:mysql:[mysql_dbname]:[mysql_host]:[mysql_port]", mysql_user, mysql_pass)
	else
		if (!sqlite) sqlite = new/database("data/sqldb.sqlite")

/Database/proc/tableExists(tableName)
	if (use_mysql) return query("SELECT 1 FROM information_schema.tables WHERE table_name = ? LIMIT 1",     tableName)
	else           return query("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1", "table", tableName)

/Database/proc/getQuery(flags = 0, sql, ...)
	src.checkConnection()

	if (use_mysql)
		sql = replacetext(sql, "UNIX_TIMESTAMP_FULL()", "CAST((UNIX_TIMESTAMP() * 1000) AS CHAR)")

		var/DBQuery/q = new/DBQuery(sql, mysql)

		q.Execute()

		var/error     = q.ErrorMsg()

		if (error)
			log_debug("#SQL: \"[error]\" query: [sql]")

		return q
	else
		sql = replacetext(sql, "NOW()", "datetime('now')")
		sql = replacetext(sql, "UNIX_TIMESTAMP_FULL()", "CAST(strftime('%s', 'now') * 1000 AS CHAR)")

		var/database/query/q = new(arglist(args.Copy(2)))

		q.Execute(sqlite)

		var/error     = q.ErrorMsg()

		if (error)
			log_debug("#SQL: [error]\n      query: [sql]")

		return q

/Database/proc/executeUpdate(sql, ...)
	.                    = 0

	var/list/arguments   = args.Copy()
	arguments.Insert(1, 0)

	var/database/query/q = getQuery(arglist(arguments)) // /DBQuery is compatible with /database/query

	if (q)               return q.RowsAffected()
	else                 return 0

/Database/proc/query(sql, ...)
	var/list/arguments   = args.Copy()
	arguments.Insert(1, 0)

	var/database/query/q = getQuery(arglist(arguments)) // /DBQuery is compatible with /database/query

	if (q && q.NextRow())
		.                = q.GetRowData()
		.                = .[.[1]]

		if (q.NextRow()) CRASH("More than 1 row returned by query.")

/Database/proc/queryForRowSet(sql, ...)
	var/list/res         = new/list()
	.                    = res

	var/list/arguments   = args.Copy()
	arguments.Insert(1, 0)

	var/database/query/q = getQuery(arglist(arguments)) // /DBQuery is compatible with /database/query

	if (q)
		while (q.NextRow())
			res.len      = res.len + 1
			res[res.len] = q.GetRowData()

/Database/proc/getDBV(sql, ...)
	.         = query(arglist(args))

	if (!.) . = ""

/Database/proc/getDBVNumber(sql, ...)
	.         = query(arglist(args))

	var/txt   = .

	.         = text2num(.)

	if (. != txt) . = 0