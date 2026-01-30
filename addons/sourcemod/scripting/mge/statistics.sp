
// ===== MENU SYSTEM =====

// Handles menu interactions for top players panel including pagination navigation
int Panel_TopPlayers(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char query[512];
            
            // Check if we have stored pagination info for this client
            bool hasPagination = g_iTopPlayersTotalPages[param1] > 1;
            
            if (hasPagination)
            {
                switch (param2)
                {
                    case 1: // Previous Page
                    {
                        g_iTopPlayersPage[param1]--;
                        GetSelectTopPlayersQuery(query, sizeof(query));
                        g_DB.Query(SQL_OnTopPlayersReceived, query, param1);
                    }
                    case 2: // Next Page
                    {
                        g_iTopPlayersPage[param1]++;
                        GetSelectTopPlayersQuery(query, sizeof(query));
                        g_DB.Query(SQL_OnTopPlayersReceived, query, param1);
                    }
                    case 3: // Close
                    {
                        // Panel closes automatically
                    }
                }
            }
            else
            {
                // No pagination, so item 1 is Close
                switch (param2)
                {
                    case 1: // Close
                    {
                        // Panel closes automatically
                    }
                }
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                ShowMainMenu(param1);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

// Creates and displays paginated top players panel with ELO rankings
void ShowTopPlayersPanel(int client, DBResultSet results, int totalRows)
{
    if (!IsValidClient(client))
        return;

    Panel panel = new Panel();
    char title[128];
    Format(title, sizeof(title), "%T\n", "EloRankingsTitle", client);
    panel.SetTitle(title);

    int playersPerPage = 10;
    int totalPages = (totalRows + playersPerPage - 1) / playersPerPage;
    int currentPage = g_iTopPlayersPage[client];
    
    if (currentPage >= totalPages)
        currentPage = 0;
    if (currentPage < 0)
        currentPage = totalPages - 1;
    
    g_iTopPlayersPage[client] = currentPage;
    g_iTopPlayersTotalPages[client] = totalPages;
    
    int startIndex = currentPage * playersPerPage;
    int endIndex = startIndex + playersPerPage;
    if (endIndex > totalRows)
        endIndex = totalRows;

    char line[256];
    Format(line, sizeof(line), "%T\n", "PageInfo", client, currentPage + 1, totalPages, totalRows);
    panel.DrawText(line);
    panel.DrawText(" ");

    int currentRow = 0;
    int rank = 1;
    
    while (results.FetchRow())
    {
        if (currentRow < startIndex)
        {
            currentRow++;
            rank++;
            continue;
        }
        
        if (currentRow >= endIndex)
            break;

        int rating = results.FetchInt(0);
        char name[MAX_NAME_LENGTH];
        results.FetchString(1, name, sizeof(name));
        int wins = results.FetchInt(2);
        int losses = results.FetchInt(3);

        if (g_bNoDisplayRating)
        {
            Format(line, sizeof(line), "#%d %s", rank, name);
        }
        else
        {
            Format(line, sizeof(line), "#%d %s (%d) [%d/%d]", rank, name, rating, wins, losses);
        }
        
        panel.DrawText(line);
        currentRow++;
        rank++;
    }

    panel.DrawText(" ");
    
    char prev_text[64], next_text[64], close_text[64];
    Format(prev_text, sizeof(prev_text), "%T", "PreviousPage", client);
    Format(next_text, sizeof(next_text), "%T", "NextPage", client);
    Format(close_text, sizeof(close_text), "%T", "Close", client);
    
    if (totalPages > 1)
    {
        if (currentPage > 0)
            panel.DrawItem(prev_text);
        else
            panel.DrawItem(prev_text, ITEMDRAW_DISABLED);
            
        if (currentPage < totalPages - 1)
            panel.DrawItem(next_text);
        else
            panel.DrawItem(next_text, ITEMDRAW_DISABLED);
    }
    
    panel.DrawItem(close_text);
    panel.Send(client, Panel_TopPlayers, MENU_TIME_FOREVER);
    delete panel;
}


// ===== DATABASE HANDLERS =====

// Processes database query results for top players rankings display
void SQL_OnTopPlayersReceived(Database db, DBResultSet results, const char[] error, any data)
{
    int client = data;

    if (db == null)
    {
        LogError("[TopPlayersPanel] Query failed: database connection lost");
        return;
    }
    
    if (results == null)
    {
        LogError("[TopPlayersPanel] Query failed: %s", error);
        return;
    }

    if (client < 1 || client > MaxClients || !IsClientConnected(client))
    {
        LogError("SQL_OnTopPlayersReceived failed: client %d <%s> is invalid.", client, g_sPlayerSteamID[client]);
        return;
    }

    int rowCount = SQL_GetRowCount(results);
    if (rowCount == 0)
    {
        MC_PrintToChat(client, "%t", "top5error");
        return;
    }

    ShowTopPlayersPanel(client, results, rowCount);
}


// ===== PLAYER COMMANDS =====

// Initiates top players query and displays ELO rankings to requesting client
Action Command_Top5(int client, int args)
{
    if (g_bNoStats || !IsValidClient(client))
    {
        MC_PrintToChat(client, "%t", "NoStatsTrue");
        return Plugin_Continue;
    }

    g_iTopPlayersPage[client] = 0;
    char query[512];
    GetSelectTopPlayersQuery(query, sizeof(query));
    g_DB.Query(SQL_OnTopPlayersReceived, query, client);
    return Plugin_Handled;
}

// Shows player's own rank or compares with another player's statistics
Action Command_Rank(int client, int args)
{
    if (g_bNoStats || !IsValidClient(client))
        return Plugin_Handled;

    int target = client;
    
    if (args > 0)
    {
        char argstr[64];
        GetCmdArgString(argstr, sizeof(argstr));
        int targ = FindTarget(0, argstr, false, false);
        
        if (targ != -1)
            target = targ;
    }
    
    // Store target for panel display callbacks
    g_iRankTargetClient[client] = target;
    
    // Start getting all rank data for the target player
    GetPlayerRankData(client, target);

    return Plugin_Handled;
}

// Initiates database queries to get all rank data for a player
void GetPlayerRankData(int requestingClient, int targetPlayer)
{
    if (!IsValidClient(targetPlayer) || g_bNoStats)
        return;
    
    // Query for rating rank
    char query[512];
    GetSelectPlayerRatingRankQuery(query, sizeof(query), g_sPlayerSteamID[targetPlayer]);
    DataPack dp = new DataPack();
    dp.WriteCell(requestingClient);
    dp.WriteCell(targetPlayer);
    dp.WriteCell(1); // Query type: 1=rating, 2=wins, 3=losses
    g_DB.Query(SQL_OnPlayerRankReceived, query, dp);
}

// Database callback for player rank queries
void SQL_OnPlayerRankReceived(Database db, DBResultSet results, const char[] error, DataPack dp)
{
    dp.Reset();
    int requestingClient = dp.ReadCell();
    int targetPlayer = dp.ReadCell();
    int queryType = dp.ReadCell();
    delete dp;
    
    if (db == null || results == null)
    {
        LogError("[PlayerRank] Query failed (type %d): %s", queryType, error);
        return;
    }
    
    if (!IsValidClient(requestingClient) || !IsValidClient(targetPlayer))
        return;
        
    int rank = 0;
    if (results.FetchRow())
        rank = results.FetchInt(0);
    
    // Store the rank data
    switch (queryType)
    {
        case 1: 
        {
            g_iPlayerRatingRank[targetPlayer] = rank;
            // Continue with wins query
            char query[512];
            GetSelectPlayerWinsRankQuery(query, sizeof(query), g_sPlayerSteamID[targetPlayer]);
            DataPack newDp = new DataPack();
            newDp.WriteCell(requestingClient);
            newDp.WriteCell(targetPlayer);
            newDp.WriteCell(2);
            g_DB.Query(SQL_OnPlayerRankReceived, query, newDp);
        }
        case 2:
        {
            g_iPlayerWinsRank[targetPlayer] = rank;
            // Continue with losses query
            char query[512];
            GetSelectPlayerLossesRankQuery(query, sizeof(query), g_sPlayerSteamID[targetPlayer]);
            DataPack newDp = new DataPack();
            newDp.WriteCell(requestingClient);
            newDp.WriteCell(targetPlayer);
            newDp.WriteCell(3);
            g_DB.Query(SQL_OnPlayerRankReceived, query, newDp);
        }
        case 3:
        {
            g_iPlayerLossesRank[targetPlayer] = rank;
            // All queries done, show the panel
            ShowPlayerRankPanel(requestingClient, targetPlayer);
        }
    }
}

// Creates and displays comprehensive player rank panel
void ShowPlayerRankPanel(int client, int targetPlayer)
{
    if (!IsValidClient(client) || !IsValidClient(targetPlayer))
        return;

    Panel panel = new Panel();
    char title[128];
    
    if (client == targetPlayer)
    {
        Format(title, sizeof(title), "%T\n", "YourStatistics", client);
    }
    else
    {
        char targetName[MAX_NAME_LENGTH];
        GetClientName(targetPlayer, targetName, sizeof(targetName));
        Format(title, sizeof(title), "%T\n", "PlayerStatistics", client, targetName);
    }
    
    panel.SetTitle(title);
    panel.DrawText(" ");
    
    // Rating display
    if (!g_bNoDisplayRating && g_bShowElo[client])
    {
        char ratingLine[256];
        Format(ratingLine, sizeof(ratingLine), "%T", "PanelRatingLine", client, g_iPlayerRating[targetPlayer], g_iPlayerRatingRank[targetPlayer]);
        panel.DrawText(ratingLine);

        int classId = view_as<int>(g_tfctPlayerClass[targetPlayer]);
        if (classId < 1 || classId > 9)
            classId = view_as<int>(TF2_GetPlayerClass(targetPlayer));

        if (classId >= 1 && classId <= 9)
        {
            char className[16];
            strcopy(className, sizeof(className), TFClassToString(view_as<TFClassType>(classId)));
            char classRatingLine[256];
            // Show average matchup rating for this class (average across all opponent classes)
            int totalRating = 0;
            int count = 0;
            for (int oppClass = 1; oppClass <= 9; oppClass++)
            {
                if (g_iPlayerClassRating[targetPlayer][classId][oppClass] > 0)
                {
                    totalRating += g_iPlayerClassRating[targetPlayer][classId][oppClass];
                    count++;
                }
            }
            int avgRating = (count > 0) ? (totalRating / count) : 0;
            Format(classRatingLine, sizeof(classRatingLine), "%T", "PanelClassRatingLine", client, className, avgRating);
            panel.DrawText(classRatingLine);
        }
    }
    
    // Wins display
    char winsLine[256];
    Format(winsLine, sizeof(winsLine), "W: %d (#%d)", g_iPlayerWins[targetPlayer], g_iPlayerWinsRank[targetPlayer]);
    panel.DrawText(winsLine);
    
    // Losses display  
    char lossesLine[256];
    Format(lossesLine, sizeof(lossesLine), "L: %d (#%d)", g_iPlayerLosses[targetPlayer], g_iPlayerLossesRank[targetPlayer]);
    panel.DrawText(lossesLine);
    
    // W/L ratio display
    char wlRatioLine[256];
    if (g_iPlayerLosses[targetPlayer] > 0)
    {
        float wlRatio = float(g_iPlayerWins[targetPlayer]) / float(g_iPlayerLosses[targetPlayer]);
        Format(wlRatioLine, sizeof(wlRatioLine), "W/L: %.2f", wlRatio);
    }
    else if (g_iPlayerWins[targetPlayer] > 0)
    {
        Format(wlRatioLine, sizeof(wlRatioLine), "W/L: ∞");
    }
    else
    {
        Format(wlRatioLine, sizeof(wlRatioLine), "W/L: 0.00");
    }
    panel.DrawText(wlRatioLine);
    
    // Win percentage display
    char winPercentLine[256];
    int totalGames = g_iPlayerWins[targetPlayer] + g_iPlayerLosses[targetPlayer];
    if (totalGames > 0)
    {
        float winRate = (float(g_iPlayerWins[targetPlayer]) / float(totalGames)) * 100.0;
        Format(winPercentLine, sizeof(winPercentLine), "WR: %.1f%%", winRate);
    }
    else
    {
        Format(winPercentLine, sizeof(winPercentLine), "WR: 0.0%%");
    }
    panel.DrawText(winPercentLine);
    
    // Win chance display (only if looking at another player and rating is enabled)
    if (client != targetPlayer && !g_bNoDisplayRating && g_bShowElo[client])
    {
        panel.DrawText(" ");
        int winChance = RoundFloat((1 / (Pow(10.0, float((g_iPlayerRating[targetPlayer] - g_iPlayerRating[client])) / 400) + 1)) * 100);
        char winChanceLine[256];
        Format(winChanceLine, sizeof(winChanceLine), "%T", "PanelWinChance", client, winChance);
        panel.DrawText(winChanceLine);
    }
    
    panel.DrawText(" ");
    char closeText[64];
    Format(closeText, sizeof(closeText), "%T", "Close", client);
    panel.DrawItem(closeText);
    panel.Send(client, Panel_PlayerRank, MENU_TIME_FOREVER);
    delete panel;
}

// Handles panel interactions for player rank display
int Panel_PlayerRank(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            // Only Close option available
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                ShowMainMenu(param1);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    
    return 0;
}
