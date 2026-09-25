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
    int elo;            // Stored rating from the currently active rating engine (mgemod_rating_engine).
                         // Same number the HUD, !rank, and chat use (raw rating, not rating-2*RD).
    int kills;          // Total kills
    int deaths;         // Total deaths  
    int wins;           // Total wins
    int losses;         // Total losses
    float rating;       // Win/Loss ratio
}

// HUD Score Line Context
// Append-only: new fields must be added at the end so existing compiled
// consumers keep reading correct offsets for the fields they know about.
enum struct MGEHudLineInfo
{
    int viewer;          // Client who will see this HUD line
    int player;          // Player whose score/rating this line represents
    int arena_index;     // Arena this line belongs to
    int slot;            // SLOT_ONE..SLOT_FOUR team/player slot for this line
    int score;           // Current score being shown on this line
    int elo;             // Player's current global ELO rating (read-only reference)
    bool isSpectator;    // True if the viewer is spectating/queued rather than actively fighting
    char extraDisplay[32]; // Mutable text placed inside the "(...)" on the HUD line; defaults to the ELO digits, but any plugin (ELO, ranks, streaks, etc.) may rewrite it
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

enum MGEPlayerStatsLoadState
{
    MGE_STATS_NONE = 0,
    MGE_STATS_LOADING,
    MGE_STATS_LOADED,
    MGE_STATS_AUTH_FAILED,
    MGE_STATS_DB_FAILED,
    MGE_STATS_DISABLED
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
 * Called when a 1v1 match ends
 *
 * @param arena_index    Arena index
 * @param winner         Winner client index
 * @param loser          Loser client index
 * @param winner_score   Winner's final score (frags)
 * @param loser_score    Loser's final score (frags)
 */
forward void MGE_On1v1MatchEnd(int arena_index, int winner, int loser, int winner_score, int loser_score);

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
forward void MGE_On2v2MatchEnd(int arena_index, int winning_team, int winning_score, int losing_score, int team1_player1, int team1_player2, int team2_player1, int team2_player2);

/**
 * Called when a player dies in an arena
 *
 * @param victim         Victim client index
 * @param attacker       Attacker client index (0 if none)
 * @param arena_index    Arena index
 */
forward void MGE_OnArenaPlayerDeath(int victim, int attacker, int arena_index);

/**
 * Called when a player's rating changes, regardless of active rating engine.
 * Fires for the winner before the loser - external plugins that pair calls by call
 * order (e.g. per-class ELO trackers) rely on this and it is preserved across engines.
 *
 * @param client         Client index
 * @param old_elo        Previous rating
 * @param new_elo        New rating
 * @param arena_index    Arena where change occurred
 */
forward void MGE_OnPlayerELOChange(int client, int old_elo, int new_elo, int arena_index);

/**
 * Called when a player's rating changes under the Glicko-2 rating engine, carrying the
 * rating deviation (RD) alongside the rating itself. Only fires when mgemod_rating_engine
 * is "glicko2" - MGE_OnPlayerELOChange still fires alongside it for every engine, including
 * this one, for consumers that only care about the plain rating number.
 * Fires for the winner before the loser, same ordering guarantee as MGE_OnPlayerELOChange.
 *
 * @param client         Client index
 * @param old_rating     Previous rating
 * @param new_rating     New rating
 * @param old_rd         Previous rating deviation
 * @param new_rd         New rating deviation
 * @param arena_index    Arena where change occurred
 */
forward void MGE_OnPlayerRatingChange(int client, int old_rating, int new_rating, float old_rd, float new_rd, int arena_index);

/**
 * Called when a player's statistics loading state changes
 *
 * @param client         Client index
 * @param old_state      Previous MGEPlayerStatsLoadState value
 * @param new_state      New MGEPlayerStatsLoadState value
 */
forward void MGE_OnPlayerStatsLoadStateChanged(int client, MGEPlayerStatsLoadState old_state, MGEPlayerStatsLoadState new_state);

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
 * Called when arena team scores change or are reset
 *
 * @param arena_index    Arena index
 * @param red_score      Red team score (SLOT_ONE)
 * @param blu_score      Blue team score (SLOT_TWO)
 */
forward void MGE_OnArenaScoreChange(int arena_index, int red_score, int blu_score);

/**
 * Called whenever an arena's status changes, regardless of cause (countdown, fight start/end,
 * a player leaving mid-match, timeout, etc.)
 *
 * @param arena_index    Arena index
 * @param old_status     Previous status (AS_* constant)
 * @param new_status     New status (AS_* constant)
 */
forward void MGE_OnArenaStatusChange(int arena_index, int old_status, int new_status);

/**
 * Called once per HUD score report, after both score lines' context has been
 * built and before their text is rendered. lines[0] is the red/SLOT_ONE line,
 * lines[1] is the blu/SLOT_TWO line (2v2 team lines still carry only one
 * representative player, same as what's shown in the parentheses today).
 * External plugins may rewrite lines[i].extraDisplay in place (e.g.
 * "1500/1610", or any other per-line text: ranks, streaks, badges, etc.)
 * without needing to parse HUD text. Multiple plugins can chain off this
 * same forward - each one should read the current extraDisplay and
 * append/rewrite it, rather than assuming it starts empty. extraDisplay
 * text only ends up on screen for a given line if that line would
 * otherwise show an ELO value (stats loaded, not a bot, ELO display
 * enabled) - the forward still fires every time so plugins always see
 * the full report context.
 *
 * @param arena_index    Arena whose score report is being shown
 * @param client         Client who will receive the HUD text
 * @param is_spectator   True if the client is spectating (or queued), false if actively fighting
 * @param redLine        Mutable HUD line context for the red/SLOT_ONE line
 * @param bluLine        Mutable HUD line context for the blu/SLOT_TWO line
 */
forward void MGE_OnFormatHudLines(int arena_index, int client, bool is_spectator, MGEHudLineInfo redLine, MGEHudLineInfo bluLine);

/**
 * Called when a map config file is missing
 * Return Plugin_Handled to suppress SetFailState (e.g. to download the config asynchronously)
 * Return Plugin_Continue to allow normal SetFailState behavior
 *
 * @param mapName        Current map name (workshop-normalized)
 * @param configPath     Full absolute path where the config should be written
 * @return               Plugin_Handled to suppress SetFailState, Plugin_Continue otherwise
 */
forward Action MGE_OnMapConfigMissing(const char[] mapName, const char[] configPath);

/**
 * Called when a map config file exists but fails to parse or contains no valid arenas.
 * Return Plugin_Handled to suppress SetFailState and take over recovery (e.g. delete and redownload).
 * Return Plugin_Continue to allow normal SetFailState behavior.
 * Only fired when a config file is present but unparseable — missing files use MGE_OnMapConfigMissing.
 *
 * @param mapName        Current map name (workshop-normalized)
 * @param configPath     Full absolute path to the invalid config file
 * @return               Plugin_Handled to suppress SetFailState, Plugin_Continue otherwise
 */
forward Action MGE_OnMapConfigInvalid(const char[] mapName, const char[] configPath);

/**
 * Called when an arena's effective whitelist.tf id changes.
 * Fires when a plugin sets or clears a whitelist override. The cfg default
 * does not fire this; read MGE_GetArenaWhitelist after map load instead.
 *
 * @param arena_index    Arena index
 */
forward void MGE_OnArenaWhitelistChanged(int arena_index);

/**
 * Reports that a previously deferred config download has failed and no config is available.
 * MGEMod will disable itself on the next game frame.
 * Only has effect after Plugin_Handled was returned from MGE_OnMapConfigMissing.
 * Call this from your async download completion handler on failure.
 */
native void MGE_ReportConfigUnavailable();

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
native bool MGE_GetPlayerStats(int client, any[] stats);

/**
 * Gets a player's statistics loading state
 *
 * @param client         Client index
 * @return               Current MGEPlayerStatsLoadState value
 */
native MGEPlayerStatsLoadState MGE_GetPlayerStatsLoadState(int client);

/**
 * Gets complete arena information
 *
 * @param arena_index    Arena index
 * @param info           Structure to store arena information in
 * @return               True on success, false if arena is invalid
 */
native bool MGE_GetArenaInfo(int arena_index, any[] info);

/**
 * Checks if a player currently occupies an active arena slot - either
 * waiting to play (e.g. alone in the arena, or during countdown) or
 * actively playing. Players queued behind the active slots (spectating
 * while waiting for their turn) are NOT considered to be "in arena".
 *
 * @param client         Client index
 * @return               True if occupying an active slot, false otherwise
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

/**
 * Gets the current score for an arena team
 *
 * @param arena_index    Arena index
 * @param team_slot      Team slot (SLOT_ONE = red, SLOT_TWO = blue)
 * @return               Team score, or 0 if arena or slot is invalid
 */
native int MGE_GetArenaScore(int arena_index, int team_slot);

/**
 * Gets the effective whitelist.tf id for an arena.
 * Override wins over the arena cfg. An empty id means no whitelist.
 *
 * @param arena_index    Arena index
 * @param id             Buffer for the whitelist.tf id or slug
 * @param maxlength      Size of id
 * @param overridden     Set to true if a plugin override is active
 */
native void MGE_GetArenaWhitelist(int arena_index, char[] id, int maxlength, bool &overridden);

/**
 * Sets a whitelist.tf id that replaces the arena cfg until cleared.
 * An empty id is rejected.
 *
 * @param arena_index    Arena index
 * @param id             whitelist.tf numeric id or slug
 * @return               True on success
 * @error                Invalid arena, or empty id
 */
native bool MGE_SetArenaWhitelistOverride(int arena_index, const char[] id);

/**
 * Clears a whitelist override so the arena cfg id applies again.
 *
 * @param arena_index    Arena index
 * @return               True on success
 * @error                Invalid arena
 */
native bool MGE_ClearArenaWhitelistOverride(int arena_index);


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
    MarkNativeAsOptional("MGE_GetPlayerStatsLoadState");
    MarkNativeAsOptional("MGE_GetArenaInfo");
    MarkNativeAsOptional("MGE_IsPlayerInArena");
    MarkNativeAsOptional("MGE_GetArenaCount");
    MarkNativeAsOptional("MGE_GetArenaPlayer");
    MarkNativeAsOptional("MGE_IsValidArena");
    MarkNativeAsOptional("MGE_AddPlayerToArena");
    MarkNativeAsOptional("MGE_RemovePlayerFromArena");
    MarkNativeAsOptional("MGE_IsPlayerReady");
    MarkNativeAsOptional("MGE_SetPlayerReady");
    MarkNativeAsOptional("MGE_GetPlayerTeammate");
    MarkNativeAsOptional("MGE_ArenaHasGameMode");
    MarkNativeAsOptional("MGE_IsValidSlotForArena");
    MarkNativeAsOptional("MGE_GetArenaScore");
    MarkNativeAsOptional("MGE_GetArenaWhitelist");
    MarkNativeAsOptional("MGE_SetArenaWhitelistOverride");
    MarkNativeAsOptional("MGE_ClearArenaWhitelistOverride");
}
#endif
