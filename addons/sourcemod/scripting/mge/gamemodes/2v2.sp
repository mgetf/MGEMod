// ===== ARENA SELECTION MENU SYSTEM =====

// Displays the main 2v2 arena selection menu with team join options and conversion to 1v1
void Show2v2SelectionMenu(int client, int arena_index)
{
    if (!IsValidClient(client))
        return;

    char title[128];
    char menu_item[128];

    Menu menu = new Menu(Menu_2v2Selection);

    // Check if player is already in this arena
    int current_slot = g_iPlayerSlot[client];
    bool already_in_arena = (g_iPlayerArena[client] == arena_index && current_slot >= SLOT_ONE && current_slot <= SLOT_FOUR);
    
    if (already_in_arena)
    {
        char current_team[32];
        Format(current_team, sizeof(current_team), "%s", (current_slot == SLOT_ONE || current_slot == SLOT_THREE) ? "RED" : "BLU", client);
        Format(title, sizeof(title), "%T", "2v2ArenaManagementTitle", client, current_team);
    }
    else
    {
        Format(title, sizeof(title), "%T", "2v2ArenaSelectionTitle", client);
    }
    menu.SetTitle(title);

    // Store arena index in menu data
    char arena_data[8];
    IntToString(arena_index, arena_data, sizeof(arena_data));

    // Count current team members
    int red_count = 0;
    int blu_count = 0;
    
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        if (g_iArenaQueue[arena_index][i])
        {
            if (i == SLOT_ONE || i == SLOT_THREE)
                red_count++;
            else
                blu_count++;
        }
    }

    // Option 1: Join normally and switch arena to 1v1 (only if logical)
    char disable_reason[64];
    bool can_convert_to_1v1 = CanConvertArenaTo1v1(arena_index, client, disable_reason, sizeof(disable_reason));
    
    if (can_convert_to_1v1)
    {
        Format(menu_item, sizeof(menu_item), "%T", "JoinNormallySwitch1v1", client);
        menu.AddItem("1", menu_item);
    }
    else
    {
        Format(menu_item, sizeof(menu_item), "%T", "Switch1v1Disabled", client, disable_reason);
        menu.AddItem("1", menu_item, ITEMDRAW_DISABLED);
    }

    // Option 2: Join RED team
    Format(menu_item, sizeof(menu_item), "%T", "JoinRedTeam", client, red_count);
    menu.AddItem("2", menu_item);

    // Option 3: Join BLU team
    Format(menu_item, sizeof(menu_item), "%T", "JoinBluTeam", client, blu_count);
    menu.AddItem("3", menu_item);

    menu.ExitBackButton = true;
    menu.Display(client, 0);
}

// Handles user selections from the 2v2 arena selection menu
int Menu_2v2Selection(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1;
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            
            // Get arena index from pending context (preferred) or current arena
            int arena_index = g_iPendingArena[client] ? g_iPendingArena[client] : g_iPlayerArena[client];
            
            if (StringToInt(info) == 1)
            {
                // Fallback validation for stale menus - check if conversion is still valid
                char reason[64];
                if (!CanConvertArenaTo1v1(arena_index, client, reason, sizeof(reason))) {
                    MC_PrintToChat(client, "%t", "CannotConvertTo1v1", reason);
                    return 0;
                }
                
                // Switch arena to 1v1 (same logic as !1v1 command)
                g_bFourPersonArena[arena_index] = false;
                g_iArenaCdTime[arena_index] = DEFAULT_COUNTDOWN_TIME;
                CreateTimer(1.5, Timer_StartDuel, arena_index);
                UpdateArenaName(arena_index);
                
                // Notify players about mode change (same as !1v1 command)
                if(g_iArenaQueue[arena_index][SLOT_ONE]) {
                    MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_ONE], "%t", "ChangedArenaTo1v1");
                }
                
                if(g_iArenaQueue[arena_index][SLOT_TWO]) {
                    MC_PrintToChat(g_iArenaQueue[arena_index][SLOT_TWO], "%t", "ChangedArenaTo1v1");
                }
                
                // If player is not already in the arena, add them
                if (g_iPlayerArena[client] != arena_index || g_iPlayerSlot[client] < SLOT_ONE || g_iPlayerSlot[client] > SLOT_FOUR)
                {
                    AddInQueue(client, arena_index, true, 0, false);
                }
                else
                {
                    // Player is already in arena, just reset them for 1v1 mode
                    CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
                }

                // Clear pending arena after action
                g_iPendingArena[client] = 0;
            }
            else if (StringToInt(info) == 2)
            {
                // Join RED team
                if (g_iPlayerArena[client] != arena_index)
                {
                    // Switching arenas: remove from current on confirm, then add with team pref
                    if (g_iPlayerArena[client])
                    {
                        RemoveFromQueue(client, true);
                    }
                    AddInQueue(client, arena_index, true, TEAM_RED, false);
                }
                else
                {
                    Handle2v2TeamSwitchFromMenu(client, arena_index, TEAM_RED);
                }

                // Clear pending arena after action
                g_iPendingArena[client] = 0;
            }
            else if (StringToInt(info) == 3)
            {
                // Join BLU team
                if (g_iPlayerArena[client] != arena_index)
                {
                    // Switching arenas: remove from current on confirm, then add with team pref
                    if (g_iPlayerArena[client])
                    {
                        RemoveFromQueue(client, true);
                    }
                    AddInQueue(client, arena_index, true, TEAM_BLU, false);
                }
                else
                {
                    Handle2v2TeamSwitchFromMenu(client, arena_index, TEAM_BLU);
                }

                // Clear pending arena after action
                g_iPendingArena[client] = 0;
            }
        }
        case MenuAction_Cancel:
        {
            // Player cancelled - only clear arena assignment if they weren't in an arena before
            int client = param1;
            int current_slot = g_iPlayerSlot[client];
            
            // Only clear arena assignment if player wasn't actually placed in a slot yet
            // (This handles the case where we temporarily set arena during menu display)
            if (g_iPlayerArena[client] && (current_slot < SLOT_ONE || current_slot > SLOT_FOUR))
            {
                g_iPlayerArena[client] = 0;
                g_iPlayerSlot[client] = 0;
            }

            // Always clear pending arena on cancel
            g_iPendingArena[client] = 0;

            if (param2 == MenuCancel_ExitBack)
            {
                ShowMainMenu(client);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}


// ===== READY SYSTEM MANAGEMENT =====

// Initializes the 2v2 ready system when all 4 players have joined an arena
void Start2v2ReadySystem(int arena_index)
{
    // Reset all players' ready status
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client)
        {
            g_bPlayer2v2Ready[client] = false;
        }
    }

    // Set arena status to waiting for ready
    SetArenaStatus(arena_index, AS_WAITING_READY);

    // Call 2v2 ready start forward
    CallForward_On2v2ReadyStart(arena_index);

    // Reset all players and show ready menu
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client)
        {
            CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
            CreateTimer(0.5, Timer_ShowReadyMenu, GetClientUserId(client));
        }
    }

    // Notify players about ready state
    PrintToChatArena(arena_index, "%t", "All4PlayersJoined");
    
    // Delay hint text by 1 second after arena selection
    CreateTimer(1.0, Timer_Show2v2InitialStatus, arena_index);
    
    // Start hud text refresh timer
    CreateTimer(5.0, Timer_Refresh2v2Hud, arena_index, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// Displays the ready confirmation menu to players in 2v2 arenas
void Show2v2ReadyMenu(int client)
{
    if (!IsValidClient(client))
        return;

    int arena_index = g_iPlayerArena[client];
    if (!arena_index || !g_bFourPersonArena[arena_index] || g_iArenaStatus[arena_index] != AS_WAITING_READY)
        return;

    char title[128];
    Menu menu = new Menu(Menu_2v2Ready);

    Format(title, sizeof(title), "%T", "Ready2v2MatchTitle", client);
    menu.SetTitle(title);

    char yes_text[64], no_text[64];
    Format(yes_text, sizeof(yes_text), "%T", "YesImReady", client);
    Format(no_text, sizeof(no_text), "%T", "NoNotReady", client);
    menu.AddItem("1", yes_text);
    menu.AddItem("0", no_text);

    menu.ExitButton = true;
    menu.Display(client, 0);
}

// Processes player responses from the ready confirmation menu
int Menu_2v2Ready(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1;
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            
            int arena_index = g_iPlayerArena[client];
            if (!arena_index || !g_bFourPersonArena[arena_index] || g_iArenaStatus[arena_index] != AS_WAITING_READY)
                return 0;

            bool ready = StringToInt(info) == 1;
            g_bPlayer2v2Ready[client] = ready;

            // Call 2v2 player ready forward
            CallForward_On2v2PlayerReady(client, arena_index, ready);

            Update2v2ReadyStatus(arena_index);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

// Updates and checks the ready status of all players in a 2v2 arena
void Update2v2ReadyStatus(int arena_index)
{
    int ready_count = 0;
    int total_players = 0;
    
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client)
        {
            total_players++;
            if (g_bPlayer2v2Ready[client])
                ready_count++;
        }
    }

    // Show progress to all players in arena
    if (total_players == 4)
    {
        Show2v2ReadyHud(arena_index, ready_count);
        
        if (ready_count == 4 && g_iArenaStatus[arena_index] == AS_WAITING_READY)
        {
            SetArenaStatus(arena_index, AS_PRECOUNTDOWN);
            PrintToChatArena(arena_index, "%t", "AllPlayersReady");
            CreateTimer(1.5, Timer_StartDuel, arena_index);
        }
    }
}


// ===== HUD DISPLAY SYSTEM =====

// Shows personalized ready status HUD text to each player in the arena
void Show2v2ReadyHud(int arena_index, int ready_count)
{
    // Show personalized HUD text to each player
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client && IsValidClient(client))
        {
            char hudtext[256];
            char status_indicator[64];
            
            // Set personal ready status indicator
            if (g_bPlayer2v2Ready[client])
            {
                Format(status_indicator, sizeof(status_indicator), "%T", "Ready2v2StatusReady", client);
            }
            else
            {
                Format(status_indicator, sizeof(status_indicator), "%T", "Ready2v2StatusNotReady", client);
            }
            
            // Format personalized hud text
            Format(hudtext, sizeof(hudtext), "%T", "Ready2v2HudText", client, ready_count, status_indicator);
            
            PrintHintText(client, "%s", hudtext);
            StopSound(client, SNDCHAN_STATIC, "UI/hint.wav");
        }
    }
}

// Clears ready status HUD text from all players in the arena
void Clear2v2ReadyHud(int arena_index)
{
    // Clear HUD text for all players in arena
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        int client = g_iArenaQueue[arena_index][i];
        if (client && IsValidClient(client))
        {
            PrintHintText(client, "");
            StopSound(client, SNDCHAN_STATIC, "UI/hint.wav");
        }
    }
}


// ===== TEAM MANAGEMENT =====

// Handles team switching logic for players already in 2v2 arenas
void Handle2v2TeamSwitch(int client, int arena_index, int new_team)
{
    int current_slot = g_iPlayerSlot[client];
    
    // Only handle switching for players in active slots
    if (current_slot < SLOT_ONE || current_slot > SLOT_FOUR)
        return;
        
    // Determine current team based on slot
    int current_team = (current_slot == SLOT_ONE || current_slot == SLOT_THREE) ? TEAM_RED : TEAM_BLU;
    
    // If already on the target team, do nothing
    if (current_team == new_team)
        return;
        
    // Find available slot on new team
    int new_slot = 0;
    if (new_team == TEAM_RED)
    {
        if (!g_iArenaQueue[arena_index][SLOT_ONE])
            new_slot = SLOT_ONE;
        else if (!g_iArenaQueue[arena_index][SLOT_THREE])
            new_slot = SLOT_THREE;
    }
    else if (new_team == TEAM_BLU)
    {
        if (!g_iArenaQueue[arena_index][SLOT_TWO])
            new_slot = SLOT_TWO;
        else if (!g_iArenaQueue[arena_index][SLOT_FOUR])
            new_slot = SLOT_FOUR;
    }
    
    // If no slot available on target team, prevent switch
    if (new_slot == 0)
    {
        char team_name[32];
        Format(team_name, sizeof(team_name), "%T", (new_team == TEAM_RED) ? "TeamRed" : "TeamBlu", client);
        MC_PrintToChat(client, "%t", "CannotSwitchTeamNoSlots", team_name);
        return;
    }
    
    // Clear old slot and assign new slot
    g_iArenaQueue[arena_index][current_slot] = 0;
    g_iArenaQueue[arena_index][new_slot] = client;
    g_iPlayerSlot[client] = new_slot;
    
    // Reset ready status if in waiting phase
    if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
    {
        g_bPlayer2v2Ready[client] = false;
    }
    
    // Reset player to spawn on new team
    CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
    
    char name[MAX_NAME_LENGTH];
    char team_name[32];
    GetClientName(client, name, sizeof(name));
    Format(team_name, sizeof(team_name), "%T", (new_team == TEAM_RED) ? "TeamRed" : "TeamBlu", client);
    
    PrintToChatArena(arena_index, "%t", "PlayerSwitchedTeam", name, team_name);
    
    // Check if we have 2v2 team balance and can start/continue ready process
    Check2v2TeamBalance(arena_index);
    
    // Update HUD for all players in the arena to reflect team changes
    UpdateHudForArena(arena_index);
}

// Processes team switching requests originating from menu selections
void Handle2v2TeamSwitchFromMenu(int client, int arena_index, int target_team)
{
    int current_slot = g_iPlayerSlot[client];
    
    // Check if player is already in the arena
    if (current_slot >= SLOT_ONE && current_slot <= SLOT_FOUR)
    {
        // Player is already in the arena, handle team switching
        int current_team = (current_slot == SLOT_ONE || current_slot == SLOT_THREE) ? TEAM_RED : TEAM_BLU;
        
        if (current_team == target_team)
        {
            // Player is already on the selected team, just show confirmation
            char team_name[32];
            Format(team_name, sizeof(team_name), "%T", (target_team == TEAM_RED) ? "TeamRed" : "TeamBlu", client);
            MC_PrintToChat(client, "%t", "AlreadyOnTeam", team_name);
            return;
        }
        
        // Use the existing team switch handler
        Handle2v2TeamSwitch(client, arena_index, target_team);
    }
    else
    {
        // Player is not in arena yet, add them with team preference
        AddInQueue(client, arena_index, true, target_team, false);
    }
}

// Validates team balance and triggers ready system when 2v2 balance is achieved
void Check2v2TeamBalance(int arena_index)
{
    int red_count = 0;
    int blu_count = 0;
    
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        if (g_iArenaQueue[arena_index][i])
        {
            if (i == SLOT_ONE || i == SLOT_THREE)
                red_count++;
            else
                blu_count++;
        }
    }
    
    if (red_count == 2 && blu_count == 2)
    {
        // Perfect 2v2 balance
        if (g_iArenaStatus[arena_index] == AS_IDLE)
        {
            Start2v2ReadySystem(arena_index);
        }
        else if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
        {
            Update2v2ReadyStatus(arena_index);
        }
        else if (g_iArenaStatus[arena_index] == AS_AFTERFIGHT || g_iArenaStatus[arena_index] == AS_FIGHT)
        {
            // Match just ended and players were promoted, transition to ready system
            Clear2v2ReadyHud(arena_index);
            SetArenaStatus(arena_index, AS_IDLE);
            // Restore any waiting/spec players before readying again
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            Start2v2ReadySystem(arena_index);
        }
    }
    else
    {
        // Not balanced, inform players
        if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
        {
            Clear2v2ReadyHud(arena_index);
            SetArenaStatus(arena_index, AS_IDLE);
            if (g_bFourPersonArena[arena_index])
            {
                Restore2v2WaitingSpectators(arena_index);
            }
            PrintToChatArena(arena_index, "%t", "TeamBalanceLost", red_count, blu_count);
        }
    }
}

// Handles 2v2 team reset logic when one team member dies and teammate is dead/spectating
void Handle2v2TeamResetOnDeath(int arena_index, int victim, int victim_teammate, int killer_teammate, int killer_team_slot)
{
    if (!g_bFourPersonArena[arena_index])
        return;
        
    // Check if victim teammate is dead or spectating
    if (!(GetClientTeam(victim_teammate) == TEAM_SPEC || !IsPlayerAlive(victim_teammate)))
        return;
        
    // Reset the arena
    ResetArena(arena_index);
    
    // Reassign teams based on killer's team slot
    if (killer_team_slot == SLOT_ONE)
    {
        // Killer team was RED, so losing team goes to BLU
        ChangeClientTeam(victim, TEAM_BLU);
        ChangeClientTeam(victim_teammate, TEAM_BLU);
        
        ChangeClientTeam(killer_teammate, TEAM_RED);
    }
    else
    {
        // Killer team was BLU, so losing team goes to RED
        ChangeClientTeam(victim, TEAM_RED);
        ChangeClientTeam(victim_teammate, TEAM_RED);
        
        ChangeClientTeam(killer_teammate, TEAM_BLU);
    }
    
    // Start new round with appropriate countdown settings
    if (g_b2v2SkipCountdown)
        CreateTimer(0.1, Timer_New2v2Round, arena_index);
    else
        CreateTimer(0.1, Timer_NewRound, arena_index);
}


// ===== PLAYER UTILITIES =====

// Gets a clients teammate if he's in a 4 player arena
int GetPlayerTeammate(int myClientSlot, int arena_index)
{
    // Map slots to teammates: RED team (1 <-> 3), BLU team (2 <-> 4)
    int client_teammate_slot = (myClientSlot <= SLOT_TWO) ? myClientSlot + 2 : myClientSlot - 2;
    return g_iArenaQueue[arena_index][client_teammate_slot];
}

// Executes class swapping between two teammates in ultiduo arenas
void SwapClasses(int client, int client_teammate)
{
    TFClassType client_class = g_tfctPlayerClass[client];
    TFClassType client_teammate_class = g_tfctPlayerClass[client_teammate];

    ForcePlayerSuicide(client);
    TF2_SetPlayerClass(client, client_teammate_class, false, true);
    ForcePlayerSuicide(client_teammate);
    TF2_SetPlayerClass(client_teammate, client_class, false, true);

    g_tfctPlayerClass[client] = client_teammate_class;
    g_tfctPlayerClass[client_teammate] = client_class;
}

// Restores any 2v2 participants who were moved to spectator while waiting for their teammate
// to finish the round. Ensures they are back on the correct team, clears waiting flag, and
// schedules a reset to spawn them properly.
void Restore2v2WaitingSpectators(int arena_index)
{
    if (!g_bFourPersonArena[arena_index])
        return;

    for (int slot = SLOT_ONE; slot <= SLOT_FOUR; slot++)
    {
        int client = g_iArenaQueue[arena_index][slot];
        if (!IsValidClient(client))
            continue;

        bool isSpec = (GetClientTeam(client) == TEAM_SPEC);
        if (g_iPlayerWaiting[client] || isSpec)
        {
            int targetTeam = (slot == SLOT_ONE || slot == SLOT_THREE) ? TEAM_RED : TEAM_BLU;
            if (GetClientTeam(client) != targetTeam)
            {
                ChangeClientTeam(client, targetTeam);
            }
            g_iPlayerWaiting[client] = false;
            CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
        }
    }
}


// ===== CLASS SWAP MENU SYSTEM =====

// Displays the class swap confirmation menu to the target teammate
void ShowSwapMenu(int client)
{
    if (!IsValidClient(client))
        return;

    char title[128];

    Menu menu = new Menu(SwapMenuHandler);

    Format(title, sizeof(title), "%T", "SwapClassesWithTeammate", client);
    menu.SetTitle(title);
    char yes_text[64], no_text[64];
    Format(yes_text, sizeof(yes_text), "%T", "Yes", client);
    Format(no_text, sizeof(no_text), "%T", "No", client);
    menu.AddItem("yes", yes_text);
    menu.AddItem("no", no_text);
    menu.ExitButton = false;
    menu.Display(client, 20);
}

// Processes responses from the class swap confirmation menu
int SwapMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    /* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select)
    {
        if (param2 == 0)
        {
            int client = param1;
            if (!client)
                return 0;

            int arena_index = g_iPlayerArena[client];
            int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
            SwapClasses(client, client_teammate);

        }
        else
            delete menu;
    }
    /* If the menu was cancelled, print a message to the server about it. */
    else if (action == MenuAction_Cancel)
    {
        PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
    }
    /* If the menu has ended, destroy it */
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}


// ===== COMMANDS =====

// Handles the !ready command for toggling ready status in 2v2 arenas
Action Command_Ready(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int arena_index = g_iPlayerArena[client];
    if (!arena_index)
    {
        MC_PrintToChat(client, "%t", "NotInArena");
        return Plugin_Handled;
    }

    if (!g_bFourPersonArena[arena_index])
    {
        MC_PrintToChat(client, "%t", "ReadyOnlyFor2v2");
        return Plugin_Handled;
    }

    if (g_iArenaStatus[arena_index] != AS_WAITING_READY)
    {
        MC_PrintToChat(client, "%t", "ArenaNotWaitingReady");
        return Plugin_Handled;
    }

    // Close any open menu for the player
    CloseClientMenu(client);

    // Toggle ready status
    g_bPlayer2v2Ready[client] = !g_bPlayer2v2Ready[client];

    // Call 2v2 player ready forward  
    CallForward_On2v2PlayerReady(client, arena_index, g_bPlayer2v2Ready[client]);

    Update2v2ReadyStatus(arena_index);
    return Plugin_Handled;
}

// Handles the !swap command for initiating class swaps in ultiduo arenas
Action Command_Swap(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    if (!g_bCanPlayerSwap[client])
    {
        MC_PrintToChat(client, "%t", "SwapCooldown");
        return Plugin_Handled;
    }
    else
    {
        g_bCanPlayerSwap[client] = false;
        CreateTimer(60.0, Timer_ResetSwap, client);
    }

    int arena_index = g_iPlayerArena[client];

    if (!g_bArenaUltiduo[arena_index] || !g_bFourPersonArena[arena_index])
        return Plugin_Continue;

    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
    ShowSwapMenu(client_teammate);
    return Plugin_Handled;
}


// ===== TIMER CALLBACKS =====

// Displays initial ready status with 1 second delay after arena selection
Action Timer_Show2v2InitialStatus(Handle timer, any arena_index)
{
    // Only show if arena is still in ready state
    if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
    {
        Update2v2ReadyStatus(arena_index);
    }
    return Plugin_Continue;
}

// Periodically refreshes the ready status HUD display for active 2v2 arenas
Action Timer_Refresh2v2Hud(Handle timer, any arena_index)
{
    // Only refresh if arena is still in ready state
    if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
    {
        int ready_count = 0;
        int valid_players = 0;
        
        for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
        {
            int client = g_iArenaQueue[arena_index][i];
            if (client && IsValidClient(client))
            {
                valid_players++;
                if (g_bPlayer2v2Ready[client])
                    ready_count++;
            }
        }
        
        if (valid_players == 4)
        {
            Show2v2ReadyHud(arena_index, ready_count);
        }
        else
        {
            // Not enough valid players, stop the timer
            return Plugin_Stop;
        }
    }
    else
    {
        // Arena is no longer in ready state, stop the timer
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

// Delayed callback to display the ready menu to newly joined players
Action Timer_ShowReadyMenu(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client)
    {
        Show2v2ReadyMenu(client);
    }
    return Plugin_Continue;
}

// Handles post-match cleanup and ready system restart for continuous 2v2 play
Action Timer_Restart2v2Ready(Handle timer, any arena_index)
{
    // Check if we still have 4 players in the arena
    int player_count = 0;
    for (int i = SLOT_ONE; i <= SLOT_FOUR; i++)
    {
        if (g_iArenaQueue[arena_index][i])
            player_count++;
    }

    if (player_count == 4)
    {
        ResetArenaScores(arena_index);
        // Ensure any players that were placed into spectator (waiting) are restored
        Restore2v2WaitingSpectators(arena_index);
        Start2v2ReadySystem(arena_index);
        PrintToChatArena(arena_index, "%t", "MatchFinishedReadyUp");
    }
    else
    {
        // Not enough players, revert to normal behavior
        Clear2v2ReadyHud(arena_index);
        SetArenaStatus(arena_index, AS_IDLE);
        // Still restore any parked spectators in case teams refill
        Restore2v2WaitingSpectators(arena_index);
        ResetArena(arena_index);
    }

    return Plugin_Continue;
}

// Resets all players in a 2v2 arena and transitions to active fighting state
Action Timer_New2v2Round(Handle timer, any arena_index) {
    int red_f1 = g_iArenaQueue[arena_index][SLOT_ONE]; /* Red (slot one) player. */
    int blu_f1 = g_iArenaQueue[arena_index][SLOT_TWO]; /* Blu (slot two) player. */

    int red_f2 = g_iArenaQueue[arena_index][SLOT_THREE]; /* 2nd Red (slot three) player. */
    int blu_f2 = g_iArenaQueue[arena_index][SLOT_FOUR]; /* 2nd Blu (slot four) player. */

    // Remove all projectiles from previous round
    if (g_bClearProjectiles && g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaBBall[arena_index])
        RemoveArenaProjectiles(arena_index);

    if (red_f1) ResetPlayer(red_f1);
    if (blu_f1) ResetPlayer(blu_f1);
    if (red_f2) ResetPlayer(red_f2);
    if (blu_f2) ResetPlayer(blu_f2);

    SetArenaStatus(arena_index, AS_FIGHT);

    return Plugin_Continue;
}

// Resets the class swap cooldown timer for a specific player
Action Timer_ResetSwap(Handle timer, int client)
{
    g_bCanPlayerSwap[client] = true;

    return Plugin_Continue;
}