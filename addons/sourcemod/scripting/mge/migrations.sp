StringMap g_migrationProgress;

// ===== MIGRATION SYSTEM CORE =====

// Initializes the migration tracking system by creating or resetting the progress map
void InitializeMigrationSystem()
{
    if (g_migrationProgress != null)
        delete g_migrationProgress;
    g_migrationProgress = new StringMap();
}

// Entry point for database schema migrations that orchestrates the entire migration process
void RunDatabaseMigrations()
{
    LogMessage("[Migrations] Starting database schema migrations");
    InitializeMigrationSystem();
    CreateMigrationsTable();
}

// Creates the migrations tracking table for both SQLite and MySQL databases
void CreateMigrationsTable()
{
    char query[512];
    GetCreateTableQuery_Migrations(query, sizeof(query));
    g_DB.Query(CreateMigrationsTableCallback, query);
}


// ===== MIGRATION EXECUTION ENGINE =====

// Checks if a migration has been executed and runs it if needed
void CheckAndRunMigration(const char[] migrationName)
{
    char query[256];
    GetSelectMigrationStatusQuery(query, sizeof(query), migrationName);
    
    DataPack pack = new DataPack();
    pack.WriteString(migrationName);
    
    g_DB.Query(CheckMigrationCallback, query, pack);
}

// Dispatches specific migration execution based on migration name
void RunMigration(const char[] migrationName)
{
    // NOTE: Migrations 001-004 are legacy migrations for SQLite/MySQL only
    // PostgreSQL gets modern schema immediately in CREATE TABLE statements
    // Future migrations (005+) should include PostgreSQL-specific queries using g_DatabaseType switch
    
    if (StrEqual(migrationName, "001_add_class_columns"))
    {
        g_migrationProgress.SetValue(migrationName, 6);
        Migration_001_AddClassColumns();
    }
    else if (StrEqual(migrationName, "002_duel_timing_columns"))
    {
        g_migrationProgress.SetValue(migrationName, 4);
        Migration_002_DuelTimingColumns();
    }
    else if (StrEqual(migrationName, "003_add_primary_keys"))
    {
        // Step counts differ by database type
        switch (g_DatabaseType)
        {
            case DB_SQLITE: g_migrationProgress.SetValue(migrationName, 11);
            case DB_MYSQL: g_migrationProgress.SetValue(migrationName, 4);
            default: g_migrationProgress.SetValue(migrationName, 1);
        }
        Migration_003_AddPrimaryKeys();
    }
    else if (StrEqual(migrationName, "004_add_elo_tracking"))
    {
        g_migrationProgress.SetValue(migrationName, 12);
        Migration_004_AddEloTracking();
    }
    else if (StrEqual(migrationName, "005_utf8mb4_charset"))
    {
        switch (g_DatabaseType)
        {
            case DB_MYSQL: g_migrationProgress.SetValue(migrationName, 1);
            default: g_migrationProgress.SetValue(migrationName, 1);
        }
        Migration_005_Utf8mb4Charset();
    }
    else if (StrEqual(migrationName, "006_drop_hitblip_column"))
    {
        Migration_006_DropHitblipColumn();
    }
    else if (StrEqual(migrationName, "007_add_glicko_columns"))
    {
        switch (g_DatabaseType)
        {
            case DB_POSTGRESQL: g_migrationProgress.SetValue(migrationName, 1);
            default: g_migrationProgress.SetValue(migrationName, 2);
        }
        Migration_007_AddGlickoColumns();
    }
    else if (StrEqual(migrationName, "008_seed_glicko_rd_defaults"))
    {
        g_migrationProgress.SetValue(migrationName, 1);
        Migration_008_SeedGlickoRdDefaults();
    }
    else if (StrEqual(migrationName, "009_glicko_period_schema"))
    {
        g_migrationProgress.SetValue(migrationName, 15);
        Migration_009_GlickoPeriodSchema();
    }
}

// Executes individual migration steps with progress tracking and error handling
void ExecuteMigrationStep(const char[] migrationName, const char[] query, int stepNumber)
{
    DataPack pack = new DataPack();
    pack.WriteString(migrationName);
    pack.WriteCell(stepNumber);
    g_DB.Query(GenericMigrationCallback, query, pack);
}

bool IsAlreadyAppliedMigrationError(const char[] error)
{
    if (StrContains(error, "duplicate column name", false) != -1)
        return true;

    if (StrContains(error, "multiple primary key", false) != -1)
        return true;

    if (StrContains(error, "duplicate key name", false) != -1)
        return true;

    if (StrContains(error, "unknown column 'gametime'", false) != -1)
        return true;

    if (StrContains(error, "no such column: gametime", false) != -1)
        return true;

    if (StrContains(error, "UNIQUE constraint failed", false) != -1)
        return true;

    if (StrContains(error, "Duplicate entry", false) != -1)
        return true;

    if (StrContains(error, "already exists", false) != -1)
        return true;

    return false;
}

// Records successful migration completion in the migrations tracking table
void MarkMigrationComplete(const char[] migrationName)
{
    char query[256];
    GetInsertMigrationCompleteQuery(query, sizeof(query), migrationName, GetTime());
    g_DB.Query(MarkMigrationCallback, query);
}


// ===== DATABASE CALLBACK HANDLERS =====

// Handles migrations table creation result and initiates individual migration checks
void CreateMigrationsTableCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while creating migrations table");
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to create migrations table: %s", error);
        return;
    }
    
    LogMessage("[Migrations] Migration tracking table ready, checking individual migrations");
    
    // Run legacy migrations for SQLite and MySQL
    CheckAndRunMigration("001_add_class_columns");
    CheckAndRunMigration("002_duel_timing_columns");
    CheckAndRunMigration("003_add_primary_keys");
    CheckAndRunMigration("004_add_elo_tracking");
    CheckAndRunMigration("005_utf8mb4_charset");
    CheckAndRunMigration("006_drop_hitblip_column");
    CheckAndRunMigration("007_add_glicko_columns");
    CheckAndRunMigration("008_seed_glicko_rd_defaults");
    CheckAndRunMigration("009_glicko_period_schema");
}

// Processes migration existence check results and triggers migration execution if needed
void CheckMigrationCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    char migrationName[64];
    pack.ReadString(migrationName, sizeof(migrationName));
    delete pack;
    
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while checking migration: %s", migrationName);
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to check migration %s: %s", migrationName, error);
        return;
    }
    
    if (results.FetchRow())
    {
        int migrationExists = results.FetchInt(0);
        if (migrationExists == 0)
        {
            LogMessage("[Migrations] Running migration: %s", migrationName);
            RunMigration(migrationName);
        }
        else
        {
            LogMessage("[Migrations] Migration %s already executed (skipping)", migrationName);
            if (StrEqual(migrationName, "009_glicko_period_schema"))
                GlickoPeriod_OnSchemaReady();
        }
    }
}

// Handles individual migration step results and tracks progress toward completion
void GenericMigrationCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    char migrationName[64];
    pack.ReadString(migrationName, sizeof(migrationName));
    int stepNumber = pack.ReadCell();
    delete pack;
    
    if (db == null)
    {
        LogError("[Migration %s] Database connection lost during step %d", migrationName, stepNumber);
        return;
    }
    
    if (!StrEqual("", error))
    {
        if (IsAlreadyAppliedMigrationError(error))
        {
            LogMessage("[Migration %s] Step %d already applied (continuing): %s", migrationName, stepNumber, error);
        }
        else
        {
            LogError("[Migration %s] Step %d failed: %s", migrationName, stepNumber, error);
            return;
        }
    }
    
    // Get expected total steps for this migration
    int totalSteps;
    if (!g_migrationProgress.GetValue(migrationName, totalSteps))
    {
        LogError("[Migration %s] No step count registered for migration", migrationName);
        return;
    }
    
    // Get current progress (completed steps)
    char progressKey[128];
    Format(progressKey, sizeof(progressKey), "%s_completed", migrationName);
    int completedSteps;
    g_migrationProgress.GetValue(progressKey, completedSteps);
    
    completedSteps++;
    g_migrationProgress.SetValue(progressKey, completedSteps);
    
    LogMessage("[Migration %s] Step %d/%d completed", migrationName, completedSteps, totalSteps);
    
    // When all steps are complete, mark migration as done
    if (completedSteps >= totalSteps)
    {
        LogMessage("[Migration %s] All steps completed successfully", migrationName);
        MarkMigrationComplete(migrationName);

        if (StrEqual(migrationName, "009_glicko_period_schema"))
            GlickoPeriod_OnSchemaReady();
        
        // Clean up progress tracking for this migration
        g_migrationProgress.Remove(migrationName);
        g_migrationProgress.Remove(progressKey);
    }
}

// Processes migration completion marking results with error logging
void MarkMigrationCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while marking migration complete");
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to mark migration complete: %s", error);
        return;
    }
}


// ===== SPECIFIC MIGRATIONS =====

// Adds class tracking columns to duel tables for both 1v1 and 2v2 matches
void Migration_001_AddClassColumns()
{
    LogMessage("[Migration 001] Adding class tracking columns");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerclass TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserclass TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerclass TEXT DEFAULT NULL", 3);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2class TEXT DEFAULT NULL", 4);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserclass TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2class TEXT DEFAULT NULL", 6);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerclass VARCHAR(64) DEFAULT NULL", 1);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserclass VARCHAR(64) DEFAULT NULL", 2);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerclass VARCHAR(64) DEFAULT NULL", 3);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2class VARCHAR(64) DEFAULT NULL", 4);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserclass VARCHAR(64) DEFAULT NULL", 5);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2class VARCHAR(64) DEFAULT NULL", 6);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema in CREATE TABLE - mark as complete
            LogMessage("[Migration 001] Skipping migration on PostgreSQL (schema already includes these columns)");
            MarkMigrationComplete("001_add_class_columns");
        }
    }
}

// Converts gametime to endtime and adds starttime column for better duel tracking
void Migration_002_DuelTimingColumns()
{
    LogMessage("[Migration 002] Converting gametime to endtime and adding starttime column");
    
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels RENAME COLUMN gametime TO endtime", 1);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels ADD COLUMN starttime INTEGER DEFAULT NULL", 2);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 RENAME COLUMN gametime TO endtime", 3);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN starttime INTEGER DEFAULT NULL", 4);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels CHANGE gametime endtime INT(11) NOT NULL", 1);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels ADD COLUMN starttime INT(11) DEFAULT NULL", 2);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 CHANGE gametime endtime INT(11) NOT NULL", 3);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN starttime INT(11) DEFAULT NULL", 4);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema in CREATE TABLE - mark as complete
            LogMessage("[Migration 002] Skipping migration on PostgreSQL (schema already includes these columns)");
            MarkMigrationComplete("002_duel_timing_columns");
        }
    }
}

// Adds primary keys to database tables and creates necessary indexes
void Migration_003_AddPrimaryKeys()
{
    LogMessage("[Migration 003] Adding primary keys to database tables");
    
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            // Note: DO NOT include ELO columns here - those are added by migration 004
            // Only include columns that exist after migrations 001 (class columns) and 002 (timing columns)
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_backup AS SELECT * FROM mgemod_duels", 1);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_new (id INTEGER PRIMARY KEY, winner TEXT, loser TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, endtime INTEGER, starttime INTEGER, mapname TEXT, arenaname TEXT, winnerclass TEXT, loserclass TEXT)", 2);
            ExecuteMigrationStep("003_add_primary_keys", "INSERT INTO mgemod_duels_new SELECT NULL, winner, loser, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, loserclass FROM mgemod_duels", 3);
            ExecuteMigrationStep("003_add_primary_keys", "DROP TABLE mgemod_duels", 4);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_new RENAME TO mgemod_duels", 5);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_2v2_backup AS SELECT * FROM mgemod_duels_2v2", 6);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_2v2_new (id INTEGER PRIMARY KEY, winner TEXT, winner2 TEXT, loser TEXT, loser2 TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, endtime INTEGER, starttime INTEGER, mapname TEXT, arenaname TEXT, winnerclass TEXT, winner2class TEXT, loserclass TEXT, loser2class TEXT)", 7);
            ExecuteMigrationStep("003_add_primary_keys", "INSERT INTO mgemod_duels_2v2_new SELECT NULL, winner, winner2, loser, loser2, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, winner2class, loserclass, loser2class FROM mgemod_duels_2v2", 8);
            ExecuteMigrationStep("003_add_primary_keys", "DROP TABLE mgemod_duels_2v2", 9);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_2v2_new RENAME TO mgemod_duels_2v2", 10);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE UNIQUE INDEX IF NOT EXISTS idx_stats_steamid ON mgemod_stats (steamid)", 11);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY FIRST", 1);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY FIRST", 2);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_stats ADD PRIMARY KEY (steamid)", 3);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE UNIQUE INDEX IF NOT EXISTS idx_stats_steamid ON mgemod_stats (steamid)", 4);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema in CREATE TABLE - mark as complete
            LogMessage("[Migration 003] Skipping migration on PostgreSQL (schema already includes primary keys)");
            MarkMigrationComplete("003_add_primary_keys");
        }
    }
}

// Adds ELO tracking columns to record rating changes for each duel participant
void Migration_004_AddEloTracking()
{
    LogMessage("[Migration 004] Adding ELO tracking columns to duel tables");
    
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_previous_elo INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_new_elo INTEGER DEFAULT NULL", 2);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_previous_elo INTEGER DEFAULT NULL", 3);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_new_elo INTEGER DEFAULT NULL", 4);
            
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_previous_elo INTEGER DEFAULT NULL", 5);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_new_elo INTEGER DEFAULT NULL", 6);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_previous_elo INTEGER DEFAULT NULL", 7);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_new_elo INTEGER DEFAULT NULL", 8);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_previous_elo INTEGER DEFAULT NULL", 9);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_new_elo INTEGER DEFAULT NULL", 10);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_previous_elo INTEGER DEFAULT NULL", 11);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_new_elo INTEGER DEFAULT NULL", 12);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_previous_elo INT(4) DEFAULT NULL", 1);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_new_elo INT(4) DEFAULT NULL", 2);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_previous_elo INT(4) DEFAULT NULL", 3);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_new_elo INT(4) DEFAULT NULL", 4);
            
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_previous_elo INT(4) DEFAULT NULL", 5);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_new_elo INT(4) DEFAULT NULL", 6);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_previous_elo INT(4) DEFAULT NULL", 7);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_new_elo INT(4) DEFAULT NULL", 8);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_previous_elo INT(4) DEFAULT NULL", 9);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_new_elo INT(4) DEFAULT NULL", 10);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_previous_elo INT(4) DEFAULT NULL", 11);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_new_elo INT(4) DEFAULT NULL", 12);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema in CREATE TABLE - mark as complete
            LogMessage("[Migration 004] Skipping migration on PostgreSQL (schema already includes ELO columns)");
            MarkMigrationComplete("004_add_elo_tracking");
        }
    }
}

void Migration_005_Utf8mb4Charset()
{
    switch (g_DatabaseType)
    {
        case DB_MYSQL:
        {
            ExecuteMigrationStep("005_utf8mb4_charset", "ALTER TABLE mgemod_stats CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", 1);
        }
        default:
        {
            // SQLite and PostgreSQL handle Unicode natively - mark as complete
            LogMessage("[Migration 005] Skipping charset migration on non-MySQL backend");
            MarkMigrationComplete("005_utf8mb4_charset");
        }
    }
}

void Migration_006_DropHitblipColumn()
{
    LogMessage("[Migration 006] Removing unused hitblip column from mgemod_stats");

    switch (g_DatabaseType)
    {
        case DB_SQLITE, DB_MYSQL:
        {
            g_DB.Query(DropHitblipColumnCallback, "ALTER TABLE mgemod_stats DROP COLUMN hitblip");
        }
        case DB_POSTGRESQL:
        {
            // hitblip was never part of the PostgreSQL schema
            LogMessage("[Migration 006] Skipping on PostgreSQL (column never existed)");
            MarkMigrationComplete("006_drop_hitblip_column");
        }
    }
}

void DropHitblipColumnCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Migration 006] Database connection lost while dropping hitblip column");
        return;
    }

    if (!StrEqual("", error))
    {
        LogMessage("[Migration 006] Column already absent or unsupported by backend (continuing): %s", error);
    }
    else
    {
        LogMessage("[Migration 006] hitblip column dropped successfully");
    }

    MarkMigrationComplete("006_drop_hitblip_column");
}

// Adds the two nullable columns the Glicko-2 rating engine needs (rd, volatility).
// The existing "rating" column is reused as-is by both engines - no schema change needed there.
void Migration_007_AddGlickoColumns()
{
    LogMessage("[Migration 007] Adding Glicko-2 columns to mgemod_stats");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("007_add_glicko_columns", "ALTER TABLE mgemod_stats ADD COLUMN rd REAL DEFAULT NULL", 1);
            ExecuteMigrationStep("007_add_glicko_columns", "ALTER TABLE mgemod_stats ADD COLUMN volatility REAL DEFAULT NULL", 2);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("007_add_glicko_columns", "ALTER TABLE mgemod_stats ADD COLUMN rd FLOAT DEFAULT NULL", 1);
            ExecuteMigrationStep("007_add_glicko_columns", "ALTER TABLE mgemod_stats ADD COLUMN volatility FLOAT DEFAULT NULL", 2);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema in CREATE TABLE - mark as complete
            LogMessage("[Migration 007] Skipping migration on PostgreSQL (schema already includes Glicko-2 columns)");
            MarkMigrationComplete("007_add_glicko_columns");
        }
    }
}

// One-time backfill fixing existing rows so rd/volatility nullability matches whatever engine
// is active right now: if mgemod_rating_engine is "glicko2", every row gets rd/volatility
// defaults instead of leaving pre-existing players (created before this migration existed, or
// who simply never played a Glicko-2 duel yet) stuck with a NULL rd that's indistinguishable
// from "this is an Elo player". If the engine is "elo", any leftover rd/volatility values are
// cleared instead. This only runs once; see Rating_GetGlickoReconcileQuery for the query this
// reuses and handler_ConVarChange for the live version that keeps this true after engine switches.
void Migration_008_SeedGlickoRdDefaults()
{
    LogMessage("[Migration 008] Reconciling rd/volatility nullability with the active rating engine (%s)",
        (g_eRatingEngine == RATING_ENGINE_GLICKO2) ? "glicko2" : "elo");

    char query[256];
    Rating_GetGlickoReconcileQuery(query, sizeof(query));
    ExecuteMigrationStep("008_seed_glicko_rd_defaults", query, 1);
}

void Migration_009_GlickoPeriodSchema()
{
    LogMessage("[Migration 009] Adding Glicko-2 period columns, duel snapshots, and period_state");

    switch (g_DatabaseType)
    {
        case DB_MYSQL:
        {
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rating_est INT DEFAULT NULL", 1);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rd_est FLOAT DEFAULT NULL", 2);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN period_dirty TINYINT NOT NULL DEFAULT 0", 3);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_id INT NOT NULL DEFAULT 0", 4);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rating INT DEFAULT NULL", 5);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rd FLOAT DEFAULT NULL", 6);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_volatility FLOAT DEFAULT NULL", 7);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rating INT DEFAULT NULL", 8);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rd FLOAT DEFAULT NULL", 9);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_volatility FLOAT DEFAULT NULL", 10);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_sealed TINYINT NOT NULL DEFAULT 0", 11);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE UNIQUE INDEX idx_mgemod_duels_match ON mgemod_duels (winner, loser, starttime, endtime)", 12);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE TABLE IF NOT EXISTS mgemod_period_state (id INT NOT NULL PRIMARY KEY, last_sealed_period_id INT NOT NULL)", 13);
            ExecuteMigrationStep("009_glicko_period_schema", "INSERT IGNORE INTO mgemod_period_state (id, last_sealed_period_id) VALUES (1, 0)", 14);
            ExecuteMigrationStep("009_glicko_period_schema", "UPDATE mgemod_stats SET rating_est = rating, rd_est = rd, period_dirty = 0 WHERE rating_est IS NULL", 15);
        }
        case DB_SQLITE:
        {
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rating_est INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rd_est REAL DEFAULT NULL", 2);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN period_dirty INTEGER NOT NULL DEFAULT 0", 3);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_id INTEGER NOT NULL DEFAULT 0", 4);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rating INTEGER DEFAULT NULL", 5);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rd REAL DEFAULT NULL", 6);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_volatility REAL DEFAULT NULL", 7);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rating INTEGER DEFAULT NULL", 8);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rd REAL DEFAULT NULL", 9);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_volatility REAL DEFAULT NULL", 10);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_sealed INTEGER NOT NULL DEFAULT 0", 11);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE UNIQUE INDEX IF NOT EXISTS idx_mgemod_duels_match ON mgemod_duels (winner, loser, starttime, endtime)", 12);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE TABLE IF NOT EXISTS mgemod_period_state (id INTEGER PRIMARY KEY, last_sealed_period_id INTEGER NOT NULL)", 13);
            ExecuteMigrationStep("009_glicko_period_schema", "INSERT OR IGNORE INTO mgemod_period_state (id, last_sealed_period_id) VALUES (1, 0)", 14);
            ExecuteMigrationStep("009_glicko_period_schema", "UPDATE mgemod_stats SET rating_est = rating, rd_est = rd, period_dirty = 0 WHERE rating_est IS NULL", 15);
        }
        case DB_POSTGRESQL:
        {
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rating_est INTEGER", 1);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN rd_est REAL", 2);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_stats ADD COLUMN period_dirty INTEGER NOT NULL DEFAULT 0", 3);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_id INTEGER NOT NULL DEFAULT 0", 4);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rating INTEGER", 5);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_rd REAL", 6);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN winner_sealed_volatility REAL", 7);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rating INTEGER", 8);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_rd REAL", 9);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN loser_sealed_volatility REAL", 10);
            ExecuteMigrationStep("009_glicko_period_schema", "ALTER TABLE mgemod_duels ADD COLUMN period_sealed INTEGER NOT NULL DEFAULT 0", 11);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE UNIQUE INDEX IF NOT EXISTS idx_mgemod_duels_match ON mgemod_duels (winner, loser, starttime, endtime)", 12);
            ExecuteMigrationStep("009_glicko_period_schema", "CREATE TABLE IF NOT EXISTS mgemod_period_state (id INTEGER PRIMARY KEY, last_sealed_period_id INTEGER NOT NULL)", 13);
            ExecuteMigrationStep("009_glicko_period_schema", "INSERT INTO mgemod_period_state (id, last_sealed_period_id) VALUES (1, 0) ON CONFLICT (id) DO NOTHING", 14);
            ExecuteMigrationStep("009_glicko_period_schema", "UPDATE mgemod_stats SET rating_est = rating, rd_est = rd, period_dirty = 0 WHERE rating_est IS NULL", 15);
        }
    }
}
