// ===== API NATIVE IMPLEMENTATIONS =====

// Register all native functions for other plugins to call
void RegisterNatives()
{
    CreateNative("MGE_GetPlayerArena", Native_GetPlayerArena);
    CreateNative("MGE_GetPlayerStats", Native_GetPlayerStats);
    CreateNative("MGE_GetArenaInfo", Native_GetArenaInfo);
    CreateNative("MGE_IsPlayerInArena", Native_IsPlayerInArena);
    CreateNative("MGE_GetArenaCount", Native_GetArenaCount);
    CreateNative("MGE_GetArenaPlayer", Native_GetArenaPlayer);
    CreateNative("MGE_IsValidArena", Native_IsValidArena);
    CreateNative("MGE_GetArenaStatus", Native_GetArenaStatus);
    CreateNative("MGE_AddPlayerToArena", Native_AddPlayerToArena);
    CreateNative("MGE_RemovePlayerFromArena", Native_RemovePlayerFromArena);
    CreateNative("MGE_IsPlayerReady", Native_IsPlayerReady);
    CreateNative("MGE_SetPlayerReady", Native_SetPlayerReady);
    CreateNative("MGE_GetPlayerTeammate", Native_GetPlayerTeammate);
    CreateNative("MGE_ArenaHasGameMode", Native_ArenaHasGameMode);
    CreateNative("MGE_IsValidSlotForArena", Native_IsValidSlotForArena);
    CreateNative("MGE_GetArenaScore", Native_GetArenaScore);
    CreateNative("MGE_GetPlayerSlot", Native_GetPlayerSlot);
    CreateNative("MGE_GetPlayerClassRating", Native_GetPlayerClassRating);
    CreateNative("MGE_GetPlayerCurrentClassRating", Native_GetPlayerCurrentClassRating);
    CreateNative("MGE_GetPlayerMatchupRating", Native_GetPlayerMatchupRating);
}

// ===== PLAYER INFORMATION NATIVES =====

// Gets a player's current arena
int Native_GetPlayerArena(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return 0;
        
    return g_iPlayerArena[client];
}

// Gets a player's complete statistics
int Native_GetPlayerStats(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return false;
    
    MGEPlayerStats stats;
    stats.elo = g_iPlayerRating[client];
    stats.kills = 0; // TODO: Implement kill tracking
    stats.deaths = 0; // TODO: Implement death tracking
    stats.wins = g_iPlayerWins[client];
    stats.losses = g_iPlayerLosses[client];
    stats.rating = (stats.losses > 0) ? float(stats.wins) / float(stats.losses) : float(stats.wins);
    
    SetNativeArray(2, stats, sizeof(stats));
    return true;
}

// Checks if a player is currently in an MGE arena
int Native_IsPlayerInArena(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return false;
        
    return (g_iPlayerArena[client] > 0);
}

// ===== ARENA INFORMATION NATIVES =====

// Gets the total number of arenas on the current map
int Native_GetArenaCount(Handle plugin, int numParams)
{
    return g_iArenaCount;
}


// Gets a player in a specific arena slot
int Native_GetArenaPlayer(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;
    if (slot < SLOT_ONE || slot > SLOT_FOUR)
        return 0;
        
    return g_iArenaQueue[arena_index][slot];
}

// Checks if an arena index is valid
int Native_IsValidArena(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    return (arena_index >= 1 && arena_index <= g_iArenaCount);
}

// Gets the status of an arena
int Native_GetArenaStatus(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);

    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;

    return g_iArenaStatus[arena_index];
}

// ===== ARENA MANAGEMENT NATIVES =====

// Adds a player to an arena with optional slot specification
int Native_AddPlayerToArena(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int arena_index = GetNativeCell(2);
    int slot = (numParams >= 3) ? GetNativeCell(3) : 0; // Default to automatic assignment
    
    if (!IsValidClient(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid client index %d", client);
        return false;
    }
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
    {
        ThrowNativeError(SP_ERROR_PARAM, "Invalid arena index %d", arena_index);
        return false;
    }
    
    // For manual slot assignment, do validation here and throw native errors
    if (slot > 0)
    {
        // Validate slot for arena type
        if (!IsValidSlotForArena(arena_index, slot))
        {
            if (g_bFourPersonArena[arena_index])
            {
                ThrowNativeError(SP_ERROR_PARAM, "Invalid slot %d for 2v2 arena (valid slots: 1-4)", slot);
            }
            else
            {
                ThrowNativeError(SP_ERROR_PARAM, "Invalid slot %d for 1v1 arena (valid slots: 1-2)", slot);
            }
            return false;
        }
        
        // Check if slot is already occupied
        if (g_iArenaQueue[arena_index][slot] != 0)
        {
            ThrowNativeError(SP_ERROR_PARAM, "Slot %d in arena %d is already occupied", slot, arena_index);
            return false;
        }
    }
    
    // Call the enhanced AddInQueue function with all parameters
    // showmsg=false for API calls, no team preference, no 2v2 menu, with forced slot
    AddInQueue(client, arena_index, false, 0, false, slot);
    return true;
}

// Removes a player from their current arena
int Native_RemovePlayerFromArena(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return false;
    if (g_iPlayerArena[client] == 0)
        return false;
    
    // Call the existing RemoveFromQueue function
    RemoveFromQueue(client, true);
    return true;
}

// ===== 2V2 NATIVES =====


// Gets a player's ready status in 2v2
int Native_IsPlayerReady(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return false;
        
    return g_bPlayer2v2Ready[client];
}

// Sets a player's ready status in 2v2
int Native_SetPlayerReady(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    bool ready = GetNativeCell(2);
    
    if (!IsValidClient(client))
        return false;
    if (g_iPlayerArena[client] == 0)
        return false;
    if (!g_bFourPersonArena[g_iPlayerArena[client]])
        return false;
    
    g_bPlayer2v2Ready[client] = ready;
    
    // Call the forward
    CallForward_On2v2PlayerReady(client, g_iPlayerArena[client], ready);
    
    return true;
}

// Gets a player's teammate in 2v2 arena
int Native_GetPlayerTeammate(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return 0;
    
    int arena_index = g_iPlayerArena[client];
    if (arena_index == 0 || !g_bFourPersonArena[arena_index])
        return 0;
    
    return GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
}

// ===== GAME MODE & VALIDATION NATIVES =====

// Checks if an arena supports a specific game mode
int Native_ArenaHasGameMode(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    int game_mode = GetNativeCell(2);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return false;
    
    switch (game_mode)
    {
        case MGE_GAMEMODE_MGE: return g_bArenaMGE[arena_index];
        case MGE_GAMEMODE_BBALL: return g_bArenaBBall[arena_index];
        case MGE_GAMEMODE_KOTH: return g_bArenaKoth[arena_index];
        case MGE_GAMEMODE_AMMOMOD: return g_bArenaAmmomod[arena_index];
        case MGE_GAMEMODE_MIDAIR: return g_bArenaMidair[arena_index];
        case MGE_GAMEMODE_ENDIF: return g_bArenaEndif[arena_index];
        case MGE_GAMEMODE_ULTIDUO: return g_bArenaUltiduo[arena_index];
        case MGE_GAMEMODE_TURRIS: return g_bArenaTurris[arena_index];
        case MGE_GAMEMODE_4PLAYER: return g_bFourPersonArena[arena_index];
    }
    
    return false;
}

// Checks if a slot is valid for the given arena type
int Native_IsValidSlotForArena(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return false;
    
    return IsValidSlotForArena(arena_index, slot);
}


// Gets complete arena information
int Native_GetArenaInfo(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return false;
    
    // Create a temporary struct to populate
    int info[7]; // MGEArenaInfo has 7 fields
    
    // Populate the struct fields
    // name is at offset 0, but it's a string array so we handle it separately
    
    // Calculate player count
    int playerCount = 0;
    int maxSlots = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int i = SLOT_ONE; i <= maxSlots; i++)
    {
        if (g_iArenaQueue[arena_index][i] > 0)
            playerCount++;
    }
    
    // Calculate game mode flags
    int flags = 0;
    if (g_bArenaMGE[arena_index])
        flags |= MGE_GAMEMODE_MGE;
    if (g_bArenaBBall[arena_index])
        flags |= MGE_GAMEMODE_BBALL;
    if (g_bArenaKoth[arena_index])
        flags |= MGE_GAMEMODE_KOTH;
    if (g_bArenaAmmomod[arena_index])
        flags |= MGE_GAMEMODE_AMMOMOD;
    if (g_bArenaMidair[arena_index])
        flags |= MGE_GAMEMODE_MIDAIR;
    if (g_bArenaEndif[arena_index])
        flags |= MGE_GAMEMODE_ENDIF;
    if (g_bArenaUltiduo[arena_index])
        flags |= MGE_GAMEMODE_ULTIDUO;
    if (g_bArenaTurris[arena_index])
        flags |= MGE_GAMEMODE_TURRIS;
    if (g_bFourPersonArena[arena_index])
        flags |= MGE_GAMEMODE_4PLAYER;
    
    info[1] = playerCount;  // players
    info[2] = maxSlots;  // maxSlots  
    info[3] = g_iArenaStatus[arena_index];  // status
    info[4] = flags;  // gameMode
    info[5] = g_bFourPersonArena[arena_index] ? 1 : 0;  // is2v2 (as int)
    info[6] = g_iArenaFraglimit[arena_index];  // fragLimit
    
    // Set the struct in the native parameter
    SetNativeArray(2, info, sizeof(info));
    
    // Set the arena name separately (string field at offset 0)
    SetNativeString(2, g_sArenaName[arena_index], 64);
    
    return true;
}

// Gets the score for a specific slot in an arena
int Native_GetArenaScore(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;
    if (slot < SLOT_ONE || slot > SLOT_FOUR)
        return 0;
        
    return g_iArenaScore[arena_index][slot];
}

// Gets a player's slot in their current arena
int Native_GetPlayerSlot(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client))
        return 0;
        
    return g_iPlayerSlot[client];
}

// Gets a player's class rating for a specific class
int Native_GetPlayerClassRating(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int classType = GetNativeCell(2);

    if (!IsValidClient(client))
        return 0;
    if (classType < 1 || classType > 9)
        return 0;

    // Return average matchup rating for this class (average across all opponent classes)
    int totalRating = 0;
    int count = 0;
    for (int oppClass = 1; oppClass <= 9; oppClass++)
    {
        if (g_iPlayerClassRating[client][classType][oppClass] > 0)
        {
            totalRating += g_iPlayerClassRating[client][classType][oppClass];
            count++;
        }
    }
    return (count > 0) ? (totalRating / count) : 0;
}

// Gets a player's class rating for their current class
int Native_GetPlayerCurrentClassRating(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    if (!IsValidClient(client))
        return 0;

    int classId = view_as<int>(g_tfctPlayerClass[client]);
    if (classId < 1 || classId > 9)
        classId = view_as<int>(TF2_GetPlayerClass(client));
    if (classId < 1 || classId > 9)
        return 0;

    // Return average matchup rating for current class (average across all opponent classes)
    int totalRating = 0;
    int count = 0;
    for (int oppClass = 1; oppClass <= 9; oppClass++)
    {
        if (g_iPlayerClassRating[client][classId][oppClass] > 0)
        {
            totalRating += g_iPlayerClassRating[client][classId][oppClass];
            count++;
        }
    }
    return (count > 0) ? (totalRating / count) : 0;
}

// Gets a player's matchup rating for a specific class vs opponent class
int Native_GetPlayerMatchupRating(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int myClass = GetNativeCell(2);
    int opponentClass = GetNativeCell(3);

    if (!IsValidClient(client))
        return 0;
    if (myClass < 1 || myClass > 9)
        return 0;
    if (opponentClass < 1 || opponentClass > 9)
        return 0;

    int rating = g_iPlayerClassRating[client][myClass][opponentClass];
    // Return 1500 (default) if rating is 0 (not initialized)
    return (rating > 0) ? rating : 1500;
}
