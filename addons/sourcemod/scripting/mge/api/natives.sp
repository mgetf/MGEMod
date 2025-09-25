// ===== API NATIVE IMPLEMENTATIONS =====

// Register all native functions for other plugins to call
void RegisterNatives()
{
    CreateNative("MGE_GetPlayerArena", Native_GetPlayerArena);
    CreateNative("MGE_GetPlayerStats", Native_GetPlayerStats);
    CreateNative("MGE_IsPlayerInArena", Native_IsPlayerInArena);
    CreateNative("MGE_GetArenaCount", Native_GetArenaCount);
    CreateNative("MGE_GetArenaPlayerCount", Native_GetArenaPlayerCount);
    CreateNative("MGE_GetArenaStatus", Native_GetArenaStatus);
    CreateNative("MGE_GetArenaGameMode", Native_GetArenaGameMode);
    CreateNative("MGE_GetArenaPlayer", Native_GetArenaPlayer);
    CreateNative("MGE_IsValidArena", Native_IsValidArena);
    CreateNative("MGE_AddPlayerToArena", Native_AddPlayerToArena);
    CreateNative("MGE_RemovePlayerFromArena", Native_RemovePlayerFromArena);
    CreateNative("MGE_IsArena2v2", Native_IsArena2v2);
    CreateNative("MGE_IsPlayerReady", Native_IsPlayerReady);
    CreateNative("MGE_SetPlayerReady", Native_SetPlayerReady);
    CreateNative("MGE_GetPlayerTeammate", Native_GetPlayerTeammate);
    CreateNative("MGE_ArenaHasGameMode", Native_ArenaHasGameMode);
    CreateNative("MGE_IsValidSlotForArena", Native_IsValidSlotForArena);
    CreateNative("MGE_GetArenaMaxSlots", Native_GetArenaMaxSlots);
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

// Gets the number of players currently in an arena
int Native_GetArenaPlayerCount(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;
    
    int count = 0;
    int maxSlots = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    
    for (int i = SLOT_ONE; i <= maxSlots; i++)
    {
        if (g_iArenaQueue[arena_index][i] > 0)
            count++;
    }
    
    return count;
}

// Gets an arena's current status
int Native_GetArenaStatus(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return AS_IDLE;
        
    return g_iArenaStatus[arena_index];
}

// Gets an arena's game mode
int Native_GetArenaGameMode(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;
    
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
        
    return flags;
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

// Checks if an arena is a 2v2 arena
int Native_IsArena2v2(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return false;
        
    return g_bFourPersonArena[arena_index];
}

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

// Gets the maximum number of slots for an arena
int Native_GetArenaMaxSlots(Handle plugin, int numParams)
{
    int arena_index = GetNativeCell(1);
    
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return 0;
    
    return g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
}

