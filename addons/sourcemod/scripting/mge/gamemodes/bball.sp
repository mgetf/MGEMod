// ===== ENTITY MANAGEMENT =====

void SetupBBallHoops()
{
    PrecacheModel(MODEL_BRIEFCASE, true);
    PrecacheModel(MODEL_AMMOPACK, true);

    for (int i = 0; i <= g_iArenaCount; i++)
    {
        if (g_bArenaBBall[i])
        {
            float hoop_1_loc[3];
            hoop_1_loc[0] = g_fBBallHoopPos[i][1][0];
            hoop_1_loc[1] = g_fBBallHoopPos[i][1][1];
            hoop_1_loc[2] = g_fBBallHoopPos[i][1][2];

            float hoop_2_loc[3];
            hoop_2_loc[0] = g_fBBallHoopPos[i][2][0];
            hoop_2_loc[1] = g_fBBallHoopPos[i][2][1];
            hoop_2_loc[2] = g_fBBallHoopPos[i][2][2];

            if (IsValidEntity(g_iBBallHoop[i][SLOT_ONE]) && g_iBBallHoop[i][SLOT_ONE] > 0)
                RemoveEntity(g_iBBallHoop[i][SLOT_ONE]);
            g_iBBallHoop[i][SLOT_ONE] = -1;

            if (IsValidEntity(g_iBBallHoop[i][SLOT_TWO]) && g_iBBallHoop[i][SLOT_TWO] > 0)
                RemoveEntity(g_iBBallHoop[i][SLOT_TWO]);
            g_iBBallHoop[i][SLOT_TWO] = -1;

            if (g_iBBallHoop[i][SLOT_ONE] == -1)
            {
                g_iBBallHoop[i][SLOT_ONE] = CreateEntityByName("item_ammopack_small");
                TeleportEntity(g_iBBallHoop[i][SLOT_ONE], hoop_1_loc, NULL_VECTOR, NULL_VECTOR);
                DispatchSpawn(g_iBBallHoop[i][SLOT_ONE]);
                SetEntProp(g_iBBallHoop[i][SLOT_ONE], Prop_Send, "m_iTeamNum", 1, 4);

                SDKHook(g_iBBallHoop[i][SLOT_ONE], SDKHook_StartTouch, OnTouchHoop);
            }

            if (g_iBBallHoop[i][SLOT_TWO] == -1)
            {
                g_iBBallHoop[i][SLOT_TWO] = CreateEntityByName("item_ammopack_small");
                TeleportEntity(g_iBBallHoop[i][SLOT_TWO], hoop_2_loc, NULL_VECTOR, NULL_VECTOR);
                DispatchSpawn(g_iBBallHoop[i][SLOT_TWO]);
                SetEntProp(g_iBBallHoop[i][SLOT_TWO], Prop_Send, "m_iTeamNum", 1, 4);

                SDKHook(g_iBBallHoop[i][SLOT_TWO], SDKHook_StartTouch, OnTouchHoop);
            }

            if (g_bVisibleHoops[i] == false)
            {
                AcceptEntityInput(g_iBBallHoop[i][SLOT_ONE], "Disable");
                AcceptEntityInput(g_iBBallHoop[i][SLOT_TWO], "Disable");
            }

            EnsureBBallIntel(i);
        }
    }
}

int EnsureBBallIntel(int arena_index)
{
    int intel = g_iBBallIntel[arena_index];
    if (IsValidEntity(intel) && intel > 0)
    {
        AcceptEntityInput(intel, "Disable");
        return intel;
    }

    intel = CreateEntityByName("item_ammopack_small");
    if (intel == -1)
    {
        LogError("[BBall] Arena %d: failed to create intel entity.", arena_index);
        g_iBBallIntel[arena_index] = -1;
        return -1;
    }

    g_iBBallIntel[arena_index] = intel;

    DispatchKeyValue(intel, "powerup_model", MODEL_BRIEFCASE);
    DispatchSpawn(intel);
    SetEntProp(intel, Prop_Send, "m_iTeamNum", 1, 4);
    SetEntPropFloat(intel, Prop_Send, "m_flModelScale", 1.15);
    SDKHook(intel, SDKHook_StartTouch, OnTouchIntel);
    AcceptEntityInput(intel, "Disable");

    return intel;
}

void ShowIntel(int arena_index, float pos[3])
{
    int intel = g_iBBallIntel[arena_index];

    if (!IsValidEntity(intel) || intel <= 0)
    {
        intel = EnsureBBallIntel(arena_index);
        if (intel == -1)
            return;
    }

    TeleportEntity(intel, pos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(intel, "Enable");
}

void HideIntel(int arena_index)
{
    int intel = g_iBBallIntel[arena_index];
    if (IsValidEntity(intel) && intel > 0)
        AcceptEntityInput(intel, "Disable");
}

void ResetIntel(int arena_index, any client = -1)
{
    if (!g_bArenaBBall[arena_index])
        return;

    float intel_loc[3];

    if (client != -1)
    {
        int client_slot = g_iPlayerSlot[client];
        g_bPlayerHasIntel[client] = false;

        if (client_slot == SLOT_ONE || client_slot == SLOT_THREE)
        {
            intel_loc[0] = g_fBBallIntelPos[arena_index][1][0];
            intel_loc[1] = g_fBBallIntelPos[arena_index][1][1];
            intel_loc[2] = g_fBBallIntelPos[arena_index][1][2];
        } else if (client_slot == SLOT_TWO || client_slot == SLOT_FOUR) {
            intel_loc[0] = g_fBBallIntelPos[arena_index][2][0];
            intel_loc[1] = g_fBBallIntelPos[arena_index][2][1];
            intel_loc[2] = g_fBBallIntelPos[arena_index][2][2];
        }
    } else {
        intel_loc[0] = g_fBBallIntelPos[arena_index][0][0];
        intel_loc[1] = g_fBBallIntelPos[arena_index][0][1];
        intel_loc[2] = g_fBBallIntelPos[arena_index][0][2];
    }

    ShowIntel(arena_index, intel_loc);
}


// ===== EVENT HANDLERS =====

Action OnTouchIntel(int entity, int other)
{
    int client = other;

    if (!IsValidClient(client))
        return Plugin_Continue;

    if (!g_bCanPlayerGetIntel[client])
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];

    if (entity != g_iBBallIntel[arena_index])
        return Plugin_Continue;

    g_bPlayerHasIntel[client] = true;
    char msg[64];
    Format(msg, sizeof(msg), "%T", "YouHaveTheIntel", client);
    PrintCenterText(client, msg);

    HideIntel(arena_index);

    int particle;
    TFTeam team = TF2_GetClientTeam(client);

    AttachParticle(client, team == TFTeam_Red ? "teleported_red" : "teleported_blue", particle);

    particle = EntRefToEntIndex(g_iClientParticle[client]);
    if (particle == 0 || !IsValidEntity(particle))
    {
        AttachParticle(client, team == TFTeam_Red ? g_sBBallParticleRed : g_sBBallParticleBlue, particle);
        g_iClientParticle[client] = EntIndexToEntRef(particle);
    }

    UpdateHud(client);
    EmitSoundToClient(client, "vo/intel_teamstolen.mp3");

    int foe = g_iArenaQueue[g_iPlayerArena[client]][(g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_TWO : SLOT_ONE];

    if (IsValidClient(foe))
    {
        EmitSoundToClient(foe, "vo/intel_enemystolen.mp3");
        UpdateHud(foe);
    }

    if (g_bFourPersonArena[g_iPlayerArena[client]])
    {
        int foe2 = g_iArenaQueue[g_iPlayerArena[client]][(g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_FOUR : SLOT_THREE];
        if (IsValidClient(foe2))
        {
            EmitSoundToClient(foe2, "vo/intel_enemystolen.mp3");
            UpdateHud(foe2);
        }
    }

    return Plugin_Continue;
}

Action OnTouchHoop(int entity, int other)
{
    int client = other;

    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];
    int fraglimit = g_iArenaFraglimit[arena_index];
    int client_slot = g_iPlayerSlot[client];
    int foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int foe = g_iArenaQueue[arena_index][foe_slot];
    int client_teammate;
    int foe_teammate;
    int foe_team_slot = (foe_slot > 2) ? (foe_slot - 2) : foe_slot;
    int client_team_slot = (client_slot > 2) ? (client_slot - 2) : client_slot;

    if (g_bFourPersonArena[arena_index])
    {
        client_teammate = GetPlayerTeammate(client_slot, arena_index);
        foe_teammate = GetPlayerTeammate(foe_slot, arena_index);
    }

    if (!IsValidClient(foe) || !g_bArenaBBall[arena_index])
        return Plugin_Continue;

    if (entity == g_iBBallHoop[arena_index][foe_slot] && g_bPlayerHasIntel[client])
    {
        RemoveClientParticle(client);

        char foe_name[MAX_NAME_LENGTH];
        GetClientName(foe, foe_name, sizeof(foe_name));
        char client_name[MAX_NAME_LENGTH];
        GetClientName(client, client_name, sizeof(client_name));

        g_bPlayerHasIntel[client] = false;
        AddArenaTeamScore(arena_index, client_team_slot);

        if (fraglimit > 0 && g_iArenaScore[arena_index][client_team_slot] >= fraglimit && g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED)
        {
            SetArenaStatus(arena_index, AS_REPORTED);
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

            MC_PrintToChatAll("%t", "XdefeatsY", client_name, g_iArenaScore[arena_index][client_team_slot], foe_name, g_iArenaScore[arena_index][foe_team_slot], fraglimit, g_sArenaName[arena_index]);

            if (!g_bFourPersonArena[arena_index])
                CallForward_On1v1MatchEnd(arena_index, client, foe, g_iArenaScore[arena_index][client_team_slot], g_iArenaScore[arena_index][foe_team_slot]);
            else
                CallForward_On2v2MatchEnd(arena_index, (client_team_slot == SLOT_ONE) ? TEAM_RED : TEAM_BLU, g_iArenaScore[arena_index][client_team_slot], g_iArenaScore[arena_index][foe_team_slot],
                    g_iArenaQueue[arena_index][SLOT_ONE], g_iArenaQueue[arena_index][SLOT_THREE],
                    g_iArenaQueue[arena_index][SLOT_TWO], g_iArenaQueue[arena_index][SLOT_FOUR]);

            Rating_ReportResult(client, client_teammate, foe, foe_teammate);

            HideIntel(arena_index);

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
                CreateTimer(3.0, Timer_StartDuel, arena_index);
            }
        } else {
            ResetPlayer(client);
            ResetPlayer(foe);

            if (g_bFourPersonArena[arena_index])
            {
                ResetPlayer(client_teammate);
                ResetPlayer(foe_teammate);
            }

            CreateTimer(0.15, Timer_ResetIntel, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        }

        UpdateHud(client);
        UpdateHud(foe);

        if (g_bFourPersonArena[arena_index])
        {
            UpdateHud(client_teammate);
            UpdateHud(foe_teammate);
        }

        EmitSoundToClient(client, "vo/intel_teamcaptured.mp3");
        EmitSoundToClient(foe, "vo/intel_enemycaptured.mp3");

        if (g_bFourPersonArena[arena_index])
        {
            if (IsValidClient(client_teammate))
                EmitSoundToClient(client_teammate, "vo/intel_teamcaptured.mp3");
            if (IsValidClient(foe_teammate))
                EmitSoundToClient(foe_teammate, "vo/intel_enemycaptured.mp3");
        }

        UpdateHudForArena(arena_index);
    }
    return Plugin_Continue;
}

void HandleBBallPlayerDeath(int victim, int killer, int arena_index)
{
    if (!g_bPlayerHasIntel[victim])
        return;

    g_bPlayerHasIntel[victim] = false;
    RemoveClientParticle(victim);

    float pos[3];
    GetClientAbsOrigin(victim, pos);
    float dist = DistanceAboveGround(victim);
    if (dist > -1)
        pos[2] = pos[2] - dist + 5;
    else
        pos[2] = g_fBBallIntelPos[arena_index][1][2];

    ShowIntel(arena_index, pos);

    EmitSoundToClient(victim, "vo/intel_teamdropped.mp3");
    if (IsValidClient(killer))
        EmitSoundToClient(killer, "vo/intel_enemydropped.mp3");
}


// ===== COMMANDS =====

Action Command_DropItem(int client, const char[] command, int argc)
{
    int arena_index = g_iPlayerArena[client];

    if (g_bArenaBBall[arena_index])
    {
        if (g_bPlayerHasIntel[client])
        {
            g_bPlayerHasIntel[client] = false;
            float pos[3];
            GetClientAbsOrigin(client, pos);
            float dist = DistanceAboveGroundAroundPlayer(client);
            if (dist > -1)
                pos[2] = pos[2] - dist + 5;
            else
                pos[2] = g_fBBallIntelPos[arena_index][1][2];

            ShowIntel(arena_index, pos);

            EmitSoundToClient(client, "vo/intel_teamdropped.mp3");
            RemoveClientParticle(client);

            g_bCanPlayerGetIntel[client] = false;
            CreateTimer(0.5, Timer_AllowPlayerCap, GetClientUserId(client));
        }
    }

    return Plugin_Continue;
}


// ===== TIMER CALLBACKS =====

Action Timer_ResetIntel(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    int arena_index = g_iPlayerArena[client];

    ResetIntel(arena_index, client);

    return Plugin_Continue;
}

Action Timer_AllowPlayerCap(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client))
        g_bCanPlayerGetIntel[client] = true;

    return Plugin_Continue;
}
