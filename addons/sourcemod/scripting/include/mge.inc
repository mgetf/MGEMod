#if defined _mge_included
  #endinput
#endif
#define _mge_included

// Game Mode Constants
#define MGE_GAMEMODE_MGE        (1 << 0)    // Standard 1v1
#define MGE_GAMEMODE_BBALL      (1 << 1)    // Basketball
#define MGE_GAMEMODE_KOTH       (1 << 2)    // King of the Hill
#define MGE_GAMEMODE_AMMOMOD    (1 << 3)    // Ammomod
#define MGE_GAMEMODE_MIDAIR     (1 << 4)    // Midair
#define MGE_GAMEMODE_ENDIF      (1 << 5)    // Endif
#define MGE_GAMEMODE_ULTIDUO    (1 << 6)    // Ultiduo
#define MGE_GAMEMODE_TURRIS     (1 << 7)    // Turris
#define MGE_GAMEMODE_4PLAYER    (1 << 8)    // 2v2

// Slot Constants
#define SLOT_ONE            1
#define SLOT_TWO            2
#define SLOT_THREE          3
#define SLOT_FOUR           4

// Team Constants (for 2v2)
#define TEAM_NONE           0
#define TEAM_SPEC           1
#define TEAM_RED            2
#define TEAM_BLU            3

// Player Statistics Structure
enum struct MGEPlayerStats
{
    int elo;            // Current ELO rating
    int kills;          // Total kills
    int deaths;         // Total deaths  
    int wins;           // Total wins
    int losses;         // Total losses
    float rating;       // Win/Loss ratio
}

// Arena Information Structure
enum struct MGEArenaInfo
{
    char name[64];      // Arena display name (e.g., "Spire [MGE 1v1]")
    int players;        // Current player count
    int maxSlots;       // Maximum players (2 for 1v1, 4 for 2v2)
    int status;         // Arena status (AS_IDLE, AS_FIGHT, etc.)
    int gameMode;       // Game mode flags
    bool is2v2;         // True if 2v2 arena
    int fragLimit;      // Frag limit for this arena
}

enum
{
    AS_IDLE = 0,
    AS_PRECOUNTDOWN,
    AS_COUNTDOWN,
    AS_FIGHT,
    AS_AFTERFIGHT,
    AS_REPORTED,
    AS_WAITING_READY
};

/**
 * Called before a player is added to an arena - can be blocked
 *
 * @param client         Client index
 * @param arena_index    Arena index
 * @param slot           Arena slot (1-4)
 * @return               Plugin_Continue to allow, Plugin_Stop to block
 */
forward Action MGE_OnPlayerArenaAdd(int client, int arena_index, int slot);

/**
 * Called after a player is successfully added to an arena
 *
 * @param client         Client index
 * @param arena_index    Arena index
 * @param slot           Arena slot (1-4)
 */
forward void MGE_OnPlayerArenaAdded(int client, int arena_index, int slot);

/**
 * Called before a player is removed from an arena - can be blocked
 *
 * @param client         Client index
 * @param arena_index    Arena index
 * @return               Plugin_Continue to allow, Plugin_Stop to block
 */
forward Action MGE_OnPlayerArenaRemove(int client, int arena_index);

/**
 * Called after a player is successfully removed from an arena
 *
 * @param client         Client index
 * @param arena_index    Arena index
 */
forward void MGE_OnPlayerArenaRemoved(int client, int arena_index);

/**
 * Called when a 1v1 match starts
 *
 * @param arena_index    Arena index
 * @param player1        First player client index
 * @param player2        Second player client index
 */
forward void MGE_On1v1MatchStart(int arena_index, int player1, int player2);

/**
 * Called when a duel actually starts (first round, when duel timer is set)
 * This is called only once per duel, not on every round
 *
 * @param arena_index    Arena index
 * @param player1        First player client index (1v1) or Team 1 first player (2v2)
 * @param player2        Second player client index (1v1) or Team 1 second player (2v2)
 * @param player3        Team 2 first player (2v2 only, 0 for 1v1)
 * @param player4        Team 2 second player (2v2 only, 0 for 1v1)
 */
forward void MGE_OnDuelStart(int arena_index, int player1, int player2, int player3, int player4);

/**
 * Called when a 1v1 match ends
 *
 * @param arena_index    Arena index
 * @param winner         Winner client index
 * @param loser          Loser client index
 * @param winner_score   Winner's final score (frags)
 * @param loser_score    Loser's final score (frags)
 */
forward void MGE_On1v1MatchEnd(int duel_id, int arena_index, int winner, int loser, int winner_score, int loser_score);

/**
 * Called when a 2v2 match starts
 *
 * @param arena_index    Arena index
 * @param team1_player1  Team 1 first player
 * @param team1_player2  Team 1 second player
 * @param team2_player1  Team 2 first player
 * @param team2_player2  Team 2 second player
 */
forward void MGE_On2v2MatchStart(int arena_index, int team1_player1, int team1_player2, int team2_player1, int team2_player2);

/**
 * Called when a 2v2 match ends
 *
 * @param arena_index        Arena index
 * @param winning_team       Winning team (TEAM_RED or TEAM_BLU)
 * @param winning_score      Winning team's final score (frags)
 * @param losing_score       Losing team's final score (frags)
 * @param team1_player1      Team 1 first player
 * @param team1_player2      Team 1 second player
 * @param team2_player1      Team 2 first player
 * @param team2_player2      Team 2 second player
 */
forward void MGE_On2v2MatchEnd(int duel_id, int arena_index, int winning_team, int winning_score, int losing_score, int team1_player1, int team1_player2, int team2_player1, int team2_player2);

/**
 * Called when a player dies in an arena
 *
 * @param victim         Victim client index
 * @param attacker       Attacker client index (0 if none)
 * @param arena_index    Arena index
 */
forward void MGE_OnArenaPlayerDeath(int victim, int attacker, int arena_index);

/**
 * Called when a player's ELO changes
 *
 * @param client         Client index
 * @param old_elo        Previous ELO rating
 * @param new_elo        New ELO rating
 * @param arena_index    Arena where change occurred
 */
forward void MGE_OnPlayerELOChange(int client, int old_elo, int new_elo, int arena_index);

/**
 * Called when 2v2 ready system starts
 *
 * @param arena_index    2v2 arena index
 */
forward void MGE_On2v2ReadyStart(int arena_index);

/**
 * Called when a player changes ready status in 2v2
 *
 * @param client         Client who changed ready status
 * @param arena_index    2v2 arena index
 * @param ready_status   New ready status (true/false)
 */
forward void MGE_On2v2PlayerReady(int client, int arena_index, bool ready_status);

/**
 * Called when a player is about to score a point (kill) in an arena
 * This can be blocked to prevent score awarding
 *
 * @param killer         Killer client index
 * @param victim         Victim client index
 * @param arena_index    Arena index
 * @return               Plugin_Continue to allow scoring, Plugin_Stop to block
 */
forward Action MGE_OnPlayerScorePoint(int killer, int victim, int arena_index);

/**
 * Called when a player successfully scores a point (kill) in an arena
 *
 * @param killer         Killer client index
 * @param victim         Victim client index
 * @param arena_index    Arena index
 * @param new_score      Killer's new score after this point
 */
forward void MGE_OnPlayerScoredPoint(int killer, int victim, int arena_index, int new_score);

/**
 * Called before ELO calculations at the end of a match
 * This can be blocked to prevent ELO changes
 *
 * @param arena_index    Arena index
 * @param winner         Winner client index
 * @param loser          Loser client index
 * @param winner_score   Winner's final score
 * @param loser_score    Loser's final score
 * @return               Plugin_Continue to allow ELO calc, Plugin_Stop to block
 */
forward Action MGE_OnMatchELOCalculation(int arena_index, int winner, int loser, int winner_score, int loser_score);

/**
 * Called before 2v2 ELO calculations at the end of a match
 * This can be blocked to prevent ELO changes
 *
 * @param arena_index        Arena index
 * @param team1_player1      Team 1 first player
 * @param team1_player2      Team 1 second player
 * @param team2_player1      Team 2 first player
 * @param team2_player2      Team 2 second player
 * @param winning_score      Winning team's score
 * @param losing_score       Losing team's score
 * @return                   Plugin_Continue to allow ELO calc, Plugin_Stop to block
 */
forward Action MGE_OnMatch2v2ELOCalculation(int arena_index, int team1_player1, int team1_player2, int team2_player1, int team2_player2, int winning_score, int losing_score);

/**
 * Gets a player's class rating for a specific class
 *
 * @param client         Client index
 * @param classType      TFClassType value (1-9)
 * @return               Class rating, or 0 on invalid client/class
 */
native int MGE_GetPlayerClassRating(int client, int classType);

/**
 * Gets a player's class rating for their current class
 *
 * @param client         Client index
 * @return               Class rating, or 0 on invalid client/class
 */
native int MGE_GetPlayerCurrentClassRating(int client);

/**
 * Gets a player's matchup rating for a specific class vs opponent class
 *
 * @param client         Client index
 * @param myClass        TFClassType value (1-9) - the class the player is playing
 * @param opponentClass  TFClassType value (1-9) - the opponent's class
 * @return               Matchup rating, or 1500 (default) if not initialized
 */
native int MGE_GetPlayerMatchupRating(int client, int myClass, int opponentClass);

/**
 * Gets a player's current arena
 *
 * @param client         Client index
 * @return               Arena index (0 if not in arena)
 */
native int MGE_GetPlayerArena(int client);

/**
 * Gets a player's complete statistics
 *
 * @param client         Client index
 * @param stats          Structure to store statistics in
 * @return               True on success, false otherwise
 */
native bool MGE_GetPlayerStats(int client, MGEPlayerStats stats);

/**
 * Gets complete arena information
 *
 * @param arena_index    Arena index
 * @param info           Structure to store arena information in
 * @return               True on success, false if arena is invalid
 */
native bool MGE_GetArenaInfo(int arena_index, MGEArenaInfo info);

/**
 * Checks if a player is currently in an MGE arena
 *
 * @param client         Client index
 * @return               True if in arena, false otherwise
 */
native bool MGE_IsPlayerInArena(int client);

/**
 * Gets the total number of arenas on the current map
 *
 * @return               Number of arenas
 */
native int MGE_GetArenaCount();


/**
 * Gets a player in a specific arena slot
 *
 * @param arena_index    Arena index
 * @param slot           Slot number (1-4)
 * @return               Client index (0 if slot empty)
 */
native int MGE_GetArenaPlayer(int arena_index, int slot);

/**
 * Checks if an arena index is valid
 *
 * @param arena_index    Arena index to check
 * @return               True if valid, false otherwise
 */
native bool MGE_IsValidArena(int arena_index);

/**
 * Gets the status of an arena
 *
 * @param arena_index    Arena index
 * @return               Arena status (AS_IDLE, AS_FIGHT, etc.)
 */
native int MGE_GetArenaStatus(int arena_index);

/**
 * Adds a player to an arena
 *
 * @param client         Client to add
 * @param arena_index    Target arena
 * @param slot           Specific slot (1-4) or 0 for automatic assignment
 * @return               True on success, false otherwise
 * @error                Invalid slot for arena type, slot already occupied, etc.
 */
native bool MGE_AddPlayerToArena(int client, int arena_index, int slot = 0);

/**
 * Removes a player from their current arena
 *
 * @param client         Client to remove
 * @return               True on success, false otherwise
 */
native bool MGE_RemovePlayerFromArena(int client);


/**
 * Gets a player's ready status in 2v2
 *
 * @param client         Client index
 * @return               True if ready, false otherwise
 */
native bool MGE_IsPlayerReady(int client);

/**
 * Sets a player's ready status in 2v2
 *
 * @param client         Client to modify
 * @param ready          Ready status
 * @return               True on success, false otherwise
 */
native bool MGE_SetPlayerReady(int client, bool ready);

/**
 * Gets a player's teammate in 2v2 arena
 *
 * @param client         Client index
 * @return               Teammate client index (0 if none)
 */
native int MGE_GetPlayerTeammate(int client);

/**
 * Gets the score for a specific slot in an arena
 *
 * @param arena_index    Arena index
 * @param slot           Slot number (SLOT_ONE, SLOT_TWO, etc.)
 * @return               Score for the slot (0 if invalid)
 */
native int MGE_GetArenaScore(int arena_index, int slot);

/**
 * Gets a player's slot in their current arena
 *
 * @param client         Client index
 * @return               Slot number (SLOT_ONE, SLOT_TWO, etc., 0 if not in arena)
 */
native int MGE_GetPlayerSlot(int client);

/**
 * Checks if an arena supports a specific game mode
 *
 * @param arena_index    Arena index
 * @param game_mode      Game mode flag to check (MGE_GAMEMODE_*)
 * @return               True if arena supports the mode, false otherwise
 */
native bool MGE_ArenaHasGameMode(int arena_index, int game_mode);

/**
 * Checks if a slot is valid for the given arena type
 *
 * @param arena_index    Arena index
 * @param slot           Slot to validate (1-4)
 * @return               True if slot is valid for arena, false otherwise
 */
native bool MGE_IsValidSlotForArena(int arena_index, int slot);


public SharedPlugin __pl_mge = 
{
    name = "mge",
    file = "mge.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mge_SetNTVOptional()
{
    MarkNativeAsOptional("MGE_GetPlayerArena");
    MarkNativeAsOptional("MGE_GetPlayerStats");
    MarkNativeAsOptional("MGE_GetArenaInfo");
    MarkNativeAsOptional("MGE_IsPlayerInArena");
    MarkNativeAsOptional("MGE_GetArenaCount");
    MarkNativeAsOptional("MGE_GetArenaPlayer");
    MarkNativeAsOptional("MGE_IsValidArena");
    MarkNativeAsOptional("MGE_GetArenaStatus");
    MarkNativeAsOptional("MGE_AddPlayerToArena");
    MarkNativeAsOptional("MGE_RemovePlayerFromArena");
    MarkNativeAsOptional("MGE_IsPlayerReady");
    MarkNativeAsOptional("MGE_SetPlayerReady");
    MarkNativeAsOptional("MGE_GetPlayerTeammate");
    MarkNativeAsOptional("MGE_ArenaHasGameMode");
    MarkNativeAsOptional("MGE_IsValidSlotForArena");
    MarkNativeAsOptional("MGE_GetPlayerMatchupRating");
}
#endif
