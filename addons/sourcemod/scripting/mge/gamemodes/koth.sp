#define KOTH_SND_IDLE 0
#define KOTH_SND_CAPPING 1
#define KOTH_SND_BLOCKED 2

// ===== ENTITY MANAGEMENT =====

// Setup KOTH capture points for all KOTH arenas during round start.
// Prefer the map's trigger_capture_area when the configured point sits inside it.
void SetupKothCapturePoints()
{
    ClearKothCaptureSounds();
    ApplyKothClockFromMap();
    RemovePluginCapturePacks();

    int triggers[MAXARENAS + 1];
    int triggerCount = CollectCaptureTriggers(triggers, sizeof(triggers));
    bool usedTrigger[MAXARENAS + 1];
    for (int i = 0; i <= MAXARENAS; i++)
        usedTrigger[i] = false;

    for (int i = 0; i <= g_iArenaCount; i++)
    {
        if (!g_bArenaKoth[i])
            continue;

        g_bKothRulesFromMap[i] = false;
        g_bKothWaveFromMap[i] = false;

        int trigger = FindTriggerContainingPoint(triggers, triggerCount, usedTrigger, g_fKothPointPos[i]);
        if (trigger != -1)
        {
            g_iCapturePoint[i] = trigger;
            SDKUnhook(trigger, SDKHook_StartTouch, OnTouchPoint);
            SDKUnhook(trigger, SDKHook_EndTouch, OnEndTouchPoint);
            SDKHook(trigger, SDKHook_StartTouch, OnTouchPoint);
            SDKHook(trigger, SDKHook_EndTouch, OnEndTouchPoint);
            ReadArenaCaptureRules(i, trigger);
            continue;
        }

        if (g_bArenaUltiduo[i])
            LogError("Arena '%s': capture_point is not inside a trigger_capture_area", g_sArenaOriginalName[i]);

        SpawnFallbackCapturePack(i);
    }
}

int CollectCaptureTriggers(int[] triggers, int maxTriggers)
{
    int count = 0;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "trigger_capture_area")) != -1)
    {
        if (count >= maxTriggers)
            break;
        triggers[count++] = ent;
    }
    return count;
}

int FindTriggerContainingPoint(const int[] triggers, int triggerCount, bool[] usedTrigger, const float point[3])
{
    for (int i = 0; i < triggerCount; i++)
    {
        if (usedTrigger[i])
            continue;
        if (!TriggerContainsPoint(triggers[i], point))
            continue;
        usedTrigger[i] = true;
        return triggers[i];
    }
    return -1;
}

bool TriggerContainsPoint(int trigger, const float point[3])
{
    if (!IsValidEntity(trigger))
        return false;

    float origin[3], mins[3], maxs[3];
    GetEntPropVector(trigger, Prop_Data, "m_vecAbsOrigin", origin);
    GetEntPropVector(trigger, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(trigger, Prop_Send, "m_vecMaxs", maxs);

    float worldMins[3], worldMaxs[3];
    AddVectors(origin, mins, worldMins);
    AddVectors(origin, maxs, worldMaxs);

    return point[0] >= worldMins[0] && point[0] <= worldMaxs[0]
        && point[1] >= worldMins[1] && point[1] <= worldMaxs[1]
        && point[2] >= worldMins[2] && point[2] <= worldMaxs[2];
}

void RemovePluginCapturePacks()
{
    int found[MAXARENAS + 1];
    int count = 0;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "item_ammopack_small")) != -1)
    {
        if (count >= sizeof(found))
            break;

        char model[64];
        GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
        if (StrEqual(model, MODEL_POINT))
            found[count++] = ent;
    }

    for (int i = 0; i < count; i++)
    {
        if (IsValidEntity(found[i]))
            RemoveEntity(found[i]);
    }

    for (int i = 0; i <= g_iArenaCount; i++)
        g_iCapturePoint[i] = -1;
}

void SpawnFallbackCapturePack(int arena)
{
    float point_loc[3];
    point_loc[0] = g_fKothPointPos[arena][0];
    point_loc[1] = g_fKothPointPos[arena][1];
    point_loc[2] = g_fKothPointPos[arena][2];

    g_iCapturePoint[arena] = CreateEntityByName("item_ammopack_small");
    if (g_iCapturePoint[arena] == -1)
        return;

    TeleportEntity(g_iCapturePoint[arena], point_loc, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(g_iCapturePoint[arena]);
    SetEntProp(g_iCapturePoint[arena], Prop_Send, "m_iTeamNum", 1, 4);
    SetEntityModel(g_iCapturePoint[arena], MODEL_POINT);
    DispatchKeyValue(g_iCapturePoint[arena], "powerup_model", MODEL_BRIEFCASE);
    SDKHook(g_iCapturePoint[arena], SDKHook_StartTouch, OnTouchPoint);
    SDKHook(g_iCapturePoint[arena], SDKHook_EndTouch, OnEndTouchPoint);
    AcceptEntityInput(g_iCapturePoint[arena], "Disable");
}

ConVar g_hCapDeteriorate = null;

void ApplyKothClockFromMap()
{
    float origins[32][3];
    int timers[32];
    int unlocks[32];
    int count = 0;

    int lumpCount = EntityLump.Length();
    for (int i = 0; i < lumpCount; i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        char classname[64];
        entry.GetNextKey("classname", classname, sizeof(classname));
        if (StrEqual(classname, "tf_logic_koth") && count < 32)
        {
            char originText[64], timerText[16], unlockText[16];
            entry.GetNextKey("origin", originText, sizeof(originText));
            entry.GetNextKey("timer_length", timerText, sizeof(timerText));
            entry.GetNextKey("unlock_point", unlockText, sizeof(unlockText));
            ParseVectorString(originText, origins[count]);
            timers[count] = StringToInt(timerText);
            unlocks[count] = StringToInt(unlockText);
            count++;
        }
        delete entry;
    }

    if (count < 1)
        return;

    for (int arena = 1; arena <= g_iArenaCount; arena++)
    {
        if (!g_bArenaKoth[arena])
            continue;

        int chosen = 0;
        if (count > 1)
        {
            float best = -1.0;
            for (int i = 0; i < count; i++)
            {
                float dist = GetVectorDistance(origins[i], g_fKothPointPos[arena], false);
                if (best < 0.0 || dist < best)
                {
                    best = dist;
                    chosen = i;
                }
            }
        }

        if (timers[chosen] > 0)
            g_iDefaultCapTime[arena] = timers[chosen];
        if (unlocks[chosen] > 0)
            g_iKothUnlockSeconds[arena] = unlocks[chosen];
    }
}

void ReadArenaCaptureRules(int arena, int trigger)
{
    g_bKothRulesFromMap[arena] = false;
    g_bKothWaveFromMap[arena] = false;
    g_bKothCanCap[arena][TEAM_RED] = true;
    g_bKothCanCap[arena][TEAM_BLU] = true;
    g_iKothStartCap[arena][TEAM_RED] = 1;
    g_iKothStartCap[arena][TEAM_BLU] = 1;
    g_iKothNumCap[arena][TEAM_RED] = 0;
    g_iKothNumCap[arena][TEAM_BLU] = 0;
    g_fKothWaveNeutral[arena][TEAM_RED] = g_fArenaRespawnTime[arena];
    g_fKothWaveNeutral[arena][TEAM_BLU] = g_fArenaRespawnTime[arena];
    g_fKothWaveWhenOwner[arena][TEAM_RED][TEAM_RED] = g_fArenaRespawnTime[arena];
    g_fKothWaveWhenOwner[arena][TEAM_RED][TEAM_BLU] = g_fArenaRespawnTime[arena];
    g_fKothWaveWhenOwner[arena][TEAM_BLU][TEAM_RED] = g_fArenaRespawnTime[arena];
    g_fKothWaveWhenOwner[arena][TEAM_BLU][TEAM_BLU] = g_fArenaRespawnTime[arena];

    int hammer = 0;
    int hammerOffset = FindDataMapInfo(trigger, "m_iHammerID");
    if (hammerOffset != -1)
        hammer = GetEntData(trigger, hammerOffset, 4);

    float origin[3];
    GetEntPropVector(trigger, Prop_Data, "m_vecAbsOrigin", origin);

    int hammerIndex = -1;
    int originIndex = -1;
    float originDist = 16.0;
    int lumpCount = EntityLump.Length();
    for (int i = 0; i < lumpCount; i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        char classname[64];
        entry.GetNextKey("classname", classname, sizeof(classname));
        if (StrEqual(classname, "trigger_capture_area"))
        {
            if (hammer > 0)
            {
                char idText[16];
                if (entry.GetNextKey("hammerid", idText, sizeof(idText)) != -1 && StringToInt(idText) == hammer)
                    hammerIndex = i;
            }
            char originText[64];
            if (entry.GetNextKey("origin", originText, sizeof(originText)) != -1)
            {
                float lumpOrigin[3];
                ParseVectorString(originText, lumpOrigin);
                float dist = GetVectorDistance(lumpOrigin, origin, false);
                if (dist < originDist)
                {
                    originDist = dist;
                    originIndex = i;
                }
            }
        }
        delete entry;
        if (hammerIndex != -1)
            break;
    }

    int useIndex = hammerIndex != -1 ? hammerIndex : originIndex;
    if (useIndex == -1)
    {
        LogError("Arena %d capture trigger %d was not found in the entity lump", arena, trigger);
        return;
    }

    EntityLumpEntry entry = EntityLump.Get(useIndex);
    float areaTime = 0.0;
    int ownerForOutput[3];
    ownerForOutput[1] = TEAM_RED;
    ownerForOutput[2] = TEAM_BLU;
    bool sawWave[3];
    bool sawRedWave[3];
    bool sawBluWave[3];
    float redWave[3];
    float bluWave[3];
    for (int slot = 0; slot < 3; slot++)
    {
        sawWave[slot] = false;
        sawRedWave[slot] = false;
        sawBluWave[slot] = false;
        redWave[slot] = 0.0;
        bluWave[slot] = 0.0;
    }

    int keyCount = entry.Length;
    for (int k = 0; k < keyCount; k++)
    {
        char key[64], value[160];
        entry.Get(k, key, sizeof(key), value, sizeof(value));
        if (StrEqual(key, "area_time_to_cap"))
            areaTime = StringToFloat(value);
        else if (StrEqual(key, "team_numcap_2"))
            g_iKothNumCap[arena][TEAM_RED] = StringToInt(value);
        else if (StrEqual(key, "team_numcap_3"))
            g_iKothNumCap[arena][TEAM_BLU] = StringToInt(value);
        else if (StrEqual(key, "team_startcap_2"))
            g_iKothStartCap[arena][TEAM_RED] = StringToInt(value);
        else if (StrEqual(key, "team_startcap_3"))
            g_iKothStartCap[arena][TEAM_BLU] = StringToInt(value);
        else if (StrEqual(key, "team_cancap_2"))
            g_bKothCanCap[arena][TEAM_RED] = StringToInt(value) != 0;
        else if (StrEqual(key, "team_cancap_3"))
            g_bKothCanCap[arena][TEAM_BLU] = StringToInt(value) != 0;
        else if (StrEqual(key, "OnCapTeam1") || StrEqual(key, "OnCapTeam2"))
        {
            int slot = StrEqual(key, "OnCapTeam1") ? 1 : 2;
            char pieces[5][64];
            int pieceCount = ExplodeString(value, ",", pieces, 5, 64);
            if (pieceCount < 2)
                continue;
            if (StrEqual(pieces[1], "SetRedKothClockActive"))
                ownerForOutput[slot] = TEAM_RED;
            else if (StrEqual(pieces[1], "SetBlueKothClockActive"))
                ownerForOutput[slot] = TEAM_BLU;
            else if (StrEqual(pieces[1], "SetRedTeamRespawnWaveTime") && pieceCount >= 3)
            {
                redWave[slot] = StringToFloat(pieces[2]);
                sawRedWave[slot] = true;
                sawWave[slot] = true;
            }
            else if (StrEqual(pieces[1], "SetBlueTeamRespawnWaveTime") && pieceCount >= 3)
            {
                bluWave[slot] = StringToFloat(pieces[2]);
                sawBluWave[slot] = true;
                sawWave[slot] = true;
            }
        }
    }
    delete entry;

    if (areaTime > 0.0 && (g_iKothNumCap[arena][TEAM_RED] > 0 || g_iKothNumCap[arena][TEAM_BLU] > 0))
    {
        if (g_iKothNumCap[arena][TEAM_RED] < 1)
            g_iKothNumCap[arena][TEAM_RED] = g_iKothNumCap[arena][TEAM_BLU];
        if (g_iKothNumCap[arena][TEAM_BLU] < 1)
            g_iKothNumCap[arena][TEAM_BLU] = g_iKothNumCap[arena][TEAM_RED];
        g_fKothCapSeconds[arena][TEAM_RED] = 2.0 * areaTime * float(g_iKothNumCap[arena][TEAM_RED]);
        g_fKothCapSeconds[arena][TEAM_BLU] = 2.0 * areaTime * float(g_iKothNumCap[arena][TEAM_BLU]);
        g_bKothRulesFromMap[arena] = true;
        LogMessage("Arena %d capture time %.2fs / %.2fs for one player", arena, g_fKothCapSeconds[arena][TEAM_RED], g_fKothCapSeconds[arena][TEAM_BLU]);
    }

    for (int slot = 1; slot <= 2; slot++)
    {
        if (!sawWave[slot])
            continue;
        int owner = ownerForOutput[slot];
        g_bKothWaveFromMap[arena] = true;
        g_fKothWaveNeutral[arena][TEAM_RED] = 0.0;
        g_fKothWaveNeutral[arena][TEAM_BLU] = 0.0;
        if (sawRedWave[slot])
            g_fKothWaveWhenOwner[arena][owner][TEAM_RED] = redWave[slot];
        if (sawBluWave[slot])
            g_fKothWaveWhenOwner[arena][owner][TEAM_BLU] = bluWave[slot];
    }
}

void ParseVectorString(const char[] text, float out[3])
{
    out[0] = 0.0;
    out[1] = 0.0;
    out[2] = 0.0;
    int part = 0;
    int i = 0;
    while (text[i] != '\0' && part < 3)
    {
        while (text[i] == ' ')
            i++;
        if (text[i] == '\0')
            break;

        char token[32];
        int len = 0;
        while (text[i] != '\0' && text[i] != ' ' && len < sizeof(token) - 1)
            token[len++] = text[i++];
        token[len] = '\0';
        out[part] = StringToFloat(token);
        part++;
    }
}


// ===== GAME MECHANICS =====

float CaptureHarmonic(int units)
{
    float sum = 0.0;
    for (int i = 1; i <= units; i++)
        sum += 1.0 / float(i);
    return sum;
}

void CountSlotOnPoint(int arena, int slot, int &players, int &units)
{
    if (!g_bPlayerTouchPoint[arena][slot])
        return;

    int client = g_iArenaQueue[arena][slot];
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return;

    players++;
    units++;
    if (g_tfctPlayerClass[client] == TF2_GetClass("scout"))
        units++;

    int weapon = GetPlayerWeaponSlot(client, 2);
    if (weapon != -1 && IsValidEntity(weapon) && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 154)
        units++;
}

void CountTeamOnPoint(int arena, int team, int &players, int &units)
{
    players = 0;
    units = 0;
    int first = team == TEAM_RED ? SLOT_ONE : SLOT_TWO;
    int second = team == TEAM_RED ? SLOT_THREE : SLOT_FOUR;
    CountSlotOnPoint(arena, first, players, units);
    if (g_bFourPersonArena[arena])
        CountSlotOnPoint(arena, second, players, units);
}

int EffectiveCaptureUnits(int arena, int team, int players, int units)
{
    if (!g_bKothCanCap[arena][team])
        return 0;
    if (g_iKothStartCap[arena][team] > 0 && players < g_iKothStartCap[arena][team])
        return 0;
    int cap = g_iKothNumCap[arena][team];
    if (cap > 0 && units > cap)
        units = cap;
    if (units < 1)
        return 0;
    return units;
}

float CapturePercentDelta(int arena, int team, int units, float dt)
{
    float seconds = g_fKothCapSeconds[arena][team];
    if (seconds <= 0.0 || units < 1)
        return 0.0;
    return 100.0 * CaptureHarmonic(units) / seconds * dt;
}

float DecayPercentDelta(int arena, float dt)
{
    if (g_hCapDeteriorate == null)
        g_hCapDeteriorate = FindConVar("mp_capdeteriorate_time");

    float seconds = 90.0;
    if (g_hCapDeteriorate != null && g_hCapDeteriorate.FloatValue > 0.0)
        seconds = g_hCapDeteriorate.FloatValue;
    if (g_bOvertimePlayed[arena][TEAM_RED] || g_bOvertimePlayed[arena][TEAM_BLU])
        seconds /= 6.0;
    if (seconds < 0.1)
        seconds = 0.1;
    return 100.0 / seconds * dt;
}

void PlayKothCapWarning(int arena_index)
{
    int red_1 = g_iArenaQueue[arena_index][SLOT_ONE];
    int blu_1 = g_iArenaQueue[arena_index][SLOT_TWO];
    char soundFile[64];
    int num = GetRandomInt(1, 3);
    if (num == 1)
        soundFile = "vo/announcer_control_point_warning.mp3";
    else if (num == 2)
        soundFile = "vo/announcer_control_point_warning2.mp3";
    else
        soundFile = "vo/announcer_control_point_warning3.mp3";

    if (g_iCappingTeam[arena_index] == TEAM_BLU)
    {
        if (IsValidClient(red_1))
            EmitSoundToClient(red_1, soundFile);
    }
    else if (IsValidClient(blu_1))
    {
        EmitSoundToClient(blu_1, soundFile);
    }

    if (!g_bFourPersonArena[arena_index])
        return;

    int red_2 = g_iArenaQueue[arena_index][SLOT_THREE];
    int blu_2 = g_iArenaQueue[arena_index][SLOT_FOUR];
    if (g_iCappingTeam[arena_index] == TEAM_BLU)
    {
        if (IsValidClient(red_2))
            EmitSoundToClient(red_2, soundFile);
    }
    else if (IsValidClient(blu_2))
    {
        EmitSoundToClient(blu_2, soundFile);
    }
}

void FinishKothCapture(int arena_index)
{
    int red1, red2, blu1, blu2;
    if (g_bFourPersonArena[arena_index])
    {
        red1 = g_iArenaQueue[arena_index][SLOT_ONE];
        red2 = g_iArenaQueue[arena_index][SLOT_THREE];
        blu1 = g_iArenaQueue[arena_index][SLOT_TWO];
        blu2 = g_iArenaQueue[arena_index][SLOT_FOUR];
        if (g_iPointState[arena_index] == TEAM_RED)
        {
            if (IsValidClient(red1))
                EmitSoundToClient(red1, "vo/announcer_we_lost_control.mp3");
            if (IsValidClient(red2))
                EmitSoundToClient(red2, "vo/announcer_we_lost_control.mp3");
            if (IsValidClient(blu1))
                EmitSoundToClient(blu1, "vo/announcer_we_captured_control.mp3");
            if (IsValidClient(blu2))
                EmitSoundToClient(blu2, "vo/announcer_we_captured_control.mp3");

            g_iCappingTeam[arena_index] = TEAM_RED;
            g_iPointState[arena_index] = TEAM_BLU;
        }
        else if (g_iPointState[arena_index] == TEAM_BLU)
        {
            if (IsValidClient(red1))
                EmitSoundToClient(red1, "vo/announcer_we_captured_control.mp3");
            if (IsValidClient(red2))
                EmitSoundToClient(red2, "vo/announcer_we_captured_control.mp3");
            if (IsValidClient(blu1))
                EmitSoundToClient(blu1, "vo/announcer_we_lost_control.mp3");
            if (IsValidClient(blu2))
                EmitSoundToClient(blu2, "vo/announcer_we_lost_control.mp3");
            g_iCappingTeam[arena_index] = TEAM_BLU;
            g_iPointState[arena_index] = TEAM_RED;
        }
        else if (g_iCappingTeam[arena_index] == TEAM_RED)
        {
            EmitSoundToClient(red1, "vo/announcer_we_captured_control.mp3");
            EmitSoundToClient(red2, "vo/announcer_we_captured_control.mp3");
            g_iPointState[arena_index] = TEAM_RED;
            g_iCappingTeam[arena_index] = TEAM_BLU;
        }
        else
        {
            EmitSoundToClient(blu1, "vo/announcer_we_captured_control.mp3");
            EmitSoundToClient(blu2, "vo/announcer_we_captured_control.mp3");
            g_iPointState[arena_index] = TEAM_BLU;
            g_iCappingTeam[arena_index] = TEAM_RED;
        }
    }
    else
    {
        red1 = g_iArenaQueue[arena_index][SLOT_ONE];
        blu1 = g_iArenaQueue[arena_index][SLOT_TWO];
        if (g_iPointState[arena_index] == TEAM_RED)
        {
            EmitSoundToClient(red1, "vo/announcer_we_lost_control.mp3");
            EmitSoundToClient(blu1, "vo/announcer_we_captured_control.mp3");
            g_iCappingTeam[arena_index] = TEAM_RED;
            g_iPointState[arena_index] = TEAM_BLU;
        }
        else if (g_iPointState[arena_index] == TEAM_BLU)
        {
            EmitSoundToClient(red1, "vo/announcer_we_captured_control.mp3");
            EmitSoundToClient(blu1, "vo/announcer_we_lost_control.mp3");
            g_iCappingTeam[arena_index] = TEAM_BLU;
            g_iPointState[arena_index] = TEAM_RED;
        }
        else if (g_iCappingTeam[arena_index] == TEAM_RED)
        {
            EmitSoundToClient(red1, "vo/announcer_we_captured_control.mp3");
            g_iPointState[arena_index] = TEAM_RED;
            g_iCappingTeam[arena_index] = TEAM_BLU;
        }
        else
        {
            EmitSoundToClient(blu1, "vo/announcer_we_captured_control.mp3");
            g_iPointState[arena_index] = TEAM_BLU;
            g_iCappingTeam[arena_index] = TEAM_RED;
        }
    }

    g_fKothCappedPercent[arena_index] = 0.0;
    g_iKothMeterDir[arena_index] = 0;
    StartKothRespawnWaves(arena_index);
    SetKothCaptureSound(arena_index, KOTH_SND_IDLE, true);
    UpdateHudForArena(arena_index);
}

void StartKothRespawnWaves(int arena)
{
    int owner = g_iPointState[arena];
    float now = GetGameTime();
    for (int team = TEAM_RED; team <= TEAM_BLU; team++)
    {
        float wave = (owner == TEAM_RED || owner == TEAM_BLU)
            ? g_fKothWaveWhenOwner[arena][owner][team]
            : g_fKothWaveNeutral[arena][team];
        g_fKothNextWave[arena][team] = wave > 0.0 ? now + wave : 0.0;
    }
}

void ApplyMapCaptureRules(int arena)
{
    if (!g_bKothUnlockArmed[arena])
    {
        g_bKothUnlockArmed[arena] = true;
        g_fKothUnlockAt[arena] = GetGameTime() + float(g_iKothUnlockSeconds[arena]);
    }
    if (GetGameTime() < g_fKothUnlockAt[arena])
    {
        g_iKothMeterDir[arena] = 0;
        return;
    }

    float dt = GetGameFrameTime();
    if (dt <= 0.0)
        return;

    int redPlayers, redUnits, bluPlayers, bluUnits;
    CountTeamOnPoint(arena, TEAM_RED, redPlayers, redUnits);
    CountTeamOnPoint(arena, TEAM_BLU, bluPlayers, bluUnits);
    if (redPlayers > 0 && bluPlayers > 0)
    {
        g_iKothMeterDir[arena] = 0;
        return;
    }

    int redCapUnits = EffectiveCaptureUnits(arena, TEAM_RED, redPlayers, redUnits);
    int bluCapUnits = EffectiveCaptureUnits(arena, TEAM_BLU, bluPlayers, bluUnits);
    int point = g_iPointState[arena];
    float before = g_fKothCappedPercent[arena];
    float delta = 0.0;
    bool decaying = false;

    if (redCapUnits > 0 && (point == NEUTRAL || point == TEAM_BLU) && (g_iCappingTeam[arena] == TEAM_RED || g_iCappingTeam[arena] == NEUTRAL))
    {
        delta = CapturePercentDelta(arena, TEAM_RED, redCapUnits, dt);
        g_iCappingTeam[arena] = TEAM_RED;
    }
    else if (bluCapUnits > 0 && (point == NEUTRAL || point == TEAM_RED) && (g_iCappingTeam[arena] == TEAM_BLU || g_iCappingTeam[arena] == NEUTRAL))
    {
        delta = CapturePercentDelta(arena, TEAM_BLU, bluCapUnits, dt);
        g_iCappingTeam[arena] = TEAM_BLU;
    }
    else if (point == NEUTRAL && before > 0.0 && redCapUnits > 0 && g_iCappingTeam[arena] == TEAM_BLU)
    {
        delta = -CapturePercentDelta(arena, TEAM_RED, redCapUnits, dt);
    }
    else if (point == NEUTRAL && before > 0.0 && bluCapUnits > 0 && g_iCappingTeam[arena] == TEAM_RED)
    {
        delta = -CapturePercentDelta(arena, TEAM_BLU, bluCapUnits, dt);
    }
    else if (before > 0.0)
    {
        delta = -DecayPercentDelta(arena, dt);
        decaying = true;
    }

    g_iKothMeterDir[arena] = delta > 0.0 ? 1 : (delta < 0.0 ? -1 : 0);
    if (delta == 0.0)
        return;

    g_fKothCappedPercent[arena] = before + delta;
    if (delta > 0.0 && before <= 0.0)
    {
        PlayKothCapWarning(arena);
        PlayKothPointSound(arena, "Hologram.Start");
    }

    if (g_fKothCappedPercent[arena] >= 100.0)
    {
        g_fKothCappedPercent[arena] = 100.0;
        FinishKothCapture(arena);
        return;
    }
    if (g_fKothCappedPercent[arena] <= 0.0)
    {
        g_fKothCappedPercent[arena] = 0.0;
        g_iKothMeterDir[arena] = 0;
        if (point == NEUTRAL)
            g_iCappingTeam[arena] = NEUTRAL;
        if (decaying)
            SetKothCaptureSound(arena, KOTH_SND_IDLE, true);
    }
}

void PrecacheKothCaptureSounds()
{
    PrecacheScriptSound("Hologram.Start");
    PrecacheScriptSound("Hologram.Stop");
    PrecacheScriptSound("Hologram.Move");
    PrecacheScriptSound("Hologram.Interrupted");
    PrecacheScriptSound("Game.YourTeamWon");
    PrecacheScriptSound("Game.YourTeamLost");
    PrecacheSound("misc/hologram_start.wav", true);
    PrecacheSound("misc/hologram_stop.wav", true);
    PrecacheSound("misc/hologram_move.wav", true);
    PrecacheSound("misc/hologram_malfunction.wav", true);
}

void ClearKothCaptureSounds()
{
    int found[MAXARENAS * 2];
    int count = 0;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "ambient_generic")) != -1 && count < sizeof(found))
    {
        char name[64];
        GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
        if (StrContains(name, "mge_koth_snd_") == 0)
            found[count++] = ent;
    }

    for (int i = 0; i < count; i++)
    {
        if (IsValidEntity(found[i]))
            RemoveEntity(found[i]);
    }

    for (int arena = 0; arena <= MAXARENAS; arena++)
    {
        g_iKothCapSound[arena] = KOTH_SND_IDLE;
        g_iKothMoveLoop[arena] = -1;
        g_iKothBlockLoop[arena] = -1;
    }
}

void PlayKothPointSound(int arena, const char[] gameSound)
{
    EmitAmbientGameSound(gameSound, g_fKothPointPos[arena]);
}

int EnsureKothLoop(int arena, int mode)
{
    int ent = mode == KOTH_SND_CAPPING ? g_iKothMoveLoop[arena] : g_iKothBlockLoop[arena];
    if (ent != -1 && IsValidEntity(ent))
        return ent;

    ent = CreateEntityByName("ambient_generic");
    if (ent == -1)
        return -1;

    char name[40];
    Format(name, sizeof(name), "mge_koth_snd_%d_%d", arena, mode);
    DispatchKeyValue(ent, "targetname", name);
    DispatchKeyValue(ent, "message", mode == KOTH_SND_CAPPING ? "misc/hologram_move.wav" : "misc/hologram_malfunction.wav");
    DispatchKeyValue(ent, "health", "10");
    DispatchKeyValue(ent, "radius", "1800");
    DispatchKeyValue(ent, "pitch", "100");
    DispatchKeyValue(ent, "spawnflags", "16");
    DispatchSpawn(ent);
    ActivateEntity(ent);
    TeleportEntity(ent, g_fKothPointPos[arena], NULL_VECTOR, NULL_VECTOR);

    if (mode == KOTH_SND_CAPPING)
        g_iKothMoveLoop[arena] = ent;
    else
        g_iKothBlockLoop[arena] = ent;
    return ent;
}

void StopKothLoop(int arena, int mode)
{
    int ent = -1;
    if (mode == KOTH_SND_CAPPING)
        ent = g_iKothMoveLoop[arena];
    else if (mode == KOTH_SND_BLOCKED)
        ent = g_iKothBlockLoop[arena];

    if (ent != -1 && IsValidEntity(ent))
        AcceptEntityInput(ent, "StopSound");
}

void SetKothCaptureSound(int arena, int mode, bool playStop)
{
    int previous = g_iKothCapSound[arena];
    if (previous == mode)
        return;

    StopKothLoop(arena, previous);
    g_iKothCapSound[arena] = mode;

    if (mode == KOTH_SND_IDLE)
    {
        if (playStop && previous != KOTH_SND_IDLE)
            PlayKothPointSound(arena, "Hologram.Stop");
        return;
    }

    int ent = EnsureKothLoop(arena, mode);
    if (ent != -1)
        AcceptEntityInput(ent, "PlaySound");
}

void UpdateKothCaptureSound(int arena)
{
    if (g_bKothRulesFromMap[arena] && g_bKothUnlockArmed[arena] && GetGameTime() < g_fKothUnlockAt[arena])
    {
        SetKothCaptureSound(arena, KOTH_SND_IDLE, false);
        return;
    }

    int redPlayers, redUnits, bluPlayers, bluUnits;
    CountTeamOnPoint(arena, TEAM_RED, redPlayers, redUnits);
    CountTeamOnPoint(arena, TEAM_BLU, bluPlayers, bluUnits);

    float percent = g_fKothCappedPercent[arena];
    int mode = KOTH_SND_IDLE;
    if (percent > 0.0 && redPlayers > 0 && bluPlayers > 0)
        mode = KOTH_SND_BLOCKED;
    else if (percent > 0.0)
        mode = KOTH_SND_CAPPING;

    SetKothCaptureSound(arena, mode, false);
}

// Process capture point mechanics across all active KOTH arenas
void ProcessKothCapturePoints()
{
    for (int arena_index = 1; arena_index <= g_iArenaCount; ++arena_index)
    {
        if (!g_bArenaKoth[arena_index])
            continue;

        if (g_bKothRoundPause[arena_index])
        {
            if (g_iKothCapSound[arena_index] != KOTH_SND_IDLE)
                SetKothCaptureSound(arena_index, KOTH_SND_IDLE, false);
            continue;
        }

        if (g_iArenaStatus[arena_index] == AS_FIGHT)
        {
            ProcessKothArenaCapture(arena_index);
            UpdateKothCaptureSound(arena_index);
        }
        else if (g_iKothCapSound[arena_index] != KOTH_SND_IDLE)
            SetKothCaptureSound(arena_index, KOTH_SND_IDLE, false);
    }
}

// Handle capture logic, timing, and team calculations for a specific arena
void ProcessKothArenaCapture(int arena_index)
{
    if (g_bKothRulesFromMap[arena_index])
    {
        ApplyMapCaptureRules(arena_index);
        return;
    }

    g_fTotalTime[arena_index] += 7;
    
    if (g_iPointState[arena_index] == NEUTRAL || g_iPointState[arena_index] == TEAM_BLU)
    {
        // If RED Team is capping and BLU Team isn't and BLU Team has the point increase the cap time
        if (!(g_bPlayerTouchPoint[arena_index][SLOT_TWO] || g_bPlayerTouchPoint[arena_index][SLOT_FOUR]) && (g_iCappingTeam[arena_index] == TEAM_RED || g_iCappingTeam[arena_index] == NEUTRAL))
        {
            int cap = 0;

            if (g_bPlayerTouchPoint[arena_index][SLOT_ONE])
            {
                cap++;
                // If the player is a Scout add one to the cap speed
                if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_ONE]] == TF2_GetClass("scout"))
                    cap++;

                int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_ONE], 2);
                int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

                // If the player has the Pain Train equipped add one to the cap speed
                if (iItemDefinitionIndex == 154)
                    cap++;
            }
            if (g_bPlayerTouchPoint[arena_index][SLOT_THREE])
            {
                cap++;
                // If the player is a Scout add one to the cap speed
                if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_THREE]] == TF2_GetClass("scout"))
                    cap++;

                int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_THREE], 2);
                int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

                // If the player has the Pain Train equipped add one to the cap speed
                if (iItemDefinitionIndex == 154)
                    cap++;
            }
            // Add cap time if needed
            if (cap)
            {
                // True harmonic cap time, yes!
                for (; cap > 0; cap--)
                {
                    g_fCappedTime[arena_index] += 7.0 / float(cap);
                }
                g_iCappingTeam[arena_index] = TEAM_RED;
                return;
            }
        }
    }

    if (g_iPointState[arena_index] == NEUTRAL || g_iPointState[arena_index] == TEAM_RED)
    {
        // If BLU Team is capping and Team RED isn't and Team RED has the point increase the cap time
        if (!(g_bPlayerTouchPoint[arena_index][SLOT_ONE] || g_bPlayerTouchPoint[arena_index][SLOT_THREE]) && (g_iCappingTeam[arena_index] == TEAM_BLU || g_iCappingTeam[arena_index] == NEUTRAL))
        {
            int cap = 0;

            if (g_bPlayerTouchPoint[arena_index][SLOT_TWO])
            {
                cap++;
                // If the player is a Scout add one to the cap speed
                if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_TWO]] == TF2_GetClass("scout"))
                    cap++;

                int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_TWO], 2);
                int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

                // If the player has the Pain Train equipped add one to the cap speed
                if (iItemDefinitionIndex == 154)
                    cap++;
            }
            if (g_bPlayerTouchPoint[arena_index][SLOT_FOUR])
            {
                cap++;
                // If the player is a Scout add one to the cap speed
                if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_FOUR]] == TF2_GetClass("scout"))
                    cap++;

                int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_FOUR], 2);
                int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

                // If the player has the Pain Train equipped add one to the cap speed
                if (iItemDefinitionIndex == 154)
                    cap++;
            }
            // Add cap time if needed
            if (cap)
            {
                // True harmonic cap time, yes!
                for (; cap > 0; cap--)
                {
                    g_fCappedTime[arena_index] += 7.0 / float(cap);
                }
                g_iCappingTeam[arena_index] = TEAM_BLU;
                return;
            }
        }
    }

    // If BLU Team is blocking and RED Team isn't capping and BLU Team has the point increase the cap diminish rate
    if ((g_bPlayerTouchPoint[arena_index][SLOT_TWO] || g_bPlayerTouchPoint[arena_index][SLOT_FOUR]) &&
        (g_iPointState[arena_index] == NEUTRAL) && g_iCappingTeam[arena_index] == TEAM_RED &&
        !(g_bPlayerTouchPoint[arena_index][SLOT_ONE] || g_bPlayerTouchPoint[arena_index][SLOT_THREE]))
    {
        int cap = 0;

        if (g_bPlayerTouchPoint[arena_index][SLOT_TWO])
        {
            cap++;
            // If the player is a Scout add one to the cap speed
            if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_TWO]] == TF2_GetClass("scout"))
                cap++;

            int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_TWO], 2);
            int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

            // If the player has the Pain Train equipped add one to the cap speed
            if (iItemDefinitionIndex == 154)
                cap++;
        }
        if (g_bPlayerTouchPoint[arena_index][SLOT_FOUR])
        {
            cap++;
            // If the player is a Scout add one to the cap speed
            if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_FOUR]] == TF2_GetClass("scout"))
                cap++;

            int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_FOUR], 2);
            int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

            // If the player has the Pain Train equipped add one to the cap speed
            if (iItemDefinitionIndex == 154)
                cap++;
        }
        // Add cap time if needed
        if (cap)
        {
            // True harmonic cap time, yes!
            for (; cap > 0; cap--)
            {
                g_fCappedTime[arena_index] -= 7.0 / float(cap);
            }
            g_iCappingTeam[arena_index] = TEAM_BLU;
            return;
        }
    }

    // If RED Team is blocking and BLU Team isn't capping and RED Team has the point increase the cap diminish rate
    if ((g_bPlayerTouchPoint[arena_index][SLOT_ONE] || g_bPlayerTouchPoint[arena_index][SLOT_THREE]) &&
        (g_iPointState[arena_index] == NEUTRAL) && g_iCappingTeam[arena_index] == TEAM_BLU &&
        !(g_bPlayerTouchPoint[arena_index][SLOT_TWO] || g_bPlayerTouchPoint[arena_index][SLOT_FOUR]))
    {
        int cap = 0;

        if (g_bPlayerTouchPoint[arena_index][SLOT_ONE])
        {
            cap++;
            // If the player is a Scout add one to the cap speed
            if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_ONE]] == TF2_GetClass("scout"))
                cap++;

            int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_ONE], 2);
            int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

            // If the player has the Pain Train equipped add one to the cap speed
            if (iItemDefinitionIndex == 154)
                cap++;
        }
        if (g_bPlayerTouchPoint[arena_index][SLOT_THREE])
        {
            cap++;
            // If the player is a Scout add one to the cap speed
            if (g_tfctPlayerClass[g_iArenaQueue[arena_index][SLOT_THREE]] == TF2_GetClass("scout"))
                cap++;

            int ent = GetPlayerWeaponSlot(g_iArenaQueue[arena_index][SLOT_THREE], 2);
            int iItemDefinitionIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");

            // If the player has the Pain Train equipped add one to the cap speed
            if (iItemDefinitionIndex == 154)
                cap++;
        }
        // Add cap time if needed
        if (cap)
        {
            // True harmonic cap time, yes!
            for (; cap > 0; cap--)
            {
                g_fCappedTime[arena_index] -= 7.0 / float(cap);
            }
            g_iCappingTeam[arena_index] = TEAM_RED;
            return;
        }
    }

    // If both teams are touching the point, do nothing
    if ((g_bPlayerTouchPoint[arena_index][SLOT_TWO] || g_bPlayerTouchPoint[arena_index][SLOT_FOUR]) && (g_bPlayerTouchPoint[arena_index][SLOT_ONE] || g_bPlayerTouchPoint[arena_index][SLOT_THREE]))
        return;

    // If in overtime, revert cap at 6x speed, if not, revert cap slowly
    if (g_bOvertimePlayed[arena_index][TEAM_RED] || g_bOvertimePlayed[arena_index][TEAM_BLU])
        g_fCappedTime[arena_index] -= 6.0;
    else
        g_fCappedTime[arena_index]--;
}

// Complete KOTH match including win conditions, ELO calculations, and queue management
void EndKoth(any arena_index, any winner_team)
{
    PlayEndgameSoundsToArena(arena_index, winner_team);
    AddArenaTeamScore(arena_index, winner_team);
    int fraglimit = g_iArenaFraglimit[arena_index];
    int client = g_iArenaQueue[arena_index][winner_team];
    int client_slot = winner_team;
    int foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int foe = g_iArenaQueue[arena_index][foe_slot];
    int client_teammate;
    int foe_teammate;

    // End the Timer if its still running
    // You shouldn't need to do this, but just incase
    if (g_bTimerRunning[arena_index])
    {
        delete g_tKothTimer[arena_index];
        g_bTimerRunning[arena_index] = false;
    }

    if (g_bFourPersonArena[arena_index])
    {
        client_teammate = GetPlayerTeammate(client_slot, arena_index);
        foe_teammate = GetPlayerTeammate(foe_slot, arena_index);
    }

    if (fraglimit > 0 && g_iArenaScore[arena_index][winner_team] >= fraglimit && g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED)
    {
        SetArenaStatus(arena_index, AS_REPORTED);
        char foe_name[MAX_NAME_LENGTH];
        GetClientName(foe, foe_name, sizeof(foe_name));
        char client_name[MAX_NAME_LENGTH];
        GetClientName(client, client_name, sizeof(client_name));

        if (g_bFourPersonArena[arena_index])
        {
            char client_teammate_name[128];
            char foe_teammate_name[128];

            GetClientName(client_teammate, client_teammate_name, sizeof(client_teammate_name));
            GetClientName(foe_teammate, foe_teammate_name, sizeof(foe_teammate_name));

            Format(client_name, sizeof(client_name), "%s and %s", client_name, client_teammate_name);
            Format(foe_name, sizeof(foe_name), "%s and %s", foe_name, foe_teammate_name);
        }

        MC_PrintToChatAll("%t", "XdefeatsY", client_name, g_iArenaScore[arena_index][winner_team], foe_name, g_iArenaScore[arena_index][foe_slot], fraglimit, g_sArenaName[arena_index]);

        if (!g_bFourPersonArena[arena_index])
            CallForward_On1v1MatchEnd(arena_index, client, foe, g_iArenaScore[arena_index][winner_team], g_iArenaScore[arena_index][foe_slot]);
        else
            CallForward_On2v2MatchEnd(arena_index, (winner_team == SLOT_ONE) ? TEAM_RED : TEAM_BLU, g_iArenaScore[arena_index][winner_team], g_iArenaScore[arena_index][foe_slot],
                g_iArenaQueue[arena_index][SLOT_ONE], g_iArenaQueue[arena_index][SLOT_THREE],
                g_iArenaQueue[arena_index][SLOT_TWO], g_iArenaQueue[arena_index][SLOT_FOUR]);

        Rating_ReportResult(client, client_teammate, foe, foe_teammate);

        if (g_bFourPersonArena[arena_index] && g_iArenaQueue[arena_index][SLOT_FOUR + 1])
        {
            RemoveFromQueue(foe, false);
            RemoveFromQueue(foe_teammate, false);
            AddInQueue(foe, arena_index, false, 0, false);
            AddInQueue(foe_teammate, arena_index, false, 0, false);
        }
        else if (g_iArenaQueue[arena_index][SLOT_TWO + 1])
        {
            RemoveFromQueue(foe, false);
            AddInQueue(foe, arena_index, false, 0, false);
        } else {
            // For 2v2 arenas, return to ready state instead of restarting immediately
            if (g_bFourPersonArena[arena_index])
            {
                CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
            }
            else
            {
                CreateTimer(3.0, Timer_StartDuel, arena_index);
            }
            PlayKothRoundHumiliation(arena_index, winner_team, 2.0);
        }
    } else {
        g_bKothRoundPause[arena_index] = true;
        SetKothCaptureSound(arena_index, KOTH_SND_IDLE, false);
        PlayKothRoundHumiliation(arena_index, winner_team, 10.0);
        CreateTimer(10.0, Timer_FinishKothRound, arena_index);
    }

    UpdateHud(client);
    UpdateHud(foe);

    if (g_bFourPersonArena[arena_index])
    {
        UpdateHud(client_teammate);
        UpdateHud(foe_teammate);
    }
}

void PlayKothRoundHumiliation(int arena, int winner_slot, float duration)
{
    int maxSlots = g_bFourPersonArena[arena] ? SLOT_FOUR : SLOT_TWO;
    for (int slot = SLOT_ONE; slot <= maxSlots; slot++)
    {
        int client = g_iArenaQueue[arena][slot];
        if (!IsValidClient(client) || !IsPlayerAlive(client))
            continue;

        bool winner = winner_slot == SLOT_ONE
            ? (slot == SLOT_ONE || slot == SLOT_THREE)
            : (slot == SLOT_TWO || slot == SLOT_FOUR);
        if (winner)
        {
            TF2_AddCondition(client, TFCond_CritOnWin, duration);
            continue;
        }

        g_bKothLoserScream[client] = true;
        TF2_StunPlayer(client, duration, 0.0, TF_STUNFLAG_THIRDPERSON | TF_STUNFLAG_NOSOUNDOREFFECT | TF_STUNFLAG_GHOSTEFFECT);
        g_bKothLoserScream[client] = false;
    }
}

Action Timer_FinishKothRound(Handle timer, int arena_index)
{
    g_bKothRoundPause[arena_index] = false;
    ResetArena(arena_index);

    int maxSlots = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int slot = SLOT_ONE; slot <= maxSlots; slot++)
    {
        int client = g_iArenaQueue[arena_index][slot];
        if (!IsValidClient(client))
            continue;

        TF2_RemoveCondition(client, TFCond_CritOnWin);
        TF2_RemoveCondition(client, TFCond_Dazed);
        ResetPlayer(client);
    }

    g_bPlayerTouchPoint[arena_index][SLOT_ONE] = false;
    g_bPlayerTouchPoint[arena_index][SLOT_TWO] = false;
    g_bPlayerTouchPoint[arena_index][SLOT_THREE] = false;
    g_bPlayerTouchPoint[arena_index][SLOT_FOUR] = false;
    g_iKothTimer[arena_index][TEAM_RED] = g_iDefaultCapTime[arena_index];
    g_iKothTimer[arena_index][TEAM_BLU] = g_iDefaultCapTime[arena_index];
    g_fKothCappedPercent[arena_index] = 0.0;
    g_iCappingTeam[arena_index] = NEUTRAL;
    g_iPointState[arena_index] = NEUTRAL;
    g_fCappedTime[arena_index] = 0.0;
    g_bOvertimePlayed[arena_index][TEAM_RED] = false;
    g_bOvertimePlayed[arena_index][TEAM_BLU] = false;
    g_bKothUnlockArmed[arena_index] = false;
    g_fKothNextWave[arena_index][TEAM_RED] = 0.0;
    g_fKothNextWave[arena_index][TEAM_BLU] = 0.0;
    g_tKothTimer[arena_index] = CreateTimer(1.0, Timer_CountDownKoth, arena_index, TIMER_REPEAT);
    g_bTimerRunning[arena_index] = true;
    if (g_bArenaUltiduo[arena_index])
        g_fUltiduoMoveUnlockAt[arena_index] = GetGameTime() + 5.0;
    UpdateHudForArena(arena_index);
    return Plugin_Stop;
}


// ===== EVENT HANDLERS =====

// When the point is touched
Action OnTouchPoint(int entity, int other)
{
    int arena_index;
    int client_slot;
    if (!IsCaptureTouch(entity, other, arena_index, client_slot))
        return Plugin_Continue;

    g_bPlayerTouchPoint[arena_index][client_slot] = true;
    UpdateHudForArena(arena_index);
    return Plugin_Continue;
}

// When the point is no longer touched
Action OnEndTouchPoint(int entity, int other)
{
    int arena_index;
    int client_slot;
    if (!IsCaptureTouch(entity, other, arena_index, client_slot))
        return Plugin_Continue;

    g_bPlayerTouchPoint[arena_index][client_slot] = false;
    UpdateHudForArena(arena_index);
    return Plugin_Continue;
}

bool IsCaptureTouch(int entity, int client, int &arena_index, int &client_slot)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return false;

    arena_index = g_iPlayerArena[client];
    client_slot = g_iPlayerSlot[client];
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return false;
    if (client_slot < SLOT_ONE || client_slot > SLOT_FOUR)
        return false;
    if (g_iCapturePoint[arena_index] != entity)
        return false;

    return true;
}


// ===== COMMANDS =====

// Allow players to switch current arena to KOTH gamemode
Action Command_Koth(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index) {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    if (g_bArenaKoth[arena_index]) {
        MC_PrintToChat(client, "%t", "ArenaAlreadyKOTH");
        return Plugin_Handled;
    }

    if (!g_bArenaAllowKoth[arena_index]) {
        MC_PrintToChat(client, "%t", "CannotKOTHInArena");
        return Plugin_Handled;
    }

    if (g_iArenaStatus[arena_index] != AS_IDLE) {
        MC_PrintToChat(client, "%t", "CannotSwitchKOTHNow");
        return Plugin_Handled;
    }

    g_bArenaKoth[arena_index] = true;
    g_bArenaMGE[arena_index] = false;
    g_fArenaRespawnTime[arena_index] = 5.0;
    g_iArenaFraglimit[arena_index] = g_iArenaCaplimit[arena_index];
    CreateTimer(1.5, Timer_StartDuel, arena_index);
    UpdateArenaName(arena_index);

    if(g_iArenaQueue[arena_index][SLOT_ONE]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_ONE], "%t", "ChangedArenaToKOTH");
    }

    if(g_iArenaQueue[arena_index][SLOT_TWO]) {
        MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_TWO], "%t", "ChangedArenaToKOTH");
    }

    return Plugin_Handled;
}


// ===== UTILITIES =====

// Check if opposing team members are currently touching the capture point
bool EnemyTeamTouching(any team, any arena_index)
{
    if (team == TEAM_RED)
    {
        if (g_bPlayerTouchPoint[arena_index][SLOT_TWO])
            return true;
        else if (g_bFourPersonArena[arena_index] && g_bPlayerTouchPoint[arena_index][SLOT_FOUR])
            return true;
        else
            return false;
    }
    else
    {
        if (g_bPlayerTouchPoint[arena_index][SLOT_ONE])
            return true;
        else if (g_bFourPersonArena[arena_index] && g_bPlayerTouchPoint[arena_index][SLOT_THREE])
            return true;
        else
            return false;
    }
}


// ===== TIMER CALLBACKS =====

// Manage countdown timers, capture progress, overtime logic, and audio cues
Action Timer_CountDownKoth(Handle timer, any arena_index)
{
    if (timer != g_tKothTimer[arena_index])
        return Plugin_Stop;

    // If there was time spent on the point/time spent reverting the point add/remove perecent to the point for however long they were/n't standing on it
    if (!g_bKothRulesFromMap[arena_index] && g_fCappedTime[arena_index] != 0)
    {
        if (g_fKothCappedPercent[arena_index] == 0 && g_fCappedTime[arena_index] > 0)
        {
            int red_1 = g_iArenaQueue[arena_index][SLOT_ONE];
            int blu_1 = g_iArenaQueue[arena_index][SLOT_TWO];
            char SoundFileTemp[64];
            int num = GetRandomInt(1, 3);
            if (num == 1)
            {
                SoundFileTemp = "vo/announcer_control_point_warning.mp3";
            }
            else if (num == 2)
            {
                SoundFileTemp = "vo/announcer_control_point_warning2.mp3";
            }
            else
            {
                SoundFileTemp = "vo/announcer_control_point_warning3.mp3";
            }

            if (g_iCappingTeam[arena_index] == TEAM_BLU)
            {
                if (IsValidClient(red_1))
                    EmitSoundToClient(red_1, SoundFileTemp);
            }
            else
            {
                if (IsValidClient(blu_1))
                    EmitSoundToClient(blu_1, SoundFileTemp);
            }

            if (g_bFourPersonArena[arena_index])
            {
                int red_2 = g_iArenaQueue[arena_index][SLOT_THREE];
                int blu_2 = g_iArenaQueue[arena_index][SLOT_FOUR];
                if (g_iCappingTeam[arena_index] == TEAM_BLU)
                {
                    if (IsValidClient(red_2))
                        EmitSoundToClient(red_2, SoundFileTemp);
                }
                else
                {
                    if (IsValidClient(blu_2))
                        EmitSoundToClient(blu_2, SoundFileTemp);
                }
            }

        }
        if (g_fTotalTime[arena_index] != 0)
        {
            float cap = (g_fCappedTime[arena_index] * 8.4) / g_fTotalTime[arena_index];
            if (!g_bArenaUltiduo[arena_index])
                cap = cap * 1.5;
            g_fKothCappedPercent[arena_index] += cap;
        }

        g_fCappedTime[arena_index] = 0.0;
    }
    g_fTotalTime[arena_index] = 0.0;
    // If the cap is below 0 then reset it to 0
    if (g_fKothCappedPercent[arena_index] <= 0)
    {
        g_fKothCappedPercent[arena_index] = 0.0;

        if (g_iPointState[arena_index] == NEUTRAL)
            g_iCappingTeam[arena_index] = NEUTRAL;
    }

    if (g_fKothCappedPercent[arena_index] >= 100.0)
        FinishKothCapture(arena_index);
    else if (g_iKothTimer[arena_index][g_iPointState[arena_index]] > 0)
    {
        g_iKothTimer[arena_index][g_iPointState[arena_index]]--;
    }

    if (g_iArenaQueue[arena_index][SLOT_ONE])
        UpdateHud(g_iArenaQueue[arena_index][SLOT_ONE]);
    if (g_iArenaQueue[arena_index][SLOT_ONE])
        UpdateHud(g_iArenaQueue[arena_index][SLOT_TWO]);

    if (g_bFourPersonArena[arena_index])
    {
        UpdateHud(g_iArenaQueue[arena_index][SLOT_THREE]);
        UpdateHud(g_iArenaQueue[arena_index][SLOT_FOUR]);
    }

    if (g_iArenaStatus[arena_index] > AS_FIGHT)
    {
        g_bTimerRunning[arena_index] = false;
        return Plugin_Stop;
    }

    // Play the count down sounds
    int kothTimeLeft = g_iKothTimer[arena_index][g_iPointState[arena_index]];
    if (kothTimeLeft == 60 || kothTimeLeft == 30 || kothTimeLeft == 10 || (kothTimeLeft <= 5 && kothTimeLeft > 0))
    {
        char SoundFile[64];
        switch (kothTimeLeft)
        {
            case 60:
            SoundFile = "vo/announcer_ends_60sec.mp3";
            case 30:
            SoundFile = "vo/announcer_ends_30sec.mp3";
            case 10:
            SoundFile = "vo/announcer_ends_10sec.mp3";
            case 5:
            SoundFile = "vo/announcer_ends_5sec.mp3";
            case 4:
            SoundFile = "vo/announcer_ends_4sec.mp3";
            case 3:
            SoundFile = "vo/announcer_ends_3sec.mp3";
            case 2:
            SoundFile = "vo/announcer_ends_2sec.mp3";
            case 1:
            SoundFile = "vo/announcer_ends_1sec.mp3";
            default:
            SoundFile = "vo/announcer_ends_5sec.mp3";
        }

        if (g_bFourPersonArena[arena_index])
        {
            int red1 = g_iArenaQueue[arena_index][SLOT_ONE];
            int red2 = g_iArenaQueue[arena_index][SLOT_THREE];
            int blu1 = g_iArenaQueue[arena_index][SLOT_TWO];
            int blu2 = g_iArenaQueue[arena_index][SLOT_FOUR];
            EmitSoundToClient(blu1, SoundFile);
            EmitSoundToClient(blu2, SoundFile);
            EmitSoundToClient(red1, SoundFile);
            EmitSoundToClient(red2, SoundFile);
        }
        else
        {
            int red1 = g_iArenaQueue[arena_index][SLOT_ONE];
            int blu1 = g_iArenaQueue[arena_index][SLOT_TWO];
            EmitSoundToClient(blu1, SoundFile);
            EmitSoundToClient(red1, SoundFile);
        }
    }

    // If the point is capped, the timer for the capped team is out and the other team is not touching the point and has no cap time on the point, end the game.
    if (g_iPointState[arena_index] > NEUTRAL && g_iKothTimer[arena_index][g_iPointState[arena_index]] <= 0 && g_fKothCappedPercent[arena_index] <= 0 && !EnemyTeamTouching(g_iPointState[arena_index], arena_index))
    {
        g_bTimerRunning[arena_index] = false;
        // I know this is shit but fuck the police
        EndKoth(arena_index, g_iPointState[arena_index] - 1);
        return Plugin_Stop;
    }
    // If the time is at 0 and a team owns the point and OT hasn't been played already tell the arena it's OT
    if (g_iPointState[arena_index] > NEUTRAL && g_iKothTimer[arena_index][g_iPointState[arena_index]] == 0)
    {
        // Fixes the infinite OT sound bug, so "Overtime!" only gets played once
        if (!g_bOvertimePlayed[arena_index][g_iPointState[arena_index]])
        {

            char SoundFileTemp[64];
            int red1 = g_iArenaQueue[arena_index][SLOT_ONE];
            int blu1 = g_iArenaQueue[arena_index][SLOT_TWO];

            switch (GetRandomInt(1, 4))
            {
                case 1: SoundFileTemp = "vo/announcer_overtime.mp3";
                case 2: SoundFileTemp = "vo/announcer_overtime2.mp3";
                case 3: SoundFileTemp = "vo/announcer_overtime3.mp3";
                case 4: SoundFileTemp = "vo/announcer_overtime4.mp3";
            }

            EmitSoundToClient(blu1, SoundFileTemp);
            EmitSoundToClient(red1, SoundFileTemp);

            if (g_bFourPersonArena[arena_index])
            {
                int blu2 = g_iArenaQueue[arena_index][SLOT_FOUR];
                int red2 = g_iArenaQueue[arena_index][SLOT_THREE];
                EmitSoundToClient(red2, SoundFileTemp);
                EmitSoundToClient(blu2, SoundFileTemp);
            }
            // The overtime sound has been played for this team and doesn't need to be played again for the rest of the round
            g_bOvertimePlayed[arena_index][g_iPointState[arena_index]] = true;
        }
    }

    return Plugin_Continue;
}
