// For neutral cap points
#define NEUTRAL 1

// Sounds
#define DEFAULT_COUNTDOWN_TIME 3

#define MODEL_POINT             "models/props_gameplay/cap_point_base.mdl"
#define MODEL_BRIEFCASE         "models/flag/briefcase.mdl"
#define MODEL_AMMOPACK          "models/items/ammopack_small.mdl"
#define MODEL_LARGE_AMMOPACK    "models/items/ammopack_large.mdl"

// Database types
enum DatabaseType {
    DB_SQLITE = 0,
    DB_MYSQL = 1,
    DB_POSTGRESQL = 2
}

DatabaseType g_DatabaseType;

bool
    g_bNoStats,
    g_bNoDisplayRating,
    g_bLate;

// HUD Handles
Handle
    hm_HP,
    hm_Score,
    hm_TeammateHP,
    hm_KothTimerBLU,
    hm_KothTimerRED,
    hm_KothCap;

// Cookie Handles
Cookie g_hShowEloCookie;
Cookie g_hShowQueueCookie;

// Global Variables
char g_sMapName[256];

bool g_bBlockFallDamage,
     g_bAutoCvar,
     g_b2v2SkipCountdown,
     g_b2v2Elo,
     g_bClearProjectiles,
     g_bAllowUnverifiedPlayers,
     g_bVipQueuePriority;

int
    g_iDefaultFragLimit,
    g_iAirshotHeight = 80;

// Database
Database g_DB; // Connection to SQL database.
Handle g_hDBReconnectTimer;
Handle g_hTopRatingTimer; // Timer for displaying top online player rating

char g_sDBConfig[256];
int g_iReconnectInterval;

// Global CVar Handles
Convar
    gcvar_fragLimit,
    gcvar_allowedClasses,
    gcvar_blockFallDamage,
    gcvar_dbConfig,
    gcvar_midairHP,
    gcvar_airshotHeight,
    gcvar_RocketForceX,
    gcvar_RocketForceY,
    gcvar_RocketForceZ,
    gcvar_autoCvar,
    gcvar_bballParticle_red,
    gcvar_bballParticle_blue,
    gcvar_noDisplayRating,
    gcvar_stats,
    gcvar_reconnectInterval,
    gcvar_2v2SkipCountdown,
    gcvar_2v2Elo,
    gcvar_clearProjectiles,
    gcvar_allowUnverifiedPlayers,
    gcvar_vipQueuePriority,
    g_cvarPlayArenaSound;

// Classes
bool g_tfctClassAllowed[10];

// Arena Vars
Handle g_tKothTimer         [MAXARENAS + 1];
char
    g_sArenaName            [MAXARENAS + 1][64],
    // From chillymge
    g_sArenaOriginalName    [MAXARENAS + 1][64],
    // Cap point trggier name for KOTH
    g_sArenaCapTrigger      [MAXARENAS + 1][64],
    // Cap point name for KOTH
    g_sArenaCap             [MAXARENAS + 1][64];

float
    g_fArenaSpawnOrigin     [MAXARENAS + 1][MAXSPAWNS+1][3],
    g_fArenaSpawnAngles     [MAXARENAS + 1][MAXSPAWNS+1][3],
    g_fArenaHPRatio         [MAXARENAS + 1],
    g_fArenaMinSpawnDist    [MAXARENAS + 1],
    g_fArenaRespawnTime     [MAXARENAS + 1],
    g_fKothCappedPercent    [MAXARENAS + 1],
    g_fTotalTime            [MAXARENAS + 1],
    g_fCappedTime           [MAXARENAS + 1];

bool
    g_bArenaAmmomod         [MAXARENAS + 1],
    g_bArenaMidair          [MAXARENAS + 1],
    g_bArenaMGE             [MAXARENAS + 1],
    g_bArenaEndif           [MAXARENAS + 1],
    g_bArenaBBall           [MAXARENAS + 1],
    g_bVisibleHoops         [MAXARENAS + 1],
    g_bArenaInfAmmo         [MAXARENAS + 1],
    g_bFourPersonArena      [MAXARENAS + 1],
    g_bArenaAllowChange     [MAXARENAS + 1],
    g_bArenaAllowKoth       [MAXARENAS + 1],
    g_bArenaKothTeamSpawn   [MAXARENAS + 1],
    g_bArenaShowHPToPlayers [MAXARENAS + 1],
    g_bArenaUltiduo         [MAXARENAS + 1],
    g_bArenaKoth            [MAXARENAS + 1],
    g_bPlayerTouchPoint     [MAXARENAS + 1][5],
    g_bArenaTurris          [MAXARENAS + 1],
    g_bOvertimePlayed       [MAXARENAS + 1][4],
    g_bTimerRunning         [MAXARENAS + 1],
    g_bArenaHasCap          [MAXARENAS + 1],
    g_bArenaHasCapTrigger   [MAXARENAS + 1],
    g_bArenaBoostVectors    [MAXARENAS + 1],
    g_bArenaClassChange     [MAXARENAS + 1];

int
    g_iArenaCount,
    g_iArenaAirshotHeight   [MAXARENAS + 1],
    g_iCappingTeam          [MAXARENAS + 1],
    g_iCapturePoint         [MAXARENAS + 1],
    g_iDefaultCapTime       [MAXARENAS + 1],
    g_iArenaDuelStartTime   [MAXARENAS + 1],  // Unix timestamp when duel started
    //                      [what arena is the cap point in][Team Red or Team Blu Time left]
    g_iKothTimer            [MAXARENAS + 1][4],
    // 1 = neutral, 2 = RED, 3 = BLU
    g_iPointState           [MAXARENAS + 1],
    g_iArenaScore           [MAXARENAS + 1][3],
    g_iArenaQueue           [MAXARENAS + 1][MAXPLAYERS + 1],
    g_iArenaStatus          [MAXARENAS + 1],
    // Countdown to round start
    g_iArenaCd              [MAXARENAS + 1],
    g_iArenaFraglimit       [MAXARENAS + 1],
    g_iArenaMgelimit        [MAXARENAS + 1],
    g_iArenaCaplimit        [MAXARENAS + 1],
    g_iArenaMinRating       [MAXARENAS + 1],
    g_iArenaMaxRating       [MAXARENAS + 1],
    g_iArenaCdTime          [MAXARENAS + 1],
    g_iArenaSpawns          [MAXARENAS + 1],
    //                      [What arena the hoop is in][Hoop 1 or Hoop 2]
    g_iBBallHoop            [MAXARENAS + 1][3],
    g_iBBallIntel           [MAXARENAS + 1],
    g_iArenaEarlyLeave      [MAXARENAS + 1],
    g_iPublicInviteArena    [MAXARENAS + 1],
    g_iTopPlayersPage       [MAXPLAYERS + 1],
    g_iTopPlayersTotalPages [MAXPLAYERS + 1],
    // Player rank data storage
    g_iPlayerRatingRank     [MAXPLAYERS + 1],
    g_iPlayerWinsRank       [MAXPLAYERS + 1],
    g_iPlayerLossesRank     [MAXPLAYERS + 1],
    // Target client for rank panel display
    g_iRankTargetClient     [MAXPLAYERS + 1];
    
float g_fPublicInviteTime   [MAXARENAS + 1];

bool g_tfctArenaAllowedClasses[MAXARENAS + 1][10];

// Player vars
char g_sPlayerSteamID       [MAXPLAYERS + 1][32]; // Saving steamid

bool
    g_bPlayerTakenDirectHit [MAXPLAYERS + 1],// Player was hit directly
    g_bPlayerRestoringAmmo  [MAXPLAYERS + 1],// Player is awaiting full ammo restore
    g_bPlayerHasIntel       [MAXPLAYERS + 1],
    g_bShowHud              [MAXPLAYERS + 1] = { true, ... },
    g_bShowElo              [MAXPLAYERS + 1] = { true, ... },
    g_bShowQueue            [MAXPLAYERS + 1] = { true, ... }, // Show queue in keyhint (default: enabled)
    g_iPlayerWaiting        [MAXPLAYERS + 1],
    g_bCanPlayerSwap        [MAXPLAYERS + 1],
    g_bCanPlayerGetIntel    [MAXPLAYERS + 1],
    g_bPlayerEloVerified    [MAXPLAYERS + 1]; // ELO loaded from authenticated Steam account

int
    g_iPlayerArena          [MAXPLAYERS + 1],
    g_iPlayerSlot           [MAXPLAYERS + 1],
    g_iPlayerHP             [MAXPLAYERS + 1], // True HP of players
    g_iPlayerSpecTarget     [MAXPLAYERS + 1],
    g_iPlayerMaxHP          [MAXPLAYERS + 1],
    g_iClientParticle       [MAXPLAYERS + 1],
    g_iPlayerClip           [MAXPLAYERS + 1][3],
    g_iPlayerWins           [MAXPLAYERS + 1],
    g_iPlayerLosses         [MAXPLAYERS + 1],
    g_iPlayerRating         [MAXPLAYERS + 1],
    g_iPlayerHandicap       [MAXPLAYERS + 1],
    // Matchup rating: g_iPlayerClassRating[player][myClass][opponentClass] (9x9 matrix)
    g_iPlayerClassRating    [MAXPLAYERS + 1][10][10],
    g_iPlayerClassPoints    [MAXPLAYERS + 1][10];
    
// Track matchup interactions during a duel: [player][myClass][opponentClass] = count
int g_iPlayerMatchupCount   [MAXPLAYERS + 1][10][10];

// Pending arena context used when presenting menus without committing to arena changes yet
int g_iPendingArena[MAXPLAYERS + 1];

TFClassType g_tfctPlayerClass[MAXPLAYERS + 1];

// 2v2 System Variables
bool g_bPlayer2v2Ready[MAXPLAYERS + 1];  // Player ready status for 2v2 matches

// Class tracking for duels
TFClassType g_tfctPlayerDuelClass[MAXPLAYERS + 1];

// Track all classes used during a duel (for arenas with class changes allowed)
ArrayList g_alPlayerDuelClasses[MAXPLAYERS + 1];

// Bot things
bool g_bPlayerAskedForBot[MAXPLAYERS + 1];

// Invite system variables
int g_iPlayerInviteFrom[MAXPLAYERS + 1];    // Who invited this player (0 = no invite)
int g_iPlayerInviteTo[MAXPLAYERS + 1];      // Who this player invited (0 = no outgoing invite)
float g_fPlayerInviteTime[MAXPLAYERS + 1]; // When invite was sent (for timeout)
int g_iPlayerInviteArena[MAXPLAYERS + 1];  // Arena index stored at invite time

// Command cooldowns
float g_fPlayerAddCooldown[MAXPLAYERS + 1]; // Last time player used 'add' command

// Wadd system (waiting list for arenas)
ArrayList g_alArenaWaitingList[MAXARENAS + 1]; // Players waiting for arenas to become available
bool g_bPlayArenaSound; // Whether to play sound when player auto-joins arena
bool g_bPlayerAddedViaWadd[MAXPLAYERS + 1]; // Track if player was added via wadd command

// Midair
int g_iMidairHP;

// Debug log
char g_sLogFile[PLATFORM_MAX_PATH];

// Endif
float
    g_fRocketForceX,
    g_fRocketForceY,
    g_fRocketForceZ;

// Bball
char
    g_sBBallParticleRed[64],
    g_sBBallParticleBlue[64];

char stockSounds[][] =  // Sounds that do not need to be downloaded.
{
    "vo/intel_teamcaptured.mp3",
    "vo/intel_teamdropped.mp3",
    "vo/intel_teamstolen.mp3",
    "vo/intel_enemycaptured.mp3",
    "vo/intel_enemydropped.mp3",
    "vo/intel_enemystolen.mp3",
    "vo/announcer_ends_5sec.mp3",
    "vo/announcer_ends_4sec.mp3",
    "vo/announcer_ends_3sec.mp3",
    "vo/announcer_ends_2sec.mp3",
    "vo/announcer_ends_1sec.mp3",
    "vo/announcer_ends_10sec.mp3",
    "vo/announcer_control_point_warning.mp3",
    "vo/announcer_control_point_warning2.mp3",
    "vo/announcer_control_point_warning3.mp3",
    "vo/announcer_overtime.mp3",
    "vo/announcer_overtime2.mp3",
    "vo/announcer_overtime3.mp3",
    "vo/announcer_overtime4.mp3",
    "vo/announcer_we_captured_control.mp3",
    "vo/announcer_we_lost_control.mp3",
    "vo/announcer_victory.mp3",
    "vo/announcer_you_failed.mp3",
    "items/spawn_item.wav",
    "mentionalert.mp3"
};

GlobalForward g_hOnPlayerArenaAdd;
GlobalForward g_hOnPlayerArenaAdded;
GlobalForward g_hOnPlayerArenaRemove;
GlobalForward g_hOnPlayerArenaRemoved;
GlobalForward g_hOn1v1MatchStart;
GlobalForward g_hOn1v1MatchEnd;
GlobalForward g_hOn2v2MatchStart;
GlobalForward g_hOnDuelStart;
GlobalForward g_hOn2v2MatchEnd;
GlobalForward g_hOnArenaPlayerDeath;
GlobalForward g_hOnPlayerELOChange;
GlobalForward g_hOn2v2ReadyStart;
GlobalForward g_hOn2v2PlayerReady;
GlobalForward g_hOnPlayerScorePoint;
GlobalForward g_hOnPlayerScoredPoint;
GlobalForward g_hOnMatchELOCalculation;
GlobalForward g_hOnMatch2v2ELOCalculation;