
// ===== SPECTATOR HUD MANAGEMENT =====

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


// ===== TIMER FUNCTIONS =====

// Fixes spectator team assignment issues by cycling through teams
Action Timer_SpecFix(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
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
    
    // Only check if still in spectator
    if (GetClientTeam(client) != TEAM_SPEC || g_iPlayerArena[client] > 0)
    {
        return Plugin_Stop;
    }

    int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

    if (IsValidClient(target) && g_iPlayerArena[target])
    {
        g_iPlayerSpecTarget[client] = target;
        UpdateHud(client);
    }
    else
    {
        HideHud(client);
        g_iPlayerSpecTarget[client] = 0;
    }

    return Plugin_Stop;
}

// Shows periodic advertisements to spectators not in arenas
Action Timer_ShowAdv(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (IsValidClient(client) && g_iPlayerArena[client] == 0)
    {
        MC_PrintToChat(client, "%t", "Adv");
        CreateTimer(15.0, Timer_ShowAdv, userid);
    }

    return Plugin_Continue;
}


// ===== PLAYER COMMANDS =====

// Handles spectator command to detect and update spectator target
Action Command_Spec(int client, int args)
{  
    // Detecting spectator target
    if (!IsValidClient(client))
        return Plugin_Handled;

    CreateTimer(0.1, Timer_ChangeSpecTarget, GetClientUserId(client));
    return Plugin_Continue;
}
