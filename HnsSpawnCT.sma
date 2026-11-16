#include <amxmodx>
#include <reapi>
#include <fakemeta>

new g_iCountSpawns
new Float: g_flSpawnsOrigin[32][3]

new g_iCurrentSpawn[MAX_PLAYERS + 1]

new Float: g_flSize[][3] =
{
	{0.0, 0.0, 1.0}, {0.0, 0.0, -1.0}, {0.0, 1.0, 0.0}, {0.0, -1.0, 0.0}, {1.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}, {-1.0, 1.0, 1.0}, {1.0, 1.0, 1.0}, {1.0, -1.0, 1.0}, {1.0, 1.0, -1.0}, {-1.0, -1.0, 1.0}, {1.0, -1.0, -1.0}, {-1.0, 1.0, -1.0}, {-1.0, -1.0, -1.0},
	{0.0, 0.0, 2.0}, {0.0, 0.0, -2.0}, {0.0, 2.0, 0.0}, {0.0, -2.0, 0.0}, {2.0, 0.0, 0.0}, {-2.0, 0.0, 0.0}, {-2.0, 2.0, 2.0}, {2.0, 2.0, 2.0}, {2.0, -2.0, 2.0}, {2.0, 2.0, -2.0}, {-2.0, -2.0, 2.0}, {2.0, -2.0, -2.0}, {-2.0, 2.0, -2.0}, {-2.0, -2.0, -2.0}
}

public plugin_init()
{
    register_plugin("HNS: Spawn Teleporter", "1.0", "OpenHNS") // loncu    

    static iEntity
    while ((iEntity = rg_find_ent_by_class(iEntity, "info_player_start")))
    {
        get_entvar(iEntity, var_origin, g_flSpawnsOrigin[g_iCountSpawns])

        g_iCountSpawns++
    }

    RegisterHookChain(RG_CBasePlayer_UseEmpty, "CBasePlayer_UseEmpty", true)
    RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn", true)
}

public CBasePlayer_UseEmpty(const pPlayer)
{
    if (!get_member_game(m_bFreezePeriod) || get_member(pPlayer, m_iTeam) != TEAM_CT)
        return

    if (++g_iCurrentSpawn[pPlayer] >= g_iCountSpawns)
        g_iCurrentSpawn[pPlayer] = 0

    set_entvar(pPlayer, var_origin, g_flSpawnsOrigin[g_iCurrentSpawn[pPlayer]])

    for (new iDHUD = 0; iDHUD < 8; iDHUD++)
        show_dhudmessage(0, "")

    set_dhudmessage(100, 100, 100, -1.0, 0.899999, 0, 0.0, 1.6, 0.0, 0.2)
    show_dhudmessage(pPlayer, "[#%d] spawn", g_iCurrentSpawn[pPlayer] + 1)

    checkForStuck(pPlayer)
}

public checkForStuck(const pPlayer)
{
    static iHull

    static Float: flOrigin[3]
    static Float: flMins[3]
    static Float: flVector[3]

    get_entvar(pPlayer, var_origin, flOrigin)

    iHull = get_entvar(pPlayer, var_flags) & FL_DUCKING ? HULL_HEAD : HULL_HUMAN

    if (isHullVacant(flOrigin, iHull, pPlayer) || get_entvar(pPlayer, var_movetype) == MOVETYPE_NOCLIP || ~get_entvar(pPlayer, var_solid) & SOLID_NOT)
        return

    get_entvar(pPlayer, var_mins, flMins)
    flVector[2] = flOrigin[2]

    for (new i = 0; i < sizeof(g_flSize); i++)
    {
        for (new j = 0; j < 3; j++)
            flVector[j] = flOrigin[j] - flMins[j] * g_flSize[i][j]

        if (isHullVacant(flVector, iHull, pPlayer))
        {
            set_entvar(pPlayer, var_origin, flVector)

            set_entvar(pPlayer, var_velocity, Float: {0.0, 0.0, 0.0})
        }
    }
}

stock bool: isHullVacant(const Float: flOrigin[3], const iHull, const pPlayer)
{
	static iTraceResult
	engfunc(EngFunc_TraceHull, flOrigin, flOrigin, 0, iHull, pPlayer, iTraceResult)

	return !get_tr2(iTraceResult, TR_StartSolid) || !get_tr2(iTraceResult, TR_AllSolid)
}

public CBasePlayer_Spawn(const pPlayer)
    g_iCurrentSpawn[pPlayer] = 0