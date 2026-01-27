
// ===== HUD DISPLAY CORE =====

// Unified HUD update method that handles both players and spectators
void UpdateHud(int client)
{
    if (!IsValidClient(client))
        return;
    
    int arena_index = 0;
    bool is_spectator = false;
    
    // Determine arena and role
    // Check if player is in an ACTIVE slot (not waiting in queue)
    int player_arena = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];
    bool is_active_player = false;
    
    if (player_arena > 0 && player_slot > 0)
    {
        // Determine if this is an active slot or a queue slot
        int max_active_slot = g_bFourPersonArena[player_arena] ? SLOT_FOUR : SLOT_TWO;
        is_active_player = (player_slot <= max_active_slot);
    }
    
    if (is_active_player)
    {
        // Player is actively fighting in arena
        arena_index = player_arena;
    }
    else if (g_iPlayerSpecTarget[client] > 0 && IsValidClient(g_iPlayerSpecTarget[client]))
    {
        // Spectator (or queued player) watching someone
        arena_index = g_iPlayerArena[g_iPlayerSpecTarget[client]];
        is_spectator = true;
    }
    else if (player_arena > 0)
    {
        // Queued player not spectating anyone - show their queued arena
        arena_index = player_arena;
        is_spectator = true;
    }
    else
    {
        // Not in arena and not spectating - hide HUD
        HideHud(client);
        return;
    }

    // Handle HUD disabled cases
    if (!g_bShowHud[client])
    {
        if (is_spectator)
        {
            // Spectators with HUD off see nothing
            return;
        }
        else
        {
            // Players with HUD off still see critical game info
            ShowCriticalGameInfo(client, arena_index);
            return;
        }
    }
    
    // Show full HUD for both players and spectators
    ShowFullHud(client, arena_index, is_spectator);
}

// Shows critical game information that players see even when HUD is disabled
void ShowCriticalGameInfo(int client, int arena_index)
{
    int client_slot = g_iPlayerSlot[client];
    int client_foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int client_foe = (g_iArenaQueue[arena_index][(client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE]);
    int client_teammate;
    int client_foe2;

    if (g_bFourPersonArena[arena_index])
    {
        client_teammate = GetPlayerTeammate(client_slot, arena_index);
        client_foe2 = GetPlayerTeammate(client_foe_slot, arena_index);
    }

    // KOTH timers (always shown to players)
    if (g_bArenaKoth[arena_index])
    {
        // Show the red team timer
            if (g_iPointState[arena_index] == TEAM_RED)
                SetHudTextParams(0.40, 0.01, HUDFADEOUTTIME, 255, 0, 0, 255); // Red
            else
                SetHudTextParams(0.40, 0.01, HUDFADEOUTTIME, 255, 255, 255, 255);

            ShowSyncHudText(client, hm_KothTimerRED, "%i:%02i", g_iKothTimer[arena_index][TEAM_RED] / 60, g_iKothTimer[arena_index][TEAM_RED] % 60);

        // Show the blue team timer
            if (g_iPointState[arena_index] == TEAM_BLU)
                SetHudTextParams(0.60, 0.01, HUDFADEOUTTIME, 0, 0, 255, 255); // Blue
            else
                SetHudTextParams(0.60, 0.01, HUDFADEOUTTIME, 255, 255, 255, 255);
        
            ShowSyncHudText(client, hm_KothTimerBLU, "%i:%02i", g_iKothTimer[arena_index][TEAM_BLU] / 60, g_iKothTimer[arena_index][TEAM_BLU] % 60);

        // Show capture point percentage
            if (g_iCappingTeam[arena_index] == TEAM_RED)
                SetHudTextParams(0.50, 0.80, HUDFADEOUTTIME, 255, 0, 0, 255); // Red
            else if (g_iCappingTeam[arena_index] == TEAM_BLU)
                SetHudTextParams(0.50, 0.80, HUDFADEOUTTIME, 0, 0, 255, 255); // Blue
            else
                SetHudTextParams(0.50, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255);
        
            ShowSyncHudText(client, hm_KothCap, "Point Capture: %.1f", g_fKothCappedPercent[arena_index]);
    }

    // Health display with BBall intel integration (always shown to players)
    if (g_bArenaBBall[arena_index] && g_iArenaStatus[arena_index] == AS_FIGHT)
    {
        // BBall arenas show intel status instead of regular health display
        char hud_text[128];
        if (g_bPlayerHasIntel[client])
        {
            Format(hud_text, sizeof(hud_text), "%T", "YouHaveTheIntel", client);
            ShowSyncHudText(client, hm_HP, hud_text, g_iPlayerHP[client]);
        }
        else if (g_bFourPersonArena[arena_index] && g_bPlayerHasIntel[client_teammate])
        {
            Format(hud_text, sizeof(hud_text), "%T", "TeammateHasTheIntel", client);
            ShowSyncHudText(client, hm_HP, hud_text, g_iPlayerHP[client]);
        }
        else if (g_bPlayerHasIntel[client_foe] || (g_bFourPersonArena[arena_index] && g_bPlayerHasIntel[client_foe2]))
        {
            Format(hud_text, sizeof(hud_text), "%T", "EnemyHasTheIntel", client);
            ShowSyncHudText(client, hm_HP, hud_text, g_iPlayerHP[client]);
        }
        else
        {
            Format(hud_text, sizeof(hud_text), "%T", "GetTheIntel", client);
            ShowSyncHudText(client, hm_HP, hud_text, g_iPlayerHP[client]);
        }
    }
    else
    {
        // Regular health display for non-BBall arenas
        if (g_bArenaShowHPToPlayers[arena_index])
        {
            float hp_ratio = ((float(g_iPlayerHP[client])) / (float(g_iPlayerMaxHP[client]) * g_fArenaHPRatio[arena_index]));
            if (hp_ratio > 0.66)
                SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 0, 255, 0, 255); // Green
            else if (hp_ratio >= 0.33)
                SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 0, 255); // Yellow
            else if (hp_ratio < 0.33)
                SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 0, 0, 255); // Red
            else
                SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255); // White
            
            ShowSyncHudText(client, hm_HP, "Health : %d", g_iPlayerHP[client]);
        }
        else
        {
            SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255);
            ShowSyncHudText(client, hm_HP, "", g_iPlayerHP[client]);
        }
    }

    // Teammate HP display for 2v2 (always shown to players)
    if (g_bFourPersonArena[arena_index] && client_teammate)
    {
        char hp_report[128];
        Format(hp_report, sizeof(hp_report), "%N : %d", client_teammate, g_iPlayerHP[client_teammate]);
        SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255);
        ShowSyncHudText(client, hm_TeammateHP, hp_report);
    }
}

// Shows complete HUD information for both players and spectators
void ShowFullHud(int client, int arena_index, bool is_spectator)
{
    if (is_spectator)
    {
        // Show HP display for spectators (all arena players)
        char hp_report[128];
        int red_f1, blu_f1, red_f2, blu_f2;
        GetArenaPlayers(arena_index, red_f1, blu_f1, red_f2, blu_f2);

    if (g_bFourPersonArena[arena_index])
        {
            if (red_f1 && IsValidClient(red_f1))
                Format(hp_report, sizeof(hp_report), "%N : %d", red_f1, g_iPlayerHP[red_f1]);

            if (red_f2 && IsValidClient(red_f2))
                Format(hp_report, sizeof(hp_report), "%s\n%N : %d", hp_report, red_f2, g_iPlayerHP[red_f2]);

            if (blu_f1 && IsValidClient(blu_f1))
                Format(hp_report, sizeof(hp_report), "%s\n\n%N : %d", hp_report, blu_f1, g_iPlayerHP[blu_f1]);

            if (blu_f2 && IsValidClient(blu_f2))
                Format(hp_report, sizeof(hp_report), "%s\n%N : %d", hp_report, blu_f2, g_iPlayerHP[blu_f2]);
        }
        else
        {
            if (red_f1 && IsValidClient(red_f1))
                Format(hp_report, sizeof(hp_report), "%N : %d", red_f1, g_iPlayerHP[red_f1]);

            if (blu_f1 && IsValidClient(blu_f1))
                Format(hp_report, sizeof(hp_report), "%s\n%N : %d", hp_report, blu_f1, g_iPlayerHP[blu_f1]);
        }

        SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255);
        ShowSyncHudText(client, hm_HP, hp_report);
    }
    else
    {
        // Players get critical info first, then score
        ShowCriticalGameInfo(client, arena_index);
    }

    // Both players and spectators get score display
    char report[256];
    SetHudTextParams(0.01, 0.01, HUDFADEOUTTIME, 255, 255, 255, 255);
    BuildArenaScoreReport(arena_index, client, is_spectator, report, sizeof(report));
    ShowSyncHudText(client, hm_Score, "%s", report);
}

// Updates HUD display for all players and spectators in a specific arena
void UpdateHudForArena(int arena_index)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount)
        return;

    // Update HUD for all players in the arena
    for (int i = SLOT_ONE; i <= (g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO); i++)
    {
        if (g_iArenaQueue[arena_index][i])
        {
            UpdateHud(g_iArenaQueue[arena_index][i]);
        }
    }
    
    // Update HUD for all spectators watching this arena
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && GetClientTeam(i) == TEAM_SPEC && 
            g_iPlayerSpecTarget[i] > 0 && 
            g_iPlayerArena[g_iPlayerSpecTarget[i]] == arena_index)
        {
            UpdateHud(i);
        }
    }
}

// Updates HUD display for all players and spectators across all arenas
void UpdateHudForAll()
{
    for (int i = 1; i <= g_iArenaCount; i++)
    {
        UpdateHudForArena(i);
    }
}

// Clears HUD elements for a specific client when they disable HUD or leave arena
void HideHud(int client)
{
    if (!IsValidClient(client))
        return;

    ClearSyncHud(client, hm_Score);
    ClearSyncHud(client, hm_HP);
}

// ===== HUD FORMATTING FUNCTIONS =====

// Formats a single player's score line with optional ELO display
void FormatPlayerScoreLine(int player, int score, bool show_elo, char[] output, int output_size)
{
    if (!player || !IsValidClient(player))
    {
        output[0] = '\0';
        return;
    }
    
    if (g_bNoStats || g_bNoDisplayRating || !show_elo)
        Format(output, output_size, "%N : %d", player, score);
    else
        Format(output, output_size, "%N (%d): %d", player, g_iPlayerRating[player], score);
}

// Formats a team score line for 2v2 with optional ELO display  
void FormatTeamScoreLine(int player1, int player2, int score, bool show_elo, bool show_2v2_elo, char[] output, int output_size)
{
    // Validate both players
    bool valid1 = (player1 && IsValidClient(player1));
    bool valid2 = (player2 && IsValidClient(player2));
    
    if (!valid1 && !valid2)
    {
        output[0] = '\0';
        return;
    }
    
    if (valid1 && valid2)
    {
        if (g_bNoStats || g_bNoDisplayRating || !show_elo || !show_2v2_elo)
            Format(output, output_size, "«%N» and «%N» : %d", player1, player2, score);
        else
            Format(output, output_size, "«%N» and «%N» (%d): %d", player1, player2, g_iPlayerRating[player1], score);
    }
    else if (valid1)
    {
        FormatPlayerScoreLine(player1, score, show_elo && show_2v2_elo, output, output_size);
    }
    else if (valid2)
    {
        FormatPlayerScoreLine(player2, score, show_elo && show_2v2_elo, output, output_size);
    }
}

// Formats arena header with name and frag/capture limit information
void FormatArenaHeader(char[] arena_name, int fraglimit, bool is_bball, bool for_spectator, int arena_status, char[] output, int output_size)
{
    if (for_spectator && arena_status == AS_IDLE)
    {
        Format(output, output_size, "%s", arena_name);
        return;
    }
    
    if (fraglimit > 0)
    {
        if (is_bball)
            Format(output, output_size, "%s - Capture Limit [%d]", arena_name, fraglimit);
        else
            Format(output, output_size, "%s - Frag Limit [%d]", arena_name, fraglimit);
    }
    else
    {
        if (is_bball)
            Format(output, output_size, "%s - No Capture Limit", arena_name);
        else
            Format(output, output_size, "%s - No Frag Limit", arena_name);
    }
}

// Builds complete arena score report for both players and spectators
void BuildArenaScoreReport(int arena_index, int client, bool for_spectator, char[] output, int output_size)
{
    char arena_name[64];
    int fraglimit;
    bool is_2v2, is_bball;
    GetArenaBasicInfo(arena_index, arena_name, sizeof(arena_name), fraglimit, is_2v2, is_bball);
    
    int red_f1, blu_f1, red_f2, blu_f2;
    GetArenaPlayers(arena_index, red_f1, blu_f1, red_f2, blu_f2);
    
    char header[128];
    FormatArenaHeader(arena_name, fraglimit, is_bball, for_spectator, g_iArenaStatus[arena_index], header, sizeof(header));
    strcopy(output, output_size, header);
    
    bool show_elo = g_bShowElo[client];
    
    if (is_2v2)
    {
        char red_line[128], blu_line[128];
        
        if (red_f1 || red_f2)
        {
            FormatTeamScoreLine(red_f1, red_f2, g_iArenaScore[arena_index][SLOT_ONE], show_elo, g_b2v2Elo, red_line, sizeof(red_line));
            if (red_line[0] != '\0')
                Format(output, output_size, "%s\n%s", output, red_line);
        }
        
        if (blu_f1 || blu_f2)
        {
            FormatTeamScoreLine(blu_f1, blu_f2, g_iArenaScore[arena_index][SLOT_TWO], show_elo, g_b2v2Elo, blu_line, sizeof(blu_line));
            if (blu_line[0] != '\0')
                Format(output, output_size, "%s\n%s", output, blu_line);
        }
    }
    else
    {
        char red_line[128], blu_line[128];
        
        FormatPlayerScoreLine(red_f1, g_iArenaScore[arena_index][SLOT_ONE], show_elo, red_line, sizeof(red_line));
        if (red_line[0] != '\0')
            Format(output, output_size, "%s\n%s", output, red_line);
        
        FormatPlayerScoreLine(blu_f1, g_iArenaScore[arena_index][SLOT_TWO], show_elo, blu_line, sizeof(blu_line));
        if (blu_line[0] != '\0')
            Format(output, output_size, "%s\n%s", output, blu_line);
    }
}


// ===== PLAYER COMMANDS =====

// Toggles HUD display on/off for individual players and saves preference
Action Command_ToggleHud(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    g_bShowHud[client] = !g_bShowHud[client];

    if (g_bShowHud[client])
    {
        UpdateHud(client);
    }
    else
    {
        HideHud(client);
    }

    char status_text[32];
    Format(status_text, sizeof(status_text), "%T", g_bShowHud[client] ? "EnabledLabel" : "DisabledLabel", client);
    MC_PrintToChat(client, "%t", "HudToggle", status_text);
    return Plugin_Handled;
}
