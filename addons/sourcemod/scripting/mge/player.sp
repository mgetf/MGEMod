// ===== PLAYER STATE MANAGEMENT =====

// Initialize basic client data when they connect (regardless of Steam status)
void HandleClientConnection(int client)
{
    if (IsFakeClient(client))
        return;
        
    // Initialize basic client state immediately (Steam-independent)
    ChangeClientTeam(client, TEAM_SPEC);
    g_bShowHud[client] = true;
    g_bPlayerRestoringAmmo[client] = false;
    g_bPlayerEloVerified[client] = false;
    
    // Clear any inherited statistics data immediately (but preserve if already properly loaded)
    // This prevents stats from being inherited from previous client in the same slot
    if (g_iPlayerRating[client] == 0 || strlen(g_sPlayerSteamID[client]) == 0)
    {
        g_iPlayerRating[client] = 0;
        g_iPlayerWins[client] = 0;
        g_iPlayerLosses[client] = 0;
        g_bPlayerEloVerified[client] = false;
    }
    
    // Initialize class tracking ArrayList
    if (g_alPlayerDuelClasses[client] != null)
        delete g_alPlayerDuelClasses[client];
    g_alPlayerDuelClasses[client] = new ArrayList();
    
    // Try to load player stats (will retry in HandleClientAuthentication if Steam ID not ready)
    TryLoadPlayerStats(client, false);
    
    CreateTimer(5.0, Timer_ShowAdv, GetClientUserId(client));
    CreateTimer(15.0, Timer_WelcomePlayer, GetClientUserId(client));
    
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// Handle Steam-authenticated connections and retry ELO loading if needed
void HandleClientAuthentication(int client)
{
    if (IsFakeClient(client))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (g_bPlayerAskedForBot[i])
            {
                int arena_index = g_iPlayerArena[i];
                DataPack pack = new DataPack();
                CreateDataTimer(1.5, Timer_AddBotInQueue, pack);
                pack.WriteCell(GetClientUserId(client));
                pack.WriteCell(arena_index);
                g_iPlayerRating[client] = 1551;
                g_bPlayerAskedForBot[i] = false;
                break;
            }
        }
    }
    else
    {
        // Steam authentication successful - retry stats loading if it failed before
        TryLoadPlayerStats(client, true);
    }
}

// Handle client disconnection and cleanup
void HandleClientDisconnection(int client)
{
    // We ignore the kick queue check for this function only so that clients that get kicked still get their elo calculated
    if (IsValidClient(client, true) && g_iPlayerArena[client])
    {
        RemoveFromQueue(client, true);
    }
    else
    {
        int
            arena_index = g_iPlayerArena[client],
            player_slot = g_iPlayerSlot[client],
            foe_slot = (player_slot == SLOT_ONE || player_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE,
            foe = g_iArenaQueue[arena_index][foe_slot];

        // Turn all this logic into a helper method
        int player_teammate, foe2;

        if (g_bFourPersonArena[arena_index])
        {
            player_teammate = GetPlayerTeammate(player_slot, arena_index);
            foe2 = GetPlayerTeammate(foe_slot, arena_index);
        }

        g_iPlayerArena[client] = 0;
        g_iPlayerSlot[client] = 0;
        g_iArenaQueue[arena_index][player_slot] = 0;
        g_iPlayerHandicap[client] = 0;
        
        // Cleanup class tracking ArrayList
        if (g_alPlayerDuelClasses[client] != null)
        {
            delete g_alPlayerDuelClasses[client];
            g_alPlayerDuelClasses[client] = null;
        }
        
        // Clear 2v2 ready status
        g_bPlayer2v2Ready[client] = false;
        
        // Clear player statistics to prevent inheritance by new clients with same ID
        g_iPlayerRating[client] = 0;
        g_iPlayerWins[client] = 0;
        g_iPlayerLosses[client] = 0;
        
        // Clear hud text if arena was in ready state
        if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
        {
            Clear2v2ReadyHud(arena_index);
        }

        // Bot cleanup logic (queue advancement is handled by RemoveFromQueue)
        if (IsValidClient(foe) && IsFakeClient(foe))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        if (IsValidClient(foe2) && IsFakeClient(foe2))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        if (IsValidClient(player_teammate) && IsFakeClient(player_teammate))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        // Ensure any 2v2 waiting/spec players are restored on disconnect
        if (g_bFourPersonArena[arena_index])
        {
            Restore2v2WaitingSpectators(arena_index);
            CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
        }

        g_iArenaStatus[arena_index] = AS_IDLE;
        return;
    }
}

// Attempts to load player statistics from database with Steam ID validation
void TryLoadPlayerStats(int client, bool isRetry)
{
    if (g_bNoStats || !IsValidClient(client))
        return;
    
    char steamid_dirty[31], steamid[64], query[256];
    
    // Get Steam ID and validate the operation succeeded
    if (!GetClientAuthId(client, AuthId_Steam2, steamid_dirty, sizeof(steamid_dirty))) {
        if (isRetry) {
            LogError("Failed to get Steam ID for client %d even after Steam auth - stats loading failed", client);
            g_bPlayerEloVerified[client] = false;
        }
        return;
    }
    
    g_DB.Escape(steamid_dirty, steamid, sizeof(steamid));
    
    // Skip if stats already loaded successfully for this specific Steam ID
    if (g_bPlayerEloVerified[client] && StrEqual(g_sPlayerSteamID[client], steamid)) {
        if (isRetry) {
            LogMessage("Stats already loaded for client %d (%s), skipping retry", client, steamid);
        }
        return;
    }
    
    strcopy(g_sPlayerSteamID[client], 32, steamid);
    
    GetSelectPlayerStatsQuery(query, sizeof(query), steamid);
    g_DB.Query(SQL_OnPlayerReceived, query, client);
}

// Validates if player's ELO is verified and safe for arena play
bool IsPlayerEloValid(int client, char[] reason, int reason_size)
{
    if (IsFakeClient(client))
        return true; // Bots are always valid
        
    if (g_bNoStats)
        return true; // Stats disabled, allow anyone
    
    if (!g_bPlayerEloVerified[client]) {
        if (g_bAllowUnverifiedPlayers) {
            return true; // Allow unverified players when convar enabled
        }
        Format(reason, reason_size, "%T", "EloNotVerified", client);
        return false;
    }
    
    if (strlen(g_sPlayerSteamID[client]) == 0) {
        Format(reason, reason_size, "%T", "InvalidSteamID", client);
        return false;
    }
    
    return true;
}

// Checks if player should be included in ELO calculations
bool IsPlayerEligibleForElo(int client)
{
    if (IsFakeClient(client))
        return false; // Bots never affect ELO
        
    if (g_bNoStats)
        return false; // Stats disabled globally
        
    return g_bPlayerEloVerified[client]; // Only verified players eligible for ELO
}

// Resets player state including health, class, team assignment, and teleports to spawn
int ResetPlayer(int client)
{
    int arena_index = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];

    if (!arena_index || !player_slot)
    {
        return 0;
    }

    // Remove projectiles when resetting a player
    if (g_bClearProjectiles && g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaBBall[arena_index])
        RemoveArenaProjectiles(arena_index);

    g_iPlayerSpecTarget[client] = 0;

    if (player_slot == SLOT_ONE || player_slot == SLOT_THREE)
        ChangeClientTeam(client, TEAM_RED);
    else
        ChangeClientTeam(client, TEAM_BLU);


    TFClassType class;
    class = g_tfctPlayerClass[client] ? g_tfctPlayerClass[client] : TFClass_Soldier;

    if (!IsPlayerAlive(client) || g_bArenaBBall[arena_index])
    {
        if (class != TF2_GetPlayerClass(client))
            TF2_SetPlayerClass(client, class);

        TF2_RespawnPlayer(client);
        
        // Reset velocity immediately to prevent momentum carryover from death
        float vel[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
    } else {
        TF2_RegeneratePlayer(client);
        ExtinguishEntity(client);
    }

    g_iPlayerMaxHP[client] = GetEntProp(client, Prop_Data, "m_iMaxHealth");

    if (g_bArenaMidair[arena_index])
        g_iPlayerHP[client] = g_iMidairHP;
    else
        g_iPlayerHP[client] = g_iPlayerHandicap[client] ? g_iPlayerHandicap[client] : RoundToNearest(float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]);

    if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
        SetEntProp(client, Prop_Data, "m_iHealth", g_iPlayerHandicap[client] ? g_iPlayerHandicap[client] : RoundToNearest(float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]));

    UpdateHud(client);
    ResetClientAmmoCounts(client);
    CreateTimer(0.1, Timer_Tele, GetClientUserId(client));

    return 1;
}

// Restores killer's health and regenerates them after scoring a frag
void ResetKiller(int killer, int arena_index)
{
    int reset_hp = g_iPlayerHandicap[killer] ? g_iPlayerHandicap[killer] : RoundToNearest(float(g_iPlayerMaxHP[killer]) * g_fArenaHPRatio[arena_index]);
    g_iPlayerHP[killer] = reset_hp;
    SetEntProp(killer, Prop_Data, "m_iHealth", reset_hp);
    RequestFrame(RegenKiller, killer);
}

// Ensures player is using a class allowed in their current arena
void SetPlayerToAllowedClass(int client, int arena_index)
{
    // If a player's class isn't allowed, set it to one that is.
    if (g_tfctPlayerClass[client] == TFClass_Unknown || !g_tfctArenaAllowedClasses[arena_index][g_tfctPlayerClass[client]])
    {
        for (int i = 1; i <= 9; i++)
        {
            if (g_tfctArenaAllowedClasses[arena_index][i])
            {
                if (g_bArenaUltiduo[arena_index] && g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] > SLOT_TWO)
                {
                    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
                    if (view_as<TFClassType>(i) == g_tfctPlayerClass[client_teammate])
                    {
                        // Tell the player what he did wrong
                        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
                        // Change him classes and set his class to the only one available
                        if (g_tfctPlayerClass[client_teammate] == TFClass_Soldier)
                        {
                            g_tfctPlayerClass[client] = TFClass_Medic;
                        }
                        else
                        {
                            g_tfctPlayerClass[client] = TFClass_Soldier;
                        }
                    }
                }
                else
                    g_tfctPlayerClass[client] = view_as<TFClassType>(i);

                break;
            }
        }
    }
}

// Regenerates killer's health and ammo after successful elimination
void RegenKiller(any killer)
{
    TF2_RegeneratePlayer(killer);
}


// ===== ENTITY AND EFFECTS MANAGEMENT =====

// Destroys all engineer buildings belonging to a specific client
void RemoveEngineerBuildings(int client)
{
    if (!IsValidClient(client))
    {
        return;
    }

    int building = -1;
    while ((building = FindEntityByClassname(building, "obj_*")) != -1)
    {
      if (GetEntPropEnt(building, Prop_Send, "m_hBuilder") == client)
      {
          SetVariantInt(9999);
          AcceptEntityInput(building, "RemoveHealth");
      }
    }
}

// Creates and attaches particle effects to entities for visual feedback
void AttachParticle(int ent, char[] particleType, int &particle) 
{
    // Particle code borrowed from "The Amplifier" and "Presents!".
    particle = CreateEntityByName("info_particle_system");

    float pos[3];

    // Get position of entity
    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

    // Teleport, set up
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    DispatchKeyValue(particle, "effect_name", particleType);

    SetVariantString("!activator");
    AcceptEntityInput(particle, "SetParent", ent, particle, 0);

    // All entities in presents are given a targetname to make clean up easier
    DispatchKeyValue(particle, "targetname", "tf2particle");

    // Spawn and start
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");
}

// Removes particle effects attached to a specific client
void RemoveClientParticle(int client)
{
    int particle = EntRefToEntIndex(g_iClientParticle[client]);

    if (particle != 0 && IsValidEntity(particle))
        RemoveEdict(particle);

    g_iClientParticle[client] = 0;
}


// ===== UTILITY FUNCTIONS =====

// Converts player slot (1-4) to team slot (1-2) for scoring and team identification
int GetTeamSlotFromPlayerSlot(int player_slot)
{
    return (player_slot > 2) ? (player_slot - 2) : player_slot;
}

// Handles engineer building removal when player changes from engineer to another class
void HandleEngineerClassChange(int client, TFClassType old_class, TFClassType new_class)
{
    if (old_class == TFClass_Engineer && new_class != TFClass_Engineer)
    {
        RemoveEngineerBuildings(client);
    }
}

// Checks if class change would create conflict in Ultiduo 2v2 (same class on team)
bool IsUltiduo2v2ClassConflict(int client, TFClassType new_class, int arena_index)
{
    if (!g_bArenaUltiduo[arena_index] || !g_bFourPersonArena[arena_index])
        return false;
        
    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
    if (!IsValidClient(client_teammate))
        return false;
        
    return (new_class == g_tfctPlayerClass[client_teammate]);
}

// Formats player names for 2v2 team display (e.g., "Player1 and Player2")
void FormatTeamPlayerNames(int player1, int player2, char[] buffer, int maxlen)
{
    if (!IsValidClient(player1))
    {
        buffer[0] = '\0';
        return;
    }
    
    char player1_name[MAX_NAME_LENGTH];
    GetClientName(player1, player1_name, sizeof(player1_name));
    
    if (!IsValidClient(player2))
    {
        strcopy(buffer, maxlen, player1_name);
        return;
    }
    
    char player2_name[MAX_NAME_LENGTH];
    GetClientName(player2, player2_name, sizeof(player2_name));
    
    Format(buffer, maxlen, "%s and %s", player1_name, player2_name);
}

// Validates if a client index represents a valid, connected, non-bot player
bool IsValidClient(int iClient, bool bIgnoreKickQueue = false)
{
    if
    (
        // "client" is 0 (console) or lower - nope!
            0 >= iClient
        // "client" is higher than MaxClients - nope!
        || MaxClients < iClient
        // "client" isnt in game aka their entity hasn't been created - nope!
        || !IsClientInGame(iClient)
        // "client" is in the kick queue - nope!
        || (IsClientInKickQueue(iClient) && !bIgnoreKickQueue)
        // "client" is sourcetv - nope!
        || IsClientSourceTV(iClient)
        // "client" is the replay bot - nope!
        || IsClientReplay(iClient)
    )
    {
        return false;
    }
    return true;
}

// Determines if player is using rocket launcher or grenade launcher for physics calculations
bool ShootsRocketsOrPipes(int client)
{
    char weapon[64];
    GetClientWeapon(client, weapon, sizeof(weapon));
    return (StrContains(weapon, "tf_weapon_rocketlauncher") == 0) || StrEqual(weapon, "tf_weapon_grenadelauncher");
}

// Forces closure of any open menu for a specific client
void CloseClientMenu(int client)
{
    if (!IsValidClient(client))
        return;

    if (GetClientMenu(client, null) != MenuSource_None)
    {
        InternalShowMenu(client, "\10", 1);
        CancelClientMenu(client, true, null);
    }
}

// Handles class change requests for players not currently in any arena
Action HandleLobbyClassChange(int client, TFClassType new_class, int arena_index)
{
    if (!g_tfctClassAllowed[view_as<int>(new_class)])
    {
        MC_PrintToChat(client, "%t", "ClassIsNotAllowed");
        return Plugin_Handled;
    }
    
    if (IsUltiduo2v2ClassConflict(client, new_class, arena_index))
    {
        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
        return Plugin_Handled;
    }
    
    HandleEngineerClassChange(client, g_tfctPlayerClass[client], new_class);
    TF2_SetPlayerClass(client, new_class);
    g_tfctPlayerClass[client] = new_class;
    
    ChangeClientTeam(client, TEAM_SPEC);
    UpdateHudForArena(g_iPlayerArena[client]);
    return Plugin_Handled;
}

// Validates if a player can change classes in their current arena
bool CanPlayerChangeClassInArena(int client, TFClassType new_class, int arena_index)
{
    if (!g_tfctArenaAllowedClasses[arena_index][new_class])
    {
        MC_PrintToChat(client, "%t", "ClassIsNotAllowed");
        return false;
    }
    
    if (IsUltiduo2v2ClassConflict(client, new_class, arena_index))
    {
        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
        return false;
    }
    
    return true;
}

// Checks class change timing restrictions for 2v2 arenas
bool CanPlayerChangeClassInTeamArena(int client, int arena_index)
{
    if (!g_bArenaClassChange[arena_index])
    {
        // Class changes only allowed during waiting phase
        if (g_iArenaStatus[arena_index] != AS_WAITING_READY && g_iArenaStatus[arena_index] != AS_IDLE)
        {
            MC_PrintToChat(client, "%t", "ClassChangesOnlyWhileWaiting");
            return false;
        }
    }
    else if (g_iArenaStatus[arena_index] == AS_FIGHT)
    {
        // Class changes allowed during countdown, but slay during fight
        MC_PrintToChat(client, "%t", "ClassChangeDuringFightSlay");
        ForcePlayerSuicide(client);
        return true; // Allow but with penalty
    }
    
    return true;
}

// Checks class change restrictions for 1v1 arenas
bool CanPlayerChangeClassIn1v1Arena(int client, int arena_index)
{
    // Allow class changes if score is still 0-0, even during fight
    if (!g_bArenaClassChange[arena_index] && g_iArenaStatus[arena_index] == AS_FIGHT && 
        (g_iArenaScore[arena_index][SLOT_ONE] != 0 || g_iArenaScore[arena_index][SLOT_TWO] != 0))
    {
        MC_PrintToChat(client, "%t", "ClassChangesDisabledDuringFight");
        return false;
    }
    
    return true;
}

// Determines if player is in an active arena slot (participating in duels)
bool IsPlayerInActiveSlot(int client, int arena_index)
{
    int slot = g_iPlayerSlot[client];
    
    if (!g_bFourPersonArena[arena_index])
        return (slot == SLOT_ONE || slot == SLOT_TWO);
    else
        return (slot >= SLOT_ONE && slot <= SLOT_FOUR);
}

// Executes the class change and handles related game mechanics
Action ExecuteArenaClassChange(int client, TFClassType new_class, int arena_index)
{
    // Check if class changes are allowed in current arena state
    if (g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaMGE[arena_index] && !g_bArenaEndif[arena_index] && !g_bArenaKoth[arena_index])
    {
        MC_PrintToChat(client, "%t", "NoClassChange");
        return Plugin_Handled;
    }
    
    HandleEngineerClassChange(client, g_tfctPlayerClass[client], new_class);
    TF2_SetPlayerClass(client, new_class);
    g_tfctPlayerClass[client] = new_class;
    
    // Add class to tracking list if class changes are allowed and duel is active
    if (g_bArenaClassChange[arena_index] && g_iArenaStatus[arena_index] != AS_IDLE && 
        g_alPlayerDuelClasses[client].FindValue(view_as<int>(new_class)) == -1)
    {
        g_alPlayerDuelClasses[client].Push(view_as<int>(new_class));
    }
    
    // Handle class change during active combat
    if (IsPlayerAlive(client))
    {
        HandleActivePlayerClassChange(client, arena_index);
    }
    
    // Reset handicap to prevent exploits
    g_iPlayerHandicap[client] = 0;
    UpdateHudForArena(g_iPlayerArena[client]);
    return Plugin_Continue;
}

// Handles class changes for players currently alive and fighting
void HandleActivePlayerClassChange(int client, int arena_index)
{
    if (!(g_iArenaStatus[arena_index] == AS_FIGHT && (g_bArenaMGE[arena_index] || g_bArenaEndif[arena_index])))
    {
        CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
        return;
    }
    
    // Handle scoring and match completion for MGE/Endif arenas
    int killer_slot = (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int fraglimit = g_iArenaFraglimit[arena_index];
    int killer = g_iArenaQueue[arena_index][killer_slot];
    int killer_teammate;
    int killer_team_slot = GetTeamSlotFromPlayerSlot(killer_slot);
    int client_team_slot = GetTeamSlotFromPlayerSlot(g_iPlayerSlot[client]);
    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
    
    if (g_bFourPersonArena[arena_index])
    {
        killer_teammate = GetPlayerTeammate(killer_slot, arena_index);
    }
    
    if (g_iArenaStatus[arena_index] == AS_FIGHT && killer)
    {
        // Award points and provide feedback
        if (g_bArenaClassChange[arena_index])
        {
            g_iArenaScore[arena_index][killer_team_slot] += 1;
            MC_PrintToChat(killer, "%t", "ClassChangePointOpponent");
            MC_PrintToChat(client, "%t", "ClassChangePoint");
        }
        
        if (g_bFourPersonArena[arena_index] && killer_teammate)
        {
            CreateTimer(3.0, Timer_NewRound, arena_index);
        }
    }
    
    // Update HUDs for all players
    UpdateHud(client);
    if (IsValidClient(killer))
    {
        ResetKiller(killer, arena_index);
        UpdateHud(killer);
    }
    
    if (g_bFourPersonArena[arena_index])
    {
        if (IsValidClient(killer_teammate))
        {
            ResetKiller(killer_teammate, arena_index);
            UpdateHud(killer_teammate);
        }
        if (IsValidClient(client_teammate))
        {
            ResetKiller(client_teammate, arena_index);
            UpdateHud(client_teammate);
        }
    }
    
    // Check for match completion
    if (ValidateMatchCompletion(arena_index, killer_team_slot, fraglimit))
    {
        ProcessClassChangeMatchCompletion(arena_index, client, killer, killer_teammate, client_teammate, killer_team_slot, client_team_slot, fraglimit);
    }
    
    CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
}


// ===== COMMAND HANDLERS =====

// Handles team join requests with special logic for spectating and 2v2 team switching
Action Command_JoinTeam(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    // Get the team argument
    char team[16];  
    GetCmdArg(1, team, sizeof(team));

    // Allow spectate command to pass through
    if (!strcmp(team, "spectate"))
    {
        // Handle spectating in arenas - treat as !remove for any arena type
        int arena_index = g_iPlayerArena[client];
        if (arena_index > 0)
        {
            // For any arena (1v1 or 2v2), going to spec means they want to leave
            MC_PrintToChat(client, "%t", "SpecRemove");
            RemoveFromQueue(client, true);
        }

        // Handle spectator HUD and target logic (moved from Event_PlayerTeam)
        HideHud(client);
        CreateTimer(0.3, Timer_ChangeSpecTarget, GetClientUserId(client));

        return Plugin_Handled;
    }
    else
    {
        // Check if player is in a 2v2 arena and trying to switch teams
        int arena_index = g_iPlayerArena[client];
        TFTeam currentTeam = TF2_GetClientTeam(client);

        if (arena_index > 0 && g_bFourPersonArena[arena_index] &&
            currentTeam != TFTeam_Spectator && currentTeam != TFTeam_Unassigned)
        {
            // Player is in a 2v2 arena - allow team switching
            int target_team = 0;
            if (!strcmp(team, "red"))
                target_team = TEAM_RED;
            else if (!strcmp(team, "blue") || !strcmp(team, "blu"))
                target_team = TEAM_BLU;

            if (target_team != 0)
            {
                // Use existing 2v2 team switch logic
                Handle2v2TeamSwitch(client, arena_index, target_team);
                return Plugin_Stop;
            }
        }

        // Block manual team joining for red/blue teams (default behavior)
        if (currentTeam == TFTeam_Spectator)
        {
            ShowMainMenu(client);
        }
        else
        {
            // Warn players who are already on a team that they can't manually switch
            MC_PrintToChat(client, "%t", "CannotJoinTeamsManually");

            // Spawn exploit prevention (moved from Event_PlayerTeam)
            if (arena_index == 0)
            {
                TF2_SetPlayerClass(client, view_as<TFClassType>(0));
            }
        }
        return Plugin_Stop;
    }
}

// Processes class change requests with arena-specific restrictions and penalties
Action Command_JoinClass(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;
        
    if (!args)
        return Plugin_Handled;
    
    // Parse class change request
    char s_class[64];
    GetCmdArg(1, s_class, sizeof(s_class));
    TFClassType new_class = TF2_GetClass(s_class);
    
    if (new_class == g_tfctPlayerClass[client])
        return Plugin_Handled;
    
    int arena_index = g_iPlayerArena[client];
    
    // Handle lobby class changes (not in arena)
    if (arena_index == 0)
        return HandleLobbyClassChange(client, new_class, arena_index);
    
    // Validate class change in current arena
    if (!CanPlayerChangeClassInArena(client, new_class, arena_index))
        return Plugin_Handled;
    
    // Handle Ultiduo class setting (special case)
    if (g_bArenaUltiduo[arena_index] && g_bFourPersonArena[arena_index])
    {
        TF2_SetPlayerClass(client, new_class);
        g_tfctPlayerClass[client] = new_class;
    }
    
    // Handle spectating players - just set class
    if (!IsPlayerInActiveSlot(client, arena_index))
    {
        g_tfctPlayerClass[client] = new_class;
        ChangeClientTeam(client, TEAM_SPEC);
        return Plugin_Handled;
    }
    
    // Check timing restrictions for active players
    if (g_bFourPersonArena[arena_index])
    {
        if (!CanPlayerChangeClassInTeamArena(client, arena_index))
            return Plugin_Handled;
    }
    else
    {
        if (!CanPlayerChangeClassIn1v1Arena(client, arena_index))
            return Plugin_Handled;
    }
    
    // Execute the class change
    return ExecuteArenaClassChange(client, new_class, arena_index);
}

// Manages player handicap system for health adjustments in duels
Action Command_Handicap(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index || g_bArenaMidair[arena_index])
    {
        MC_PrintToChat(client, "%t", "MustJoinArena");
        g_iPlayerHandicap[client] = 0;
        return Plugin_Handled;
    }

    if (args == 0)
    {
        if (g_iPlayerHandicap[client] == 0)
            MC_PrintToChat(client, "%t", "NoCurrentHandicap", g_iPlayerHandicap[client]);
        else
            MC_PrintToChat(client, "%t", "CurrentHandicap", g_iPlayerHandicap[client]);
    } else {
        char argstr[64];
        GetCmdArgString(argstr, sizeof(argstr));
        int argint = StringToInt(argstr);

        if (StrEqual(argstr, "off", false))
        {
            MC_PrintToChat(client, "%t", "HandicapDisabled");
            g_iPlayerHandicap[client] = 0;
            return Plugin_Handled;
        }

        if (argint > RoundToNearest(float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]))
        {
            MC_PrintToChat(client, "%t", "InvalidHandicap");
            g_iPlayerHandicap[client] = 0;
        } else if (argint <= 0) {
            MC_PrintToChat(client, "%t", "InvalidHandicap");
        } else {
            g_iPlayerHandicap[client] = argint;

            // If the client currently has more health than their handicap allows, lower it to the proper amount.
            if (IsPlayerAlive(client) && g_iPlayerHP[client] > g_iPlayerHandicap[client])
            {
                if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
                {
                    // Prevent an possible exploit where a player could restore their buff if it decayed naturally without them taking damage.
                    if (GetEntProp(client, Prop_Data, "m_iHealth") > g_iPlayerHandicap[client])
                    {
                        SetEntProp(client, Prop_Data, "m_iHealth", g_iPlayerHandicap[client]);
                        g_iPlayerHP[client] = g_iPlayerHandicap[client];
                    }
                } else {
                    g_iPlayerHP[client] = g_iPlayerHandicap[client];
                }

                // Update overlay huds to reflect health change.
                int
                    player_slot = g_iPlayerSlot[client],
                    foe_slot = player_slot == SLOT_ONE ? SLOT_TWO : SLOT_ONE,
                    foe = g_iArenaQueue[arena_index][foe_slot],
                    foe_teammate,
                    player_teammate;

                if (g_bFourPersonArena[arena_index])
                {
                    player_teammate = GetPlayerTeammate(player_slot, arena_index);
                    foe_teammate = GetPlayerTeammate(foe_slot, arena_index);

                    UpdateHud(player_teammate);
                    UpdateHud(foe_teammate);
                }

                UpdateHud(client);
                UpdateHud(foe);
                UpdateHudForArena(g_iPlayerArena[client]);
            }
        }
    }

    return Plugin_Handled;
}

// Blocks eureka effect teleportation to prevent arena exploitation
Action Command_EurekaTeleport(int client, int args)
{
    // Block eureka effect teleport
    return Plugin_Handled;
}

// Blocks automatic team assignment and shows arena selection menu instead
Action Command_AutoTeam(int client, int args)
{
    // Block autoteam command usage, and show add menu instead
    if (!IsValidClient(client))
        return Plugin_Handled;
    
    if (TF2_GetClientTeam(client) == TFTeam_Spectator)
    {
        ShowMainMenu(client);
    }
    return Plugin_Stop;
}


// ===== GAME EVENT HANDLERS =====

// Handles player spawn events to set class, reset ammo, and manage team assignments
Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int arena_index = g_iPlayerArena[client];

    g_tfctPlayerClass[client] = TF2_GetPlayerClass(client);


    ResetClientAmmoCounts(client);

    if (!g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] != SLOT_ONE && g_iPlayerSlot[client] != SLOT_TWO)
        ChangeClientTeam(client, TEAM_SPEC);

    else if (g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] != SLOT_ONE && g_iPlayerSlot[client] != SLOT_TWO && (g_iPlayerSlot[client] != SLOT_THREE && g_iPlayerSlot[client] != SLOT_FOUR))
        ChangeClientTeam(client, TEAM_SPEC);

    if (g_bArenaMGE[arena_index])
    {
        g_iPlayerHP[client] = RoundToNearest(float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]);
        UpdateHudForArena(arena_index);
    }

    if (g_bArenaBBall[arena_index])
    {
        g_bPlayerHasIntel[client] = false;
    }

    return Plugin_Continue;
}

// Processes damage events for health tracking, airshot detection, and ammo management
Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(victim))
        return Plugin_Continue;

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int arena_index = g_iPlayerArena[victim];
    int iDamage = event.GetInt("damageamount");

    if (attacker > 0 && victim != attacker) // If the attacker wasn't the person being hurt, or the world (fall damage).
    {
        bool shootsRocketsOrPipes = ShootsRocketsOrPipes(attacker);
        if (g_bArenaEndif[arena_index])
        {
            if (shootsRocketsOrPipes)
                CreateTimer(0.1, BoostVectors, GetClientUserId(victim));
        }

        if (g_bPlayerTakenDirectHit[victim])
        {
            bool isVictimInAir = !(GetEntityFlags(victim) & (FL_ONGROUND));

            if (isVictimInAir)
            {
                // Airshot
                float dist = DistanceAboveGround(victim);
                if (dist >= g_iAirshotHeight)
                {
                    if (g_bArenaMidair[arena_index])
                        g_iPlayerHP[victim] -= 1;

                    if (g_bArenaEndif[arena_index] && dist >= 250)
                    {
                        g_iPlayerHP[victim] = -1;
                    }
                }
            }
        }
    }

    g_bPlayerTakenDirectHit[victim] = false;

    if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
        g_iPlayerHP[victim] = GetClientHealth(victim);
    else if (g_bArenaAmmomod[arena_index])
        g_iPlayerHP[victim] -= iDamage;

    if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index] || g_bArenaEndif[arena_index])
    {
        if (g_iPlayerHP[victim] <= 0)
            SetEntityHealth(victim, 0);
        else
            SetEntityHealth(victim, g_iPlayerMaxHP[victim]);
    }

    UpdateHud(victim);
    UpdateHud(attacker);
    UpdateHudForArena(g_iPlayerArena[victim]);

    return Plugin_Continue;
}

// Manages player death events including scoring, ELO calculation, and respawn logic
Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int arena_index = g_iPlayerArena[victim];
    int victim_slot = g_iPlayerSlot[victim];

    // Reset victim's velocity to prevent momentum carryover to respawn
    if (IsValidClient(victim) && arena_index > 0)
    {
        float vel[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vel);
    }

    int killer_slot;
    int killer;
    int killer_teammate;
    int victim_teammate;
    
    // In 2v2: RED (slots 1,3) vs BLU (slots 2,4)
    // In 1v1: RED (slot 1) vs BLU (slot 2)
    if (g_bFourPersonArena[arena_index])
    {
        // 2v2 logic: find an alive enemy player
        if (victim_slot == SLOT_ONE || victim_slot == SLOT_THREE)
        {
            // Victim was RED, killer is BLU (slot 2 or 4)
            killer = g_iArenaQueue[arena_index][SLOT_TWO];
            killer_slot = SLOT_TWO;
            if (!IsValidClient(killer) || !IsPlayerAlive(killer))
            {
                killer = g_iArenaQueue[arena_index][SLOT_FOUR];
                killer_slot = SLOT_FOUR;
            }
        }
        else
        {
            // Victim was BLU, killer is RED (slot 1 or 3)  
            killer = g_iArenaQueue[arena_index][SLOT_ONE];
            killer_slot = SLOT_ONE;
            if (!IsValidClient(killer) || !IsPlayerAlive(killer))
            {
                killer = g_iArenaQueue[arena_index][SLOT_THREE];
                killer_slot = SLOT_THREE;
            }
        }
        
        victim_teammate = GetPlayerTeammate(victim_slot, arena_index);
        if (IsValidClient(killer))
            killer_teammate = GetPlayerTeammate(killer_slot, arena_index);
    }
    else
    {
        // 1v1 logic: simple slot mapping
        killer_slot = (victim_slot == SLOT_ONE) ? SLOT_TWO : SLOT_ONE;
        killer = g_iArenaQueue[arena_index][killer_slot];
    }

    // Gets the killer and victims team slot (red 1, blu 2)
    int killer_team_slot = GetTeamSlotFromPlayerSlot(killer_slot);
    int victim_team_slot = GetTeamSlotFromPlayerSlot(victim_slot);

    // Don't detect dead ringer deaths
    int victim_deathflags = event.GetInt("death_flags");
    if (victim_deathflags & 32)
    {
        return Plugin_Continue;
    }


    RemoveClientParticle(victim);

    if (!arena_index)
        ChangeClientTeam(victim, TEAM_SPEC);

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (g_iArenaStatus[arena_index] < AS_FIGHT && IsValidClient(attacker) && IsPlayerAlive(attacker))
    {
        TF2_RegeneratePlayer(attacker);
        int raised_hp = RoundToNearest(float(g_iPlayerMaxHP[attacker]) * g_fArenaHPRatio[arena_index]);
        g_iPlayerHP[attacker] = raised_hp;
        SetEntProp(attacker, Prop_Data, "m_iHealth", raised_hp);
    }

    // Call arena player death forward
    if (arena_index > 0)
    {
        CallForward_OnArenaPlayerDeath(victim, attacker, arena_index);
    }

    if (g_iArenaStatus[arena_index] < AS_FIGHT || g_iArenaStatus[arena_index] > AS_FIGHT)
    {
        CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(victim));
        return Plugin_Handled;
    }

    if ((g_bFourPersonArena[arena_index] && !IsPlayerAlive(killer)) || (g_bFourPersonArena[arena_index] && !IsPlayerAlive(killer_teammate) && !IsPlayerAlive(killer)))
    {
        if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])
            return Plugin_Handled;
    }

    if (!g_bArenaBBall[arena_index] && !g_bArenaKoth[arena_index] && (!g_bFourPersonArena[arena_index] || (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate)))) // Kills shouldn't give points in bball. Or if only 1 player in a two person arena dies
        g_iArenaScore[arena_index][killer_team_slot] += 1;

    if (!g_bArenaEndif[arena_index]) // Endif does not need to display health, since it is one-shot kills.
    {
        // We must get the player that shot you last in 4 player arenas
        // The valid client check shouldn't be necessary but I'm getting invalid clients here for some reason
        // This may be caused by players killing themselves in 1v1 arenas without being attacked, or dieing after
        // A player disconnects but before the arena status transitions out of fight mode?
        // TODO: check properly
        if (g_bFourPersonArena[arena_index] && IsValidClient(attacker) && IsPlayerAlive(attacker))
        {
            if ((g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index]) && (victim != attacker))
                MC_PrintToChat(victim, "%t", "HPLeft", GetClientHealth(attacker));
            else if (victim != attacker)
                MC_PrintToChat(victim, "%t", "HPLeft", g_iPlayerHP[attacker]);
        }
        // In 1v1 arenas we can assume the person who killed you is the other person in the arena
        else if (IsValidClient(killer) && IsPlayerAlive(killer))
        {
            if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index])
                MC_PrintToChat(victim, "%t", "HPLeft", GetClientHealth(killer));
            else
                MC_PrintToChat(victim, "%t", "HPLeft", g_iPlayerHP[killer]);
        }
    }

    // Currently set up so that if its a 2v2 duel the round will reset after both players on one team die and a point will be added for that round to the other team
    // Another possibility is to make it like dm where its instant respawn for every player, killer gets hp, and a point is awarded for every kill

    int fraglimit = g_iArenaFraglimit[arena_index];

    if ((!g_bFourPersonArena[arena_index] && (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])) ||
        (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate) && !g_bArenaBBall[arena_index] && !g_bArenaKoth[arena_index]))
    g_iArenaStatus[arena_index] = AS_AFTERFIGHT;

    if (ShouldProcessMatchCompletion(arena_index, killer_team_slot, fraglimit))
    {
        ProcessMatchCompletion(arena_index, killer, killer_teammate, victim, victim_teammate, killer_team_slot, victim_team_slot, fraglimit);
    }
    else if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])
    {
        if (!g_bFourPersonArena[arena_index])
            CreateTimer(3.0, Timer_NewRound, arena_index);

        else if (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate))
            CreateTimer(3.0, Timer_NewRound, arena_index);
        
        else if (g_bFourPersonArena[arena_index] && victim_teammate && IsPlayerAlive(victim_teammate))
        {
            // Set the player as waiting (same as other 2v2 modes)
            g_iPlayerWaiting[victim] = true;
            // Change the player to spec to keep him from respawning
            CreateTimer(5.0, Timer_ChangePlayerSpec, victim);
        }

    }
    else
    {
        if (g_bArenaBBall[arena_index])
        {
            HandleBBallPlayerDeath(victim, killer, arena_index);
        } else {
            if (!g_bFourPersonArena[arena_index] && !g_bArenaKoth[arena_index])
            {
                ResetKiller(killer, arena_index);
            }
            // Handle 2v2 team reset when one team is eliminated
            Handle2v2TeamResetOnDeath(arena_index, victim, victim_teammate, killer_teammate, killer_team_slot);


        }


        // TODO: Check to see if its koth and apply a spawn penalty if needed depending on who's capping
        if (g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index])
        {
            CreateTimer(g_fArenaRespawnTime[arena_index], Timer_ResetPlayer, GetClientUserId(victim));
        }
        else if (g_bFourPersonArena[arena_index] && victim_teammate && IsPlayerAlive(victim_teammate))
        {
            // Set the player as waiting
            g_iPlayerWaiting[victim] = true;
            // Change the player to spec to keep him from respawning
            CreateTimer(5.0, Timer_ChangePlayerSpec, victim);
        }
        else
            CreateTimer(g_fArenaRespawnTime[arena_index], Timer_ResetPlayer, GetClientUserId(victim));

    }

    UpdateHud(victim);
    UpdateHud(killer);

    if (g_bFourPersonArena[arena_index])
    {
        UpdateHud(victim_teammate);
        UpdateHud(killer_teammate);
    }

    UpdateHudForArena(arena_index);

    return Plugin_Continue;
}


// ===== TIMER FUNCTIONS =====

// Displays welcome messages to new players with plugin information
Action Timer_WelcomePlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    MC_PrintToChat(client, "%t", "Welcome1", PL_VERSION);
    if (StrContains(g_sMapName, "mge_", false) == 0)
        MC_PrintToChat(client, "%t", "Welcome2");
    MC_PrintToChat(client, "%t", "Welcome3");

    return Plugin_Continue;
}

// Handles player teleportation to appropriate spawn points based on arena type
Action Timer_Tele(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    int arena_index = g_iPlayerArena[client];

    if (!arena_index)
        return Plugin_Continue;

    int player_slot = g_iPlayerSlot[client];
    if ((!g_bFourPersonArena[arena_index] && player_slot > SLOT_TWO) || (g_bFourPersonArena[arena_index] && player_slot > SLOT_FOUR))
    {
        return Plugin_Continue;
    }

    float vel[3] =  { 0.0, 0.0, 0.0 };

    // CHECK FOR MANNTREADS IN ENDIF
    if (g_bArenaEndif[arena_index])
    {
        // Loop thru client's wearable entities. not adding gamedata for this shiz
        int i = -1;
        while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
        {
            if (client != GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity"))
            {
                continue;
            }
            int itemdef = GetEntProp(i, Prop_Send, "m_iItemDefinitionIndex");
            // Manntreads itemdef
            if (itemdef == 444)
            {
                // Just in case.
                RemoveEntity(i);
                MC_PrintToChat(client, "%t", "EndIfManntreadsRemoval");
                // Run elo calc so clients can't be cheeky if they're losing
                RemoveFromQueue(client, true);
            }
        }
    }


    // BBall and 2v2 arenas handle spawns differently, each team, has their own spawns.
    if (g_bArenaBBall[arena_index])
    {
        int random_int;
        int offset_high, offset_low;
        if (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE)
        {
            offset_high = ((g_iArenaSpawns[arena_index] - 5) / 2);
            random_int = GetRandomInt(1, offset_high); // The first half of the player spawns are for slot one and three.
        } else {
            offset_high = (g_iArenaSpawns[arena_index] - 5);
            offset_low = (((g_iArenaSpawns[arena_index] - 5) / 2) + 1);
            random_int = GetRandomInt(offset_low, offset_high); // The last 5 spawns are for the intel and trigger spawns, not players.
        }

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        return Plugin_Continue;
    }
    else if (g_bArenaKoth[arena_index])
    {
        int random_int;
        int offset_high, offset_low;
        if (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE)
        {
            offset_high = ((g_iArenaSpawns[arena_index] - 1) / 2);
            random_int = GetRandomInt(1, offset_high); // The first half of the player spawns are for slot one and three.
        } else {
            offset_high = (g_iArenaSpawns[arena_index] - 1);
            offset_low = (((g_iArenaSpawns[arena_index] + 1) / 2));
            random_int = GetRandomInt(offset_low, offset_high); // The last spawn is for the point
        }

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        return Plugin_Continue;
    }
    else if (g_bFourPersonArena[arena_index])
    {
        int random_int;
        int offset_high, offset_low;
        if (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE)
        {
            offset_high = ((g_iArenaSpawns[arena_index]) / 2);
            offset_low = 1;
        } else {
            offset_high = (g_iArenaSpawns[arena_index]);
            offset_low = (((g_iArenaSpawns[arena_index]) / 2) + 1);
        }

        // Get teammate and check if they're using a spawn point
        int teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
        int teammate_spawn = -1;
        if (IsValidClient(teammate) && IsPlayerAlive(teammate)) {
            teammate_spawn = GetPlayerCurrentSpawnPoint(teammate, arena_index);
        }

        // Pick random spawn from team's pool, avoiding teammate's spawn
        int attempts = 0;
        do {
            random_int = GetRandomInt(offset_low, offset_high);
            attempts++;
        } while (random_int == teammate_spawn && attempts < 50); // Prevent infinite loop

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        return Plugin_Continue;
    }

    // Create an array that can hold all the arena's spawns.
    int[] RandomSpawn = new int[g_iArenaSpawns[arena_index] + 1];

    // Fill the array with the spawns.
    for (int i = 0; i < g_iArenaSpawns[arena_index]; i++)
    RandomSpawn[i] = i + 1;

    // Shuffle them into a random order.
    SortIntegers(RandomSpawn, g_iArenaSpawns[arena_index], Sort_Random);

    // Now when the array is gone through sequentially, it will still provide a random spawn.
    float besteffort_dist;
    int besteffort_spawn;
    for (int i = 0; i < g_iArenaSpawns[arena_index]; i++)
    {
        int client_slot = g_iPlayerSlot[client];
        int foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
        if (foe_slot)
        {
            float distance;
            int foe = g_iArenaQueue[arena_index][foe_slot];
            if (IsValidClient(foe))
            {
                float foe_pos[3];
                GetClientAbsOrigin(foe, foe_pos);
                distance = GetVectorDistance(foe_pos, g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]]);
                if (distance > g_fArenaMinSpawnDist[arena_index])
                {
                    TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]], g_fArenaSpawnAngles[arena_index][RandomSpawn[i]], vel);
                    EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]], _, SNDLEVEL_NORMAL, _, 1.0);
                    UpdateHud(client);
                    return Plugin_Continue;
                } else if (distance > besteffort_dist) {
                    besteffort_dist = distance;
                    besteffort_spawn = RandomSpawn[i];
                }
            }
        }
    }

    if (besteffort_spawn)
    {
        // Couldn't find a spawn that was far enough away, so use the one that was the farthest.
        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][besteffort_spawn], g_fArenaSpawnAngles[arena_index][besteffort_spawn], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][besteffort_spawn], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        return Plugin_Continue;
    } else {
        // No foe, so just pick a random spawn.
        int random_int = GetRandomInt(1, g_iArenaSpawns[arena_index]);
        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        return Plugin_Continue;
    }
}

// Timer callback to reset player state after respawn delay
Action Timer_ResetPlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (IsValidClient(client))
    {
        ResetPlayer(client);
    }
    
    return Plugin_Continue;
}


// ===== CALCULATION AND ANALYSIS =====

// Calculates player's height above ground for airshot detection
float DistanceAboveGround(int victim)
{
    float vStart[3];
    float vEnd[3];
    float vAngles[3] =  { 90.0, 0.0, 0.0 };
    GetClientAbsOrigin(victim, vStart);
    Handle trace = TR_TraceRayFilterEx(vStart, vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilterPlayer);

    float distance = -1.0;
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(vEnd, trace);
        distance = GetVectorDistance(vStart, vEnd, false);
    } else {
        LogError("trace error. victim %N(%d)", victim, victim);
    }

    delete trace;
    return distance;
}

// Calculates minimum ground distance around player for drop detection
float DistanceAboveGroundAroundPlayer(int client)
{
    static const float SAMPLE_OFFSET = 10.0;
    static const float INVALID_DISTANCE = -1.0;
    
    float playerPos[3];
    GetClientAbsOrigin(client, playerPos);
    
    // Define sample positions: center and 4 cardinal directions
    float samplePositions[5][3];
    samplePositions[0] = playerPos;                                    // Center
    samplePositions[1] = playerPos; samplePositions[1][0] += SAMPLE_OFFSET; // +X
    samplePositions[2] = playerPos; samplePositions[2][0] -= SAMPLE_OFFSET; // -X
    samplePositions[3] = playerPos; samplePositions[3][1] += SAMPLE_OFFSET; // +Y
    samplePositions[4] = playerPos; samplePositions[4][1] -= SAMPLE_OFFSET; // -Y
    
    float minDistance = INVALID_DISTANCE;
    float vEnd[3];
    float vAngles[3] = { 90.0, 0.0, 0.0 };
    
    for (int i = 0; i < sizeof(samplePositions); i++)
    {
        Handle trace = TR_TraceRayFilterEx(samplePositions[i], vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilterPlayer);
        
        if (TR_DidHit(trace))
        {
            TR_GetEndPosition(vEnd, trace);
            float distance = GetVectorDistance(samplePositions[i], vEnd, false);
            
            if (minDistance == INVALID_DISTANCE || distance < minDistance)
            {
                minDistance = distance;
            }
        }
        else
        {
            LogError("Ground trace failed for client %N(%d) at position [%.1f, %.1f, %.1f]", 
                     client, client, samplePositions[i][0], samplePositions[i][1], samplePositions[i][2]);
        }
        
        delete trace;
    }
    
    return minDistance;
}

// Determines which spawn point a player is currently closest to
int GetPlayerCurrentSpawnPoint(int client, int arena_index)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return -1;
    
    float client_pos[3];
    GetClientAbsOrigin(client, client_pos);
    
    // Find the closest spawn point to the player's current position
    int closest_spawn = -1;
    float closest_distance = 999999.0;
    
    for (int i = 1; i <= g_iArenaSpawns[arena_index]; i++)
    {
        float distance = GetVectorDistance(client_pos, g_fArenaSpawnOrigin[arena_index][i]);
        if (distance < closest_distance)
        {
            closest_distance = distance;
            closest_spawn = i;
        }
    }
    
    // Only return the spawn if the player is very close to it (within 100 units)
    if (closest_distance < 100.0)
        return closest_spawn;
    
    return -1;
}

// Filter function for ray tracing to exclude player entities
bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
    return entity > MaxClients || !entity;
}

// Formats player class information for database storage and display
void GetPlayerClassString(int client, int arena_index, char[] buffer, int maxlen)
{
    if (g_bArenaClassChange[arena_index] && g_alPlayerDuelClasses[client] != null && g_alPlayerDuelClasses[client].Length > 0)
    {
        // Build comma-separated list of all classes used
        buffer[0] = '\0';
        for (int i = 0; i < g_alPlayerDuelClasses[client].Length; i++)
        {
            char className[16];
            strcopy(className, sizeof(className), TFClassToString(view_as<TFClassType>(g_alPlayerDuelClasses[client].Get(i))));
            
            if (i > 0)
                StrCat(buffer, maxlen, ",");
            StrCat(buffer, maxlen, className);
        }
    }
    else
    {
        // Use single class from duel start
        strcopy(buffer, maxlen, TFClassToString(g_tfctPlayerDuelClass[client]));
    }
}
