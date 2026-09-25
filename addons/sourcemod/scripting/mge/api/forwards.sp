// ===== API FORWARD DECLARATIONS =====

void RegisterForwards()
{
    g_hOnPlayerArenaAdd = new GlobalForward("MGE_OnPlayerArenaAdd", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerArenaAdded = new GlobalForward("MGE_OnPlayerArenaAdded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerArenaRemove = new GlobalForward("MGE_OnPlayerArenaRemove", ET_Hook, Param_Cell, Param_Cell);
    g_hOnPlayerArenaRemoved = new GlobalForward("MGE_OnPlayerArenaRemoved", ET_Ignore, Param_Cell, Param_Cell);
    g_hOn1v1MatchStart = new GlobalForward("MGE_On1v1MatchStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOn1v1MatchEnd = new GlobalForward("MGE_On1v1MatchEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2MatchStart = new GlobalForward("MGE_On2v2MatchStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2MatchEnd = new GlobalForward("MGE_On2v2MatchEnd", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnArenaPlayerDeath = new GlobalForward("MGE_OnArenaPlayerDeath", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerELOChange = new GlobalForward("MGE_OnPlayerELOChange", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnPlayerRatingChange = new GlobalForward("MGE_OnPlayerRatingChange", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Float, Param_Cell);
    g_hOnPlayerStatsLoadStateChanged = new GlobalForward("MGE_OnPlayerStatsLoadStateChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOn2v2ReadyStart = new GlobalForward("MGE_On2v2ReadyStart", ET_Ignore, Param_Cell);
    g_hOn2v2PlayerReady = new GlobalForward("MGE_On2v2PlayerReady", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnArenaScoreChange = new GlobalForward("MGE_OnArenaScoreChange", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnArenaStatusChange = new GlobalForward("MGE_OnArenaStatusChange", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    g_hOnMapConfigMissing = new GlobalForward("MGE_OnMapConfigMissing", ET_Hook, Param_String, Param_String);
    g_hOnMapConfigInvalid = new GlobalForward("MGE_OnMapConfigInvalid", ET_Hook, Param_String, Param_String);
    g_hOnFormatHudLines = new GlobalForward("MGE_OnFormatHudLines", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array);
    g_hOnArenaWhitelistChanged = new GlobalForward("MGE_OnArenaWhitelistChanged", ET_Ignore, Param_Cell);
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
void CallForward_On1v1MatchEnd(int arena_index, int winner, int loser, int winner_score, int loser_score)
{
    Call_StartForward(g_hOn1v1MatchEnd);
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

// Call the On2v2MatchEnd forward
void CallForward_On2v2MatchEnd(int arena_index, int winning_team, int winning_score, int losing_score, int team1_player1, int team1_player2, int team2_player1, int team2_player2)
{
    Call_StartForward(g_hOn2v2MatchEnd);
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

// Call the OnPlayerRatingChange forward
void CallForward_OnPlayerRatingChange(int client, int old_rating, int new_rating, float old_rd, float new_rd, int arena_index)
{
    Call_StartForward(g_hOnPlayerRatingChange);
    Call_PushCell(client);
    Call_PushCell(old_rating);
    Call_PushCell(new_rating);
    Call_PushFloat(old_rd);
    Call_PushFloat(new_rd);
    Call_PushCell(arena_index);
    Call_Finish();
}

// Call the OnPlayerStatsLoadStateChanged forward
void CallForward_OnPlayerStatsLoadStateChanged(int client, MGEPlayerStatsLoadState old_state, MGEPlayerStatsLoadState new_state)
{
    Call_StartForward(g_hOnPlayerStatsLoadStateChanged);
    Call_PushCell(client);
    Call_PushCell(old_state);
    Call_PushCell(new_state);
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

// Call the OnArenaScoreChange forward
void CallForward_OnArenaScoreChange(int arena_index, int red_score, int blu_score)
{
    Call_StartForward(g_hOnArenaScoreChange);
    Call_PushCell(arena_index);
    Call_PushCell(red_score);
    Call_PushCell(blu_score);
    Call_Finish();
}

// Call the OnArenaStatusChange forward
void CallForward_OnArenaStatusChange(int arena_index, int old_status, int new_status)
{
    Call_StartForward(g_hOnArenaStatusChange);
    Call_PushCell(arena_index);
    Call_PushCell(old_status);
    Call_PushCell(new_status);
    Call_Finish();
}

// Call the OnFormatHudLines forward so external plugins can rewrite both score-line parentheticals at once
void CallForward_OnFormatHudLines(int arena_index, int client, bool is_spectator, MGEHudLineInfo redLine, MGEHudLineInfo bluLine)
{
    Call_StartForward(g_hOnFormatHudLines);
    Call_PushCell(arena_index);
    Call_PushCell(client);
    Call_PushCell(is_spectator);
    Call_PushArrayEx(redLine, sizeof(redLine), SM_PARAM_COPYBACK);
    Call_PushArrayEx(bluLine, sizeof(bluLine), SM_PARAM_COPYBACK);
    Call_Finish();
}

// Call the OnMapConfigMissing forward
Action CallForward_OnMapConfigMissing(const char[] mapName, const char[] configPath)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnMapConfigMissing);
    Call_PushString(mapName);
    Call_PushString(configPath);
    Call_Finish(result);
    return result;
}

// Call the OnMapConfigInvalid forward
Action CallForward_OnMapConfigInvalid(const char[] mapName, const char[] configPath)
{
    Action result = Plugin_Continue;
    Call_StartForward(g_hOnMapConfigInvalid);
    Call_PushString(mapName);
    Call_PushString(configPath);
    Call_Finish(result);
    return result;
}

void CallForward_OnArenaWhitelistChanged(int arena_index)
{
    Call_StartForward(g_hOnArenaWhitelistChanged);
    Call_PushCell(arena_index);
    Call_Finish();
}
