// ===== PLUGIN CORE LIFECYCLE =====

// Timer callback to initialize public invite arrays
public Action Timer_InitializePublicInvites(Handle timer)
{
    for (int i = 0; i <= MAXARENAS; i++)
    {
        g_iPublicInviteArena[i] = 0;
        g_fPublicInviteTime[i] = 0.0;
    }
    return Plugin_Stop;
}

// Load and parse spawn point configurations from map-specific config files
bool LoadSpawnPoints()
{
    char txtfile[256];
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));

    //  "workshop/mge_training_v8_beta4b.ugc1996603816"
    if (StrContains(g_sMapName, "workshop/", false) != -1)
    {
        char nonWorkshopName[256];
        if (!GetMapDisplayName(g_sMapName, nonWorkshopName, sizeof(nonWorkshopName)))
        {
            LogError("Failed to convert workshop map name %s to pretty name! This map will probably not work!");
        }
        else
        {
            strcopy(g_sMapName, sizeof(g_sMapName), nonWorkshopName);
        }
    }

    // Build path to map-specific config file: configs/mge/{mapname}.cfg
    Format(txtfile, sizeof(txtfile), "configs/mge/%s.cfg", g_sMapName);
    BuildPath(Path_SM, txtfile, sizeof(txtfile), txtfile);

    KeyValues kv = new KeyValues("SpawnConfigs");

    char spawn[64];
    char spawnCo[6][16];
    int count;
    int i;
    g_iArenaCount = 0;

    for (int j = 0; j <= MAXARENAS; j++)
    {
        g_iArenaSpawns[j] = 0;
    }

    if (!kv.ImportFromFile(txtfile))
    {
        LogError("Error. Can't find cfg file: %s", txtfile);
        delete kv;
        return false;
    }
    
    if (!kv.GotoFirstSubKey())
    {
        LogError("Error in cfg file: %s", txtfile);
        delete kv;
        return false;
    }
    
    do
    {
        g_iArenaCount++;
        kv.GetSectionName(g_sArenaOriginalName[g_iArenaCount], 64);
        int id;
        if (kv.GetNameSymbol("1", id))
        {
            char intstr[4];
            char intstr2[4];
            do
            {
                g_iArenaSpawns[g_iArenaCount]++;
                IntToString(g_iArenaSpawns[g_iArenaCount], intstr, sizeof(intstr));
                IntToString(g_iArenaSpawns[g_iArenaCount]+1, intstr2, sizeof(intstr2));
                kv.GetString(intstr, spawn, sizeof(spawn));
                count = ExplodeString(spawn, " ", spawnCo, 6, 16);
                if (count==6)
                {
                    for (i=0; i<3; i++)
                    {
                        g_fArenaSpawnOrigin[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][i] = StringToFloat(spawnCo[i]);
                    }
                    for (i=3; i<6; i++)
                    {
                        g_fArenaSpawnAngles[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][i-3] = StringToFloat(spawnCo[i]);
                    }
                } else if(count==4) {
                    for (i=0; i<3; i++)
                    {
                        g_fArenaSpawnOrigin[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][i] = StringToFloat(spawnCo[i]);
                    }
                    g_fArenaSpawnAngles[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][0] = 0.0;
                    g_fArenaSpawnAngles[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][1] = StringToFloat(spawnCo[3]);
                    g_fArenaSpawnAngles[g_iArenaCount][g_iArenaSpawns[g_iArenaCount]][2] = 0.0;
                } else {
                    SetFailState("Error in cfg file. Wrong number of parameters (%d) on spawn <%i> in arena <%s>",count,g_iArenaSpawns[g_iArenaCount],g_sArenaOriginalName[g_iArenaCount]);
                }
            } while (kv.GetNameSymbol(intstr2, id));
        } else {
            LogError("Could not load spawns on arena %s.", g_sArenaOriginalName[g_iArenaCount]);
        }

        if (kv.GetNameSymbol("cap", id)) {
            kv.GetString("cap",  g_sArenaCap[g_iArenaCount], 64);
            g_bArenaHasCap[g_iArenaCount] = true;
        } else {
            g_bArenaHasCap[g_iArenaCount] = false;
        }

        if (kv.GetNameSymbol("cap_trigger", id)) {
            kv.GetString("cap_trigger",  g_sArenaCapTrigger[g_iArenaCount], 64);
            g_bArenaHasCapTrigger[g_iArenaCount] = true;
        }

        // Optional parameters
        g_iArenaMgelimit[g_iArenaCount] = kv.GetNum("fraglimit", g_iDefaultFragLimit);
        g_iArenaCaplimit[g_iArenaCount] = kv.GetNum("caplimit", g_iDefaultFragLimit);
        g_iArenaMinRating[g_iArenaCount] = kv.GetNum("minrating", -1);
        g_iArenaMaxRating[g_iArenaCount] = kv.GetNum("maxrating", -1);
        g_bArenaMidair[g_iArenaCount] = kv.GetNum("midair", 0) ? true : false;
        g_iArenaCdTime[g_iArenaCount] = kv.GetNum("cdtime", DEFAULT_COUNTDOWN_TIME);
        g_bArenaMGE[g_iArenaCount] = kv.GetNum("mge", 0) ? true : false;
        g_fArenaHPRatio[g_iArenaCount] = kv.GetFloat("hpratio", 1.5);
        g_bArenaEndif[g_iArenaCount] = kv.GetNum("endif", 0) ? true : false;
        g_iArenaAirshotHeight[g_iArenaCount] = kv.GetNum("airshotheight", 250);
        g_bArenaBoostVectors[g_iArenaCount] = kv.GetNum("boostvectors", 0) ? true : false;
        g_bArenaBBall[g_iArenaCount] = kv.GetNum("bball", 0) ? true : false;
        g_bVisibleHoops[g_iArenaCount] = kv.GetNum("vishoop", 0) ? true : false;
        g_iArenaEarlyLeave[g_iArenaCount] = kv.GetNum("earlyleave", 0);
        g_bArenaInfAmmo[g_iArenaCount] = kv.GetNum("infammo", 1) ? true : false;
        g_bArenaShowHPToPlayers[g_iArenaCount] = kv.GetNum("showhp", 1) ? true : false;
        g_fArenaMinSpawnDist[g_iArenaCount] = kv.GetFloat("mindist", 100.0);
        g_bFourPersonArena[g_iArenaCount] = kv.GetNum("4player", 0) ? true : false;
        g_bArenaAllowChange[g_iArenaCount] = kv.GetNum("allowchange", 0) ? true : false;
        g_bArenaAllowKoth[g_iArenaCount] = kv.GetNum("allowkoth", 0) ? true : false;
        g_bArenaKothTeamSpawn[g_iArenaCount] = kv.GetNum("kothteamspawn", 0) ? true : false;
        g_fArenaRespawnTime[g_iArenaCount] = kv.GetFloat("respawntime", 0.1);
        g_bArenaAmmomod[g_iArenaCount] = kv.GetNum("ammomod", 0) ? true : false;
        g_bArenaUltiduo[g_iArenaCount] = kv.GetNum("ultiduo", 0) ? true : false;
        g_bArenaKoth[g_iArenaCount] = kv.GetNum("koth", 0) ? true : false;
        g_bArenaTurris[g_iArenaCount] = kv.GetNum("turris", 0) ? true : false;
        g_bArenaClassChange[g_iArenaCount] = kv.GetNum("classchange", 1) ? true : false;
        g_iDefaultCapTime[g_iArenaCount] = kv.GetNum("timer", 180);

        // Parsing allowed classes for current arena
        char sAllowedClasses[128];
        kv.GetString("classes", sAllowedClasses, sizeof(sAllowedClasses));
        ParseAllowedClasses(sAllowedClasses,g_tfctArenaAllowedClasses[g_iArenaCount]);
        g_iArenaFraglimit[g_iArenaCount] = g_iArenaMgelimit[g_iArenaCount];
        UpdateArenaName(g_iArenaCount);
    } while (kv.GotoNextKey());
    
    if (g_iArenaCount)
    {
        LogMessage("Loaded %d arenas from %s. MGEMod enabled.", g_iArenaCount, txtfile);
        delete kv;
        return true;
    } else {
        LogMessage("No arenas found in %s.", txtfile);
        delete kv;
        return false;
    }
}


// ===== ARENA MANAGEMENT =====

// Reset arena state and prepare for next match including spawn points and game settings
void ResetArena(int arena_index)
{
    // Tell the game this was a forced suicide and it shouldn't do anything about it

    int maxSlots;
    if (g_bFourPersonArena[arena_index])
    {
        maxSlots = SLOT_FOUR;
    }
    else
    {
        maxSlots = SLOT_TWO;
    }

    for (int i = SLOT_ONE; i <= maxSlots; ++i)
    {
        int thisClient = g_iArenaQueue[arena_index][i];
        if
        (
               IsValidClient(thisClient)
            && IsPlayerAlive(thisClient)
            && TF2_GetPlayerClass(thisClient) == TFClass_Medic
        )
        {
            // Medigun
            int medigunIndex = GetPlayerWeaponSlot(thisClient, TFWeaponSlot_Secondary);
            if (IsValidEntity(medigunIndex))
            {
                SetEntPropFloat(medigunIndex, Prop_Send, "m_flChargeLevel", 0.0);
            }
        }
    }
}

// Update arena display name based on current gamemode and configuration
void UpdateArenaName(int arena)
{
    char mode[4], type[8];
    Format(mode, sizeof(mode), "%s", g_bFourPersonArena[arena] ? "2v2" : "1v1");
    Format(type, sizeof(type), "%s",
        g_bArenaMGE[arena] ? "MGE" :
        g_bArenaUltiduo[arena] ? "ULTI" :
        g_bArenaKoth[arena] ? "KOTH" :
        g_bArenaAmmomod[arena] ? "AMOD" :
        g_bArenaBBall[arena] ? "BBALL" :
        g_bArenaMidair[arena] ? "MIDA" :
        g_bArenaEndif[arena] ? "ENDIF" : ""
    );
    Format(g_sArenaName[arena], sizeof(g_sArenaName), "%s [%s %s]", g_sArenaOriginalName[arena], mode, type);
}

// Reset class point tracking for all active players in an arena
void ResetClassPointsForArena(int arena_index)
{
    int maxSlots = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int slot = SLOT_ONE; slot <= maxSlots; slot++)
    {
        int player = g_iArenaQueue[arena_index][slot];
        if (player != 0 && IsValidClient(player))
        {
            for (int classId = 1; classId <= 9; classId++)
            {
                g_iPlayerClassPoints[player][classId] = 0;
                for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
                {
                    g_iPlayerMatchupCount[player][classId][oppClassId] = 0;
                }
            }
        }
    }
}


// ===== QUEUE MANAGEMENT =====

// Check if a player has VIP queue priority (admin flags 'a' or 'z')
bool IsPlayerVipForQueue(int client)
{
    if (!g_bVipQueuePriority)
        return false;

    AdminId admin = GetUserAdmin(client);
    if (admin == INVALID_ADMIN_ID)
        return false;

    return (GetAdminFlag(admin, Admin_Generic, Access_Effective) ||
            GetAdminFlag(admin, Admin_Root, Access_Effective));
}

// Assign appropriate slot for player considering VIP priority and insert into queue
int AssignQueueSlotAndInsert(int client, int arena_index, int playerPrefTeam, int forcedSlot)
{
    // Handle forced slot assignment (used by API natives)
    if (forcedSlot > 0)
    {
        // Validate forced slot for arena type
        if (!IsValidSlotForArena(arena_index, forcedSlot))
            return 0; // Invalid slot

        // Check if forced slot is already occupied
        if (g_iArenaQueue[arena_index][forcedSlot] != 0)
            return 0; // Slot occupied

        return forcedSlot;
    }

    bool isVip = IsPlayerVipForQueue(client);
    int maxActiveSlot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;

    // For 2v2 arenas, handle team preference for active slots (team switching)
    if (g_bFourPersonArena[arena_index] && playerPrefTeam != 0)
    {
        // This is team switching for active players only
        if (playerPrefTeam == TEAM_RED)
        {
            // Try main RED slots first
            if (!g_iArenaQueue[arena_index][SLOT_ONE])
                return SLOT_ONE;
            else if (!g_iArenaQueue[arena_index][SLOT_THREE])
                return SLOT_THREE;
            else
            {
                // RED slots full, put in regular queue with VIP priority
                return InsertIntoQueueWithVipPriority(arena_index, SLOT_FOUR + 1, isVip);
            }
        }
        else if (playerPrefTeam == TEAM_BLU)
        {
            // Try main BLU slots first
            if (!g_iArenaQueue[arena_index][SLOT_TWO])
                return SLOT_TWO;
            else if (!g_iArenaQueue[arena_index][SLOT_FOUR])
                return SLOT_FOUR;
            else
            {
                // BLU slots full, put in regular queue with VIP priority
                return InsertIntoQueueWithVipPriority(arena_index, SLOT_FOUR + 1, isVip);
            }
        }
    }
    else
    {
        // Regular queue assignment: fill active slots first, then queue with VIP priority
        for (int slot = SLOT_ONE; slot <= maxActiveSlot; slot++)
        {
            if (!g_iArenaQueue[arena_index][slot])
                return slot;
        }

        return InsertIntoQueueWithVipPriority(arena_index, maxActiveSlot + 1, isVip);
    }
    return 0;
}

// Insert player into queue with VIP priority (shifts queue as needed)
int InsertIntoQueueWithVipPriority(int arena_index, int startSlot, bool isVip)
{
    int insertSlot = startSlot;

    if (isVip)
    {
        // VIP gets priority - find insertion point before first non-VIP player
        while (g_iArenaQueue[arena_index][insertSlot])
        {
            int queuedPlayer = g_iArenaQueue[arena_index][insertSlot];
            if (!IsPlayerVipForQueue(queuedPlayer))
                break; // Found first non-VIP, insert before them
            insertSlot++;
        }
    }
    else
    {
        // Non-VIP goes to end of queue
        while (g_iArenaQueue[arena_index][insertSlot])
            insertSlot++;
    }

    // If we found an occupied slot for VIP insertion, shift the queue
    if (g_iArenaQueue[arena_index][insertSlot] != 0)
    {
        // Find the last occupied slot to know how far to shift
        int lastSlot = insertSlot;
        while (g_iArenaQueue[arena_index][lastSlot])
            lastSlot++;

        // Shift all players from lastSlot down to insertSlot one position forward
        for (int shiftSlot = lastSlot; shiftSlot > insertSlot; shiftSlot--)
        {
            g_iArenaQueue[arena_index][shiftSlot] = g_iArenaQueue[arena_index][shiftSlot - 1];
            if (g_iArenaQueue[arena_index][shiftSlot] != 0)
            {
                g_iPlayerSlot[g_iArenaQueue[arena_index][shiftSlot]] = shiftSlot;
            }
        }
        g_iArenaQueue[arena_index][insertSlot] = 0; // Clear the insert slot for the new player
    }

    return insertSlot;
}

// Add a loser back to queue without VIP priority (goes to end of queue)
void AddLoserToQueue(int client, int arena_index)
{
    if (!IsValidClient(client) || arena_index <= 0 || arena_index > g_iArenaCount)
        return;

    // Remove any existing invites for this player
    ClearPlayerInvites(client);

    // Find the end of the queue
    int queueSlot = g_bFourPersonArena[arena_index] ? SLOT_FOUR + 1 : SLOT_TWO + 1;
    while (g_iArenaQueue[arena_index][queueSlot])
        queueSlot++;

    // Add to end of queue (no VIP priority)
    g_iPlayerArena[client] = arena_index;
    g_iPlayerSlot[client] = queueSlot;
    g_iArenaQueue[arena_index][queueSlot] = client;

    // Set player to spectator if not already
    if (GetClientTeam(client) != TEAM_SPEC)
        ChangeClientTeam(client, TEAM_SPEC);

    UpdateHudForArena(arena_index);
}

// Remove player from arena queue with optional statistics calculation and spectator handling
// TODO: refactor this crap
void RemoveFromQueue(int client, bool calcstats = false, bool specfix = false)
{
    int arena_index = g_iPlayerArena[client];

    if (arena_index == 0)
    {
        return;
    }
    
    // Call OnPlayerArenaRemove forward - allow blocking
    Action result = CallForward_OnPlayerArenaRemove(client, arena_index);
    if (result >= Plugin_Handled)
        return;

    int player_slot = g_iPlayerSlot[client];
    g_iPlayerArena[client] = 0;
    g_iPlayerSlot[client] = 0;
    g_iArenaQueue[arena_index][player_slot] = 0;
    g_iPlayerHandicap[client] = 0;
    g_bPlayerAddedViaWadd[client] = false;
    
    // Clear public invite if this player created one
    if (g_iPublicInviteArena[arena_index] == client)
    {
        g_iPublicInviteArena[arena_index] = 0;
        g_fPublicInviteTime[arena_index] = 0.0;
    }

    // Update keyhint immediately when queue changes
    UpdateQueueKeyHintText(arena_index);

    if (IsValidClient(client) && GetClientTeam(client) != TEAM_SPEC)
    {
        ForcePlayerSuicide(client);
        ChangeClientTeam(client, TEAM_SPEC);

        if (specfix)
            CreateTimer(0.1, Timer_SpecFix, GetClientUserId(client));
    }

    int after_leaver_slot = player_slot + 1;

    // I beleive I don't need to do this anymore BUT
    // If the player was in the arena, and the timer was running, kill it
    if (((player_slot <= SLOT_TWO) || (g_bFourPersonArena[arena_index] && player_slot <= SLOT_FOUR)) && g_bTimerRunning[arena_index])
    {
        delete g_tKothTimer[arena_index];
        g_bTimerRunning[arena_index] = false;
    }

    if (g_bFourPersonArena[arena_index])
    {
        int foe_team_slot;
        int player_team_slot;

        if (player_slot <= SLOT_FOUR && player_slot > 0)
        {
            int foe_slot = (player_slot == SLOT_ONE || player_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
            int foe = g_iArenaQueue[arena_index][foe_slot];
            int player_teammate;
            int foe2;

            foe_team_slot = (foe_slot > 2) ? (foe_slot - 2) : foe_slot;
            player_team_slot = (player_slot > 2) ? (player_slot - 2) : player_slot;

            if (g_bFourPersonArena[arena_index])
            {
                player_teammate = GetPlayerTeammate(player_slot, arena_index);
                foe2 = GetPlayerTeammate(foe_slot, arena_index);

            }

            if (g_bArenaBBall[arena_index])
            {
                if (IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > 0)
                {
                    RemoveEdict(g_iBBallIntel[arena_index]);
                    g_iBBallIntel[arena_index] = -1;
                }

                RemoveClientParticle(client);
                g_bPlayerHasIntel[client] = false;

                if (foe)
                {
                    RemoveClientParticle(foe);
                    g_bPlayerHasIntel[foe] = false;
                }

                if (foe2)
                {
                    RemoveClientParticle(foe2);
                    g_bPlayerHasIntel[foe2] = false;
                }

                if (player_teammate)
                {
                    RemoveClientParticle(player_teammate);
                    g_bPlayerHasIntel[player_teammate] = false;
                }
            }

            if (g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED && calcstats && !g_bNoStats && IsValidClient(foe))
            {
                char foe_name[MAX_NAME_LENGTH * 2];
                char player_name[MAX_NAME_LENGTH * 2];
                char foe2_name[MAX_NAME_LENGTH];
                char player_teammate_name[MAX_NAME_LENGTH];

                GetClientName(foe, foe_name, sizeof(foe_name));
                GetClientName(client, player_name, sizeof(player_name));
                
                if (IsValidClient(foe2))
                    GetClientName(foe2, foe2_name, sizeof(foe2_name));
                else
                    strcopy(foe2_name, sizeof(foe2_name), "Unknown");
                    
                if (IsValidClient(player_teammate))
                    GetClientName(player_teammate, player_teammate_name, sizeof(player_teammate_name));
                else
                    strcopy(player_teammate_name, sizeof(player_teammate_name), "Unknown");

                Format(foe_name, sizeof(foe_name), "%s and %s", foe_name, foe2_name);
                Format(player_name, sizeof(player_name), "%s and %s", player_name, player_teammate_name);

                g_iArenaStatus[arena_index] = AS_REPORTED;

                if (g_iArenaScore[arena_index][foe_team_slot] > g_iArenaScore[arena_index][player_team_slot])
                {
                    if (g_iArenaScore[arena_index][foe_team_slot] >= g_iArenaEarlyLeave[arena_index])
                    {
                        CalcELO(foe, client);
                        if (IsValidClient(foe2))
                            CalcELO(foe2, client);
                        // Calculate duel duration
                        char duel_time[32] = "";
                        if (g_iArenaDuelStartTime[arena_index] > 0)
                        {
                            int currentTime = GetTime();
                            int elapsedTime = currentTime - g_iArenaDuelStartTime[arena_index];
                            int minutes = elapsedTime / 60;
                            int seconds = elapsedTime % 60;
                            Format(duel_time, sizeof(duel_time), "%02dм %02dс", minutes, seconds);
                        }

                        MC_PrintToChatAll("%t", "XdefeatsYearly", foe_name, g_iArenaScore[arena_index][foe_team_slot], player_name, g_iArenaScore[arena_index][player_team_slot], g_sArenaName[arena_index], duel_time);
                    }
                }
            }

            if (g_iArenaQueue[arena_index][SLOT_FOUR + 1])
            {
                int next_client = g_iArenaQueue[arena_index][SLOT_FOUR + 1];
                g_iArenaQueue[arena_index][SLOT_FOUR + 1] = 0;
                g_iArenaQueue[arena_index][player_slot] = next_client;
                g_iPlayerSlot[next_client] = player_slot;
                after_leaver_slot = SLOT_FOUR + 2;
                char playername[MAX_NAME_LENGTH];
                CreateTimer(2.0, Timer_Restart2v2Ready, arena_index);
                GetClientName(next_client, playername, sizeof(playername));

                SendArenaJoinMessage(playername, g_iPlayerRating[next_client], g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[next_client], IsPlayerEligibleForElo(next_client));
                
                // Play sound if player was added via wadd
                if (g_bPlayerAddedViaWadd[next_client] && g_bPlayArenaSound)
                {
                    PlayArenaSound(next_client);
                    g_bPlayerAddedViaWadd[next_client] = false;
                }
                
                UpdateHudForArena(arena_index);
            } else {
                if (IsValidClient(foe) && IsFakeClient(foe))
                {
                    ConVar cvar = FindConVar("tf_bot_quota");
                    int quota = cvar.IntValue;
                    ServerCommand("tf_bot_quota %d", quota - 1);
                }

                if (g_bFourPersonArena[arena_index])
                {
                    Restore2v2WaitingSpectators(arena_index);
                    CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
                }

                g_iArenaStatus[arena_index] = AS_IDLE;
                // Reset duel start time since arena became idle due to insufficient players
                g_iArenaDuelStartTime[arena_index] = 0;

                UpdateHudForArena(arena_index);
                return;
            }
        }
    }

    else
    {
        if (player_slot == SLOT_ONE || player_slot == SLOT_TWO)
        {
            int foe_slot = player_slot == SLOT_ONE ? SLOT_TWO : SLOT_ONE;
            int foe = g_iArenaQueue[arena_index][foe_slot];

            if (g_bArenaBBall[arena_index])
            {
                if (IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > 0)
                {
                    RemoveEdict(g_iBBallIntel[arena_index]);
                    g_iBBallIntel[arena_index] = -1;
                }

                RemoveClientParticle(client);
                g_bPlayerHasIntel[client] = false;

                if (foe)
                {
                    RemoveClientParticle(foe);
                    g_bPlayerHasIntel[foe] = false;
                }
            }

            if (g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED && calcstats && !g_bNoStats && IsValidClient(foe))
            {
                char foe_name[MAX_NAME_LENGTH];
                char player_name[MAX_NAME_LENGTH];
                GetClientName(foe, foe_name, sizeof(foe_name));
                GetClientName(client, player_name, sizeof(player_name));

                g_iArenaStatus[arena_index] = AS_REPORTED;

                if (g_iArenaScore[arena_index][foe_slot] > g_iArenaScore[arena_index][player_slot])
                {
                    if (g_iArenaScore[arena_index][foe_slot] >= g_iArenaEarlyLeave[arena_index])
                    {
                        CalcELO(foe, client);
                        // Calculate duel duration
                        char duel_time[32] = "";
                        if (g_iArenaDuelStartTime[arena_index] > 0)
                        {
                            int currentTime = GetTime();
                            int elapsedTime = currentTime - g_iArenaDuelStartTime[arena_index];
                            int minutes = elapsedTime / 60;
                            int seconds = elapsedTime % 60;
                            Format(duel_time, sizeof(duel_time), "%02dм %02dс", minutes, seconds);
                        }

                        MC_PrintToChatAll("%t", "XdefeatsYearly", foe_name, g_iArenaScore[arena_index][foe_slot], player_name, g_iArenaScore[arena_index][player_slot], g_sArenaName[arena_index], duel_time);
                    }
                }
            }

            if (g_iArenaQueue[arena_index][SLOT_TWO + 1])
            {
                int next_client = g_iArenaQueue[arena_index][SLOT_TWO + 1];
                g_iArenaQueue[arena_index][SLOT_TWO + 1] = 0;
                g_iArenaQueue[arena_index][player_slot] = next_client;
                g_iPlayerSlot[next_client] = player_slot;
                after_leaver_slot = SLOT_TWO + 2;
                char playername[MAX_NAME_LENGTH];
                CreateTimer(2.0, Timer_StartDuel, arena_index);
                GetClientName(next_client, playername, sizeof(playername));

                SendArenaJoinMessage(playername, g_iPlayerRating[next_client], g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[next_client], IsPlayerEligibleForElo(next_client));
                
                // Play sound if player was added via wadd
                if (g_bPlayerAddedViaWadd[next_client] && g_bPlayArenaSound)
                {
                    PlayArenaSound(next_client);
                    g_bPlayerAddedViaWadd[next_client] = false;
                }
                
                UpdateHudForArena(arena_index);
            } else {
                if (IsValidClient(foe) && IsFakeClient(foe))
                {
                    ConVar cvar = FindConVar("tf_bot_quota");
                    int quota = cvar.IntValue;
                    ServerCommand("tf_bot_quota %d", quota - 1);
                }

                g_iArenaStatus[arena_index] = AS_IDLE;
                // Reset duel start time since arena became idle due to insufficient players
                g_iArenaDuelStartTime[arena_index] = 0;

                UpdateHudForArena(arena_index);
                return;
            }
        }
    }
    if (g_iArenaQueue[arena_index][after_leaver_slot])
    {
        while (g_iArenaQueue[arena_index][after_leaver_slot])
        {
            g_iArenaQueue[arena_index][after_leaver_slot - 1] = g_iArenaQueue[arena_index][after_leaver_slot];
            g_iPlayerSlot[g_iArenaQueue[arena_index][after_leaver_slot]] -= 1;
            after_leaver_slot++;
        }
        g_iArenaQueue[arena_index][after_leaver_slot - 1] = 0;
    }
    
    UpdateHudForArena(arena_index);

    // Check if we should auto-add players from waiting list
    CheckWaitingList(arena_index);

    // Call OnPlayerArenaRemoved forward
    CallForward_OnPlayerArenaRemoved(client, arena_index);
}

// Check and auto-add players from waiting list when arena becomes available
void CheckWaitingList(int arena_index)
{
    if (g_alArenaWaitingList[arena_index] == null || g_alArenaWaitingList[arena_index].Length == 0)
        return;

    // Add players from waiting list when arena has at least one player
    int player_count = 0;
    int slot_one = g_iArenaQueue[arena_index][SLOT_ONE];
    int slot_two = g_iArenaQueue[arena_index][SLOT_TWO];
    
    if (slot_one) player_count++;
    if (slot_two) player_count++;
    
    if (g_bFourPersonArena[arena_index])
    {
        int slot_three = g_iArenaQueue[arena_index][SLOT_THREE];
        int slot_four = g_iArenaQueue[arena_index][SLOT_FOUR];
        if (slot_three) player_count++;
        if (slot_four) player_count++;
    }
    
    // Add all players from waiting list when arena has at least one player
    bool should_add_players = (player_count >= 1) && (g_alArenaWaitingList[arena_index].Length > 0);

    while (should_add_players && g_alArenaWaitingList[arena_index].Length > 0)
    {
        // Get first player from waiting list
        int waiting_player = g_alArenaWaitingList[arena_index].Get(0);
        g_alArenaWaitingList[arena_index].Erase(0);

        if (IsValidClient(waiting_player) && g_iPlayerArena[waiting_player] == 0)
        {
            // Check if player was added via wadd and play sound if needed
            bool was_wadd_player = g_bPlayerAddedViaWadd[waiting_player];

            // Add player to arena
            AddInQueue(waiting_player, arena_index, true);

            // Play sound if player was added via wadd
            if (was_wadd_player && g_bPlayArenaSound)
            {
                PlayArenaSound(waiting_player);
                g_bPlayerAddedViaWadd[waiting_player] = false;
            }

            MC_PrintToChat(waiting_player, "%t", "AutoJoinedArena", g_sArenaName[arena_index]);
        }
        else
        {
            // If the player is invalid or already in an arena, just remove from waiting list
            g_bPlayerAddedViaWadd[waiting_player] = false;
            continue;
        }
    }
}

// Play sound for player joining arena automatically
void PlayArenaSound(int client)
{
    if (!IsValidClient(client))
        return;

    Handle setup = CreateKeyValues("data");
    KvSetString(setup, "title", "Arena Join");
    KvSetNum(setup, "type", MOTDPANEL_TYPE_URL);
    KvSetString(setup, "msg", "https://progameszet.ru/Announcer_am_roundstart03.mp3");
    ShowVGUIPanel(client, "info", setup, false);
    CloseHandle(setup);
}

// Add player to arena queue with team preference and menu options
void AddInQueue(int client, int arena_index, bool showmsg = true, int playerPrefTeam = 0, bool show2v2Menu = true, int forcedSlot = 0)
{
    if (!IsValidClient(client))
        return;

    // Handle case where player is already in an arena
    if (g_iPlayerArena[client])
    {
        if (g_iPlayerArena[client] == arena_index)
        {
            // Player is re-selecting the same arena
            if (g_bFourPersonArena[arena_index] && playerPrefTeam == 0 && show2v2Menu)
            {
                Show2v2SelectionMenu(client, arena_index);
                return;
            }
            else if (show2v2Menu && playerPrefTeam == 0)
            {
                MC_PrintToChat(client, "%t", "AlreadyInArena", g_sArenaName[arena_index]);
                return;
            }
            // Intentional action (team switch / re-slot) within same arena: clear old slot now
            if (g_iPlayerSlot[client] != 0)
            {
                g_iArenaQueue[g_iPlayerArena[client]][g_iPlayerSlot[client]] = 0;
            }
        }
    }

    // Show 2v2 selection menu if this is a 2v2 arena and no team preference is set
    // Only show menu if there are available main slots (not all 4 slots filled)
    if (g_bFourPersonArena[arena_index] && playerPrefTeam == 0 && show2v2Menu)
    {
        // Check if all main slots are filled
        bool allSlotsFilled = g_iArenaQueue[arena_index][SLOT_ONE] && 
                             g_iArenaQueue[arena_index][SLOT_TWO] && 
                             g_iArenaQueue[arena_index][SLOT_THREE] && 
                             g_iArenaQueue[arena_index][SLOT_FOUR];
        
        if (!allSlotsFilled)
        {
            // Show menu using pending arena context
            g_iPendingArena[client] = arena_index;
            Show2v2SelectionMenu(client, arena_index);
            return;
        }
        // If all slots filled, continue to regular queue logic
    }

    // Assign queue slot considering VIP priority and insert into queue
    int player_slot = AssignQueueSlotAndInsert(client, arena_index, playerPrefTeam, forcedSlot);
    if (player_slot == 0)
    {
        // Slot assignment failed (invalid or occupied forced slot)
        if (showmsg)
        {
            if (forcedSlot > 0)
            {
                if (!IsValidSlotForArena(arena_index, forcedSlot))
                {
                    if (g_bFourPersonArena[arena_index])
                        MC_PrintToChat(client, "[MGE] Invalid slot %d for 2v2 arena (valid slots: 1-4)", forcedSlot);
                    else
                        MC_PrintToChat(client, "[MGE] Invalid slot %d for 1v1 arena (valid slots: 1-2)", forcedSlot);
                }
                else
                {
                    MC_PrintToChat(client, "[MGE] Slot %d is already occupied", forcedSlot);
                }
            }
        }
        return;
    }

    // Validate ELO authentication before allowing arena join
    char reason[128];
    if (!IsPlayerEloValid(client, reason, sizeof(reason)))
    {
        if (showmsg)
            MC_PrintToChat(client, "%t", "CannotJoinArena", reason);
        return;
    }
    
    // If committing to a different arena now, cleanly remove from current first
    if (g_iPlayerArena[client] && g_iPlayerArena[client] != arena_index)
    {
        RemoveFromQueue(client, true);
    }
    
    // Call OnPlayerArenaAdd forward - allow blocking
    Action result = CallForward_OnPlayerArenaAdd(client, arena_index, player_slot);
    if (result >= Plugin_Handled)
        return;
    
    g_iPlayerArena[client] = arena_index;
    g_iPlayerSlot[client] = player_slot;
    g_iArenaQueue[arena_index][player_slot] = client;

    // Update keyhint immediately when queue changes
    UpdateQueueKeyHintText(arena_index);
    
    // Call OnPlayerArenaAdded forward
    CallForward_OnPlayerArenaAdded(client, arena_index, player_slot);

    SetPlayerToAllowedClass(client, arena_index);

    if (showmsg)
    {
        MC_PrintToChat(client, "%t", "ChoseArena", g_sArenaName[arena_index]);
    }
    if (g_bFourPersonArena[arena_index])
    {
        if (player_slot <= SLOT_FOUR)
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(client, name, sizeof(name));

            SendArenaJoinMessage(name, g_iPlayerRating[client], g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[client], IsPlayerEligibleForElo(client));

            // Play sound if player was added via wadd
            if (g_bPlayerAddedViaWadd[client] && g_bPlayArenaSound)
            {
                PlayArenaSound(client);
                g_bPlayerAddedViaWadd[client] = false;
            }

            // Check if we have exactly 2 players per team for 2v2 match
            int red_count = 0;
            int blu_count = 0;
            for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
            {
                if (g_iArenaQueue[arena_index][i])
                {
                    if (i == SLOT_ONE || i == SLOT_THREE)
                        red_count++;
                    else
                        blu_count++;
                }
            }
            
            if (red_count == 2 && blu_count == 2)
            {
                // Transition to ready waiting state instead of immediately starting
                Start2v2ReadySystem(arena_index);
            }
            else
                CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
        } else {
            if (GetClientTeam(client) != TEAM_SPEC)
                ChangeClientTeam(client, TEAM_SPEC);
            if (player_slot == SLOT_FOUR + 1)
                MC_PrintToChat(client, "%t", "NextInLine");
            else
                MC_PrintToChat(client, "%t", "InLine", player_slot - SLOT_FOUR);
        }
    }
    else
    {
        if (player_slot <= SLOT_TWO)
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(client, name, sizeof(name));

            SendArenaJoinMessage(name, g_iPlayerRating[client], g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[client], IsPlayerEligibleForElo(client));

            // Play sound if player was added via wadd
            if (g_bPlayerAddedViaWadd[client] && g_bPlayArenaSound)
            {
                PlayArenaSound(client);
                g_bPlayerAddedViaWadd[client] = false;
            }

            if (g_iArenaQueue[arena_index][SLOT_ONE] && g_iArenaQueue[arena_index][SLOT_TWO])
            {
                CreateTimer(1.5, Timer_StartDuel, arena_index);
            } else
                CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
        } else {
            if (GetClientTeam(client) != TEAM_SPEC)
                ChangeClientTeam(client, TEAM_SPEC);
            if (player_slot == SLOT_TWO + 1)
                MC_PrintToChat(client, "%t", "NextInLine");
            else
                MC_PrintToChat(client, "%t", "InLine", player_slot - SLOT_TWO);
        }
    }

    UpdateHudForArena(arena_index);

    // Check if we should add players from waiting list after successful join
    // Only check if the joining player was added to main slots (not waiting queue)
    if (player_slot <= SLOT_TWO || (g_bFourPersonArena[arena_index] && player_slot <= SLOT_FOUR))
    {
        CheckWaitingList(arena_index);
    }

    return;
}

// ===== MATCH FLOW CONTROL =====

// Initialize countdown sequence and prepare arena for match start
int StartCountDown(int arena_index)
{
    int red_f1 = g_iArenaQueue[arena_index][SLOT_ONE]; /* Red (slot one) player. */
    int blu_f1 = g_iArenaQueue[arena_index][SLOT_TWO]; /* Blu (slot two) player. */

    // Remove all projectiles from previous round
    if (g_bClearProjectiles && g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaBBall[arena_index])
        RemoveArenaProjectiles(arena_index);

    if (g_bFourPersonArena[arena_index])
    {
        int red_f2 = g_iArenaQueue[arena_index][SLOT_THREE]; /* 2nd Red (slot three) player. */
        int blu_f2 = g_iArenaQueue[arena_index][SLOT_FOUR]; /* 2nd Blu (slot four) player. */

        if (red_f1)
            ResetPlayer(red_f1);
        if (blu_f1)
            ResetPlayer(blu_f1);
        if (red_f2)
            ResetPlayer(red_f2);
        if (blu_f2)
            ResetPlayer(blu_f2);


        if (red_f1 && blu_f1 && red_f2 && blu_f2)
        {
            // Store player classes for duel tracking
            g_tfctPlayerDuelClass[red_f1] = g_tfctPlayerClass[red_f1];
            g_tfctPlayerDuelClass[blu_f1] = g_tfctPlayerClass[blu_f1];
            g_tfctPlayerDuelClass[red_f2] = g_tfctPlayerClass[red_f2];
            g_tfctPlayerDuelClass[blu_f2] = g_tfctPlayerClass[blu_f2];
            
            // Initialize class tracking lists for dynamic recording
            if (g_bArenaClassChange[arena_index])
            {
                // Ensure ArrayLists are initialized for all players (including bots)
                if (g_alPlayerDuelClasses[red_f1] == null)
                    g_alPlayerDuelClasses[red_f1] = new ArrayList();
                if (g_alPlayerDuelClasses[blu_f1] == null)
                    g_alPlayerDuelClasses[blu_f1] = new ArrayList();
                if (g_alPlayerDuelClasses[red_f2] == null)
                    g_alPlayerDuelClasses[red_f2] = new ArrayList();
                if (g_alPlayerDuelClasses[blu_f2] == null)
                    g_alPlayerDuelClasses[blu_f2] = new ArrayList();
                    
                g_alPlayerDuelClasses[red_f1].Clear();
                g_alPlayerDuelClasses[blu_f1].Clear();
                g_alPlayerDuelClasses[red_f2].Clear();
                g_alPlayerDuelClasses[blu_f2].Clear();
                
                g_alPlayerDuelClasses[red_f1].Push(view_as<int>(g_tfctPlayerClass[red_f1]));
                g_alPlayerDuelClasses[blu_f1].Push(view_as<int>(g_tfctPlayerClass[blu_f1]));
                g_alPlayerDuelClasses[red_f2].Push(view_as<int>(g_tfctPlayerClass[red_f2]));
                g_alPlayerDuelClasses[blu_f2].Push(view_as<int>(g_tfctPlayerClass[blu_f2]));
            }
            
            float enginetime = GetGameTime();

            for (int i = 0; i <= 2; i++)
            {
                int ent = GetPlayerWeaponSlot(red_f1, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);

                ent = GetPlayerWeaponSlot(blu_f1, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);

                ent = GetPlayerWeaponSlot(red_f2, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);

                ent = GetPlayerWeaponSlot(blu_f2, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);
            }

            g_iArenaCd[arena_index] = g_iArenaCdTime[arena_index] + 1;
            g_iArenaStatus[arena_index] = AS_PRECOUNTDOWN;
            CreateTimer(0.1, Timer_CountDown, arena_index, TIMER_FLAG_NO_MAPCHANGE);
            return 1;
        } else {
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            g_iArenaStatus[arena_index] = AS_IDLE;
            // Reset duel start time since there are not enough players to continue
            g_iArenaDuelStartTime[arena_index] = 0;
            return 0;
        }
    }
    else {
        if (red_f1)
            ResetPlayer(red_f1);
        if (blu_f1)
            ResetPlayer(blu_f1);

        if (red_f1 && blu_f1)
        {
            // Store player classes for duel tracking
            g_tfctPlayerDuelClass[red_f1] = g_tfctPlayerClass[red_f1];
            g_tfctPlayerDuelClass[blu_f1] = g_tfctPlayerClass[blu_f1];
            
            // Initialize class tracking lists for dynamic recording
            if (g_bArenaClassChange[arena_index])
            {
                // Ensure ArrayLists are initialized for all players (including bots)
                if (g_alPlayerDuelClasses[red_f1] == null)
                    g_alPlayerDuelClasses[red_f1] = new ArrayList();
                if (g_alPlayerDuelClasses[blu_f1] == null)
                    g_alPlayerDuelClasses[blu_f1] = new ArrayList();
                    
                g_alPlayerDuelClasses[red_f1].Clear();
                g_alPlayerDuelClasses[blu_f1].Clear();
                
                g_alPlayerDuelClasses[red_f1].Push(view_as<int>(g_tfctPlayerClass[red_f1]));
                g_alPlayerDuelClasses[blu_f1].Push(view_as<int>(g_tfctPlayerClass[blu_f1]));
            }
            
            float enginetime = GetGameTime();

            for (int i = 0; i <= 2; i++)
            {
                int ent = GetPlayerWeaponSlot(red_f1, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);

                ent = GetPlayerWeaponSlot(blu_f1, i);

                if (IsValidEntity(ent))
                    SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + 1.1);
            }

            g_iArenaCd[arena_index] = g_iArenaCdTime[arena_index] + 1;
            g_iArenaStatus[arena_index] = AS_PRECOUNTDOWN;
            CreateTimer(0.1, Timer_CountDown, arena_index, TIMER_FLAG_NO_MAPCHANGE);
            return 1;
        }
        else
        {
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            g_iArenaStatus[arena_index] = AS_IDLE;
            // Reset duel start time since there are not enough players to continue
            g_iArenaDuelStartTime[arena_index] = 0;
            return 0;
        }
    }
}


// ===== GAME MECHANICS =====

// Play appropriate victory/defeat sounds to all players in an arena
void PlayEndgameSoundsToArena(any arena_index, any winner_team)
{
    int red_1 = g_iArenaQueue[arena_index][SLOT_ONE];
    int blu_1 = g_iArenaQueue[arena_index][SLOT_TWO];
    char SoundFileBlu[124];
    char SoundFileRed[124];

    // If the red team won
    if (winner_team == 1)
    {
        SoundFileRed = "vo/announcer_victory.mp3";
        SoundFileBlu = "vo/announcer_you_failed.mp3";
    }
    // Else the blu team won
    else
    {
        SoundFileBlu = "vo/announcer_victory.mp3";
        SoundFileRed = "vo/announcer_you_failed.mp3";
    }
    if (IsValidClient(red_1))
        EmitSoundToClient(red_1, SoundFileRed);

    if (IsValidClient(blu_1))
        EmitSoundToClient(blu_1, SoundFileBlu);

    if (g_bFourPersonArena[arena_index])
    {
        int red_2 = g_iArenaQueue[arena_index][SLOT_THREE];
        int blu_2 = g_iArenaQueue[arena_index][SLOT_FOUR];
        if (g_iCappingTeam[arena_index] == TEAM_BLU)
        {
            if (IsValidClient(red_2))
                EmitSoundToClient(red_2, SoundFileRed);
        }
        else
        {
            if (IsValidClient(blu_2))
                EmitSoundToClient(blu_2, SoundFileBlu);
        }
    }
}


// ===== UI AND MENUS =====

// Display main arena selection menu with player listings and options
void ShowMainMenu(int client, bool listplayers = true)
{
    if (!IsValidClient(client))
        return;

    char title[128];
    char menu_item[128];

    Menu menu = new Menu(Menu_Main);

    Format(title, sizeof(title), "%T", "MenuTitle", client);
    menu.SetTitle(title);
    char si[4];

    for (int i = 1; i <= g_iArenaCount; i++)
    {
        // Count total players in the arena regardless of slot order
        int totalPlayers = 0;
        for (int NUM = 1; NUM <= MAXPLAYERS; NUM++)
        {
            if (g_iArenaQueue[i][NUM] != 0)
            {
                totalPlayers++;
            }
        }

        // Cap active players shown based on arena type (1v1:2, 2v2:4)
        int cap = g_bFourPersonArena[i] ? 4 : 2;
        int active = (totalPlayers < cap) ? totalPlayers : cap;
        int waiting = (totalPlayers > cap) ? (totalPlayers - cap) : 0;

        if (waiting > 0)
            Format(menu_item, sizeof(menu_item), "%s (%d)(%d)", g_sArenaName[i], active, waiting);
        else if (active > 0)
            Format(menu_item, sizeof(menu_item), "%s (%d)", g_sArenaName[i], active);
        else
            Format(menu_item, sizeof(menu_item), "%s", g_sArenaName[i]);

        IntToString(i, si, sizeof(si));
        menu.AddItem(si, menu_item);
    }

    Format(menu_item, sizeof(menu_item), "%T", "MenuRemove", client);
    menu.AddItem("1000", menu_item);

    menu.ExitButton = true;
    menu.Display(client, 0);

    char report[256];

    // Listing players
    if (!listplayers)
        return;

    for (int i = 1; i <= g_iArenaCount; i++)
    {
        int red_f1 = g_iArenaQueue[i][SLOT_ONE];
        int blu_f1 = g_iArenaQueue[i][SLOT_TWO];
        
        // Validate players are still connected
        bool red_valid = (red_f1 > 0 && IsValidClient(red_f1));
        bool blu_valid = (blu_f1 > 0 && IsValidClient(blu_f1));
        
        if (red_valid || blu_valid)
        {
            Format(report, sizeof(report), "\x05%s:", g_sArenaName[i]);

            if (!g_bNoDisplayRating)
            {
                if (red_valid && blu_valid)
                    Format(report, sizeof(report), "%s \x04%N \x03(%d) \x05vs \x04%N (%d) \x05", report, red_f1, g_iPlayerRating[red_f1], blu_f1, g_iPlayerRating[blu_f1]);
                else if (red_valid)
                    Format(report, sizeof(report), "%s \x04%N (%d)\x05", report, red_f1, g_iPlayerRating[red_f1]);
                else if (blu_valid)
                    Format(report, sizeof(report), "%s \x04%N (%d)\x05", report, blu_f1, g_iPlayerRating[blu_f1]);
            } else {
                if (red_valid && blu_valid)
                    Format(report, sizeof(report), "%s \x04%N \x05vs \x04%N \x05", report, red_f1, blu_f1);
                else if (red_valid)
                    Format(report, sizeof(report), "%s \x04%N \x05", report, red_f1);
                else if (blu_valid)
                    Format(report, sizeof(report), "%s \x04%N \x05", report, blu_f1);
            }

            if (g_iArenaQueue[i][SLOT_TWO + 1])
            {
                Format(report, sizeof(report), "%s Waiting: ", report);
                int j = SLOT_TWO + 1;
                while (g_iArenaQueue[i][j + 1])
                {
                    if (IsValidClient(g_iArenaQueue[i][j]))
                        Format(report, sizeof(report), "%s\x04%N \x05, ", report, g_iArenaQueue[i][j]);
                    j++;
                }
                if (IsValidClient(g_iArenaQueue[i][j]))
                    Format(report, sizeof(report), "%s\x04%N", report, g_iArenaQueue[i][j]);
            }
            PrintToChat(client, "%s", report);
        }
    }
}

// Handle main menu selections and navigation logic
int Menu_Main(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1;
            if (!client)return 0;
            char capt[32];
            char sanum[32];

            menu.GetItem(param2, sanum, sizeof(sanum), _, capt, sizeof(capt));
            int arena_index = StringToInt(sanum);

            if (arena_index > 0 && arena_index <= g_iArenaCount)
            {
                char reason[128];
                if (!IsPlayerEloValid(client, reason, sizeof(reason)))
                {
                    MC_PrintToChat(client, "%t", "CannotJoinArena", reason);
                    return 0;
                }
                
                // Checking rating (but allow re-selection of same arena)
                if (arena_index != g_iPlayerArena[client])
                {
                    int playerrating = g_iPlayerRating[client];
                    int minrating = g_iArenaMinRating[arena_index];
                    int maxrating = g_iArenaMaxRating[arena_index];

                    if (minrating > 0 && playerrating < minrating)
                    {
                        MC_PrintToChat(client, "%t", "LowRating", playerrating, minrating);
                        ShowMainMenu(client, false);
                        return 0;
                    } else if (maxrating > 0 && playerrating > maxrating) {
                        MC_PrintToChat(client, "%t", "HighRating", playerrating, maxrating);
                        ShowMainMenu(client, false);
                        return 0;
                    }
                }
                // Always call AddInQueue - it handles re-selection logic internally
                AddInQueue(client, arena_index);

            } else {
                RemoveFromQueue(client, true);
            }
        }
        case MenuAction_Cancel:
        {
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}


// ===== MESSAGING SYSTEM =====

// Send formatted join message with player rating and arena information
void SendArenaJoinMessage(const char[] playername, int player_rating, const char[] arena_name, bool show_elo, bool is_verified = true)
{
    for (int i = 1; i <= MaxClients; ++i)
    {
        if (!IsClientInGame(i))
            continue;
            
        if (show_elo && g_bShowElo[i] && is_verified)
            MC_PrintToChat(i, "%t", "JoinsArena", playername, player_rating, arena_name);
        else
            MC_PrintToChat(i, "%t", "JoinsArenaNoStats", playername, arena_name);
    }
}

// Send formatted message to all players in a specific arena
void PrintToChatArena(int arena_index, const char[] message, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), message, 3);
    
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client)
        {
            PrintToChat(client, buffer);
        }
    }
}


// ===== COMMANDS =====

// Display arena selection menu to players
Action Command_Menu(int client, int args)
{
    // Handle commands "!ammomod" "!add" and such // Building queue's menu and listing arena's
    int playerPrefTeam = 0;

    if (!IsValidClient(client))
        return Plugin_Continue;

    // Check cooldown for add command (2 seconds)
    float currentTime = GetGameTime();
    if (currentTime - g_fPlayerAddCooldown[client] < 2.0)
    {
        return Plugin_Handled;
    }
    g_fPlayerAddCooldown[client] = currentTime;

    char sArg[32];
    if (GetCmdArg(1, sArg, sizeof(sArg)) > 0)
    {
        // If they want to add to a color
        char cArg[32];
        if (GetCmdArg(2, cArg, sizeof(cArg)) > 0)
        {
            if (StrContains("blu", cArg, false) >= 0)
            {
                playerPrefTeam = TEAM_BLU;
            }
            else if (StrContains("red", cArg, false) >= 0)
            {
                playerPrefTeam = TEAM_RED;
            }
        }
        
        // Check if the argument starts with @ (target player)
        if (sArg[0] == '@')
        {
            char targetName[32];
            strcopy(targetName, sizeof(targetName), sArg[1]); // Remove the @ prefix
            
            int target = FindTarget(client, targetName, false, false);
            if (target == -1)
            {
                return Plugin_Handled;
            }
            
            int target_arena = g_iPlayerArena[target];
            if (target_arena == 0)
            {
                MC_PrintToChat(client, "%t", "PlayerNotInAnyArena", target);
                return Plugin_Handled;
            }
            
            if (target_arena == g_iPlayerArena[client])
            {
                MC_PrintToChat(client, "%t", "AlreadySameArena", target);
                return Plugin_Handled;
            }
            
            CloseClientMenu(client);
            AddInQueue(client, target_arena, true, playerPrefTeam);
            return Plugin_Handled;
        }
        
        // Was the argument an arena_index number?
        int iArg = StringToInt(sArg);
        if (iArg > 0 && iArg <= g_iArenaCount)
        {
            // Always call AddInQueue - it will handle re-selection logic internally
            CloseClientMenu(client);
            AddInQueue(client, iArg, true, playerPrefTeam);
            return Plugin_Handled;
        }

        // Was the argument an arena name?
        GetCmdArgString(sArg, sizeof(sArg));
        int found_arena;
        for(int i = 1; i <= g_iArenaCount; i++)
        {
            if(StrContains(g_sArenaName[i], sArg, false) >= 0)
            {
                if (g_iArenaStatus[i] == AS_IDLE) {
                    found_arena = i;
                    break;
                }
            }
        }
        // If there was only one string match, and it was a valid match, place the player in that arena if they aren't already in it.
        if (found_arena > 0 && found_arena <= g_iArenaCount && found_arena != g_iPlayerArena[client])
        {
            CloseClientMenu(client);
            AddInQueue(client, found_arena, true, playerPrefTeam);
            return Plugin_Handled;
        }
    }

    // Couldn't find a matching arena for the argument.
    ShowMainMenu(client);
    return Plugin_Handled;
}

// Check if arena has any players in main slots
/*
bool IsArenaEmpty(int arena_index)
{
    if (g_bFourPersonArena[arena_index])
    {
        // For 2v2: check all 4 main slots
        return !g_iArenaQueue[arena_index][SLOT_ONE] && 
               !g_iArenaQueue[arena_index][SLOT_TWO] && 
               !g_iArenaQueue[arena_index][SLOT_THREE] && 
               !g_iArenaQueue[arena_index][SLOT_FOUR];
    }
    else
    {
        // For 1v1: check both main slots
        return !g_iArenaQueue[arena_index][SLOT_ONE] && 
               !g_iArenaQueue[arena_index][SLOT_TWO];
    }
}
*/

// Add player to waiting list for arena or directly to arena if players exist
Action Command_Wadd(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    // If no arguments, show menu
    if (args == 0)
    {
        ShowMainMenu(client);
        return Plugin_Handled;
    }

    char sArg[32];
    GetCmdArg(1, sArg, sizeof(sArg));

    int arena_index = -1;

    // Try to parse as arena number
    int iArg = StringToInt(sArg);
    if (iArg > 0 && iArg <= g_iArenaCount)
    {
        arena_index = iArg;
    }
    else
    {
        // Try to find by arena name
        for(int i = 1; i <= g_iArenaCount; i++)
        {
            if(StrContains(g_sArenaName[i], sArg, false) >= 0)
            {
                if (g_iArenaStatus[i] == AS_IDLE) {
                    arena_index = i;
                    break;
                }
            }
        }
    }

    if (arena_index <= 0 || arena_index > g_iArenaCount)
    {
        MC_PrintToChat(client, "%t", "ArenaNotFound");
        ShowMainMenu(client);
        return Plugin_Handled;
    }

    // Check if player is already in waiting list for this arena
    if (g_alArenaWaitingList[arena_index].FindValue(client) != -1)
    {
        MC_PrintToChat(client, "%t", "AlreadyInWaitingList", g_sArenaName[arena_index]);
        return Plugin_Handled;
    }

    // Check if player is already in an arena
    if (g_iPlayerArena[client])
    {
        MC_PrintToChat(client, "%t", "AlreadyInArena");
        return Plugin_Handled;
    }

    // Count current players on arena
    int player_count = 0;
    if (g_iArenaQueue[arena_index][SLOT_ONE]) player_count++;
    if (g_iArenaQueue[arena_index][SLOT_TWO]) player_count++;

    if (g_bFourPersonArena[arena_index])
    {
        if (g_iArenaQueue[arena_index][SLOT_THREE]) player_count++;
        if (g_iArenaQueue[arena_index][SLOT_FOUR]) player_count++;
    }

    // If arena is empty, add to waiting list
    if (player_count == 0)
    {
        g_alArenaWaitingList[arena_index].Push(client);
        g_bPlayerAddedViaWadd[client] = true;
        MC_PrintToChat(client, "%t", "AddedToWaitingList");
        ShowMainMenu(client);
        return Plugin_Handled;
    }

    // If arena has players, add directly like normal add command
    CloseClientMenu(client);
    AddInQueue(client, arena_index, true);
    return Plugin_Handled;
}

// Remove player from current arena queue or waiting list
Action Command_Remove(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    // First check if player is in waiting list for any arena
    for (int i = 1; i <= g_iArenaCount; i++)
    {
        int index = g_alArenaWaitingList[i].FindValue(client);
        if (index != -1)
        {
            g_alArenaWaitingList[i].Erase(index);
            g_bPlayerAddedViaWadd[client] = false;
            MC_PrintToChat(client, "%t", "RemovedFromWaitingList");
            return Plugin_Handled;
        }
    }

    // If not in waiting list, remove from arena
    RemoveFromQueue(client, true);
    return Plugin_Handled;
}

// Move player to first position in arena queue
Action Command_First(int client, int args)
{
    if (!client || !IsValidClient(client))
        return Plugin_Continue;

    // Try to find an arena with one person in the queue..
    for (int i = 1; i <= g_iArenaCount; i++)
    {
        if (!g_iArenaQueue[i][SLOT_TWO] && g_iPlayerArena[client] != i)
        {
            if (g_iArenaQueue[i][SLOT_ONE])
            {
                CloseClientMenu(client);
                AddInQueue(client, i, true);
                return Plugin_Handled;
            }
        }
    }

    // Couldn't find an arena with only one person in the queue, so find one with none.
    if (!g_iPlayerArena[client])
    {
        for (int i = 1; i <= g_iArenaCount; i++)
        {
            if (!g_iArenaQueue[i][SLOT_TWO] && g_iPlayerArena[client] != i)
            {
                CloseClientMenu(client);
                AddInQueue(client, i, true);
                return Plugin_Handled;
            }
        }
    }

    // Couldn't find any empty or half-empty arenas, so display the menu.
    ShowMainMenu(client);
    return Plugin_Handled;
}

// Switch current arena to 1v1 MGE mode
Action Command_OneVsOne(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index) {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    if (!g_bFourPersonArena[arena_index]) {
        MC_PrintToChat(client, "%t", "ArenaAlready1v1");
        return Plugin_Handled;
    }

    if (!g_bArenaAllowChange[arena_index]) {
        MC_PrintToChat(client, "%t", "Cannot1v1InArena");
        return Plugin_Handled;
    }

    if (g_iArenaStatus[arena_index] != AS_IDLE) {
        MC_PrintToChat(client, "%t", "CannotSwitch1v1Now");
        return Plugin_Handled;
    }

    if(g_iArenaQueue[arena_index][SLOT_THREE] || g_iArenaQueue[arena_index][SLOT_FOUR]) {
        MC_PrintToChat(client, "%t", "MoreThan2Players");
        return Plugin_Handled;
    }

    g_bFourPersonArena[arena_index] = false;
    g_iArenaCdTime[arena_index] = DEFAULT_COUNTDOWN_TIME;
    CreateTimer(1.5, Timer_StartDuel, arena_index);
    UpdateArenaName(arena_index);

    if(g_iArenaQueue[arena_index][SLOT_ONE]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_ONE], "%t", "ChangedArenaTo1v1");
    }

    if(g_iArenaQueue[arena_index][SLOT_TWO]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_TWO], "%t", "ChangedArenaTo1v1");
    }

    return Plugin_Handled;
}

// Switch current arena to 2v2 team mode
Action Command_TwoVsTwo(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index) {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    if(g_bFourPersonArena[arena_index]) {
        MC_PrintToChat(client, "%t", "ArenaAlready2v2");
        return Plugin_Handled;
    }

    if (!g_bArenaAllowChange[arena_index]) {
        MC_PrintToChat(client, "%t", "Cannot2v2InArena");
        return Plugin_Handled;
    }

    if (g_iArenaStatus[arena_index] != AS_IDLE) {
        MC_PrintToChat(client, "%t", "CannotSwitch2v2Now");
        return Plugin_Handled;
    }

    g_bFourPersonArena[arena_index] = true;
    g_iArenaCdTime[arena_index] = 0;
    CreateTimer(1.5, Timer_StartDuel, arena_index);
    UpdateArenaName(arena_index);

    if(g_iArenaQueue[arena_index][SLOT_ONE]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_ONE], "%t", "ChangedArenaTo2v2");
    }

    if(g_iArenaQueue[arena_index][SLOT_TWO]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_TWO], "%t", "ChangedArenaTo2v2");
    }

    return Plugin_Handled;
}

// Switch current arena to standard MGE mode
Action Command_Mge(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index) {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    if (g_bArenaMGE[arena_index]) {
        MC_PrintToChat(client, "%t", "ArenaAlreadyMGE");
        return Plugin_Handled;
    }

    g_bArenaKoth[arena_index] = false;
    g_bArenaMGE[arena_index] = true;
    g_fArenaRespawnTime[arena_index] = 0.2;
    g_iArenaFraglimit[arena_index] = g_iArenaMgelimit[arena_index];
    CreateTimer(1.5, Timer_StartDuel, arena_index);
    UpdateArenaName(arena_index);

    if(g_iArenaQueue[arena_index][SLOT_ONE]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_ONE], "%t", "ChangedArenaToMGE");
    }

    if(g_iArenaQueue[arena_index][SLOT_TWO]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_TWO], "%t", "ChangedArenaToMGE");
    }

    return Plugin_Handled;
}

// Add bot player to arena queue for testing purposes
Action Command_AddBot(int client, int args)
{  
    // Adding bot to client's arena
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];

    if (arena_index && (player_slot == SLOT_ONE || player_slot == SLOT_TWO || (g_bFourPersonArena[arena_index] && (player_slot == SLOT_THREE || player_slot == SLOT_FOUR))))
    {
        ServerCommand("tf_bot_add");
        g_bPlayerAskedForBot[client] = true;
    }
    return Plugin_Handled;
}


// ===== TIMER CALLBACKS =====

// Handle countdown timer progression and match preparation
Action Timer_CountDown(Handle timer, any arena_index)
{
    int red_f1 = g_iArenaQueue[arena_index][SLOT_ONE];
    int blu_f1 = g_iArenaQueue[arena_index][SLOT_TWO];
    int red_f2;
    int blu_f2;
    if (g_bFourPersonArena[arena_index])
    {
        red_f2 = g_iArenaQueue[arena_index][SLOT_THREE];
        blu_f2 = g_iArenaQueue[arena_index][SLOT_FOUR];
    }
    if (g_bFourPersonArena[arena_index])
    {
        if (red_f1 && blu_f1 && red_f2 && blu_f2)
        {
            g_iArenaCd[arena_index]--;

            if (g_iArenaCd[arena_index] > 0)
            {  // Blocking +attack
                float enginetime = GetGameTime();

                for (int i = 0; i <= 2; i++)
                {
                    int ent = GetPlayerWeaponSlot(red_f1, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));

                    ent = GetPlayerWeaponSlot(blu_f1, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));

                    ent = GetPlayerWeaponSlot(red_f2, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));

                    ent = GetPlayerWeaponSlot(blu_f2, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));
                }
            }

            if (g_iArenaCd[arena_index] <= 3 && g_iArenaCd[arena_index] >= 1)
            {
                char msg[64];

                switch (g_iArenaCd[arena_index])
                {
                    case 1:msg = "ONE";
                    case 2:msg = "TWO";
                    case 3:msg = "THREE";
                }

                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                PrintCenterText(red_f2, msg);
                PrintCenterText(blu_f2, msg);
                ShowCountdownToSpec(arena_index, msg);
                g_iArenaStatus[arena_index] = AS_COUNTDOWN;
            } else if (g_iArenaCd[arena_index] <= 0) {
                g_iArenaStatus[arena_index] = AS_FIGHT;
                // Set duel start time only if not already set (first round of the duel)
                bool isDuelStart = (g_iArenaDuelStartTime[arena_index] == 0);
                if (isDuelStart)
                    g_iArenaDuelStartTime[arena_index] = GetTime();
                if (isDuelStart)
                    ResetClassPointsForArena(arena_index);
                char msg[64];
                Format(msg, sizeof(msg), "FIGHT", g_iArenaCd[arena_index]);
                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                PrintCenterText(red_f2, msg);
                PrintCenterText(blu_f2, msg);
                ShowCountdownToSpec(arena_index, msg);

                // Call 2v2 match start forward
                CallForward_On2v2MatchStart(arena_index, red_f1, red_f2, blu_f1, blu_f2);
                
                // Call duel start forward only when duel actually starts (first round)
                if (isDuelStart)
                    CallForward_OnDuelStart(arena_index, red_f1, red_f2, blu_f1, blu_f2);

                // For bball.
                if (g_bArenaBBall[arena_index])
                {
                    ResetIntel(arena_index);
                }

                return Plugin_Stop;
            }


            CreateTimer(1.0, Timer_CountDown, arena_index, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            return Plugin_Stop;
        } else {
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            g_iArenaStatus[arena_index] = AS_IDLE;
            g_iArenaCd[arena_index] = 0;
            return Plugin_Stop;
        }
    }
    else
    {
        if (red_f1 && blu_f1)
        {
            g_iArenaCd[arena_index]--;

            if (g_iArenaCd[arena_index] > 0)
            {  // Blocking +attack
                float enginetime = GetGameTime();

                for (int i = 0; i <= 2; i++)
                {
                    int ent = GetPlayerWeaponSlot(red_f1, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));

                    ent = GetPlayerWeaponSlot(blu_f1, i);

                    if (IsValidEntity(ent))
                        SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", enginetime + float(g_iArenaCd[arena_index]));
                }
            }

            if (g_iArenaCd[arena_index] <= 3 && g_iArenaCd[arena_index] >= 1)
            {
                char msg[64];

                switch (g_iArenaCd[arena_index])
                {
                    case 1:msg = "ONE";
                    case 2:msg = "TWO";
                    case 3:msg = "THREE";
                }

                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                ShowCountdownToSpec(arena_index, msg);
                g_iArenaStatus[arena_index] = AS_COUNTDOWN;
            } else if (g_iArenaCd[arena_index] <= 0) {
                g_iArenaStatus[arena_index] = AS_FIGHT;
                // Set duel start time only if not already set (first round of the duel)
                bool isDuelStart = (g_iArenaDuelStartTime[arena_index] == 0);
                if (isDuelStart)
                    g_iArenaDuelStartTime[arena_index] = GetTime();
                if (isDuelStart)
                    ResetClassPointsForArena(arena_index);
                char msg[64];
                Format(msg, sizeof(msg), "FIGHT", g_iArenaCd[arena_index]);
                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                ShowCountdownToSpec(arena_index, msg);

                // Call match start forward
                CallForward_On1v1MatchStart(arena_index, red_f1, blu_f1);
                
                // Call duel start forward only when duel actually starts (first round)
                if (isDuelStart)
                    CallForward_OnDuelStart(arena_index, red_f1, blu_f1, 0, 0);

                // For bball.
                if (g_bArenaBBall[arena_index])
                {
                    ResetIntel(arena_index);
                }
                return Plugin_Stop;
            }

            CreateTimer(1.0, Timer_CountDown, arena_index, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
            return Plugin_Stop;
        } else {
            g_iArenaStatus[arena_index] = AS_IDLE;
            g_iArenaCd[arena_index] = 0;
            return Plugin_Stop;
        }
    }
}

// Initialize duel start sequence and player setup
Action Timer_StartDuel(Handle timer, any arena_index)
{
    // Clear any pending invites when match starts
    for (int i = SLOT_ONE; i <= (g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO); i++)
    {
        int player = g_iArenaQueue[arena_index][i];
        if (player != 0 && IsValidClient(player))
        {
            ClearPlayerInvites(player);
        }
    }
    
    // Clear public invite for this arena when match starts
    g_iPublicInviteArena[arena_index] = 0;
    g_fPublicInviteTime[arena_index] = 0.0;

    ResetArena(arena_index);

    if (g_bArenaTurris[arena_index])
    {
        CreateTimer(5.0, Timer_RegenArena, arena_index, TIMER_REPEAT);
    }
    if (g_bArenaKoth[arena_index])
    {

        g_bPlayerTouchPoint[arena_index][SLOT_ONE] = false;
        g_bPlayerTouchPoint[arena_index][SLOT_TWO] = false;
        g_bPlayerTouchPoint[arena_index][SLOT_THREE] = false;
        g_bPlayerTouchPoint[arena_index][SLOT_FOUR] = false;
        g_iKothTimer[arena_index][0] = 0;
        g_iKothTimer[arena_index][1] = 0;
        g_iKothTimer[arena_index][TEAM_RED] = g_iDefaultCapTime[arena_index];
        g_iKothTimer[arena_index][TEAM_BLU] = g_iDefaultCapTime[arena_index];
        g_iCappingTeam[arena_index] = NEUTRAL;
        g_iPointState[arena_index] = NEUTRAL;
        g_fTotalTime[arena_index] = 0.0;
        g_fCappedTime[arena_index] = 0.0;
        g_fKothCappedPercent[arena_index] = 0.0;
        g_bOvertimePlayed[arena_index][TEAM_RED] = false;
        g_bOvertimePlayed[arena_index][TEAM_BLU] = false;
        g_tKothTimer[arena_index] = CreateTimer(1.0, Timer_CountDownKoth, arena_index, TIMER_REPEAT);
        g_bTimerRunning[arena_index] = true;
    }

    g_iArenaScore[arena_index][SLOT_ONE] = 0;
    g_iArenaScore[arena_index][SLOT_TWO] = 0;
    // Don't reset duel start time here - it should persist across rounds until match completion
    UpdateHudForArena(arena_index);
    
    // Clear 2v2 ready hud text
    Clear2v2ReadyHud(arena_index);

    StartCountDown(arena_index);

    return Plugin_Continue;
}

// Regenerate arena entities and restore initial conditions
Action Timer_RegenArena(Handle timer, any arena_index)
{
    if (g_iArenaStatus[arena_index] != AS_FIGHT)
        return Plugin_Stop;

    int client = g_iArenaQueue[arena_index][SLOT_ONE];
    int client2 = g_iArenaQueue[arena_index][SLOT_TWO];

    if (IsPlayerAlive(client))
    {
        TF2_RegeneratePlayer(client);
        int raised_hp = RoundToNearest(float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]);
        g_iPlayerHP[client] = raised_hp;
        SetEntProp(client, Prop_Data, "m_iHealth", raised_hp);
    }

    if (IsPlayerAlive(client2))
    {
        TF2_RegeneratePlayer(client2);
        int raised_hp2 = RoundToNearest(float(g_iPlayerMaxHP[client2]) * g_fArenaHPRatio[arena_index]);
        g_iPlayerHP[client2] = raised_hp2;
        SetEntProp(client2, Prop_Data, "m_iHealth", raised_hp2);
    }

    if (g_bFourPersonArena[arena_index])
    {
        int client3 = g_iArenaQueue[arena_index][SLOT_THREE];
        int client4 = g_iArenaQueue[arena_index][SLOT_FOUR];
        if (IsPlayerAlive(client3))
        {
            TF2_RegeneratePlayer(client3);
            int raised_hp3 = RoundToNearest(float(g_iPlayerMaxHP[client3]) * g_fArenaHPRatio[arena_index]);
            g_iPlayerHP[client3] = raised_hp3;
            SetEntProp(client3, Prop_Data, "m_iHealth", raised_hp3);
        }
        if (IsPlayerAlive(client4))
        {
            TF2_RegeneratePlayer(client4);
            int raised_hp4 = RoundToNearest(float(g_iPlayerMaxHP[client4]) * g_fArenaHPRatio[arena_index]);
            g_iPlayerHP[client4] = raised_hp4;
            SetEntProp(client4, Prop_Data, "m_iHealth", raised_hp4);
        }
    }

    return Plugin_Continue;
}

// Reset round state and prepare for next round
Action Timer_NewRound(Handle timer, any arena_index)
{
    StartCountDown(arena_index);

    return Plugin_Continue;
}

// Add bot to queue after delay to ensure proper initialization
Action Timer_AddBotInQueue(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int arena_index = pack.ReadCell();
    AddInQueue(client, arena_index);

    return Plugin_Continue;
}

// ===== UTILITIES =====

// Parse comma-separated class list into boolean array for validation
void ParseAllowedClasses(const char[] sList, bool[] output)
{
    int count;
    char a_class[9][9];

    if (strlen(sList) > 0)
    {
        count = ExplodeString(sList, " ", a_class, 9, 9);
    } else {
        char sDefList[128];
        gcvar_allowedClasses.GetString(sDefList, sizeof(sDefList));
        count = ExplodeString(sDefList, " ", a_class, 9, 9);
    }

    for (int i = 1; i <= 9; i++) {
        output[i] = false;
    }

    for (int i = 0; i < count; i++)
    {
        TFClassType c = TF2_GetClass(a_class[i]);

        if (c)
            output[view_as<int>(c)] = true;
    }
}

// Check if an arena can be converted to 1v1 mode and provide reason if not
stock bool CanConvertArenaTo1v1(int arena_index, int client, char[] reason, int reason_size)
{
    if (!g_bArenaAllowChange[arena_index]) {
        Format(reason, reason_size, "arena doesn't allow mode changes");
        return false;
    }
    
    int red_count = 0, blu_count = 0;
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        if (g_iArenaQueue[arena_index][i])
        {
            if (i == SLOT_ONE || i == SLOT_THREE)
                red_count++;
            else
                blu_count++;
        }
    }
    
    int total_players = red_count + blu_count;
    int current_slot = g_iPlayerSlot[client];
    bool already_in_arena = (g_iPlayerArena[client] == arena_index && current_slot >= SLOT_ONE && current_slot <= SLOT_FOUR);
    
    if (already_in_arena)
    {
        if (total_players <= 1)
        {
            return true;
        }
        else if (total_players == 2 && red_count == 1 && blu_count == 1)
        {
            return true;
        }
        else if (total_players == 2)
        {
            Format(reason, reason_size, "both players on same team");
            return false;
        }
        else
        {
            Format(reason, reason_size, "%d players in arena", total_players);
            return false;
        }
    }
    else
    {
        if (total_players == 0)
        {
            return true;
        }
        else if (total_players == 1)
        {
            return true;
        }
        else
        {
            Format(reason, reason_size, "arena not empty");
            return false;
        }
    }
}

// Removes all projectiles shot by players in the specified arena
void RemoveArenaProjectiles(int arena_index)
{
    if (!arena_index)
        return;

    int entity = -1;
    char classname[64];
    
    // Collect entities to remove first, then remove them
    ArrayList entitiesToRemove = new ArrayList();
    
    while ((entity = FindEntityByClassname(entity, "*")) != -1)
    {
        if (!IsValidEntity(entity))
            continue;
            
        GetEntityClassname(entity, classname, sizeof(classname));
        
        if (StrContains(classname, "tf_projectile_", false) == 0)
        {
            // Skip sentry rockets as they don't have m_hThrower property and use different owner system
            if (StrEqual(classname, "tf_projectile_sentryrocket", false))
                continue;
                
            int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
            if (owner == -1)
            {
                // Only try m_hThrower if the property exists and entity is not sentryrocket
                if (HasEntProp(entity, Prop_Send, "m_hThrower"))
                {
                    owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
                }
            }
                
            if (IsValidClient(owner) && g_iPlayerArena[owner] == arena_index)
            {
                entitiesToRemove.Push(entity);
            }
        }
        else if (StrEqual(classname, "tf_ball_ornament", false))
        {
            int owner = -1;
            if (HasEntProp(entity, Prop_Send, "m_hThrower"))
                owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
            if (IsValidClient(owner) && g_iPlayerArena[owner] == arena_index)
            {
                entitiesToRemove.Push(entity);
            }
        }
    }
    
    for (int i = 0; i < entitiesToRemove.Length; i++)
    {
        entity = entitiesToRemove.Get(i);
        if (IsValidEntity(entity))
        {
            RemoveEdict(entity);
        }
    }
    
    delete entitiesToRemove;
}

// ===== ARENA VALIDATION =====

// Validates if a slot is appropriate for an arena type
bool IsValidSlotForArena(int arena_index, int slot)
{
    if (slot < SLOT_ONE || slot > SLOT_FOUR)
        return false;
    
    // For 1v1 arenas, only slots 1-2 are valid
    if (!g_bFourPersonArena[arena_index])
        return (slot == SLOT_ONE || slot == SLOT_TWO);
    
    // For 2v2 arenas, all slots 1-4 are valid
    return true;
}

// ===== ARENA DATA EXTRACTION =====

// Retrieves arena player assignments for external use
void GetArenaPlayers(int arena_index, int &red_f1, int &blu_f1, int &red_f2, int &blu_f2)
{
    red_f1 = g_iArenaQueue[arena_index][SLOT_ONE];
    blu_f1 = g_iArenaQueue[arena_index][SLOT_TWO];
    red_f2 = 0;
    blu_f2 = 0;
    
    if (g_bFourPersonArena[arena_index])
    {
        red_f2 = g_iArenaQueue[arena_index][SLOT_THREE];
        blu_f2 = g_iArenaQueue[arena_index][SLOT_FOUR];
    }
}

// Retrieves basic arena configuration information
void GetArenaBasicInfo(int arena_index, char[] arena_name, int name_size, int &fraglimit, bool &is_2v2, bool &is_bball)
{
    strcopy(arena_name, name_size, g_sArenaName[arena_index]);
    fraglimit = g_iArenaFraglimit[arena_index];
    is_2v2 = g_bFourPersonArena[arena_index];
    is_bball = g_bArenaBBall[arena_index];
}


// ===== INVITE SYSTEM =====

// Check if player can send invites (must be in an arena)
bool CanPlayerInvite(int client)
{
    int arena_index = g_iPlayerArena[client];
    if (arena_index == 0)
        return false;

    return true;
}

// Clear all invites for a player
void ClearPlayerInvites(int client)
{
    // Clear incoming invite
    if (g_iPlayerInviteFrom[client] != 0)
    {
        g_iPlayerInviteFrom[g_iPlayerInviteFrom[client]] = 0;
        g_iPlayerInviteFrom[client] = 0;
    }
    g_iPlayerInviteArena[client] = 0;

    // Clear outgoing invite
    if (g_iPlayerInviteTo[client] != 0)
    {
        g_iPlayerInviteArena[g_iPlayerInviteTo[client]] = 0;
        g_iPlayerInviteTo[g_iPlayerInviteTo[client]] = 0;
        g_iPlayerInviteTo[client] = 0;
    }

    g_fPlayerInviteTime[client] = 0.0;
}

// Send invite to specific player
void SendInvite(int inviter, int target)
{
    // Clear any existing invites
    ClearPlayerInvites(inviter);
    ClearPlayerInvites(target);

    // Set invite relationship
    g_iPlayerInviteFrom[target] = inviter;
    g_iPlayerInviteTo[inviter] = target;
    g_fPlayerInviteTime[inviter] = GetGameTime();
    g_iPlayerInviteArena[target] = g_iPlayerArena[inviter];

    // Notify target
    char inviter_name[MAX_NAME_LENGTH];
    char arena_name[64];
    int temp_fraglimit;
    bool temp_is_2v2, temp_is_bball;
    GetClientName(inviter, inviter_name, sizeof(inviter_name));
    GetArenaBasicInfo(g_iPlayerArena[inviter], arena_name, sizeof(arena_name), temp_fraglimit, temp_is_2v2, temp_is_bball);

    MC_PrintToChat(target, "%t", "InviteReceived", inviter_name, arena_name);

    // Play ping sound for target (same as xf_forum_chat2 ping)
    if (IsClientInGame(target) && !IsFakeClient(target))
    {
        EmitSoundToClient(target, "mentionalert.mp3", _, SNDLEVEL_NORMAL);
    }

    // If target is already in arena, mention they'll be moved
    if (g_iPlayerArena[target] != 0)
    {
        MC_PrintToChat(target, "%t", "InviteWillMoveYou");
    }

    MC_PrintToChat(target, "%t", "InviteInstructions");

    // Notify inviter
    char target_name[MAX_NAME_LENGTH];
    GetClientName(target, target_name, sizeof(target_name));
    MC_PrintToChat(inviter, "%t", "InviteSent", target_name);
}

// Send public invite to all players
void SendPublicInvite(int inviter)
{
    if (!CanPlayerInvite(inviter))
        return;

    int arena_index = g_iPlayerArena[inviter];
    
    // Set public invite for this arena
    g_iPublicInviteArena[arena_index] = inviter;
    g_fPublicInviteTime[arena_index] = GetGameTime();

    char inviter_name[MAX_NAME_LENGTH];
    char arena_name[64];
    int temp_fraglimit;
    bool temp_is_2v2, temp_is_bball;
    GetClientName(inviter, inviter_name, sizeof(inviter_name));
    GetArenaBasicInfo(arena_index, arena_name, sizeof(arena_name), temp_fraglimit, temp_is_2v2, temp_is_bball);

    MC_PrintToChatAll("%t", "InviteAnyoneMessage", inviter_name, arena_name);
}

// Show player selection menu for invite
void ShowInviteMenu(int client)
{
    Menu menu = new Menu(Menu_InviteSelect);
    char title[128];
    Format(title, sizeof(title), "%T", "InviteMenuTitle", client);
    menu.SetTitle(title);

    // Add "Invite Anyone" option as first item
    char invite_anyone_text[64];
    Format(invite_anyone_text, sizeof(invite_anyone_text), "%T", "InviteAnyone", client);
    menu.AddItem("anyone", invite_anyone_text);

    char player_name[MAX_NAME_LENGTH];
    char player_id[8];
    char menu_item[128];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || i == client || !IsClientInGame(i))
            continue;

        GetClientName(i, player_name, sizeof(player_name));
        IntToString(i, player_id, sizeof(player_id));

        // Show status if player is in arena or spectating
        if (g_iPlayerArena[i] != 0)
        {
            char arena_name[64];
            int temp_fraglimit;
            bool temp_is_2v2, temp_is_bball;
            GetArenaBasicInfo(g_iPlayerArena[i], arena_name, sizeof(arena_name), temp_fraglimit, temp_is_2v2, temp_is_bball);
            Format(menu_item, sizeof(menu_item), "%s (in %s)", player_name, arena_name);
        }
        else if (GetClientTeam(i) == TEAM_SPEC)
        {
            char spectatingLabel[32];
            Format(spectatingLabel, sizeof(spectatingLabel), "%T", "SpectatingLabel", client);
            Format(menu_item, sizeof(menu_item), "%s (%s)", player_name, spectatingLabel);
        }
        else
        {
            Format(menu_item, sizeof(menu_item), "%s", player_name);
        }

        menu.AddItem(player_id, menu_item);
    }

    if (menu.ItemCount == 0)
    {
        MC_PrintToChat(client, "%t", "NoPlayersAvailable");
        delete menu;
        return;
    }

    menu.ExitButton = true;
    menu.Display(client, 30);
}

// Handle invite menu selection
int Menu_InviteSelect(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1;
            char selected[16];
            menu.GetItem(param2, selected, sizeof(selected));

            // Check if "Invite Anyone" was selected
            if (StrEqual(selected, "anyone"))
            {
                if (CanPlayerInvite(client))
                {
                    SendPublicInvite(client);
                }
                return 0;
            }

            int target = StringToInt(selected);
            if (IsValidClient(target) && CanPlayerInvite(client))
            {
                SendInvite(client, target);
            }
            else
            {
                MC_PrintToChat(client, "%t", "NotInArena");
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

// ===== INVITE COMMANDS =====

// Main invite command
Action Command_Invite(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    if (!CanPlayerInvite(client))
    {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    char arg[64];
    if (GetCmdArg(1, arg, sizeof(arg)) && strlen(arg) > 0)
    {
        // Try to find player by name
        int target = FindTarget(client, arg, false, false);
        if (target == -1)
        {
            MC_PrintToChat(client, "%t", "PlayerNotFound", arg);
            return Plugin_Handled;
        }

        if (target == client)
        {
            MC_PrintToChat(client, "%t", "CannotInviteSelf");
            return Plugin_Handled;
        }

        SendInvite(client, target);
    }
    else
    {
        // Show menu
        ShowInviteMenu(client);
    }

    return Plugin_Handled;
}

// Accept invite command
Action Command_AcceptInvite(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    int inviter = g_iPlayerInviteFrom[client];
    int arena_index = 0;
    bool isPublicInvite = false;

    // Check for personal invite first
    if (inviter != 0)
    {
        if (!IsValidClient(inviter) || g_iPlayerArena[inviter] == 0)
        {
            MC_PrintToChat(client, "%t", "InviteExpired");
            ClearPlayerInvites(client);
            return Plugin_Handled;
        }

        // Check timeout (30 seconds)
        if (GetGameTime() - g_fPlayerInviteTime[inviter] > 30.0)
        {
            MC_PrintToChat(client, "%t", "InviteExpired");
            ClearPlayerInvites(client);
            return Plugin_Handled;
        }

        arena_index = g_iPlayerInviteArena[client];
        if (arena_index <= 0 || arena_index > g_iArenaCount || g_iPlayerArena[inviter] != arena_index)
        {
            MC_PrintToChat(client, "%t", "InviteExpired");
            ClearPlayerInvites(client);
            return Plugin_Handled;
        }
    }
    else
    {
        // Check for public invite
        for (int i = 1; i <= g_iArenaCount; i++)
        {
            if (g_iPublicInviteArena[i] != 0)
            {
                // Check timeout (30 seconds)
                if (GetGameTime() - g_fPublicInviteTime[i] <= 30.0)
                {
                    arena_index = i;
                    inviter = g_iPublicInviteArena[i];
                    isPublicInvite = true;
                    break;
                }
                else
                {
                    // Clear expired public invite
                    g_iPublicInviteArena[i] = 0;
                    g_fPublicInviteTime[i] = 0.0;
                }
            }
        }

        if (arena_index == 0)
        {
            MC_PrintToChat(client, "%t", "NoInviteToAccept");
            return Plugin_Handled;
        }
    }

    // Imitate "add <arena>" logic
    AddInQueue(client, arena_index, true);

    // Clear invites
    ClearPlayerInvites(client);
    
    // Clear public invite if this was a public invite
    if (isPublicInvite)
    {
        g_iPublicInviteArena[arena_index] = 0;
        g_fPublicInviteTime[arena_index] = 0.0;
    }

    // Notify inviter (if it was a personal invite)
    if (!isPublicInvite && IsValidClient(inviter))
    {
        char client_name[MAX_NAME_LENGTH];
        GetClientName(client, client_name, sizeof(client_name));
        MC_PrintToChat(inviter, "%t", "InviteAccepted", client_name);
    }

    return Plugin_Handled;
}

// Decline invite command
Action Command_DeclineInvite(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    int inviter = g_iPlayerInviteFrom[client];
    if (inviter == 0)
    {
        MC_PrintToChat(client, "%t", "NoInviteToDecline");
        return Plugin_Handled;
    }

    // Clear invites
    ClearPlayerInvites(client);

    // Notify inviter if still valid
    if (IsValidClient(inviter))
    {
        char client_name[MAX_NAME_LENGTH];
        GetClientName(client, client_name, sizeof(client_name));
        MC_PrintToChat(inviter, "%t", "InviteDeclined", client_name);
    }

    MC_PrintToChat(client, "%t", "InviteDeclinedSelf");

    return Plugin_Handled;
}

// Block spectate command and execute remove instead
Action Command_BlockSpectate(int client, const char[] command, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];
    if (arena_index > 0)
    {
        // Execute remove command instead of spectate
        MC_PrintToChat(client, "%t", "SpecRemove");
        RemoveFromQueue(client, true);
        return Plugin_Handled; // Block the original spectate command
    }

    return Plugin_Continue; // Allow spectate if not in arena
}

// Toggle queue display in keyhint
Action Command_ToggleQueue(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    // Toggle the setting
    g_bShowQueue[client] = !g_bShowQueue[client];

    // Save to cookie
    char cookieValue[8];
    IntToString(g_bShowQueue[client] ? 1 : 0, cookieValue, sizeof(cookieValue));
    g_hShowQueueCookie.Set(client, cookieValue);

    // Notify player
    if (g_bShowQueue[client])
    {
        MC_PrintToChat(client, "%t", "QueueKeyhintEnabled");
    }
    else
    {
        MC_PrintToChat(client, "%t", "QueueKeyhintDisabled");
    }

    // Update keyhint immediately if player is in arena
    if (g_iPlayerArena[client] > 0)
    {
        if (g_bShowQueue[client])
        {
            UpdateQueueKeyHintText(g_iPlayerArena[client]);
        }
        else
        {
            ClearQueueKeyHintText(client);
        }
    }

    return Plugin_Handled;
}