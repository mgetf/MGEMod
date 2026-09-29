
// ===== SPECTATOR HUD MANAGEMENT =====

// TF2 inserts OBS_MODE_POI (Passtime/MvM points of interest) at slot 6,
// shifting OBS_MODE_ROAMING to 7 here vs. 6 in base Source (HL2DM/CSS)
#define OBS_MODE_ROAMING 7
#define SPEC_CHASE_DISTANCE 200.0
#define SPEC_CHASE_HEIGHT   150.0

// Displays countdown messages to spectators watching a specific arena
void ShowCountdownToSpec(int arena_index, char[] text)
{
    if (!arena_index)
    {
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if
        (
            IsValidClient(i)
            && GetClientTeam(i) == TEAM_SPEC
            && g_iPlayerArena[g_iPlayerSpecTarget[i]] == arena_index
        )
        {
            PrintCenterText(i, text);
        }
    }
}

// Computes a third-person-style camera placement behind and slightly above a
// target (further back than TF2's normal chase cam), facing the target, for
// use when teleporting a freeroam spectator onto a newly cycled-to player.
void GetSpecChaseCamPosition(int target, float pos[3], float ang[3])
{
    float target_origin[3], target_ang[3];
    GetClientAbsOrigin(target, target_origin);
    GetClientEyeAngles(target, target_ang);

    float yaw_rad = DegToRad(target_ang[1]);

    pos[0] = target_origin[0] - (Cosine(yaw_rad) * SPEC_CHASE_DISTANCE);
    pos[1] = target_origin[1] - (Sine(yaw_rad) * SPEC_CHASE_DISTANCE);
    pos[2] = target_origin[2] + SPEC_CHASE_HEIGHT;

    float look_dir[3];
    SubtractVectors(target_origin, pos, look_dir);
    GetVectorAngles(look_dir, ang);
}

// ===== TIMER FUNCTIONS =====

// Fixes spectator team assignment issues by cycling through teams
Action Timer_SpecFix(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
        return Plugin_Continue;

    // Player may have since joined a new arena as an active fighter (e.g. hopping
    // arenas via !add) - don't clobber that back to spectator
    int player_arena = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];
    if (player_arena > 0 && player_slot > 0)
    {
        int max_active_slot = g_bFourPersonArena[player_arena] ? SLOT_FOUR : SLOT_TWO;
        if (player_slot <= max_active_slot)
            return Plugin_Continue;
    }

    if (GetClientTeam(client) != TEAM_SPEC)
        return Plugin_Continue;

    ChangeClientTeam(client, TEAM_RED);
    ChangeClientTeam(client, TEAM_SPEC);

    return Plugin_Continue;
}

// Updates spectator HUD for all arenas on a timer basis
Action Timer_SpecHudToAllArenas(Handle timer, int userid)
{
    for (int i = 1; i <= g_iArenaCount; i++)
    UpdateHudForArena(i);

    return Plugin_Continue;
}

// Changes dead player to spectator team after delay
Action Timer_ChangePlayerSpec(Handle timer, any player)
{
    if (IsValidClient(player) && !IsPlayerAlive(player))
    {
        ChangeClientTeam(player, TEAM_SPEC);
    }
    
    return Plugin_Continue;
}

// Updates spectator target and refreshes HUD when target changes
Action Timer_ChangeSpecTarget(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client))
    {
        return Plugin_Stop;
    }
    
    // Only check if still in spectator team
    if (GetClientTeam(client) != TEAM_SPEC)
    {
        return Plugin_Stop;
    }
    
    // Check if player is actively fighting (not waiting in queue)
    // If they're in an active slot, don't update spec target
    int player_arena = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];
    if (player_arena > 0 && player_slot > 0)
    {
        int max_active_slot = g_bFourPersonArena[player_arena] ? SLOT_FOUR : SLOT_TWO;
        if (player_slot <= max_active_slot)
        {
            // Player is in an active slot, shouldn't be spectating
            return Plugin_Stop;
        }
    }

    // Freeroam camera position is independent of m_hObserverTarget, so don't let
    // the engine's internal target cycling desync the HUD from what's on screen
    if (GetEntProp(client, Prop_Send, "m_iObserverMode") == OBS_MODE_ROAMING)
    {
        return Plugin_Stop;
    }

    int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

    if (IsValidClient(target) && g_iPlayerArena[target] > 0 && IsPlayerAlive(target))
    {
        if (g_iPlayerSpecTarget[client] != target)
        {
            g_iPlayerSpecTarget[client] = target;
            UpdateHud(client);
        }
    }
    else
    {
        if (g_iPlayerSpecTarget[client] != 0)
        {
            HideHud(client);
            g_iPlayerSpecTarget[client] = 0;
        }
    }

    return Plugin_Stop;
}

// Shows the join advertisement to spectators not in arenas.
// Repeats every mgemod_adv_interval seconds. Interval 0 prints once, then stops.
Action Timer_ShowAdv(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (IsValidClient(client) && g_iPlayerArena[client] == 0)
    {
        MC_PrintToChat(client, "%t", "Adv");
        if (g_fAdvInterval > 0.0)
            CreateTimer(g_fAdvInterval, Timer_ShowAdv, userid);
    }

    return Plugin_Continue;
}


// ===== PLAYER COMMANDS =====

// Single entry point for spec_next/spec_prev. Free spectators (not queued in
// any arena) get their target cycling hijacked so it only ever lands on alive
// arena players, with an explicit HUD sync and freeroam teleport handled here.
// Spectators still queued/waiting in an arena aren't hijacked - they keep the
// engine's default cycling behavior, and just get their HUD resynced afterward
// via Timer_ChangeSpecTarget once the engine has picked a target.
Action Command_SpecNavigation(int client, const char[] command, int args)
{
    bool isNext = StrEqual(command, "spec_next");
    bool isPrev = StrEqual(command, "spec_prev");
    if (!isNext && !isPrev)
        return Plugin_Continue;

    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_SPEC)
        return Plugin_Continue;

    if (g_iPlayerArena[client] > 0)
    {
        CreateTimer(0.1, Timer_ChangeSpecTarget, GetClientUserId(client));
        return Plugin_Continue;
    }

    int observer_mode = GetEntProp(client, Prop_Send, "m_iObserverMode");
    bool isRoaming = (observer_mode == OBS_MODE_ROAMING);

    int current_target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

    int valid_targets[MAXPLAYERS + 1];
    int target_count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && g_iPlayerArena[i] > 0 && IsPlayerAlive(i))
        {
            valid_targets[target_count++] = i;
        }
    }

    if (target_count == 0)
        return Plugin_Continue;

    int current_index = -1;
    for (int i = 0; i < target_count; i++)
    {
        if (valid_targets[i] == current_target)
        {
            current_index = i;
            break;
        }
    }

    int next_index;
    if (current_index == -1)
    {
        next_index = isNext ? 0 : (target_count - 1);
    }
    else if (isNext)
    {
        next_index = (current_index + 1) % target_count;
    }
    else
    {
        next_index = (current_index - 1 + target_count) % target_count;
    }

    int new_target = valid_targets[next_index];
    if (!IsValidClient(new_target) || !IsPlayerAlive(new_target) || g_iPlayerArena[new_target] <= 0)
        return Plugin_Continue;

    if (new_target != current_target)
        SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", new_target);

    if (GetEntProp(client, Prop_Send, "m_iObserverMode") != observer_mode)
        SetEntProp(client, Prop_Send, "m_iObserverMode", observer_mode);

    // In freeroam the camera is the client's own entity, so cycling targets
    // has to move the player there directly instead of relying on the engine
    if (isRoaming)
    {
        float cam_pos[3], cam_ang[3];
        GetSpecChaseCamPosition(new_target, cam_pos, cam_ang);
        TeleportEntity(client, cam_pos, cam_ang, NULL_VECTOR);
    }

    g_iPlayerSpecTarget[client] = new_target;
    UpdateHud(client);

    return Plugin_Handled;
}
