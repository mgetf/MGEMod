// For neutral cap points
#define NEUTRAL 1

// Sounds
#define DEFAULT_COUNTDOWN_TIME 3

#define MAX_ELO_FAST_RETRIES    5
#define ELO_RETRY_BASE_DELAY    3.0
#define ELO_RETRY_SLOW_INTERVAL 60.0
#define DEFAULT_STARTING_ELO    1600

// Used by ExecuteMatchResultQueries() (mge/sql.sp) to bundle a match's duel-log insert and all
// participants' stats updates into a single atomic Transaction. Declared here (included before
// the rating engines and sql.sp) since #define is a preprocessor construct and must appear
// textually before any file that uses it, unlike function symbols.
#define MATCH_TXN_MAX_QUERIES 8
#define MATCH_TXN_MAX_RETRIES 5
#define MATCH_TXN_QUERY_LEN 2048
#define GLICKO2_MAX_PERIOD_GAMES 512
#define GLICKO_PERIOD_LOCK_NAME "mgemod_period_close"

#define MODEL_POINT             "models/props_gameplay/cap_point_base.mdl"
#define MODEL_BRIEFCASE         "models/flag/briefcase.mdl"
#define MODEL_AMMOPACK          "models/items/ammopack_small.mdl"
#define MODEL_LARGE_AMMOPACK    "models/items/ammopack_large.mdl"

#define ITEM_DEFINDEX_COW_MANGLER       441
#define ITEM_DEFINDEX_BEGGARS_BAZOOKA   730
#define BEGGARS_BAZOOKA_RESERVE_AMMO    20

// Database types
enum DatabaseType {
    DB_SQLITE = 0,
    DB_MYSQL = 1,
    DB_POSTGRESQL = 2
}

DatabaseType g_DatabaseType;

// Rating engines
enum RatingEngine {
    RATING_ENGINE_ELO = 0,
    RATING_ENGINE_GLICKO2 = 1
}

RatingEngine g_eRatingEngine;
float g_fGlickoTau;
float g_fGlickoPeriodDays;
float g_fGlickoProvisionalRd;
float g_fGlickoRankedRd;
int g_iGlickoRankedMinGames;
int g_iGlickoPeriodHours;
int g_iGlickoPeriodHour;
int g_iGlickoPeriodMinute;
int g_iGlickoPeriodUtcOffset;
bool g_bGlickoPeriodCloseEnabled;
bool g_bGlickoPeriodSchemaReady;
bool g_bGlickoPeriodCloseRunning;
bool g_bGlickoPeriodLockHeld;
int g_iGlickoLastSealedPeriodId;
Handle g_hGlickoPeriodTimer;

#define GLICKO2_SCALE               173.7178
#define GLICKO2_MAX_RD              350.0
#define GLICKO2_DEFAULT_VOLATILITY  0.06
#define GLICKO2_CONVERGENCE_EPSILON 0.000001
#define GLICKO2_E                   2.718281828459045
#define GLICKO2_PI                  3.14159265358979323846

bool
    g_bNoStats,
    g_bSuppressEloUpdates,
    g_bNoDisplayRating,
    g_bLate,
    g_bDeferred;

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

// Global Variables
char g_sMapName[256];

bool g_bBlockFallDamage,
     g_bAutoCvar,
     g_b2v2SkipCountdown,
     g_b2v2Elo,
     g_bClearProjectiles;

int
    g_iDefaultFragLimit,
    g_iAirshotHeight = 80;

// Database
Database g_DB; // Connection to SQL database.
Handle g_hDBReconnectTimer;

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
    gcvar_ratingEngine,
    gcvar_glickoTau,
    gcvar_glickoPeriodDays,
    gcvar_glickoProvisionalRd,
    gcvar_glickoRankedRd,
    gcvar_glickoRankedMinGames,
    gcvar_glickoPeriodHours,
    gcvar_glickoPeriodHour,
    gcvar_glickoPeriodMinute,
    gcvar_glickoPeriodUtcOffset,
    gcvar_glickoPeriodClose;

// Classes
bool g_tfctClassAllowed[10];

// Arena Vars
Handle g_tKothTimer         [MAXARENAS + 1];
char
    g_sArenaName            [MAXARENAS + 1][64],
    g_sArenaOriginalName    [MAXARENAS + 1][64],
    g_sArenaWhitelistId     [MAXARENAS + 1][64],
    g_sArenaWhitelistOverride[MAXARENAS + 1][64];

float
    g_fArenaSpawnOrigin     [MAXARENAS + 1][MAXSPAWNS+1][3],
    g_fArenaSpawnAngles     [MAXARENAS + 1][MAXSPAWNS+1][3],
    g_fBBallHoopPos         [MAXARENAS + 1][3][3],
    g_fBBallIntelPos        [MAXARENAS + 1][3][3],
    g_fKothPointPos         [MAXARENAS + 1][3],
    g_fArenaHPRatio         [MAXARENAS + 1],
    g_fArenaMinSpawnDist    [MAXARENAS + 1],
    g_fArenaRespawnTime     [MAXARENAS + 1],
    g_fKothCappedPercent    [MAXARENAS + 1],
    g_fTotalTime            [MAXARENAS + 1],
    g_fCappedTime           [MAXARENAS + 1],
    g_fKothCapSeconds       [MAXARENAS + 1][4],
    g_fKothUnlockAt         [MAXARENAS + 1],
    g_fKothWaveNeutral      [MAXARENAS + 1][4],
    g_fKothWaveWhenOwner    [MAXARENAS + 1][4][4],
    g_fKothNextWave         [MAXARENAS + 1][4],
    g_fUltiduoMoveUnlockAt  [MAXARENAS + 1];

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
    g_bKothRulesFromMap     [MAXARENAS + 1],
    g_bKothWaveFromMap      [MAXARENAS + 1],
    g_bKothUnlockArmed      [MAXARENAS + 1],
    g_bKothRoundPause       [MAXARENAS + 1],
    g_bKothLoserScream      [MAXPLAYERS + 1],
    g_bKothCanCap           [MAXARENAS + 1][4],
    g_bArenaBoostVectors    [MAXARENAS + 1],
    g_bArenaClassChange     [MAXARENAS + 1],
    g_bArenaWhitelistOverride[MAXARENAS + 1];

int
    g_iArenaCount,
    g_iArenaAirshotHeight   [MAXARENAS + 1],
    g_iCappingTeam          [MAXARENAS + 1],
    g_iCapturePoint         [MAXARENAS + 1],
    g_iDefaultCapTime       [MAXARENAS + 1],
    g_iKothNumCap           [MAXARENAS + 1][4],
    g_iKothStartCap         [MAXARENAS + 1][4],
    g_iKothUnlockSeconds    [MAXARENAS + 1],
    g_iKothMeterDir         [MAXARENAS + 1],
    g_iKothCapSound         [MAXARENAS + 1],
    g_iKothMoveLoop         [MAXARENAS + 1],
    g_iKothBlockLoop        [MAXARENAS + 1],
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
    g_iArenaRedSpawnCount   [MAXARENAS + 1],
    //                      [What arena the hoop is in][Hoop 1 or Hoop 2]
    g_iBBallHoop            [MAXARENAS + 1][3],
    g_iBBallIntel           [MAXARENAS + 1],
    g_iArenaEarlyLeave      [MAXARENAS + 1],
    g_iTopPlayersPage       [MAXPLAYERS + 1],
    g_iTopPlayersTotalPages [MAXPLAYERS + 1],
    // Player rank data storage
    g_iPlayerRatingRank     [MAXPLAYERS + 1],
    g_iPlayerWinsRank       [MAXPLAYERS + 1], 
    g_iPlayerLossesRank     [MAXPLAYERS + 1],
    // Target client for rank panel display
    g_iRankTargetClient     [MAXPLAYERS + 1];

bool g_tfctArenaAllowedClasses[MAXARENAS + 1][10];
TFClassType g_tfctArenaSpawnClass[MAXARENAS + 1][MAXSPAWNS + 1];

// Player vars
char g_sPlayerSteamID       [MAXPLAYERS + 1][32]; // Saving steamid

bool
    g_bPlayerTakenDirectHit [MAXPLAYERS + 1],// Player was hit directly
    g_bPlayerRestoringAmmo  [MAXPLAYERS + 1],// Player is awaiting full ammo restore
    g_bPlayerHasIntel       [MAXPLAYERS + 1],
    g_bShowHud              [MAXPLAYERS + 1] = { true, ... },
    g_bShowElo              [MAXPLAYERS + 1] = { true, ... },
    g_iPlayerWaiting        [MAXPLAYERS + 1],
    g_bCanPlayerSwap        [MAXPLAYERS + 1],
    g_bCanPlayerGetIntel    [MAXPLAYERS + 1],
    g_bEloSlowRetry         [MAXPLAYERS + 1];

Handle g_hEloRetryTimer     [MAXPLAYERS + 1];
float g_fPlayerRespawnAt    [MAXPLAYERS + 1];
int
    g_iEloRetryCount        [MAXPLAYERS + 1],
    g_iPlayerStatsLoadGeneration[MAXPLAYERS + 1];

MGEPlayerStatsLoadState g_ePlayerStatsLoadState[MAXPLAYERS + 1];
MGEPlayerStatsLoadState g_ePlayerStatsRetryFailureState[MAXPLAYERS + 1];

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
    g_iPlayerLastPlayed     [MAXPLAYERS + 1],
    g_iPlayerHandicap       [MAXPLAYERS + 1];

// Glicko-2 rating engine state (only meaningful when mgemod_rating_engine is "glicko2")
bool g_bPlayerGlickoSeeded [MAXPLAYERS + 1];
bool g_bPlayerPeriodDirty  [MAXPLAYERS + 1];
float
    g_fPlayerRD             [MAXPLAYERS + 1],
    g_fPlayerVolatility     [MAXPLAYERS + 1],
    g_fPlayerRDEst          [MAXPLAYERS + 1];
int g_iPlayerRatingEst     [MAXPLAYERS + 1];

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
char g_sPendingBotClass[MAXPLAYERS + 1][16]; // Class requested via !botme, keyed by the requesting client
char g_sBotDesiredClass[MAXPLAYERS + 1][16]; // Class to force once the bot itself is queued into the arena

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
    "vo/announcer_ends_60sec.mp3",
    "vo/announcer_ends_30sec.mp3",
    "vo/announcer_ends_10sec.mp3",
    "vo/announcer_ends_5sec.mp3",
    "vo/announcer_ends_4sec.mp3",
    "vo/announcer_ends_3sec.mp3",
    "vo/announcer_ends_2sec.mp3",
    "vo/announcer_ends_1sec.mp3",
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
    "items/spawn_item.wav"
};

GlobalForward g_hOnPlayerArenaAdd;
GlobalForward g_hOnPlayerArenaAdded;
GlobalForward g_hOnPlayerArenaRemove;
GlobalForward g_hOnPlayerArenaRemoved;
GlobalForward g_hOn1v1MatchStart;
GlobalForward g_hOn1v1MatchEnd;
GlobalForward g_hOn2v2MatchStart;
GlobalForward g_hOn2v2MatchEnd;
GlobalForward g_hOnArenaPlayerDeath;
GlobalForward g_hOnPlayerELOChange;
GlobalForward g_hOnPlayerRatingChange;
GlobalForward g_hOnPlayerStatsLoadStateChanged;
GlobalForward g_hOn2v2ReadyStart;
GlobalForward g_hOn2v2PlayerReady;
GlobalForward g_hOnArenaScoreChange;
GlobalForward g_hOnArenaStatusChange;
GlobalForward g_hOnMapConfigMissing;
GlobalForward g_hOnMapConfigInvalid;
GlobalForward g_hOnFormatHudLines;
GlobalForward g_hOnArenaWhitelistChanged;