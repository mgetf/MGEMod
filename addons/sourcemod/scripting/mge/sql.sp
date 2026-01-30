// ===== DATABASE INITIALIZATION =====

// Establishes database connection, detects database type, creates initial tables, and runs migrations
void PrepareSQL() 
{
    char error[256];

    // Check if database config is specified
    if (strlen(g_sDBConfig) == 0)
    {
        g_DB = SQL_Connect("storage-local", true, error, sizeof(error));
        
        if (g_DB == null)
        {
            SetFailState("Could not connect to SQLite database: %s", error);
        }
    }
    else
    {
        if (!SQL_CheckConfig(g_sDBConfig))
        {
            SetFailState("Database config '%s' not found in databases.cfg", g_sDBConfig);
        }
        
        g_DB = SQL_Connect(g_sDBConfig, true, error, sizeof(error));
        
        if (g_DB == null)
        {
            SetFailState("Could not connect to specified database config '%s': %s", g_sDBConfig, error);
        }
    }

    char ident[16];
    g_DB.Driver.GetIdentifier(ident, sizeof(ident));

    if (StrEqual(ident, "mysql", false))
    {
        g_DatabaseType = DB_MYSQL;
    }
    else if (StrEqual(ident, "sqlite", false))
    {
        g_DatabaseType = DB_SQLITE;
    }
    else if (StrEqual(ident, "pgsql", false))
    {
        g_DatabaseType = DB_POSTGRESQL;
    }
    else
    {
        SetFailState("Unsupported database type: %s", ident);
    }

    LogMessage("Successfully connected to database config '%s' [%s]", g_sDBConfig, ident);

    // Create tables using abstraction layer
    char query[1024];
    
    GetCreateTableQuery_Stats(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);
    
    GetCreateTableQuery_Duels(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);
    
    GetCreateTableQuery_Duels2v2(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    GetCreateTableQuery_DuelClassRatings(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    GetCreateTableQuery_DuelClassRatings2v2(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);
    
    GetCreateTableQuery_MatchupRatings(query, sizeof(query));
    g_DB.Query(SQL_OnGenericQueryFinished, query);
    
    if (g_DatabaseType == DB_POSTGRESQL)
    {
        g_DB.Query(SQL_OnGenericQueryFinished, "CREATE UNIQUE INDEX IF NOT EXISTS idx_stats_steamid ON mgemod_stats (steamid)");
        g_DB.Query(SQL_OnGenericQueryFinished, "CREATE INDEX IF NOT EXISTS idx_duel_class_ratings_duel_player ON mgemod_duel_class_ratings (duel_id, player_steamid)");
        g_DB.Query(SQL_OnGenericQueryFinished, "CREATE INDEX IF NOT EXISTS idx_duel_class_ratings_class ON mgemod_duel_class_ratings (class_name)");
        g_DB.Query(SQL_OnGenericQueryFinished, "CREATE INDEX IF NOT EXISTS idx_duel_class_ratings_2v2_duel_player ON mgemod_duel_class_ratings_2v2 (duel_id, player_steamid)");
        g_DB.Query(SQL_OnGenericQueryFinished, "CREATE INDEX IF NOT EXISTS idx_duel_class_ratings_2v2_class ON mgemod_duel_class_ratings_2v2 (class_name)");
        
        int currentTime = GetTime();
        char migrationQuery[256];
        g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('001_add_class_columns', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
        g_DB.Query(SQL_OnGenericQueryFinished, migrationQuery);
        
        g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('002_duel_timing_columns', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
        g_DB.Query(SQL_OnGenericQueryFinished, migrationQuery);
        
        g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('003_add_primary_keys', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
        g_DB.Query(SQL_OnGenericQueryFinished, migrationQuery);
        
        g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('004_add_elo_tracking', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
        g_DB.Query(SQL_OnGenericQueryFinished, migrationQuery);
    }

    RunDatabaseMigrations();

    // Handle hot reload after database is ready
    if (g_bLate)
    {
        HandleHotReload();
    }
}


// ===== CONNECTION MANAGEMENT =====

// Tests database connection and handles reconnection logic with player state restoration
void SQLDbConnTest(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("Database connection test failed: connection lost");
        LogError("Database reconnect failed, next attempt in %i minutes.", g_iReconnectInterval);
        PrintHintTextToAll("%t", "DatabaseDown", g_iReconnectInterval);

        if (g_hDBReconnectTimer == null)
            g_hDBReconnectTimer = CreateTimer(float(60 * g_iReconnectInterval), Timer_ReconnectToDB, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (!StrEqual("", error))
    {
        LogError("Database connection test query failed: %s", error);
        LogError("Database reconnect failed, next attempt in %i minutes.", g_iReconnectInterval);
        PrintHintTextToAll("%t", "DatabaseDown", g_iReconnectInterval);

        if (g_hDBReconnectTimer == null)
            g_hDBReconnectTimer = CreateTimer(float(60 * g_iReconnectInterval), Timer_ReconnectToDB, TIMER_FLAG_NO_MAPCHANGE);
    } else {
        g_bNoStats = gcvar_stats.BoolValue ? false : true;

        if (!g_bNoStats && db != null)
        {
            // Database connection successful - handle both reconnection and hot-loading scenarios
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsValidClient(i))
                {
                    char steamid_dirty[31], steamid[64], query[256];
                    
                    // Get Steam ID and validate the operation succeeded
                    if (!GetClientAuthId(i, AuthId_Steam2, steamid_dirty, sizeof(steamid_dirty))) {
                        LogError("Failed to get Steam ID for client %d during reconnection - skipping", i);
                        continue;
                    }

                    db.Escape(steamid_dirty, steamid, sizeof(steamid));
                    strcopy(g_sPlayerSteamID[i], 32, steamid);
                    GetSelectPlayerStatsQuery(query, sizeof(query), steamid);
                    db.Query(SQL_OnPlayerReceived, query, i);
                    
                    // Handle hot-loading case: initialize client state that requires DB
                    if (!IsFakeClient(i))
                    {
                        // Ensure spectator team and proper client setup
                        ChangeClientTeam(i, TFTeam_Spectator);
                        g_bShowHud[i] = true;
                        g_bPlayerRestoringAmmo[i] = false;
                    }
                }
            }

            // Refresh all huds to show stats again.
            UpdateHudForAll();

            PrintHintTextToAll("%t", "StatsRestored");
            LogError("Database connection restored.");
        } else {
            PrintHintTextToAll("%t", "StatsRestoredDown");
            LogError("Database connection restored but stats are disabled or DB handle is invalid.");
        }
    }
}


// ===== DATABASE QUERY HANDLERS =====

// Processes database test query results and reports connection status to client
void SQL_OnTestReceived(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null)
    {
        LogError("[Test] Query failed: database connection lost");
        MC_PrintToChat(client, "%t", "DatabaseConnectionLost");
        return;
    }
    
    if (results == null)
    {
        LogError("[Test] Query failed: %s", error);
        MC_PrintToChat(client, "%t", "QueryFailed", error);
        return;
    }

    if (client < 1 || client > MaxClients || !IsClientConnected(client))
    {
        LogError("SQL_OnTestReceived failed: client %d <%s> is invalid.", client, g_sPlayerSteamID[client]);
        return;
    }

    if (results.FetchRow())
        MC_PrintToChat(client, "%t", "DatabaseUp");
    else
        MC_PrintToChat(client, "%t", "DatabaseDown");
}

// Handles player statistics retrieval from database and creates new player records if needed
void SQL_OnPlayerReceived(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null)
    {
        LogError("SQL_OnPlayerReceived failed: database connection lost");
        return;
    }
    
    if (results == null)
    {
        LogError("SQL_OnPlayerReceived FAILED for client %d (%s): %s", 
                 client, g_sPlayerSteamID[client], error);
        return;
    }

    if ( client < 1 || client > MaxClients || !IsClientConnected(client) )
    {
        LogError("SQL_OnPlayerReceived failed: client %d <%s> is invalid.", client, g_sPlayerSteamID[client]);
        return;
    }

    char query[512];
    char namesql_dirty[MAX_NAME_LENGTH], namesql[(MAX_NAME_LENGTH * 2) + 1];
    GetClientName(client, namesql_dirty, sizeof(namesql_dirty));
    db.Escape(namesql_dirty, namesql, sizeof(namesql));

    if (results.FetchRow())
    {
        g_iPlayerRating[client] = results.FetchInt(0);
        g_iPlayerWins[client] = results.FetchInt(1);
        g_iPlayerLosses[client] = results.FetchInt(2);
        // Legacy class ratings (for backward compatibility, but not used in new system)
        // Load matchup ratings separately
        g_bPlayerEloVerified[client] = true;
        
        // Load matchup ratings from separate table
        char matchupQuery[256];
        GetSelectMatchupRatingsQuery(matchupQuery, sizeof(matchupQuery), g_sPlayerSteamID[client]);
        g_DB.Query(SQL_OnMatchupRatingsReceived, matchupQuery, client);

        GetUpdatePlayerNameQuery(query, sizeof(query), namesql, g_sPlayerSteamID[client]);
        db.Query(SQL_OnGenericQueryFinished, query);
    } else {
        GetInsertPlayerQuery(query, sizeof(query), g_sPlayerSteamID[client], namesql, GetTime());
        db.Query(SQL_OnGenericQueryFinished, query);

        g_iPlayerRating[client] = 1600;
        g_bPlayerEloVerified[client] = true;
        // Matchup ratings will be initialized to 1500 when first used (in AddClassPointForPlayer)
    }
}

// Generic callback for database queries with error handling and connection monitoring
void SQL_OnGenericQueryFinished(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("SQL_OnGenericQueryFinished: Database connection lost (db handle is null)");
        
        if (!g_bNoStats)
        {
            g_bNoStats = true;
            PrintHintTextToAll("%t", "DatabaseDown", g_iReconnectInterval);

            // Refresh all huds to get rid of stats display.
            UpdateHudForAll();

            LogError("Lost connection to database, attempting reconnect in %i minutes.", g_iReconnectInterval);

            if (g_hDBReconnectTimer == null)
                g_hDBReconnectTimer = CreateTimer(float(60 * g_iReconnectInterval), Timer_ReconnectToDB, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    else if (!StrEqual("", error))
    {
        LogError("SQL_OnGenericQueryFinished: Query failed (connection OK): %s", error);
    }
}


// ===== TIMER FUNCTIONS =====

// Attempts database reconnection after connection loss with periodic retry mechanism
Action Timer_ReconnectToDB(Handle timer)
{
    g_hDBReconnectTimer = null;

    char query[256];
    GetSelectConnectionTestQuery(query, sizeof(query));
    g_DB.Query(SQLDbConnTest, query);

    return Plugin_Continue;
}


// ===== DATABASE ABSTRACTION LAYER =====

// Gets database-specific CREATE TABLE statement for mgemod_stats
void GetCreateTableQuery_Stats(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_stats (rating INTEGER, steamid TEXT, name TEXT, wins INTEGER, losses INTEGER, lastplayed INTEGER, scout_rating INTEGER DEFAULT 1600, sniper_rating INTEGER DEFAULT 1600, soldier_rating INTEGER DEFAULT 1600, demoman_rating INTEGER DEFAULT 1600, medic_rating INTEGER DEFAULT 1600, heavy_rating INTEGER DEFAULT 1600, pyro_rating INTEGER DEFAULT 1600, spy_rating INTEGER DEFAULT 1600, engineer_rating INTEGER DEFAULT 1600)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_stats (rating INT(4) NOT NULL, steamid VARCHAR(32) NOT NULL, name VARCHAR(64) NOT NULL, wins INT(4) NOT NULL, losses INT(4) NOT NULL, lastplayed INT(11) NOT NULL, scout_rating INT(4) NOT NULL DEFAULT 1600, sniper_rating INT(4) NOT NULL DEFAULT 1600, soldier_rating INT(4) NOT NULL DEFAULT 1600, demoman_rating INT(4) NOT NULL DEFAULT 1600, medic_rating INT(4) NOT NULL DEFAULT 1600, heavy_rating INT(4) NOT NULL DEFAULT 1600, pyro_rating INT(4) NOT NULL DEFAULT 1600, spy_rating INT(4) NOT NULL DEFAULT 1600, engineer_rating INT(4) NOT NULL DEFAULT 1600) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_stats (rating INTEGER NOT NULL, steamid VARCHAR(32) NOT NULL, name VARCHAR(64) NOT NULL, wins INTEGER NOT NULL, losses INTEGER NOT NULL, lastplayed INTEGER NOT NULL, scout_rating INTEGER NOT NULL DEFAULT 1600, sniper_rating INTEGER NOT NULL DEFAULT 1600, soldier_rating INTEGER NOT NULL DEFAULT 1600, demoman_rating INTEGER NOT NULL DEFAULT 1600, medic_rating INTEGER NOT NULL DEFAULT 1600, heavy_rating INTEGER NOT NULL DEFAULT 1600, pyro_rating INTEGER NOT NULL DEFAULT 1600, spy_rating INTEGER NOT NULL DEFAULT 1600, engineer_rating INTEGER NOT NULL DEFAULT 1600)");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_duels
void GetCreateTableQuery_Duels(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels (winner TEXT, loser TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, gametime INTEGER, mapname TEXT, arenaname TEXT)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels (winner VARCHAR(32) NOT NULL, loser VARCHAR(32) NOT NULL, winnerscore INT(4) NOT NULL, loserscore INT(4) NOT NULL, winlimit INT(4) NOT NULL, gametime INT(11) NOT NULL, mapname VARCHAR(64) NOT NULL, arenaname VARCHAR(32) NOT NULL) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels (id SERIAL PRIMARY KEY, winner VARCHAR(32) NOT NULL, winnerclass VARCHAR(64), loser VARCHAR(32) NOT NULL, loserclass VARCHAR(64), winnerscore INTEGER NOT NULL, loserscore INTEGER NOT NULL, winlimit INTEGER NOT NULL, starttime INTEGER, endtime INTEGER NOT NULL, mapname VARCHAR(64) NOT NULL, arenaname VARCHAR(32) NOT NULL, winner_previous_elo INTEGER, winner_new_elo INTEGER, loser_previous_elo INTEGER, loser_new_elo INTEGER, canceled INTEGER DEFAULT 0, canceled_reason TEXT DEFAULT NULL, canceled_by VARCHAR(32) DEFAULT NULL)");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_duel_class_ratings (1v1)
void GetCreateTableQuery_DuelClassRatings(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings (id INTEGER PRIMARY KEY, duel_id INTEGER NOT NULL, player_steamid TEXT NOT NULL, class_name TEXT NOT NULL, previous_rating INTEGER NOT NULL, new_rating INTEGER NOT NULL, rating_change INTEGER NOT NULL, contribution_weight REAL NOT NULL, FOREIGN KEY (duel_id) REFERENCES mgemod_duels(id) ON DELETE CASCADE)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings (id INT AUTO_INCREMENT PRIMARY KEY, duel_id INT NOT NULL, player_steamid VARCHAR(32) NOT NULL, class_name VARCHAR(16) NOT NULL, previous_rating INT(4) NOT NULL, new_rating INT(4) NOT NULL, rating_change INT(4) NOT NULL, contribution_weight FLOAT NOT NULL, INDEX idx_duel_player (duel_id, player_steamid), INDEX idx_class_name (class_name), CONSTRAINT fk_mge_duel_class_ratings_duel FOREIGN KEY (duel_id) REFERENCES mgemod_duels(id) ON DELETE CASCADE) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings (id SERIAL PRIMARY KEY, duel_id INTEGER NOT NULL REFERENCES mgemod_duels(id) ON DELETE CASCADE, player_steamid VARCHAR(32) NOT NULL, class_name VARCHAR(16) NOT NULL, previous_rating INTEGER NOT NULL, new_rating INTEGER NOT NULL, rating_change INTEGER NOT NULL, contribution_weight REAL NOT NULL)");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_duel_class_ratings_2v2
void GetCreateTableQuery_DuelClassRatings2v2(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings_2v2 (id INTEGER PRIMARY KEY, duel_id INTEGER NOT NULL, player_steamid TEXT NOT NULL, class_name TEXT NOT NULL, previous_rating INTEGER NOT NULL, new_rating INTEGER NOT NULL, rating_change INTEGER NOT NULL, contribution_weight REAL NOT NULL, FOREIGN KEY (duel_id) REFERENCES mgemod_duels_2v2(id) ON DELETE CASCADE)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings_2v2 (id INT AUTO_INCREMENT PRIMARY KEY, duel_id INT NOT NULL, player_steamid VARCHAR(32) NOT NULL, class_name VARCHAR(16) NOT NULL, previous_rating INT(4) NOT NULL, new_rating INT(4) NOT NULL, rating_change INT(4) NOT NULL, contribution_weight FLOAT NOT NULL, INDEX idx_duel_player (duel_id, player_steamid), INDEX idx_class_name (class_name), CONSTRAINT fk_mge_duel_class_ratings_2v2_duel FOREIGN KEY (duel_id) REFERENCES mgemod_duels_2v2(id) ON DELETE CASCADE) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duel_class_ratings_2v2 (id SERIAL PRIMARY KEY, duel_id INTEGER NOT NULL REFERENCES mgemod_duels_2v2(id) ON DELETE CASCADE, player_steamid VARCHAR(32) NOT NULL, class_name VARCHAR(16) NOT NULL, previous_rating INTEGER NOT NULL, new_rating INTEGER NOT NULL, rating_change INTEGER NOT NULL, contribution_weight REAL NOT NULL)");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_duels_2v2
void GetCreateTableQuery_Duels2v2(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels_2v2 (winner TEXT, winner2 TEXT, loser TEXT, loser2 TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, gametime INTEGER, mapname TEXT, arenaname TEXT)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels_2v2 (winner VARCHAR(32) NOT NULL, winner2 VARCHAR(32) NOT NULL, loser VARCHAR(32) NOT NULL, loser2 VARCHAR(32) NOT NULL, winnerscore INT(4) NOT NULL, loserscore INT(4) NOT NULL, winlimit INT(4) NOT NULL, gametime INT(11) NOT NULL, mapname VARCHAR(64) NOT NULL, arenaname VARCHAR(32) NOT NULL) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_duels_2v2 (id SERIAL PRIMARY KEY, winner VARCHAR(32) NOT NULL, winnerclass VARCHAR(64), winner2 VARCHAR(32) NOT NULL, winner2class VARCHAR(64), loser VARCHAR(32) NOT NULL, loserclass VARCHAR(64), loser2 VARCHAR(32) NOT NULL, loser2class VARCHAR(64), winnerscore INTEGER NOT NULL, loserscore INTEGER NOT NULL, winlimit INTEGER NOT NULL, starttime INTEGER, endtime INTEGER NOT NULL, mapname VARCHAR(64) NOT NULL, arenaname VARCHAR(32) NOT NULL, winner_previous_elo INTEGER, winner_new_elo INTEGER, winner2_previous_elo INTEGER, winner2_new_elo INTEGER, loser_previous_elo INTEGER, loser_new_elo INTEGER, loser2_previous_elo INTEGER, loser2_new_elo INTEGER, canceled INTEGER DEFAULT 0, canceled_reason TEXT DEFAULT NULL, canceled_by VARCHAR(32) DEFAULT NULL)");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_matchup_ratings
void GetCreateTableQuery_MatchupRatings(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_matchup_ratings (steamid TEXT NOT NULL, my_class INTEGER NOT NULL, opponent_class INTEGER NOT NULL, rating INTEGER NOT NULL DEFAULT 1500, PRIMARY KEY (steamid, my_class, opponent_class))");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_matchup_ratings (steamid VARCHAR(32) NOT NULL, my_class INT(1) NOT NULL, opponent_class INT(1) NOT NULL, rating INT(4) NOT NULL DEFAULT 1500, PRIMARY KEY (steamid, my_class, opponent_class), INDEX idx_steamid (steamid)) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_matchup_ratings (steamid VARCHAR(32) NOT NULL, my_class INTEGER NOT NULL, opponent_class INTEGER NOT NULL, rating INTEGER NOT NULL DEFAULT 1500, PRIMARY KEY (steamid, my_class, opponent_class))");
        }
    }
}

// Gets database-specific CREATE TABLE statement for mgemod_migrations
void GetCreateTableQuery_Migrations(char[] query, int maxlen)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_migrations (id INTEGER PRIMARY KEY, migration_name TEXT UNIQUE, executed_at INTEGER)");
        }
        case DB_MYSQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_migrations (id INT AUTO_INCREMENT PRIMARY KEY, migration_name VARCHAR(255) UNIQUE, executed_at INT) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ENGINE = InnoDB");
        }
        case DB_POSTGRESQL:
        {
            strcopy(query, maxlen, "CREATE TABLE IF NOT EXISTS mgemod_migrations (id SERIAL PRIMARY KEY, migration_name VARCHAR(255) UNIQUE, executed_at INTEGER)");
        }
    }
}

// Gets database-specific INSERT statement for player stats
void GetInsertPlayerQuery(char[] query, int maxlen, const char[] steamid, const char[] name, int timestamp)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_stats (rating, steamid, name, wins, losses, lastplayed, scout_rating, sniper_rating, soldier_rating, demoman_rating, medic_rating, heavy_rating, pyro_rating, spy_rating, engineer_rating) VALUES(1600, '%s', '%s', 0, 0, %i, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600)", steamid, name, timestamp);
        }
        case DB_MYSQL:
        {
			g_DB.Format(query, maxlen, "INSERT INTO mgemod_stats (rating, steamid, name, wins, losses, lastplayed, scout_rating, sniper_rating, soldier_rating, demoman_rating, medic_rating, heavy_rating, pyro_rating, spy_rating, engineer_rating) VALUES (1600, '%s', '%s', 0, 0, %i, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600) ON DUPLICATE KEY UPDATE name = VALUES(name), lastplayed = VALUES(lastplayed)", steamid, name, timestamp);
        }
        case DB_POSTGRESQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_stats (rating, steamid, name, wins, losses, lastplayed, scout_rating, sniper_rating, soldier_rating, demoman_rating, medic_rating, heavy_rating, pyro_rating, spy_rating, engineer_rating) VALUES (1600, '%s', '%s', 0, 0, %i, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600, 1600) ON CONFLICT (steamid) DO UPDATE SET name = EXCLUDED.name, lastplayed = EXCLUDED.lastplayed", steamid, name, timestamp);
        }
    }
}

// Gets database-specific SELECT statement for player stats
void GetSelectPlayerStatsQuery(char[] query, int maxlen, const char[] steamid)
{
    // Only load basic stats, matchup ratings are loaded separately
    g_DB.Format(query, maxlen, "SELECT rating, wins, losses, 0, 0, 0, 0, 0, 0, 0, 0, 0 FROM mgemod_stats WHERE steamid='%s' LIMIT 1", steamid);
}

// Gets database-specific UPDATE statement for player name
void GetUpdatePlayerNameQuery(char[] query, int maxlen, const char[] name, const char[] steamid)
{
    g_DB.Format(query, maxlen, "UPDATE mgemod_stats SET name='%s' WHERE steamid='%s'", name, steamid);
}

// Gets database-specific UPDATE statement for winner stats
void GetUpdateWinnerStatsQuery(char[] query, int maxlen, int rating, int timestamp, const char[] steamid)
{
    g_DB.Format(query, maxlen, "UPDATE mgemod_stats SET rating=%i,wins=wins+1,lastplayed=%i WHERE steamid='%s'", rating, timestamp, steamid);
}

// Gets database-specific UPDATE statement for loser stats
void GetUpdateLoserStatsQuery(char[] query, int maxlen, int rating, int timestamp, const char[] steamid)
{
    g_DB.Format(query, maxlen, "UPDATE mgemod_stats SET rating=%i,losses=losses+1,lastplayed=%i WHERE steamid='%s'", rating, timestamp, steamid);
}



// Gets database-specific INSERT statement for duel results
void GetInsertDuelQuery(char[] query, int maxlen, const char[] winner, const char[] loser, int winnerScore, int loserScore, int fragLimit, int endTime, int startTime, const char[] mapName, const char[] arenaName, const char[] winnerClass, const char[] loserClass, int winnerPrevElo, int winnerNewElo, int loserPrevElo, int loserNewElo)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels VALUES (NULL, '%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', %i, %i, %i, %i)", 
                winner, loser, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, loserClass, winnerPrevElo, winnerNewElo, loserPrevElo, loserNewElo);
        }
        case DB_MYSQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels (winner, loser, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, loserclass, winner_previous_elo, winner_new_elo, loser_previous_elo, loser_new_elo) VALUES ('%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', %i, %i, %i, %i)",
                winner, loser, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, loserClass, winnerPrevElo, winnerNewElo, loserPrevElo, loserNewElo);
        }
        case DB_POSTGRESQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels (winner, loser, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, loserclass, winner_previous_elo, winner_new_elo, loser_previous_elo, loser_new_elo) VALUES ('%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', %i, %i, %i, %i) RETURNING id",
                winner, loser, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, loserClass, winnerPrevElo, winnerNewElo, loserPrevElo, loserNewElo);
        }
    }
}

// Gets database-specific INSERT statement for 2v2 duel results
void GetInsert2v2DuelQuery(char[] query, int maxlen, const char[] winner, const char[] winner2, const char[] loser, const char[] loser2, int winnerScore, int loserScore, int fragLimit, int endTime, int startTime, const char[] mapName, const char[] arenaName, const char[] winnerClass, const char[] winner2Class, const char[] loserClass, const char[] loser2Class, int winnerPrevElo, int winnerNewElo, int winner2PrevElo, int winner2NewElo, int loserPrevElo, int loserNewElo, int loser2PrevElo, int loser2NewElo)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels_2v2 VALUES (NULL, '%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i)",
                winner, winner2, loser, loser2, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, winner2Class, loserClass, loser2Class, winnerPrevElo, winnerNewElo, winner2PrevElo, winner2NewElo, loserPrevElo, loserNewElo, loser2PrevElo, loser2NewElo);
        }
        case DB_MYSQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels_2v2 (winner, winner2, loser, loser2, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, winner2class, loserclass, loser2class, winner_previous_elo, winner_new_elo, winner2_previous_elo, winner2_new_elo, loser_previous_elo, loser_new_elo, loser2_previous_elo, loser2_new_elo) VALUES ('%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i)",
                winner, winner2, loser, loser2, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, winner2Class, loserClass, loser2Class, winnerPrevElo, winnerNewElo, winner2PrevElo, winner2NewElo, loserPrevElo, loserNewElo, loser2PrevElo, loser2NewElo);
        }
        case DB_POSTGRESQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_duels_2v2 (winner, winner2, loser, loser2, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, winner2class, loserclass, loser2class, winner_previous_elo, winner_new_elo, winner2_previous_elo, winner2_new_elo, loser_previous_elo, loser_new_elo, loser2_previous_elo, loser2_new_elo) VALUES ('%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, '%s', '%s', '%s', '%s', '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i) RETURNING id",
                winner, winner2, loser, loser2, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, winner2Class, loserClass, loser2Class, winnerPrevElo, winnerNewElo, winner2PrevElo, winner2NewElo, loserPrevElo, loserNewElo, loser2PrevElo, loser2NewElo);
        }
    }
}

void InsertDuelWithClassRatings1v1(int arena_index, int winner, int loser, const char[] winner_steamid, const char[] loser_steamid, int winnerScore, int loserScore, int fragLimit, int endTime, int startTime, const char[] mapName, const char[] arenaName, const char[] winnerClass, const char[] loserClass, int winnerPrevElo, int winnerNewElo, int loserPrevElo, int loserNewElo, ArrayList classEntries)
{
    char query[1024];
    GetInsertDuelQuery(query, sizeof(query), winner_steamid, loser_steamid, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, loserClass, winnerPrevElo, winnerNewElo, loserPrevElo, loserNewElo);
    DataPack pack = new DataPack();
    pack.WriteCell(false); // is2v2
    pack.WriteCell(classEntries);
    pack.WriteCell(arena_index);
    pack.WriteCell(winner);
    pack.WriteCell(loser);
    pack.WriteCell(winnerScore);
    pack.WriteCell(loserScore);
    g_DB.Query(SQL_OnDuelInserted, query, pack);
}

void InsertDuelWithClassRatings2v2(int arena_index, int winning_team, int winnerScore, int loserScore, const char[] winner_steamid, const char[] winner2_steamid, const char[] loser_steamid, const char[] loser2_steamid, int fragLimit, int endTime, int startTime, const char[] mapName, const char[] arenaName, const char[] winnerClass, const char[] winner2Class, const char[] loserClass, const char[] loser2Class, int winnerPrevElo, int winnerNewElo, int winner2PrevElo, int winner2NewElo, int loserPrevElo, int loserNewElo, int loser2PrevElo, int loser2NewElo, ArrayList classEntries)
{
    char query[1024];
    GetInsert2v2DuelQuery(query, sizeof(query), winner_steamid, winner2_steamid, loser_steamid, loser2_steamid, winnerScore, loserScore, fragLimit, endTime, startTime, mapName, arenaName, winnerClass, winner2Class, loserClass, loser2Class, winnerPrevElo, winnerNewElo, winner2PrevElo, winner2NewElo, loserPrevElo, loserNewElo, loser2PrevElo, loser2NewElo);
    DataPack pack = new DataPack();
    pack.WriteCell(true); // is2v2
    pack.WriteCell(classEntries);
    pack.WriteCell(arena_index);
    pack.WriteCell(winning_team);
    pack.WriteCell(winnerScore);
    pack.WriteCell(loserScore);
    pack.WriteCell(g_iArenaQueue[arena_index][SLOT_ONE]);
    pack.WriteCell(g_iArenaQueue[arena_index][SLOT_THREE]);
    pack.WriteCell(g_iArenaQueue[arena_index][SLOT_TWO]);
    pack.WriteCell(g_iArenaQueue[arena_index][SLOT_FOUR]);
    g_DB.Query(SQL_OnDuelInserted, query, pack);
}

void SQL_OnDuelInserted(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    bool is2v2 = pack.ReadCell();
    ArrayList classEntries = view_as<ArrayList>(pack.ReadCell());
    int arena_index = pack.ReadCell();
    // Common parameters to pass to SQL_OnDuelIdReceived
    DataPack idPack = new DataPack();
    idPack.WriteCell(is2v2);
    idPack.WriteCell(classEntries);
    idPack.WriteCell(arena_index);

    if (is2v2)
    {
        int winning_team = pack.ReadCell();
        int winnerScore = pack.ReadCell();
        int loserScore = pack.ReadCell();
        int team1_player1 = pack.ReadCell();
        int team1_player2 = pack.ReadCell();
        int team2_player1 = pack.ReadCell();
        int team2_player2 = pack.ReadCell();

        if (g_DatabaseType == DB_POSTGRESQL)
        {
            if (results != null && results.FetchRow())
            {
                int duelId = results.FetchInt(0);
                CallForward_On2v2MatchEnd(duelId, arena_index, winning_team, winnerScore, loserScore, team1_player1, team1_player2, team2_player1, team2_player2);
                InsertClassRatingRows(duelId, classEntries, is2v2);
            }
            else
            {
                LogError("SQL_OnDuelInserted failed: missing duel id for 2v2");
                if (classEntries != null)
                    delete classEntries;
            }
            delete pack;
            return;
        }

        char idQuery[128];
        if (g_DatabaseType == DB_MYSQL)
            strcopy(idQuery, sizeof(idQuery), "SELECT LAST_INSERT_ID()");
        else
            strcopy(idQuery, sizeof(idQuery), "SELECT last_insert_rowid()");
        
        idPack.WriteCell(winning_team);
        idPack.WriteCell(winnerScore);
        idPack.WriteCell(loserScore);
        idPack.WriteCell(team1_player1);
        idPack.WriteCell(team1_player2);
        idPack.WriteCell(team2_player1);
        idPack.WriteCell(team2_player2);
        g_DB.Query(SQL_OnDuelIdReceived, idQuery, idPack);
    }
    else // 1v1 case
    {
        int winner = pack.ReadCell();
        int loser = pack.ReadCell();
        int winnerScore = pack.ReadCell();
        int loserScore = pack.ReadCell();

        if (g_DatabaseType == DB_POSTGRESQL)
        {
            if (results != null && results.FetchRow())
            {
                int duelId = results.FetchInt(0);
                CallForward_On1v1MatchEnd(duelId, arena_index, winner, loser, winnerScore, loserScore);
                InsertClassRatingRows(duelId, classEntries, is2v2);
            }
            else
            {
                LogError("SQL_OnDuelInserted failed: missing duel id for 1v1");
                if (classEntries != null)
                    delete classEntries;
            }
            delete pack;
            return;
        }

        char idQuery[128];
        if (g_DatabaseType == DB_MYSQL)
            strcopy(idQuery, sizeof(idQuery), "SELECT LAST_INSERT_ID()");
        else
            strcopy(idQuery, sizeof(idQuery), "SELECT last_insert_rowid()");

        idPack.WriteCell(winner);
        idPack.WriteCell(loser);
        idPack.WriteCell(winnerScore);
        idPack.WriteCell(loserScore);
        g_DB.Query(SQL_OnDuelIdReceived, idQuery, idPack);
    }
    delete pack;
}

void SQL_OnDuelIdReceived(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    bool is2v2 = pack.ReadCell();
    ArrayList classEntries = view_as<ArrayList>(pack.ReadCell());
    int arena_index = pack.ReadCell();

    if (db == null)
    {
        LogError("SQL_OnDuelIdReceived failed: database connection lost");
        if (classEntries != null)
            delete classEntries;
        delete pack;
        return;
    }

    if (!StrEqual("", error))
    {
        LogError("SQL_OnDuelIdReceived failed: %s", error);
        if (classEntries != null)
            delete classEntries;
        delete pack;
        return;
    }

    if (results == null || !results.FetchRow())
    {
        LogError("SQL_OnDuelIdReceived failed: missing duel id");
        if (classEntries != null)
            delete classEntries;
        delete pack;
        return;
    }

    int duelId = results.FetchInt(0);

    if (is2v2)
    {
        int winning_team = pack.ReadCell();
        int winnerScore = pack.ReadCell();
        int loserScore = pack.ReadCell();
        int team1_player1 = pack.ReadCell();
        int team1_player2 = pack.ReadCell();
        int team2_player1 = pack.ReadCell();
        int team2_player2 = pack.ReadCell();
        CallForward_On2v2MatchEnd(duelId, arena_index, winning_team, winnerScore, loserScore, team1_player1, team1_player2, team2_player1, team2_player2);
    }
    else // 1v1 case
    {
        int winner = pack.ReadCell();
        int loser = pack.ReadCell();
        int winnerScore = pack.ReadCell();
        int loserScore = pack.ReadCell();
        CallForward_On1v1MatchEnd(duelId, arena_index, winner, loser, winnerScore, loserScore);
    }

    InsertClassRatingRows(duelId, classEntries, is2v2);
    delete pack;
}

void InsertClassRatingRows(int duelId, ArrayList classEntries, bool is2v2)
{
    if (classEntries == null || classEntries.Length == 0)
    {
        if (classEntries != null)
            delete classEntries;
        return;
    }

    char query[8192];
    char tableName[64];
    if (is2v2)
        strcopy(tableName, sizeof(tableName), "mgemod_duel_class_ratings_2v2");
    else
        strcopy(tableName, sizeof(tableName), "mgemod_duel_class_ratings");
    Format(query, sizeof(query), "INSERT INTO %s (duel_id, player_steamid, class_name, previous_rating, new_rating, rating_change, contribution_weight) VALUES ", tableName);

    for (int i = 0; i < classEntries.Length; i++)
    {
        ClassRatingEntry entry;
        classEntries.GetArray(i, entry, sizeof(entry));

        char className[16];
        strcopy(className, sizeof(className), TFClassToString(view_as<TFClassType>(entry.classId)));

        char steamidEscaped[64];
        g_DB.Escape(g_sPlayerSteamID[entry.player], steamidEscaped, sizeof(steamidEscaped));

        char values[256];
        Format(values, sizeof(values), "%s(%d, '%s', '%s', %d, %d, %d, %.4f)",
            (i > 0) ? "," : "", duelId, steamidEscaped, className, entry.previousRating, entry.newRating, entry.ratingChange, entry.weight);
        StrCat(query, sizeof(query), values);
    }

    g_DB.Query(SQL_OnGenericQueryFinished, query);
    delete classEntries;
}

// Gets database-specific SELECT statement for top players
void GetSelectTopPlayersQuery(char[] query, int maxlen)
{
    g_DB.Format(query, maxlen, "SELECT rating, name, wins, losses FROM mgemod_stats ORDER BY rating DESC");
}

// Gets database-specific SELECT statement for player rating rank
void GetSelectPlayerRatingRankQuery(char[] query, int maxlen, const char[] steamid)
{
    g_DB.Format(query, maxlen, "SELECT COUNT(*) + 1 FROM mgemod_stats WHERE rating > (SELECT rating FROM mgemod_stats WHERE steamid='%s')", steamid);
}

// Gets database-specific SELECT statement for player wins rank
void GetSelectPlayerWinsRankQuery(char[] query, int maxlen, const char[] steamid)
{
    g_DB.Format(query, maxlen, "SELECT COUNT(*) + 1 FROM mgemod_stats WHERE wins > (SELECT wins FROM mgemod_stats WHERE steamid='%s')", steamid);
}

// Gets database-specific SELECT statement for player losses rank
void GetSelectPlayerLossesRankQuery(char[] query, int maxlen, const char[] steamid)
{
    g_DB.Format(query, maxlen, "SELECT COUNT(*) + 1 FROM mgemod_stats WHERE losses < (SELECT losses FROM mgemod_stats WHERE steamid='%s')", steamid);
}


// Gets database-specific SELECT statement for database connection test
void GetSelectConnectionTestQuery(char[] query, int maxlen)
{
    g_DB.Format(query, maxlen, "SELECT rating FROM mgemod_stats LIMIT 1");
}

// Gets database-specific SELECT statement to check migration status
void GetSelectMigrationStatusQuery(char[] query, int maxlen, const char[] migrationName)
{
    g_DB.Format(query, maxlen, "SELECT COUNT(*) FROM mgemod_migrations WHERE migration_name = '%s'", migrationName);
}

// Gets database-specific INSERT statement to mark migration complete
void GetInsertMigrationCompleteQuery(char[] query, int maxlen, const char[] migrationName, int timestamp)
{
    g_DB.Format(query, maxlen, "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('%s', %d)", migrationName, timestamp);
}

// Load matchup ratings from database
void GetSelectMatchupRatingsQuery(char[] query, int maxlen, const char[] steamid)
{
    g_DB.Format(query, maxlen, "SELECT my_class, opponent_class, rating FROM mgemod_matchup_ratings WHERE steamid='%s'", steamid);
}

// Callback for loading matchup ratings
void SQL_OnMatchupRatingsReceived(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null || results == null || !StrEqual("", error))
    {
        if (!StrEqual("", error))
            LogError("SQL_OnMatchupRatingsReceived failed for client %d: %s", client, error);
        return;
    }

    if (client < 1 || client > MaxClients || !IsClientConnected(client))
        return;

    while (results.FetchRow())
    {
        int myClass = results.FetchInt(0);
        int opponentClass = results.FetchInt(1);
        int rating = results.FetchInt(2);
        
        if (myClass >= 1 && myClass <= 9 && opponentClass >= 1 && opponentClass <= 9)
        {
            g_iPlayerClassRating[client][myClass][opponentClass] = rating;
        }
    }
}

// Update matchup ratings in database
void UpdateMatchupRatings(int client)
{
    if (!IsValidClient(client) || strlen(g_sPlayerSteamID[client]) == 0)
        return;

    // Update all matchup ratings that have been set (non-zero)
    for (int myClass = 1; myClass <= 9; myClass++)
    {
        for (int oppClass = 1; oppClass <= 9; oppClass++)
        {
            int rating = g_iPlayerClassRating[client][myClass][oppClass];
            if (rating > 0) // Only update if rating has been set
            {
                char query[256];
                GetUpsertMatchupRatingQuery(query, sizeof(query), g_sPlayerSteamID[client], myClass, oppClass, rating);
                g_DB.Query(SQL_OnGenericQueryFinished, query);
            }
        }
    }
}

// Gets database-specific UPSERT statement for matchup rating
void GetUpsertMatchupRatingQuery(char[] query, int maxlen, const char[] steamid, int myClass, int opponentClass, int rating)
{
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            g_DB.Format(query, maxlen, "INSERT OR REPLACE INTO mgemod_matchup_ratings (steamid, my_class, opponent_class, rating) VALUES ('%s', %d, %d, %d)", steamid, myClass, opponentClass, rating);
        }
        case DB_MYSQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_matchup_ratings (steamid, my_class, opponent_class, rating) VALUES ('%s', %d, %d, %d) ON DUPLICATE KEY UPDATE rating = VALUES(rating)", steamid, myClass, opponentClass, rating);
        }
        case DB_POSTGRESQL:
        {
            g_DB.Format(query, maxlen, "INSERT INTO mgemod_matchup_ratings (steamid, my_class, opponent_class, rating) VALUES ('%s', %d, %d, %d) ON CONFLICT (steamid, my_class, opponent_class) DO UPDATE SET rating = EXCLUDED.rating", steamid, myClass, opponentClass, rating);
        }
    }
}