// ===== MATCH LIFECYCLE MANAGEMENT =====

// Increments an arena team score and notifies API consumers
void AddArenaTeamScore(int arena_index, int team_slot, int amount = 1)
{
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return;
    if (team_slot != SLOT_ONE && team_slot != SLOT_TWO)
        return;

    g_iArenaScore[arena_index][team_slot] += amount;
    CallForward_OnArenaScoreChange(arena_index, g_iArenaScore[arena_index][SLOT_ONE], g_iArenaScore[arena_index][SLOT_TWO]);
}

// Resets arena team scores and notifies API consumers
void ResetArenaScores(int arena_index)
{
    if (arena_index < 1 || arena_index > g_iArenaCount)
        return;

    g_iArenaScore[arena_index][SLOT_ONE] = 0;
    g_iArenaScore[arena_index][SLOT_TWO] = 0;
    CallForward_OnArenaScoreChange(arena_index, 0, 0);
}

// Determines if a match should be completed based on current conditions
bool ShouldProcessMatchCompletion(int arena_index, int killer_team_slot, int fraglimit)
{
    if (g_iArenaStatus[arena_index] < AS_FIGHT || g_iArenaStatus[arena_index] >= AS_REPORTED)
        return false;
        
    if (fraglimit <= 0)
        return false;
        
    return (g_iArenaScore[arena_index][killer_team_slot] >= fraglimit);
}

// Processes complete match end sequence including ELO, announcements, and queue rotation
void ProcessMatchCompletion(int arena_index, int winner1, int winner2, int loser1, int loser2, int winner_team_slot, int loser_team_slot, int fraglimit)
{
    // Set match as completed
    SetArenaStatus(arena_index, AS_REPORTED);
    
    // Format team names for announcement
    char winner_names[128];
    char loser_names[128];
    
    if (g_bFourPersonArena[arena_index])
    {
        FormatTeamPlayerNames(winner1, winner2, winner_names, sizeof(winner_names));
        FormatTeamPlayerNames(loser1, loser2, loser_names, sizeof(loser_names));
    }
    else
    {
        GetClientName(winner1, winner_names, sizeof(winner_names));
        GetClientName(loser1, loser_names, sizeof(loser_names));
    }
    
    // Announce match result
    MC_PrintToChatAll("%t", "XdefeatsY", winner_names, g_iArenaScore[arena_index][winner_team_slot], 
                      loser_names, g_iArenaScore[arena_index][loser_team_slot], fraglimit, g_sArenaName[arena_index]);
    
    // Call API forwards for match end
    if (!g_bFourPersonArena[arena_index])
    {
        CallForward_On1v1MatchEnd(arena_index, winner1, loser1, g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot]);
    }
    else
    {
        int winning_team = (winner_team_slot == SLOT_ONE) ? TEAM_RED : TEAM_BLU;
        CallForward_On2v2MatchEnd(arena_index, winning_team, g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot], 
                                g_iArenaQueue[arena_index][SLOT_ONE], g_iArenaQueue[arena_index][SLOT_THREE],
                                g_iArenaQueue[arena_index][SLOT_TWO], g_iArenaQueue[arena_index][SLOT_FOUR]);
    }
    
    // Handle rating calculations (Elo or Glicko-2, depending on mgemod_rating_engine)
    Rating_ReportResult(winner1, winner2, loser1, loser2);
    
    // Handle post-match queue rotation and timers
    HandlePostMatchQueueRotation(arena_index, loser1, loser2);
}

// Early-leave forfeit. `early_leave_threshold` 0 disables it. The stayer must be strictly
// above that many points, and the leaver must not be ahead. At or below the threshold there
// is no rating change, no mgemod_duels row, and no match-end forward (classelo included).
bool ShouldForfeitOnLeave(int arena_index, int stayerScore, int leaverScore)
{
    int threshold = g_iArenaEarlyLeave[arena_index];
    if (threshold <= 0)
        return false;

    if (stayerScore <= threshold)
        return false;

    return leaverScore <= stayerScore;
}

void ProcessMatchForfeit(int arena_index, int winner1, int winner2, int loser1, int loser2, int winner_team_slot, int loser_team_slot, int leaver, int leaver_slot)
{
    SetArenaStatus(arena_index, AS_REPORTED);

    char winner_names[128];
    char loser_names[128];

    if (g_bFourPersonArena[arena_index])
    {
        FormatTeamPlayerNames(winner1, winner2, winner_names, sizeof(winner_names));
        FormatTeamPlayerNames(loser1, loser2, loser_names, sizeof(loser_names));
    }
    else
    {
        GetClientName(winner1, winner_names, sizeof(winner_names));
        GetClientName(loser1, loser_names, sizeof(loser_names));
    }

    MC_PrintToChatAll("%t", "XdefeatsYearly", winner_names, g_iArenaScore[arena_index][winner_team_slot],
                      loser_names, g_iArenaScore[arena_index][loser_team_slot], g_sArenaName[arena_index]);

    int saved_arena = g_iPlayerArena[leaver];
    int saved_slot = g_iPlayerSlot[leaver];
    g_iPlayerArena[leaver] = arena_index;
    g_iPlayerSlot[leaver] = leaver_slot;

    if (!g_bFourPersonArena[arena_index])
    {
        CallForward_On1v1MatchEnd(arena_index, winner1, loser1, g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot]);
    }
    else
    {
        int slotPlayers[5];
        slotPlayers[SLOT_ONE] = g_iArenaQueue[arena_index][SLOT_ONE];
        slotPlayers[SLOT_TWO] = g_iArenaQueue[arena_index][SLOT_TWO];
        slotPlayers[SLOT_THREE] = g_iArenaQueue[arena_index][SLOT_THREE];
        slotPlayers[SLOT_FOUR] = g_iArenaQueue[arena_index][SLOT_FOUR];
        slotPlayers[leaver_slot] = leaver;

        int winning_team = (winner_team_slot == SLOT_ONE) ? TEAM_RED : TEAM_BLU;
        CallForward_On2v2MatchEnd(arena_index, winning_team, g_iArenaScore[arena_index][winner_team_slot], g_iArenaScore[arena_index][loser_team_slot],
                                slotPlayers[SLOT_ONE], slotPlayers[SLOT_THREE],
                                slotPlayers[SLOT_TWO], slotPlayers[SLOT_FOUR]);
    }

    if (g_bFourPersonArena[arena_index] && IsValidClient(winner2) && IsValidClient(loser2))
        Rating_ReportResult(winner1, winner2, loser1, loser2);
    else
    {
        Rating_ReportResult(winner1, 0, loser1, 0);
        if (g_bFourPersonArena[arena_index] && IsValidClient(winner2))
            Rating_ReportResult(winner2, 0, loser1, 0);
    }

    g_iPlayerArena[leaver] = saved_arena;
    g_iPlayerSlot[leaver] = saved_slot;
}


// ===== QUEUE ROTATION MANAGEMENT =====

// Manages queue rotation and timer scheduling after match completion
void HandlePostMatchQueueRotation(int arena_index, int loser1, int loser2)
{
    if (!g_bFourPersonArena[arena_index])
    {
        // 1v1 queue rotation
        if (g_iArenaQueue[arena_index][SLOT_TWO + 1])
        {
            RemoveFromQueue(loser1, false, true);
            AddInQueue(loser1, arena_index, false, 0, false);
        } 
        else 
        {
            CreateTimer(3.0, Timer_StartDuel, arena_index);
        }
    }
    else
    {
        // 2v2 queue rotation
        if (g_iArenaQueue[arena_index][SLOT_FOUR + 1] && g_iArenaQueue[arena_index][SLOT_FOUR + 2])
        {
            RemoveFromQueue(loser2, false, true);
            RemoveFromQueue(loser1, false, true);
            AddInQueue(loser2, arena_index, false, 0, false);
            AddInQueue(loser1, arena_index, false, 0, false);
        }
        else if (g_iArenaQueue[arena_index][SLOT_FOUR + 1])
        {
            RemoveFromQueue(loser1, false, true);
            AddInQueue(loser1, arena_index, false, 0, false);
        }
        else 
        {
            // Return to ready state for 2v2 arenas
            CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
        }
    }
}


// ===== CLASS CHANGE MATCH COMPLETION =====

// Handles match completion triggered by class changes during fights (MGE/Endif specific)
void ProcessClassChangeMatchCompletion(int arena_index, int client, int killer, int killer_teammate, int client_teammate, int killer_team_slot, int client_team_slot, int fraglimit)
{
    if (g_iArenaStatus[arena_index] != AS_FIGHT || fraglimit <= 0 || g_iArenaScore[arena_index][killer_team_slot] < fraglimit)
        return;
    
    // Use the main match completion function
    ProcessMatchCompletion(arena_index, killer, killer_teammate, client, client_teammate, killer_team_slot, client_team_slot, fraglimit);
}


// ===== MATCH STATE VALIDATION =====

// Validates if match completion conditions are met
bool ValidateMatchCompletion(int arena_index, int team_slot, int fraglimit)
{
    if (g_iArenaStatus[arena_index] < AS_FIGHT || g_iArenaStatus[arena_index] >= AS_REPORTED)
        return false;
        
    if (fraglimit <= 0)
        return false;
        
    return (g_iArenaScore[arena_index][team_slot] >= fraglimit);
}
