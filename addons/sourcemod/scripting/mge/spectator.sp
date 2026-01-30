
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

    // Check if current target is still valid and in arena
    if (IsValidClient(target) && g_iPlayerArena[target] && IsPlayerAlive(target))
    {
        // Target is valid, update HUD if target changed
        if (g_iPlayerSpecTarget[client] != target)
        {
            g_iPlayerSpecTarget[client] = target;
            UpdateHud(client);
        }
    }
    else
    {
        // Target is invalid or not in arena anymore, hide HUD
        if (g_iPlayerSpecTarget[client] != 0)
        {
            HideHud(client);
            g_iPlayerSpecTarget[client] = 0;
        }
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

// Handles spec_next and spec_prev commands to cycle only through arena players
Action Command_SpecNavigation(int client, const char[] command, int args)
{
    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_SPEC || g_iPlayerArena[client] > 0)
        return Plugin_Continue;

    // Get current target
    int current_target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

    // Find all valid arena players
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

    // Find current target index
    int current_index = -1;
    for (int i = 0; i < target_count; i++)
    {
        if (valid_targets[i] == current_target)
        {
            current_index = i;
            break;
        }
    }

    // Determine next target based on command
    int next_index;
    if (StrEqual(command, "spec_next"))
    {
        next_index = (current_index + 1) % target_count;
    }
    else if (StrEqual(command, "spec_prev"))
    {
        next_index = (current_index - 1 + target_count) % target_count;
    }
    else
    {
        return Plugin_Continue;
    }

    // Set new target
    int new_target = valid_targets[next_index];
    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", new_target);
    SetEntProp(client, Prop_Send, "m_iObserverMode", 4); // Third person mode

    // Update HUD
    g_iPlayerSpecTarget[client] = new_target;
    UpdateHud(client);

    return Plugin_Handled;
}
