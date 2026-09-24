
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
                SetHudTextParams(0.47, 0.06, HUDFADEOUTTIME, 255, 0, 0, 255); // Red
            else
                SetHudTextParams(0.47, 0.06, HUDFADEOUTTIME, 255, 255, 255, 255);

            ShowSyncHudText(client, hm_KothTimerRED, "%i:%02i", g_iKothTimer[arena_index][TEAM_RED] / 60, g_iKothTimer[arena_index][TEAM_RED] % 60);

        // Show the blue team timer
            if (g_iPointState[arena_index] == TEAM_BLU)
                SetHudTextParams(0.53, 0.06, HUDFADEOUTTIME, 0, 0, 255, 255); // Blue
            else
                SetHudTextParams(0.53, 0.06, HUDFADEOUTTIME, 255, 255, 255, 255);
        
            ShowSyncHudText(client, hm_KothTimerBLU, "%i:%02i", g_iKothTimer[arena_index][TEAM_BLU] / 60, g_iKothTimer[arena_index][TEAM_BLU] % 60);

        ShowKothCaptureHud(client, arena_index);
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
    else if (g_fPlayerRespawnAt[client] <= GetGameTime())
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

    if (g_bFourPersonArena[arena_index] && client_teammate && g_bArenaShowHPToPlayers[arena_index])
    {
        char hp_report[128];
        Format(hp_report, sizeof(hp_report), "%N : %d", client_teammate, g_iPlayerHP[client_teammate]);
        SetHudTextParams(0.01, 0.80, HUDFADEOUTTIME, 255, 255, 255, 255);
        ShowSyncHudText(client, hm_TeammateHP, hp_report);
    }
    else
        ClearSyncHud(client, hm_TeammateHP);
}

void CountKothTouchers(int arena_index, int &redCount, int &bluCount)
{
    redCount = 0;
    bluCount = 0;
    if (g_bPlayerTouchPoint[arena_index][SLOT_ONE])
        redCount++;
    if (g_bPlayerTouchPoint[arena_index][SLOT_TWO])
        bluCount++;
    if (g_bFourPersonArena[arena_index])
    {
        if (g_bPlayerTouchPoint[arena_index][SLOT_THREE])
            redCount++;
        if (g_bPlayerTouchPoint[arena_index][SLOT_FOUR])
            bluCount++;
    }
}

void BuildCaptureMeter(float percent, int direction, char[] buffer, int maxlen)
{
    int width = 16;
    if (percent < 0.0)
        percent = 0.0;
    else if (percent > 100.0)
        percent = 100.0;

    int filled = RoundToNearest(percent / 100.0 * float(width));
    if (filled < 0)
        filled = 0;
    else if (filled > width)
        filled = width;

    char bar[24];
    int pos = 0;
    bar[pos++] = '[';
    for (int i = 0; i < width; i++)
    {
        if (filled > 0 && filled < width && i == filled - 1 && direction != 0)
            bar[pos++] = direction > 0 ? '>' : '<';
        else if (i < filled)
            bar[pos++] = '=';
        else
            bar[pos++] = '-';
    }
    bar[pos++] = ']';
    bar[pos] = '\0';
    Format(buffer, maxlen, "%s  %d%%", bar, RoundToNearest(percent));
}

void ShowKothCaptureHud(int client, int arena_index)
{
    if (!g_bArenaKoth[arena_index])
        return;

    int redCount, bluCount;
    CountKothTouchers(arena_index, redCount, bluCount);
    if (g_bKothRoundPause[arena_index])
    {
        redCount = 0;
        bluCount = 0;
    }

    int point = g_iPointState[arena_index];
    float percent = g_fKothCappedPercent[arena_index];
    bool contested = redCount > 0 && bluCount > 0;
    bool redCapping = !contested && redCount > 0 && (point == NEUTRAL || point == TEAM_BLU);
    bool bluCapping = !contested && bluCount > 0 && (point == NEUTRAL || point == TEAM_RED);
    bool interrupted = percent > 0.5 && !redCapping && !bluCapping && !contested;

    int r = 210;
    int g = 210;
    int b = 210;
    if (redCapping)
    {
        r = 255;
        g = 70;
        b = 70;
    }
    else if (bluCapping)
    {
        r = 80;
        g = 150;
        b = 255;
    }
    else if (interrupted)
    {
        r = 255;
        g = 176;
        b = 48;
    }
    else if (contested)
    {
        r = 255;
        g = 220;
        b = 40;
    }
    else if (point == TEAM_RED)
    {
        r = 255;
        g = 90;
        b = 90;
    }
    else if (point == TEAM_BLU)
    {
        r = 90;
        g = 160;
        b = 255;
    }

    int direction = 0;
    if (g_bKothRulesFromMap[arena_index])
        direction = g_iKothMeterDir[arena_index];
    else if (redCapping || bluCapping)
        direction = 1;
    else if (interrupted)
        direction = -1;

    char meter[48];
    BuildCaptureMeter(percent, direction, meter, sizeof(meter));
    int cappers = 0;
    if (redCapping)
        cappers = redCount;
    else if (bluCapping)
        cappers = bluCount;
    if (cappers > 0)
        Format(meter, sizeof(meter), "%s  x%d", meter, cappers);

    SetHudTextParams(-1.0, 0.95, HUDFADEOUTTIME, r, g, b, 255, 0, 0.0, 0.0, 0.0);
    ShowSyncHudText(client, hm_KothCap, "%s", meter);
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
        ShowKothCaptureHud(client, arena_index);
    }
    else
    {
        // Players get critical info first, then score
        ShowCriticalGameInfo(client, arena_index);
    }

    // Both players and spectators get score display
    char report[384];
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
    ClearSyncHud(client, hm_KothTimerRED);
    ClearSyncHud(client, hm_KothTimerBLU);
    ClearSyncHud(client, hm_KothCap);
}

// ===== HUD FORMATTING FUNCTIONS =====

// Populates a HUD line's context and defaults its display text to the raw ELO digits;
// called for both score lines before MGE_OnFormatHudLines fires, regardless of whether
// that line will end up showing ELO at render time
void PopulateHudLineInfo(int viewer, int player, int arena_index, int slot, bool is_spectator, int score, MGEHudLineInfo info)
{
    info.viewer = viewer;
    info.player = player;
    info.arena_index = arena_index;
    info.slot = slot;
    info.score = score;
    info.isSpectator = is_spectator;
    info.elo = (player && IsValidClient(player)) ? Rating_GetHudDisplayValue(player) : 0;
    if (player && IsValidClient(player) && Rating_IsProvisional(player))
    {
        if (g_eRatingEngine == RATING_ENGINE_GLICKO2 && g_bPlayerPeriodDirty[player])
            Format(info.extraDisplay, sizeof(info.extraDisplay), "~%d?", info.elo);
        else
            Format(info.extraDisplay, sizeof(info.extraDisplay), "%d?", info.elo);
    }
    else if (player && IsValidClient(player) && g_eRatingEngine == RATING_ENGINE_GLICKO2 && g_bPlayerPeriodDirty[player])
        Format(info.extraDisplay, sizeof(info.extraDisplay), "~%d", info.elo);
    else
        Format(info.extraDisplay, sizeof(info.extraDisplay), "%d", info.elo);
}

// Renders a single player's score line, using the line's (possibly plugin-modified) display text
void RenderPlayerScoreLine(int player, int score, bool show_elo, const MGEHudLineInfo info, char[] output, int output_size)
{
    if (!player || !IsValidClient(player))
    {
        output[0] = '\0';
        return;
    }
    
    if (g_bNoStats || g_bNoDisplayRating || !show_elo)
        Format(output, output_size, "%N : %d", player, score);
    else if (IsFakeClient(player))
        Format(output, output_size, "%N (BOT): %d", player, score);
    else if (!IsPlayerStatsLoaded(player))
        Format(output, output_size, "%N : %d", player, score);
    else
        Format(output, output_size, "%N (%s): %d", player, info.extraDisplay, score);
}

// Renders a team score line for 2v2, using the line's (possibly plugin-modified) display text
void RenderTeamScoreLine(int player1, int player2, int score, bool show_elo, bool show_2v2_elo, const MGEHudLineInfo info, char[] output, int output_size)
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
        if (g_bNoStats || g_bNoDisplayRating || !show_elo || !show_2v2_elo
            || IsFakeClient(player1) || IsFakeClient(player2)
            || !IsPlayerStatsLoaded(player1) || !IsPlayerStatsLoaded(player2))
            Format(output, output_size, "«%N» and «%N» : %d", player1, player2, score);
        else
            Format(output, output_size, "«%N» and «%N» (%s): %d", player1, player2, info.extraDisplay, score);
    }
    else if (valid1)
    {
        RenderPlayerScoreLine(player1, score, show_elo && show_2v2_elo, info, output, output_size);
    }
    else if (valid2)
    {
        RenderPlayerScoreLine(player2, score, show_elo && show_2v2_elo, info, output, output_size);
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

    MGEHudLineInfo redInfo, bluInfo;
    PopulateHudLineInfo(client, red_f1, arena_index, SLOT_ONE, for_spectator, g_iArenaScore[arena_index][SLOT_ONE], redInfo);
    PopulateHudLineInfo(client, blu_f1, arena_index, SLOT_TWO, for_spectator, g_iArenaScore[arena_index][SLOT_TWO], bluInfo);

    CallForward_OnFormatHudLines(arena_index, client, for_spectator, redInfo, bluInfo);

    if (is_2v2)
    {
        char red_line[128], blu_line[128];
        
        if (red_f1 || red_f2)
        {
            RenderTeamScoreLine(red_f1, red_f2, g_iArenaScore[arena_index][SLOT_ONE], show_elo, g_b2v2Elo, redInfo, red_line, sizeof(red_line));
            if (red_line[0] != '\0')
                Format(output, output_size, "%s\n%s", output, red_line);
        }
        
        if (blu_f1 || blu_f2)
        {
            RenderTeamScoreLine(blu_f1, blu_f2, g_iArenaScore[arena_index][SLOT_TWO], show_elo, g_b2v2Elo, bluInfo, blu_line, sizeof(blu_line));
            if (blu_line[0] != '\0')
                Format(output, output_size, "%s\n%s", output, blu_line);
        }
    }
    else
    {
        char red_line[128], blu_line[128];
        
        RenderPlayerScoreLine(red_f1, g_iArenaScore[arena_index][SLOT_ONE], show_elo, redInfo, red_line, sizeof(red_line));
        if (red_line[0] != '\0')
            Format(output, output_size, "%s\n%s", output, red_line);
        
        RenderPlayerScoreLine(blu_f1, g_iArenaScore[arena_index][SLOT_TWO], show_elo, bluInfo, blu_line, sizeof(blu_line));
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
