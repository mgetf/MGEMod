
// ===== ELO CALCULATION CORE =====

enum struct ClassRatingEntry
{
    int player;
    int classId;
    int opponentClassId;
    int previousRating;
    int newRating;
    int ratingChange;
    float weight;
}

void AddClassRatingEntry(ArrayList entries, int player, int classId, int opponentClassId, int previousRating, int newRating, int ratingChange, float weight)
{
    ClassRatingEntry entry;
    entry.player = player;
    entry.classId = classId;
    entry.opponentClassId = opponentClassId;
    entry.previousRating = previousRating;
    entry.newRating = newRating;
    entry.ratingChange = ratingChange;
    entry.weight = weight;
    entries.PushArray(entry, sizeof(entry));
}

void PrintClassRatingMessages(int client, ArrayList classEntries)
{
    if (!IsValidClient(client) || g_bNoDisplayRating || !g_bShowElo[client])
        return;

    if (classEntries == null || classEntries.Length == 0)
        return;

    for (int i = 0; i < classEntries.Length; i++)
    {
        ClassRatingEntry entry;
        classEntries.GetArray(i, entry, sizeof(entry));

        if (entry.player != client || entry.ratingChange == 0)
            continue;

        char className[16];
        char opponentClassName[16];
        strcopy(className, sizeof(className), TFClassToString(view_as<TFClassType>(entry.classId)));
        strcopy(opponentClassName, sizeof(opponentClassName), TFClassToString(view_as<TFClassType>(entry.opponentClassId)));

        if (entry.ratingChange > 0)
            MC_PrintToChat(client, "%t", "GainedMatchupPoints", className, opponentClassName, entry.ratingChange);
        else
            MC_PrintToChat(client, "%t", "LostMatchupPoints", className, opponentClassName, -entry.ratingChange);
    }
}

// Calculate matchup rating changes for a player based on interactions with opponent
void CalculateClassRatingChanges(int player, int opponent, bool didWin, ArrayList entries)
{
    if (!IsValidClient(player) || !IsValidClient(opponent))
        return;

    int totalInteractions = 0;
    for (int classId = 1; classId <= 9; classId++)
    {
        for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
    {
            totalInteractions += g_iPlayerMatchupCount[player][classId][oppClassId];
        }
    }

    if (totalInteractions <= 0)
        return;

    // Calculate ELO for each matchup separately
    for (int classId = 1; classId <= 9; classId++)
    {
        for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
        {
            int interactions = g_iPlayerMatchupCount[player][classId][oppClassId];
            if (interactions <= 0)
            continue;

            // Get opponent's matchup rating (opponentClass vs myClass)
            int opponentRating = 1500; // Default if not set
            if (IsValidClient(opponent) && g_iPlayerClassRating[opponent][oppClassId][classId] > 0)
            {
                opponentRating = g_iPlayerClassRating[opponent][oppClassId][classId];
            }
            else if (IsValidClient(opponent))
            {
                // Initialize opponent's matchup rating if it doesn't exist (only if opponent is still valid)
                g_iPlayerClassRating[opponent][oppClassId][classId] = 1500;
            }

            // Get player's matchup rating
            int previousRating = g_iPlayerClassRating[player][classId][oppClassId];
            if (previousRating == 0)
            {
                previousRating = 1500;
                g_iPlayerClassRating[player][classId][oppClassId] = 1500;
    }

            // Calculate ELO change using EXACT same formula as general rating
            // El represents the win probability of the "winner" in this matchup (same as general rating logic)
            float winnerRating, loserRating;
            if (didWin) {
                winnerRating = float(previousRating);
                loserRating = float(opponentRating);
            } else {
                winnerRating = float(opponentRating);
                loserRating = float(previousRating);
            }
            float ratingDiff = winnerRating - loserRating;
            float El = 1.0 / (Pow(10.0, ratingDiff / 400.0) + 1.0);
            int k = (previousRating >= 2400) ? 10 : 15;
            int matchupScore = RoundFloat(k * El);
            int delta = didWin ? matchupScore : -matchupScore;

            int newRating = previousRating + delta;
            g_iPlayerClassRating[player][classId][oppClassId] = newRating;

            float weight = float(interactions) / float(totalInteractions);
            AddClassRatingEntry(entries, player, classId, oppClassId, previousRating, newRating, delta, weight);
        }
    }
}

// Calculates ELO ratings for 1v1 duels and updates player statistics in database
void CalcELO(int winner, int loser)
{
    if (IsFakeClient(winner) || IsFakeClient(loser) || g_bNoStats)
        return;
        
    // Skip ELO calculations if either player has unverified ELO
    if (!IsPlayerEligibleForElo(winner) || !IsPlayerEligibleForElo(loser))
        return;

    // Store previous ELO values before calculating new ones
    int winner_previous_elo = g_iPlayerRating[winner];
    int loser_previous_elo = g_iPlayerRating[loser];

    // ELO formula
    float El = 1 / (Pow(10.0, float((g_iPlayerRating[winner] - g_iPlayerRating[loser])) / 400) + 1);
    int k = (g_iPlayerRating[winner] >= 2400) ? 10 : 15;
    int winnerscore = RoundFloat(k * El);
    g_iPlayerRating[winner] += winnerscore;
    k = (g_iPlayerRating[loser] >= 2400) ? 10 : 15;
    int loserscore = RoundFloat(k * El);
    g_iPlayerRating[loser] -= loserscore;
    
    // Call ELO change forwards
    int arena_index = g_iPlayerArena[winner];
    CallForward_OnPlayerELOChange(winner, winner_previous_elo, g_iPlayerRating[winner], arena_index);
    CallForward_OnPlayerELOChange(loser, loser_previous_elo, g_iPlayerRating[loser], arena_index);
    int time = GetTime();
    char query[1024], sCleanArenaname[128], sCleanMapName[128];

    g_DB.Escape(g_sArenaName[g_iPlayerArena[winner]], sCleanArenaname, sizeof(sCleanArenaname));
    g_DB.Escape(g_sMapName, sCleanMapName, sizeof(sCleanMapName));

    if (IsValidClient(winner) && !g_bNoDisplayRating && g_bShowElo[winner])
        MC_PrintToChat(winner, "%t", "GainedPoints", winnerscore);

    if (IsValidClient(loser) && !g_bNoDisplayRating && g_bShowElo[loser])
        MC_PrintToChat(loser, "%t", "LostPoints", loserscore);

    // This is necessary for when a player leaves a 2v2 arena that is almost done.
    // I don't want to penalize the player that doesn't leave, so only the winners/leavers ELO will be effected.
    int winner_team_slot = (g_iPlayerSlot[winner] > 2) ? (g_iPlayerSlot[winner] - 2) : g_iPlayerSlot[winner];
    int loser_team_slot = (g_iPlayerSlot[loser] > 2) ? (g_iPlayerSlot[loser] - 2) : g_iPlayerSlot[loser];

    // DB entry for this specific duel.
    char winnerClass[64], loserClass[64];
    GetPlayerClassString(winner, arena_index, winnerClass, sizeof(winnerClass));
    GetPlayerClassString(loser, arena_index, loserClass, sizeof(loserClass));
    
    int startTime = g_iArenaDuelStartTime[arena_index];
    int endTime = time;
    
    ArrayList classEntries = new ArrayList(sizeof(ClassRatingEntry));
    CalculateClassRatingChanges(winner, loser, true, classEntries);
    CalculateClassRatingChanges(loser, winner, false, classEntries);

    PrintClassRatingMessages(winner, classEntries);
    PrintClassRatingMessages(loser, classEntries);
    
    InsertDuelWithClassRatings1v1(arena_index, winner, loser, g_sPlayerSteamID[winner], g_sPlayerSteamID[loser],
        g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot],
        g_iArenaFraglimit[arena_index], endTime, startTime, g_sMapName, g_sArenaName[arena_index],
        winnerClass, loserClass, winner_previous_elo, g_iPlayerRating[winner], loser_previous_elo, g_iPlayerRating[loser], classEntries);

    // Winner's stats
    GetUpdateWinnerStatsQuery(query, sizeof(query), g_iPlayerRating[winner], time, g_sPlayerSteamID[winner]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Loser's stats
    GetUpdateLoserStatsQuery(query, sizeof(query), g_iPlayerRating[loser], time, g_sPlayerSteamID[loser]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Update matchup ratings for both players
    UpdateMatchupRatings(winner);
    UpdateMatchupRatings(loser);
}

// Calculates ELO ratings for 2v2 duels using team-averaged ratings and updates player statistics
void CalcELO2(int winner, int winner2, int loser, int loser2)
{
    if (IsFakeClient(winner) || IsFakeClient(loser) || g_bNoStats || IsFakeClient(loser2) || IsFakeClient(winner2) || !g_b2v2Elo)
        return;
        
    // Skip ELO calculations if any player has unverified ELO
    if (!IsPlayerEligibleForElo(winner) || !IsPlayerEligibleForElo(winner2) || 
        !IsPlayerEligibleForElo(loser) || !IsPlayerEligibleForElo(loser2))
        return;

    // Store previous ELO values before calculating new ones
    int winner_previous_elo = g_iPlayerRating[winner];
    int winner2_previous_elo = g_iPlayerRating[winner2];
    int loser_previous_elo = g_iPlayerRating[loser];
    int loser2_previous_elo = g_iPlayerRating[loser2];

    float Losers_ELO = float((g_iPlayerRating[loser] + g_iPlayerRating[loser2]) / 2);
    float Winners_ELO = float((g_iPlayerRating[winner] + g_iPlayerRating[winner2]) / 2);

    // ELO formula
    float El = 1 / (Pow(10.0, (Winners_ELO - Losers_ELO) / 400) + 1);
    int k = (Winners_ELO >= 2400) ? 10 : 15;
    int winnerscore = RoundFloat(k * El);
    g_iPlayerRating[winner] += winnerscore;
    g_iPlayerRating[winner2] += winnerscore;
    k = (Losers_ELO >= 2400) ? 10 : 15;
    int loserscore = RoundFloat(k * El);
    g_iPlayerRating[loser] -= loserscore;
    g_iPlayerRating[loser2] -= loserscore;
    
    // Call ELO change forwards for all players
    int arena_index = g_iPlayerArena[winner];
    CallForward_OnPlayerELOChange(winner, winner_previous_elo, g_iPlayerRating[winner], arena_index);
    CallForward_OnPlayerELOChange(winner2, winner2_previous_elo, g_iPlayerRating[winner2], arena_index);
    CallForward_OnPlayerELOChange(loser, loser_previous_elo, g_iPlayerRating[loser], arena_index);
    CallForward_OnPlayerELOChange(loser2, loser2_previous_elo, g_iPlayerRating[loser2], arena_index);

    int winner_team_slot = (g_iPlayerSlot[winner] > 2) ? (g_iPlayerSlot[winner] - 2) : g_iPlayerSlot[winner];
    int loser_team_slot = (g_iPlayerSlot[loser] > 2) ? (g_iPlayerSlot[loser] - 2) : g_iPlayerSlot[loser];
    int time = GetTime();
    char query[1024], sCleanArenaname[128], sCleanMapName[128];

    g_DB.Escape(g_sArenaName[g_iPlayerArena[winner]], sCleanArenaname, sizeof(sCleanArenaname));
    g_DB.Escape(g_sMapName, sCleanMapName, sizeof(sCleanMapName));

    if (IsValidClient(winner) && !g_bNoDisplayRating && g_bShowElo[winner])
        MC_PrintToChat(winner, "%t", "GainedPoints", winnerscore);

    if (IsValidClient(winner2) && !g_bNoDisplayRating && g_bShowElo[winner2])
        MC_PrintToChat(winner2, "%t", "GainedPoints", winnerscore);

    if (IsValidClient(loser) && !g_bNoDisplayRating && g_bShowElo[loser])
        MC_PrintToChat(loser, "%t", "LostPoints", loserscore);

    if (IsValidClient(loser2) && !g_bNoDisplayRating && g_bShowElo[loser2])
        MC_PrintToChat(loser2, "%t", "LostPoints", loserscore);


    // DB entry for this specific duel.
    char winnerClass[64], winner2Class[64], loserClass[64], loser2Class[64];
    GetPlayerClassString(winner, arena_index, winnerClass, sizeof(winnerClass));
    GetPlayerClassString(winner2, arena_index, winner2Class, sizeof(winner2Class));
    GetPlayerClassString(loser, arena_index, loserClass, sizeof(loserClass));
    GetPlayerClassString(loser2, arena_index, loser2Class, sizeof(loser2Class));
    
    int startTime = g_iArenaDuelStartTime[arena_index];
    int endTime = time;
    
    ArrayList classEntries = new ArrayList(sizeof(ClassRatingEntry));
    // Calculate matchup ratings for all players against all opponents
    CalculateClassRatingChanges(winner, loser, true, classEntries);
    CalculateClassRatingChanges(winner, loser2, true, classEntries);
    CalculateClassRatingChanges(winner2, loser, true, classEntries);
    CalculateClassRatingChanges(winner2, loser2, true, classEntries);
    CalculateClassRatingChanges(loser, winner, false, classEntries);
    CalculateClassRatingChanges(loser, winner2, false, classEntries);
    CalculateClassRatingChanges(loser2, winner, false, classEntries);
    CalculateClassRatingChanges(loser2, winner2, false, classEntries);

    PrintClassRatingMessages(winner, classEntries);
    PrintClassRatingMessages(winner2, classEntries);
    PrintClassRatingMessages(loser, classEntries);
    PrintClassRatingMessages(loser2, classEntries);
    
    int winning_team = (winner_team_slot == SLOT_ONE) ? TEAM_RED : TEAM_BLU;
    
    InsertDuelWithClassRatings2v2(arena_index, winning_team, g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot],
        g_sPlayerSteamID[winner], g_sPlayerSteamID[winner2], g_sPlayerSteamID[loser], g_sPlayerSteamID[loser2],
        g_iArenaFraglimit[arena_index], endTime, startTime, g_sMapName, g_sArenaName[arena_index],
        winnerClass, winner2Class, loserClass, loser2Class, winner_previous_elo, g_iPlayerRating[winner],
        winner2_previous_elo, g_iPlayerRating[winner2], loser_previous_elo, g_iPlayerRating[loser], loser2_previous_elo, g_iPlayerRating[loser2],
        classEntries);

    // Winner's stats
    GetUpdateWinnerStatsQuery(query, sizeof(query), g_iPlayerRating[winner], time, g_sPlayerSteamID[winner]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Winner's teammate stats
    GetUpdateWinnerStatsQuery(query, sizeof(query), g_iPlayerRating[winner2], time, g_sPlayerSteamID[winner2]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Loser's stats
    GetUpdateLoserStatsQuery(query, sizeof(query), g_iPlayerRating[loser], time, g_sPlayerSteamID[loser]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Loser's teammate stats
    GetUpdateLoserStatsQuery(query, sizeof(query), g_iPlayerRating[loser2], time, g_sPlayerSteamID[loser2]);
    g_DB.Query(SQL_OnGenericQueryFinished, query);

    // Update matchup ratings for all players
    UpdateMatchupRatings(winner);
    UpdateMatchupRatings(winner2);
    UpdateMatchupRatings(loser);
    UpdateMatchupRatings(loser2);
}


// ===== PLAYER COMMANDS =====

// Toggles ELO rating display for individual players and saves preference to cookies
Action Command_ToggleElo(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    g_bShowElo[client] = !g_bShowElo[client];

    // Save the preference to client cookie
    g_hShowEloCookie.Set(client, g_bShowElo[client] ? "1" : "0");

    char status_text[32];
    Format(status_text, sizeof(status_text), "%T", g_bShowElo[client] ? "EnabledLabel" : "DisabledLabel", client);
    MC_PrintToChat(client, "%t", "EloToggle", status_text);
    
    // Refresh the appropriate HUD based on player's current state
    int arena_index = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];
    
    if (arena_index > 0 && player_slot > 0)
    {
        // Player is actively in an arena - show player HUD
        UpdateHud(client);
    }
    else if (TF2_GetClientTeam(client) == TFTeam_Spectator && g_iPlayerSpecTarget[client] > 0)
    {
        // Player is spectating someone - show spectator HUD
        UpdateHud(client);
    }
    
    return Plugin_Handled;
}
