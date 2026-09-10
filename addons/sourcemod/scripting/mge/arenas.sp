// ===== CONFIG PARSING HELPERS =====

bool ParseSpawnCoord(const char[] raw, int arena, int spawnIdx)
{
    char co[6][16];
    int count = ExplodeString(raw, " ", co, 6, 16);
    if (count == 6)
    {
        for (int i = 0; i < 3; i++)
            g_fArenaSpawnOrigin[arena][spawnIdx][i] = StringToFloat(co[i]);
        for (int i = 3; i < 6; i++)
            g_fArenaSpawnAngles[arena][spawnIdx][i - 3] = StringToFloat(co[i]);
        return true;
    }
    else if (count == 4)
    {
        for (int i = 0; i < 3; i++)
            g_fArenaSpawnOrigin[arena][spawnIdx][i] = StringToFloat(co[i]);
        g_fArenaSpawnAngles[arena][spawnIdx][0] = 0.0;
        g_fArenaSpawnAngles[arena][spawnIdx][1] = StringToFloat(co[3]);
        g_fArenaSpawnAngles[arena][spawnIdx][2] = 0.0;
        return true;
    }
    return false;
}

bool ParseCoordInto(const char[] raw, float pos[3])
{
    char co[6][16];
    int count = ExplodeString(raw, " ", co, 6, 16);
    if (count >= 3)
    {
        for (int i = 0; i < 3; i++)
            pos[i] = StringToFloat(co[i]);
        return true;
    }
    return false;
}

int LoadNumberedSpawns(KeyValues kv, int arena, int offset, TFClassType classTag)
{
    int loaded = 0;
    int id;
    char numStr[4], nextStr[4], raw[64];

    if (!kv.GetNameSymbol("1", id))
        return 0;

    do
    {
        loaded++;
        int idx = offset + loaded;
        if (idx > MAXSPAWNS)
        {
            LogError("Arena '%s': Exceeded max spawns (%d)", g_sArenaOriginalName[arena], MAXSPAWNS);
            break;
        }

        IntToString(loaded, numStr, sizeof(numStr));
        IntToString(loaded + 1, nextStr, sizeof(nextStr));
        kv.GetString(numStr, raw, sizeof(raw));

        if (!ParseSpawnCoord(raw, arena, idx))
        {
            LogError("Arena '%s': Bad coordinates on spawn %d", g_sArenaOriginalName[arena], loaded);
            loaded--;
            break;
        }

        g_tfctArenaSpawnClass[arena][idx] = classTag;
    } while (kv.GetNameSymbol(nextStr, id));

    return loaded;
}

void SetArenaGamemode(int arena, const char[] gamemode)
{
    g_bArenaMGE[arena] = false;
    g_bArenaBBall[arena] = false;
    g_bArenaKoth[arena] = false;
    g_bArenaAmmomod[arena] = false;
    g_bArenaMidair[arena] = false;
    g_bArenaEndif[arena] = false;
    g_bArenaUltiduo[arena] = false;
    g_bArenaTurris[arena] = false;

    if (StrEqual(gamemode, "bball"))
        g_bArenaBBall[arena] = true;
    else if (StrEqual(gamemode, "koth"))
        g_bArenaKoth[arena] = true;
    else if (StrEqual(gamemode, "ammomod"))
        g_bArenaAmmomod[arena] = true;
    else if (StrEqual(gamemode, "midair"))
        g_bArenaMidair[arena] = true;
    else if (StrEqual(gamemode, "endif"))
        g_bArenaEndif[arena] = true;
    else if (StrEqual(gamemode, "ultiduo"))
    {
        g_bArenaUltiduo[arena] = true;
        g_bArenaKoth[arena] = true;
    }
    else if (StrEqual(gamemode, "turris"))
        g_bArenaTurris[arena] = true;
    else
        g_bArenaMGE[arena] = true;
}

void SetArenaTeamSize(int arena, const char[] teamSize)
{
    char tokens[2][8];
    int count = ExplodeString(teamSize, " ", tokens, 2, 8);

    g_bFourPersonArena[arena] = StrEqual(tokens[0], "2v2");
    g_bArenaAllowChange[arena] = (count == 2);
}

bool LoadSpawnSection(KeyValues kv, int arena)
{
    if (!kv.JumpToKey("spawns"))
        return false;

    if (kv.JumpToKey("red"))
    {
        // Check for class-specific subsections: if GotoFirstSubKey succeeds,
        // the children are sections (class names), not key-value pairs.
        if (kv.GotoFirstSubKey())
        {
            // Class-specific format: red { soldier { ... } medic { ... } }
            int redCount = 0;
            do
            {
                char className[16];
                kv.GetSectionName(className, sizeof(className));
                TFClassType classType = TF2_GetClass(className);

                int loaded = LoadNumberedSpawns(kv, arena, redCount, classType);
                redCount += loaded;
            } while (kv.GotoNextKey());
            kv.GoBack(); // back to red
            kv.GoBack(); // back to spawns

            g_iArenaRedSpawnCount[arena] = redCount;

            if (!kv.JumpToKey("blu"))
            {
                kv.GoBack();
                return false;
            }

            int bluCount = 0;
            if (kv.GotoFirstSubKey())
            {
                do
                {
                    char className[16];
                    kv.GetSectionName(className, sizeof(className));
                    TFClassType classType = TF2_GetClass(className);

                    int loaded = LoadNumberedSpawns(kv, arena, redCount + bluCount, classType);
                    bluCount += loaded;
                } while (kv.GotoNextKey());
                kv.GoBack(); // back to blu
            }
            kv.GoBack(); // back to spawns

            g_iArenaSpawns[arena] = redCount + bluCount;
        }
        else
        {
            // Team-split format: red { "1" "..." } blu { "1" "..." }
            int redCount = LoadNumberedSpawns(kv, arena, 0, TFClass_Unknown);
            kv.GoBack(); // back to spawns

            g_iArenaRedSpawnCount[arena] = redCount;

            int bluCount = 0;
            if (kv.JumpToKey("blu"))
            {
                bluCount = LoadNumberedSpawns(kv, arena, redCount, TFClass_Unknown);
                kv.GoBack(); // back to spawns
            }

            g_iArenaSpawns[arena] = redCount + bluCount;
        }
    }
    else
    {
        // Flat format: spawns { "1" "..." "2" "..." }
        int total = LoadNumberedSpawns(kv, arena, 0, TFClass_Unknown);
        int mid = total / 2;

        g_iArenaRedSpawnCount[arena] = mid;
        g_iArenaSpawns[arena] = total;
    }

    kv.GoBack(); // back to arena section
    return (g_iArenaSpawns[arena] > 0);
}

void LoadEntitySection(KeyValues kv, int arena)
{
    if (!kv.JumpToKey("entities"))
        return;

    char raw[64];

    kv.GetString("hoop_red", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fBBallHoopPos[arena][1]);

    kv.GetString("hoop_blu", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fBBallHoopPos[arena][2]);

    kv.GetString("intel_start", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fBBallIntelPos[arena][0]);

    kv.GetString("intel_red", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fBBallIntelPos[arena][1]);

    kv.GetString("intel_blu", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fBBallIntelPos[arena][2]);

    kv.GetString("capture_point", raw, sizeof(raw), "");
    if (raw[0]) ParseCoordInto(raw, g_fKothPointPos[arena]);

    kv.GoBack();
}

bool ValidateArenaSchema(int arena)
{
    char name[64];
    strcopy(name, sizeof(name), g_sArenaOriginalName[arena]);

    if (g_bArenaBBall[arena])
    {
        if (g_fBBallHoopPos[arena][1][0] == 0.0 && g_fBBallHoopPos[arena][1][1] == 0.0 && g_fBBallHoopPos[arena][1][2] == 0.0)
        {
            LogError("Arena '%s': BBall requires 'hoop_red' in entities section, skipping", name);
            return false;
        }
        if (g_fBBallHoopPos[arena][2][0] == 0.0 && g_fBBallHoopPos[arena][2][1] == 0.0 && g_fBBallHoopPos[arena][2][2] == 0.0)
        {
            LogError("Arena '%s': BBall requires 'hoop_blu' in entities section, skipping", name);
            return false;
        }
        if (g_fBBallIntelPos[arena][0][0] == 0.0 && g_fBBallIntelPos[arena][0][1] == 0.0 && g_fBBallIntelPos[arena][0][2] == 0.0)
        {
            LogError("Arena '%s': BBall requires 'intel_start' in entities section, skipping", name);
            return false;
        }
    }

    if (g_bArenaKoth[arena])
    {
        if (g_fKothPointPos[arena][0] == 0.0 && g_fKothPointPos[arena][1] == 0.0 && g_fKothPointPos[arena][2] == 0.0)
        {
            LogError("Arena '%s': KOTH/Ultiduo requires 'capture_point' in entities section, skipping", name);
            return false;
        }
    }

    if (g_bArenaUltiduo[arena])
    {
        bool hasSoldier = false, hasMedic = false;
        for (int i = 1; i <= g_iArenaSpawns[arena]; i++)
        {
            if (g_tfctArenaSpawnClass[arena][i] == TFClass_Soldier) hasSoldier = true;
            if (g_tfctArenaSpawnClass[arena][i] == TFClass_Medic) hasMedic = true;
        }
        if (!hasSoldier || !hasMedic)
        {
            LogError("Arena '%s': Ultiduo requires class-specific spawns (soldier + medic) under red/blu, skipping", name);
            return false;
        }
    }

    return true;
}


// ===== PLUGIN CORE LIFECYCLE =====

// Returns 1 on success, 0 if the config file is missing, -1 if the file exists but is invalid.
int LoadSpawnPoints()
{
    char txtfile[256];
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));

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

    Format(txtfile, sizeof(txtfile), "configs/mge/%s.cfg", g_sMapName);
    BuildPath(Path_SM, txtfile, sizeof(txtfile), txtfile);

    KeyValues kv = new KeyValues("SpawnConfigs");

    g_iArenaCount = 0;

    for (int j = 0; j <= MAXARENAS; j++)
    {
        g_iArenaSpawns[j] = 0;
        g_iArenaRedSpawnCount[j] = 0;
    }

    if (!FileExists(txtfile))
    {
        LogError("Config file missing: %s", txtfile);
        delete kv;
        return 0;
    }

    if (!kv.ImportFromFile(txtfile))
    {
        LogError("Config file exists but failed to parse: %s", txtfile);
        delete kv;
        return -1;
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError("Config file has no arena entries: %s", txtfile);
        delete kv;
        return -1;
    }

    do
    {
        g_iArenaCount++;
        kv.GetSectionName(g_sArenaOriginalName[g_iArenaCount], 64);

        // Gamemode
        char gamemode[32];
        kv.GetString("gamemode", gamemode, sizeof(gamemode), "mge");
        SetArenaGamemode(g_iArenaCount, gamemode);

        // Team size
        char teamSize[32];
        kv.GetString("team_size", teamSize, sizeof(teamSize), "1v1");
        SetArenaTeamSize(g_iArenaCount, teamSize);

        // Spawns
        if (!LoadSpawnSection(kv, g_iArenaCount))
        {
            LogError("Arena '%s': No valid spawns found, skipping", g_sArenaOriginalName[g_iArenaCount]);
            g_iArenaCount--;
            continue;
        }

        // Entities
        LoadEntitySection(kv, g_iArenaCount);

        // Settings
        g_iArenaMgelimit[g_iArenaCount] = kv.GetNum("frag_limit", g_iDefaultFragLimit);
        g_iArenaCaplimit[g_iArenaCount] = kv.GetNum("cap_limit", g_iDefaultFragLimit);
        g_iArenaMinRating[g_iArenaCount] = kv.GetNum("min_elo", -1);
        g_iArenaMaxRating[g_iArenaCount] = kv.GetNum("max_elo", -1);
        g_iArenaCdTime[g_iArenaCount] = kv.GetNum("countdown_seconds", DEFAULT_COUNTDOWN_TIME);
        g_fArenaHPRatio[g_iArenaCount] = kv.GetFloat("hp_multiplier", 1.5);
        g_iArenaAirshotHeight[g_iArenaCount] = kv.GetNum("airshot_min_height", 250);
        g_bArenaBoostVectors[g_iArenaCount] = kv.GetNum("knockback_boost", 0) ? true : false;
        g_bVisibleHoops[g_iArenaCount] = kv.GetNum("visible_hoops", 0) ? true : false;
        g_iArenaEarlyLeave[g_iArenaCount] = kv.GetNum("early_leave_threshold", 0);
        g_bArenaInfAmmo[g_iArenaCount] = kv.GetNum("infinite_ammo", 1) ? true : false;
        g_bArenaShowHPToPlayers[g_iArenaCount] = kv.GetNum("show_hp", 1) ? true : false;
        g_fArenaMinSpawnDist[g_iArenaCount] = kv.GetFloat("min_spawn_distance", 100.0);
        g_bArenaAllowKoth[g_iArenaCount] = kv.GetNum("allow_koth_switch", 0) ? true : false;
        g_bArenaKothTeamSpawn[g_iArenaCount] = kv.GetNum("koth_team_spawns", 0) ? true : false;
        g_fArenaRespawnTime[g_iArenaCount] = kv.GetFloat("respawn_delay", 0.1);
        g_bArenaClassChange[g_iArenaCount] = kv.GetNum("allow_class_change", 1) ? true : false;
        g_iDefaultCapTime[g_iArenaCount] = kv.GetNum("koth_round_time", 180);

        char sAllowedClasses[128];
        kv.GetString("allowed_classes", sAllowedClasses, sizeof(sAllowedClasses));
        ParseAllowedClasses(sAllowedClasses, g_tfctArenaAllowedClasses[g_iArenaCount]);

        // Schema validation
        if (!ValidateArenaSchema(g_iArenaCount))
        {
            g_iArenaCount--;
            continue;
        }

        g_iArenaFraglimit[g_iArenaCount] = g_iArenaMgelimit[g_iArenaCount];
        UpdateArenaName(g_iArenaCount);
    } while (kv.GotoNextKey());

    if (g_iArenaCount)
    {
        LogMessage("Loaded %d arenas from %s. MGEMod enabled.", g_iArenaCount, txtfile);
        delete kv;
        return 1;
    }
    else
    {
        LogMessage("No valid arenas found in %s.", txtfile);
        delete kv;
        return -1;
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


// ===== ARENA STATUS =====

// Sets an arena's status and notifies API consumers, but only if it actually changed
void SetArenaStatus(int arena_index, int status)
{
    int old_status = g_iArenaStatus[arena_index];
    if (old_status == status)
        return;

    g_iArenaStatus[arena_index] = status;
    CallForward_OnArenaStatusChange(arena_index, old_status, status);
}

// ===== QUEUE MANAGEMENT =====

// Remove player from arena queue with optional statistics calculation and spectator handling
// TODO: refactor this crap
void RemoveFromQueue(int client, bool calcstats = false, bool specfix = true)
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
                HideIntel(arena_index);

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

            if (g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED && calcstats && IsValidClient(foe))
            {
                SetArenaStatus(arena_index, AS_REPORTED);

                int stayerScore = g_iArenaScore[arena_index][foe_team_slot];
                int leaverScore = g_iArenaScore[arena_index][player_team_slot];

                if (ShouldForfeitOnLeave(arena_index, stayerScore, leaverScore))
                {
                    ProcessMatchForfeit(arena_index, foe, foe2, client, player_teammate, foe_team_slot, player_team_slot, client, player_slot);
                }
            }

            if (g_iArenaQueue[arena_index][SLOT_FOUR + 1])
            {
                int next_client = g_iArenaQueue[arena_index][SLOT_FOUR + 1];
                g_iArenaQueue[arena_index][SLOT_FOUR + 1] = 0;
                g_iArenaQueue[arena_index][player_slot] = next_client;
                g_iPlayerSlot[next_client] = player_slot;
                after_leaver_slot = SLOT_FOUR + 2;
                CreateTimer(2.0, Timer_Restart2v2Ready, arena_index);

                SendArenaJoinMessage(next_client, g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[next_client], IsPlayerEligibleForElo(next_client));
                
                UpdateHudForArena(arena_index);
            } else {
                if (IsValidClient(foe) && IsFakeClient(foe))
                {
                    DecrementBotQuota();
                }

                if (g_bFourPersonArena[arena_index])
                {
                    Restore2v2WaitingSpectators(arena_index);
                    CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
                }

                SetArenaStatus(arena_index, AS_IDLE);
                
                UpdateHudForArena(arena_index);
                CallForward_OnPlayerArenaRemoved(client, arena_index);
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
                HideIntel(arena_index);

                RemoveClientParticle(client);
                g_bPlayerHasIntel[client] = false;

                if (foe)
                {
                    RemoveClientParticle(foe);
                    g_bPlayerHasIntel[foe] = false;
                }
            }

            if (g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED && calcstats && IsValidClient(foe))
            {
                SetArenaStatus(arena_index, AS_REPORTED);

                int stayerScore = g_iArenaScore[arena_index][foe_slot];
                int leaverScore = g_iArenaScore[arena_index][player_slot];

                if (ShouldForfeitOnLeave(arena_index, stayerScore, leaverScore))
                {
                    ProcessMatchForfeit(arena_index, foe, 0, client, 0, foe_slot, player_slot, client, player_slot);
                }
            }

            if (g_iArenaQueue[arena_index][SLOT_TWO + 1])
            {
                int next_client = g_iArenaQueue[arena_index][SLOT_TWO + 1];
                g_iArenaQueue[arena_index][SLOT_TWO + 1] = 0;
                g_iArenaQueue[arena_index][player_slot] = next_client;
                g_iPlayerSlot[next_client] = player_slot;
                after_leaver_slot = SLOT_TWO + 2;
                CreateTimer(2.0, Timer_StartDuel, arena_index);

                SendArenaJoinMessage(next_client, g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[next_client], IsPlayerEligibleForElo(next_client));
                
                UpdateHudForArena(arena_index);
            } else {
                if (IsValidClient(foe) && IsFakeClient(foe))
                {
                    DecrementBotQuota();
                }

                SetArenaStatus(arena_index, AS_IDLE);
                
                UpdateHudForArena(arena_index);
                CallForward_OnPlayerArenaRemoved(client, arena_index);
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
    
    // Call OnPlayerArenaRemoved forward
    CallForward_OnPlayerArenaRemoved(client, arena_index);
}

bool CanPlayerJoinArena(int client, int arena_index, bool showmsg)
{
    if (IsFakeClient(client)
        || g_iPlayerArena[client] == arena_index
        || !gcvar_stats.BoolValue
        || (g_iArenaMinRating[arena_index] <= 0 && g_iArenaMaxRating[arena_index] <= 0))
        return true;

    if (!IsPlayerStatsLoaded(client))
    {
        if (showmsg)
        {
            if (g_ePlayerStatsLoadState[client] == MGE_STATS_AUTH_FAILED)
                MC_PrintToChat(client, "%t", "StatsAuthFailedRestrictedArena");
            else if (g_ePlayerStatsLoadState[client] == MGE_STATS_DB_FAILED)
                MC_PrintToChat(client, "%t", "StatsLoadFailedRestrictedArena");
            else
                MC_PrintToChat(client, "%t", "StatsLoadingRestrictedArena");
        }
        return false;
    }

    int rating = Rating_GetDisplayValue(client);
    if (g_iArenaMinRating[arena_index] > 0 && rating < g_iArenaMinRating[arena_index])
    {
        if (showmsg)
            MC_PrintToChat(client, "%t", "LowRating", rating, g_iArenaMinRating[arena_index]);
        return false;
    }

    if (g_iArenaMaxRating[arena_index] > 0 && rating > g_iArenaMaxRating[arena_index])
    {
        if (showmsg)
            MC_PrintToChat(client, "%t", "HighRating", rating, g_iArenaMaxRating[arena_index]);
        return false;
    }

    return true;
}

// Add player to arena queue with team preference and menu options
void AddInQueue(int client, int arena_index, bool showmsg = true, int playerPrefTeam = 0, bool show2v2Menu = true, int forcedSlot = 0)
{
    if (!IsValidClient(client))
        return;

    if (!CanPlayerJoinArena(client, arena_index, showmsg))
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

    // Handle forced slot assignment (used by API natives)
    int player_slot = SLOT_ONE;
    if (forcedSlot > 0)
    {
        // Validate forced slot for arena type
        if (!IsValidSlotForArena(arena_index, forcedSlot))
        {
            if (showmsg)
            {
                if (g_bFourPersonArena[arena_index])
                    MC_PrintToChat(client, "[MGE] Invalid slot %d for 2v2 arena (valid slots: 1-4)", forcedSlot);
                else
                    MC_PrintToChat(client, "[MGE] Invalid slot %d for 1v1 arena (valid slots: 1-2)", forcedSlot);
            }
            return;
        }
        
        // Check if forced slot is already occupied
        if (g_iArenaQueue[arena_index][forcedSlot] != 0)
        {
            if (showmsg)
                MC_PrintToChat(client, "[MGE] Slot %d is already occupied", forcedSlot);
            return;
        }
        
        player_slot = forcedSlot;
    }
    // For 2v2 arenas, only respect team preference for active slots (team switching)
    // Queued players just join the first available slot regardless of team
    else if (g_bFourPersonArena[arena_index] && playerPrefTeam != 0)
    {
        // This is team switching for active players only
        if (playerPrefTeam == TEAM_RED)
        {
            // Try main RED slots first
            if (!g_iArenaQueue[arena_index][SLOT_ONE])
                player_slot = SLOT_ONE;
            else if (!g_iArenaQueue[arena_index][SLOT_THREE])
                player_slot = SLOT_THREE;
            else
            {
                // RED slots full, put in regular queue
                player_slot = SLOT_FOUR + 1;
                while (g_iArenaQueue[arena_index][player_slot])
                    player_slot++;
            }
        }
        else if (playerPrefTeam == TEAM_BLU)
        {
            // Try main BLU slots first  
            if (!g_iArenaQueue[arena_index][SLOT_TWO])
                player_slot = SLOT_TWO;
            else if (!g_iArenaQueue[arena_index][SLOT_FOUR])
                player_slot = SLOT_FOUR;
            else
            {
                // BLU slots full, put in regular queue
                player_slot = SLOT_FOUR + 1;
                while (g_iArenaQueue[arena_index][player_slot])
                    player_slot++;
            }
        }
    }
    else
    {
        // Regular queue assignment - find first available slot
        while (g_iArenaQueue[arena_index][player_slot])
            player_slot++;
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
    
    // Call OnPlayerArenaAdded forward
    CallForward_OnPlayerArenaAdded(client, arena_index, player_slot);

    SetPlayerToAllowedClass(client, arena_index);

    if (showmsg)
        MC_PrintToChat(client, "%t", "ChoseArena", g_sArenaName[arena_index]);

    if (g_bFourPersonArena[arena_index])
    {
        if (player_slot <= SLOT_FOUR)
        {
            SendArenaJoinMessage(client, g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[client], IsPlayerEligibleForElo(client), client);

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
            SendArenaJoinMessage(client, g_sArenaName[arena_index], !g_bNoStats && !g_bNoDisplayRating && g_bShowElo[client], IsPlayerEligibleForElo(client), client);

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
            SetArenaStatus(arena_index, AS_PRECOUNTDOWN);
            CreateTimer(0.1, Timer_CountDown, arena_index, TIMER_FLAG_NO_MAPCHANGE);
            return 1;
        } else {
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            SetArenaStatus(arena_index, AS_IDLE);
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
            SetArenaStatus(arena_index, AS_PRECOUNTDOWN);
            CreateTimer(0.1, Timer_CountDown, arena_index, TIMER_FLAG_NO_MAPCHANGE);
            return 1;
        }
        else
        {
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            SetArenaStatus(arena_index, AS_IDLE);
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

            if (!g_bNoDisplayRating && g_bShowElo[client])
            {
                if (red_valid)
                    AppendPlayerWithOptionalRating(report, sizeof(report), red_f1);

                if (red_valid && blu_valid)
                    StrCat(report, sizeof(report), " \x05vs ");

                if (blu_valid)
                    AppendPlayerWithOptionalRating(report, sizeof(report), blu_f1);

                StrCat(report, sizeof(report), "\x05");
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
            MC_PrintToChat(client, "%s", report);
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
                // Always call AddInQueue - it handles re-selection logic internally
                AddInQueue(client, arena_index);

            } else {
                RemovePlayerWithConfirmation(client);
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

// Formats a player's rating for display
void FormatRatingDisplay(int player, char[] output, int output_size)
{
    if (IsFakeClient(player))
        strcopy(output, output_size, "BOT");
    else if (!IsPlayerStatsLoaded(player))
        output[0] = '\0';
    else if (Rating_IsProvisional(player))
        Format(output, output_size, "%d?", Rating_GetDisplayValue(player));
    else
        IntToString(Rating_GetDisplayValue(player), output, output_size);
}

void AppendPlayerWithOptionalRating(char[] output, int output_size, int player)
{
    char segment[MAX_NAME_LENGTH + 32];
    char rating[16];
    FormatRatingDisplay(player, rating, sizeof(rating));

    if (rating[0] == '\0')
        Format(segment, sizeof(segment), " \x04%N", player);
    else
        Format(segment, sizeof(segment), " \x04%N \x03(%s)", player, rating);

    StrCat(output, output_size, segment);
}

// Send formatted join message with player rating and arena information
void SendArenaJoinMessage(int player, const char[] arena_name, bool show_elo, bool is_verified = true, int actor = 0)
{
    char playername[MAX_NAME_LENGTH];
    GetClientName(player, playername, sizeof(playername));

    char rating[16];
    FormatRatingDisplay(player, rating, sizeof(rating));

    for (int i = 1; i <= MaxClients; ++i)
    {
        if (!IsClientInGame(i) || i == actor)
            continue;

        if (show_elo && g_bShowElo[i] && is_verified)
            MC_PrintToChat(i, "%t", "JoinsArena", playername, rating, arena_name);
        else
            MC_PrintToChat(i, "%t", "JoinsArenaNoStats", playername, arena_name);
    }
}

void SendArenaLeaveMessage(int player, const char[] arena_name)
{
    char playername[MAX_NAME_LENGTH];
    GetClientName(player, playername, sizeof(playername));

    for (int i = 1; i <= MaxClients; ++i)
    {
        if (!IsClientInGame(i) || i == player)
            continue;

        MC_PrintToChat(i, "%t", "LeavesArena", playername, arena_name);
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
            MC_PrintToChat(client, buffer);
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

// Remove player from current arena queue
bool RemovePlayerWithConfirmation(int client)
{
    int arena_index = g_iPlayerArena[client];
    if (arena_index <= 0)
        return false;

    char arena_name[64];
    strcopy(arena_name, sizeof(arena_name), g_sArenaName[arena_index]);

    RemoveFromQueue(client, true);
    if (g_iPlayerArena[client] != 0)
        return false;

    MC_PrintToChat(client, "%t", "LeftArena", arena_name);
    SendArenaLeaveMessage(client, arena_name);
    return true;
}

Action Command_Remove(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    RemovePlayerWithConfirmation(client);
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

// Releases one tf_bot_quota slot when a bot leaves an arena for good, never going below 0
// (tf_bot_quota is a persistent server convar; letting it drift negative causes the engine's
// quota enforcement to auto-kick any newly added bot, since it believes it already has too many)
void DecrementBotQuota()
{
    ConVar cvar = FindConVar("tf_bot_quota");
    int quota = cvar.IntValue;
    if (quota > 0)
        cvar.SetInt(quota - 1);
}

// Add bot player to arena queue for testing purposes
// Maps a user-supplied class name to the argument tf_bot_add expects, defaulting to scout
void GetBotClassArg(int args, char[] output, int output_size)
{
    static const char VALID_CLASSES[9][13] = { "scout", "sniper", "soldier", "demoman", "medic", "heavyweapons", "pyro", "spy", "engineer" };

    char arg[32] = "scout";
    if (args >= 1)
        GetCmdArg(1, arg, sizeof(arg));

    if (StrEqual(arg, "heavy", false))
        strcopy(arg, sizeof(arg), "heavyweapons");

    for (int i = 0; i < sizeof(VALID_CLASSES); i++)
    {
        if (StrEqual(arg, VALID_CLASSES[i], false))
        {
            strcopy(output, output_size, VALID_CLASSES[i]);
            return;
        }
    }

    strcopy(output, output_size, "scout");
}

// Converts a tf_bot_add-style class name (as produced by GetBotClassArg) into its TFClassType
TFClassType GetClassTypeFromBotClassArg(const char[] name)
{
    static const char VALID_CLASSES[9][13] = { "scout", "sniper", "soldier", "demoman", "medic", "heavyweapons", "pyro", "spy", "engineer" };

    for (int i = 0; i < sizeof(VALID_CLASSES); i++)
    {
        if (StrEqual(name, VALID_CLASSES[i], false))
            return view_as<TFClassType>(i + 1);
    }

    return TFClass_Scout;
}

// Checks whether any of an arena's active (fighting, not queued) slots already hold a bot
bool ArenaHasActiveBot(int arena_index)
{
    int max_active_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int i = SLOT_ONE; i <= max_active_slot; i++)
    {
        int occupant = g_iArenaQueue[arena_index][i];
        if (occupant && IsFakeClient(occupant))
            return true;
    }
    return false;
}

Action Command_AddBot(int client, int args)
{
    // Adding bot to client's arena
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];

    if (arena_index && (player_slot == SLOT_ONE || player_slot == SLOT_TWO || (g_bFourPersonArena[arena_index] && (player_slot == SLOT_THREE || player_slot == SLOT_FOUR))))
    {
        // Prevent re-requesting while a previous request is still connecting/queueing, or while
        // a bot from a previous request is already fighting in this arena - stacking requests
        // races the async bot-connection tracking (which just grabs the first pending request it
        // sees) and corrupts arena/class attribution for both bots.
        if (g_bPlayerAskedForBot[client])
        {
            MC_PrintToChat(client, "%t", "BotAlreadyRequested");
            return Plugin_Handled;
        }

        if (ArenaHasActiveBot(arena_index))
        {
            MC_PrintToChat(client, "%t", "BotAlreadyInArena");
            return Plugin_Handled;
        }

        // Bots otherwise re-roll a random class (often medic) on every respawn
        FindConVar("tf_bot_keep_class_after_death").SetInt(1);

        // Note: we deliberately do NOT pass a class to tf_bot_add here. Forcing a class at
        // creation makes the engine spawn the bot immediately at the map's default team spawns
        // (before we get a chance to queue it into the arena), and on some maps those default
        // spawns don't support every class, which gets the bot kicked for failing to spawn.
        // Instead we stash the desired class and force it once the bot is safely queued into
        // the arena (which uses the arena's own working spawn points).
        GetBotClassArg(args, g_sPendingBotClass[client], sizeof(g_sPendingBotClass[]));

        ServerCommand("tf_bot_add");
        g_bPlayerAskedForBot[client] = true;
    }
    else
    {
        MC_PrintToChat(client, "%t", "NotInArena");
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
                SetArenaStatus(arena_index, AS_COUNTDOWN);
            } else if (g_iArenaCd[arena_index] <= 0) {
                SetArenaStatus(arena_index, AS_FIGHT);
                g_iArenaDuelStartTime[arena_index] = GetTime(); // Capture duel start time
                char msg[64];
                Format(msg, sizeof(msg), "FIGHT", g_iArenaCd[arena_index]);
                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                PrintCenterText(red_f2, msg);
                PrintCenterText(blu_f2, msg);
                ShowCountdownToSpec(arena_index, msg);

                // Call 2v2 match start forward
                CallForward_On2v2MatchStart(arena_index, red_f1, red_f2, blu_f1, blu_f2);

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
            SetArenaStatus(arena_index, AS_IDLE);
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
                SetArenaStatus(arena_index, AS_COUNTDOWN);
            } else if (g_iArenaCd[arena_index] <= 0) {
                SetArenaStatus(arena_index, AS_FIGHT);
                g_iArenaDuelStartTime[arena_index] = GetTime(); // Capture duel start time
                char msg[64];
                Format(msg, sizeof(msg), "FIGHT", g_iArenaCd[arena_index]);
                PrintCenterText(red_f1, msg);
                PrintCenterText(blu_f1, msg);
                ShowCountdownToSpec(arena_index, msg);

                // Call match start forward
                CallForward_On1v1MatchStart(arena_index, red_f1, blu_f1);

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
            SetArenaStatus(arena_index, AS_IDLE);
            g_iArenaCd[arena_index] = 0;
            return Plugin_Stop;
        }
    }
}

// Initialize duel start sequence and player setup
Action Timer_StartDuel(Handle timer, any arena_index)
{
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

    ResetArenaScores(arena_index);
    g_iArenaDuelStartTime[arena_index] = 0; // Reset duel start time
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

    // Force the requested class now that the bot is queued into the arena's own spawn points,
    // rather than at tf_bot_add time (see Command_AddBot for why that's unsafe on some maps).
    // g_sBotDesiredClass is intentionally left set - Event_PlayerSpawn re-enforces it on every
    // future respawn too, since TFBots can otherwise still drift off it over time.
    if (IsValidClient(client) && IsFakeClient(client) && strlen(g_sBotDesiredClass[client]) > 0)
    {
        TFClassType desired_class = GetClassTypeFromBotClassArg(g_sBotDesiredClass[client]);
        g_tfctPlayerClass[client] = desired_class;
        TF2_SetPlayerClass(client, desired_class);
        TF2_RespawnPlayer(client);
    }

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
            int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
            if (owner == -1 && HasEntProp(entity, Prop_Send, "m_hThrower"))
                owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
                
            if (IsValidClient(owner) && g_iPlayerArena[owner] == arena_index)
            {
                entitiesToRemove.Push(entity);
            }
        }
        else if (StrEqual(classname, "tf_ball_ornament", false))
        {
            if (!HasEntProp(entity, Prop_Send, "m_hThrower"))
                continue;

            int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
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
            RemoveEntity(entity);
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