// ===== API FORWARD DECLARATIONS =====

void RegisterForwards()
{
    g_hOnPlayerArenaAdd = new GlobalForward("MGE_OnPlayerArenaAdd", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerArenaAdded = new GlobalForward("MGE_OnPlayerArenaAdded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerArenaRemove = new GlobalForward("MGE_OnPlayerArenaRemove", ET_Hook, Param_Cell, Param_Cell);
    g_hOnPlayerArenaRemoved = new GlobalForward("MGE_OnPlayerArenaRemoved", ET_Ignore, Param_Cell, Param_Cell);
    g_hOn1v1MatchStart = new GlobalForward("MGE_On1v1MatchStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOn1v1MatchEnd = new GlobalForward("MGE_On1v1MatchEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2MatchStart = new GlobalForward("MGE_On2v2MatchStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnDuelStart = new GlobalForward("MGE_OnDuelStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2MatchEnd = new GlobalForward("MGE_On2v2MatchEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnArenaPlayerDeath = new GlobalForward("MGE_OnArenaPlayerDeath", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerELOChange = new GlobalForward("MGE_OnPlayerELOChange", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2ReadyStart = new GlobalForward("MGE_On2v2ReadyStart", ET_Ignore, Param_Cell);
    g_hOn2v2PlayerReady = new GlobalForward("MGE_On2v2PlayerReady", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerScorePoint = new GlobalForward("MGE_OnPlayerScorePoint", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerScoredPoint = new GlobalForward("MGE_OnPlayerScoredPoint", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnMatchELOCalculation = new GlobalForward("MGE_OnMatchELOCalculation", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnMatch2v2ELOCalculation = new GlobalForward("MGE_OnMatch2v2ELOCalculation", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
}

// ===== FORWARD CALL HELPERS =====

// Call the OnPlayerArenaAdd forward
Action CallForward_OnPlayerArenaAdd(int client, int arena_index, int slot)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnPlayerArenaAdd);
    Call_PushCell(client);
    Call_PushCell(arena_index);
    Call_PushCell(slot);
    Call_Finish(result);
    return result;
}

// Call the OnPlayerArenaAdded forward
void CallForward_OnPlayerArenaAdded(int client, int arena_index, int slot)
{
    Call_StartForward(g_hOnPlayerArenaAdded);
    Call_PushCell(client);
    Call_PushCell(arena_index);
    Call_PushCell(slot);
    Call_Finish();
}

// Call the OnPlayerArenaRemove forward
Action CallForward_OnPlayerArenaRemove(int client, int arena_index)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnPlayerArenaRemove);
    Call_PushCell(client);
    Call_PushCell(arena_index);
    Call_Finish(result);
    return result;
}

// Call the OnPlayerArenaRemoved forward
void CallForward_OnPlayerArenaRemoved(int client, int arena_index)
{
    Call_StartForward(g_hOnPlayerArenaRemoved);
    Call_PushCell(client);
    Call_PushCell(arena_index);
    Call_Finish();
}

// Call the On1v1MatchStart forward
void CallForward_On1v1MatchStart(int arena_index, int player1, int player2)
{
    Call_StartForward(g_hOn1v1MatchStart);
    Call_PushCell(arena_index);
    Call_PushCell(player1);
    Call_PushCell(player2);
    Call_Finish();
}

// Call the On1v1MatchEnd forward
void CallForward_On1v1MatchEnd(int duel_id, int arena_index, int winner, int loser, int winner_score, int loser_score)
{
    Call_StartForward(g_hOn1v1MatchEnd);
    Call_PushCell(duel_id);
    Call_PushCell(arena_index);
    Call_PushCell(winner);
    Call_PushCell(loser);
    Call_PushCell(winner_score);
    Call_PushCell(loser_score);
    Call_Finish();
}

// Call the On2v2MatchStart forward
void CallForward_On2v2MatchStart(int arena_index, int team1_player1, int team1_player2, int team2_player1, int team2_player2)
{
    Call_StartForward(g_hOn2v2MatchStart);
    Call_PushCell(arena_index);
    Call_PushCell(team1_player1);
    Call_PushCell(team1_player2);
    Call_PushCell(team2_player1);
    Call_PushCell(team2_player2);
    Call_Finish();
}

// Call the OnDuelStart forward (called only when duel actually starts, not on every round)
void CallForward_OnDuelStart(int arena_index, int player1, int player2, int player3, int player4)
{
    Call_StartForward(g_hOnDuelStart);
    Call_PushCell(arena_index);
    Call_PushCell(player1);
    Call_PushCell(player2);
    Call_PushCell(player3);
    Call_PushCell(player4);
    Call_Finish();
}

// Call the On2v2MatchEnd forward
void CallForward_On2v2MatchEnd(int duel_id, int arena_index, int winning_team, int winning_score, int losing_score, int team1_player1, int team1_player2, int team2_player1, int team2_player2)
{
    Call_StartForward(g_hOn2v2MatchEnd);
    Call_PushCell(duel_id);
    Call_PushCell(arena_index);
    Call_PushCell(winning_team);
    Call_PushCell(winning_score);
    Call_PushCell(losing_score);
    Call_PushCell(team1_player1);
    Call_PushCell(team1_player2);
    Call_PushCell(team2_player1);
    Call_PushCell(team2_player2);
    Call_Finish();
}

// Call the OnArenaPlayerDeath forward
void CallForward_OnArenaPlayerDeath(int victim, int attacker, int arena_index)
{
    Call_StartForward(g_hOnArenaPlayerDeath);
    Call_PushCell(victim);
    Call_PushCell(attacker);
    Call_PushCell(arena_index);
    Call_Finish();
}

// Call the OnPlayerELOChange forward
void CallForward_OnPlayerELOChange(int client, int old_elo, int new_elo, int arena_index)
{
    Call_StartForward(g_hOnPlayerELOChange);
    Call_PushCell(client);
    Call_PushCell(old_elo);
    Call_PushCell(new_elo);
    Call_PushCell(arena_index);
    Call_Finish();
}

// Call the On2v2ReadyStart forward
void CallForward_On2v2ReadyStart(int arena_index)
{
    Call_StartForward(g_hOn2v2ReadyStart);
    Call_PushCell(arena_index);
    Call_Finish();
}

// Call the On2v2PlayerReady forward
void CallForward_On2v2PlayerReady(int client, int arena_index, bool ready_status)
{
    Call_StartForward(g_hOn2v2PlayerReady);
    Call_PushCell(client);
    Call_PushCell(arena_index);
    Call_PushCell(ready_status);
    Call_Finish();
}

// Call the OnPlayerScorePoint forward
Action CallForward_OnPlayerScorePoint(int killer, int victim, int arena_index)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnPlayerScorePoint);
    Call_PushCell(killer);
    Call_PushCell(victim);
    Call_PushCell(arena_index);
    Call_Finish(result);
    return result;
}

// Call the OnPlayerScoredPoint forward
void CallForward_OnPlayerScoredPoint(int killer, int victim, int arena_index, int new_score)
{
    Call_StartForward(g_hOnPlayerScoredPoint);
    Call_PushCell(killer);
    Call_PushCell(victim);
    Call_PushCell(arena_index);
    Call_PushCell(new_score);
    Call_Finish();
}

// Call the OnMatchELOCalculation forward
Action CallForward_OnMatchELOCalculation(int arena_index, int winner, int loser, int winner_score, int loser_score)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnMatchELOCalculation);
    Call_PushCell(arena_index);
    Call_PushCell(winner);
    Call_PushCell(loser);
    Call_PushCell(winner_score);
    Call_PushCell(loser_score);
    Call_Finish(result);
    return result;
}

// Call the OnMatch2v2ELOCalculation forward
Action CallForward_OnMatch2v2ELOCalculation(int arena_index, int team1_player1, int team1_player2, int team2_player1, int team2_player2, int winning_score, int losing_score)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnMatch2v2ELOCalculation);
    Call_PushCell(arena_index);
    Call_PushCell(team1_player1);
    Call_PushCell(team1_player2);
    Call_PushCell(team2_player1);
    Call_PushCell(team2_player2);
    Call_PushCell(winning_score);
    Call_PushCell(losing_score);
    Call_Finish(result);
    return result;
}
