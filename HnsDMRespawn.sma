#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hns_matchsystem>

// TODO: Добавить возможность отключать все

#define TASK_UNGHOST_BASE 12832

new bool:g_bHasRespawnOrigin[MAX_PLAYERS + 1];
new Float:g_flRespawnOrigin[MAX_PLAYERS + 1][3];
new bool:g_bTtGhost[MAX_PLAYERS + 1];
new bool:g_bFallDeath[MAX_PLAYERS + 1];

new g_pCvarTpDeathPos;
new g_pCvarTtGhostTime;
new g_pCvarTtGhostAlpha;

new const Float:g_flSearchRadius[] = {16.0, 32.0, 48.0, 64.0, 80.0, 96.0, 128.0};
new const Float:g_flSearchHeight[] = {0.0, 18.0, -18.0, 36.0, -36.0, 54.0};

public plugin_init() {
	register_plugin("HNS: DM respawn + TT ghost", "2.0", "OpenHNS");

	g_pCvarTpDeathPos = register_cvar("hns_dmresp_ct_deathtp", "1");
	g_pCvarTtGhostTime = register_cvar("hns_dmresp_tt_time", "2.0");
	g_pCvarTtGhostAlpha = register_cvar("hns_dmresp_tt_alpha", "120");

	RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", true);
	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", true);
	RegisterHookChain(RG_CSGameRules_FlPlayerFallDamage, "CSGameRules_FlPlayerFallDamage_Post", true);
	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Post", true);
}

public client_disconnected(id) {
	remove_task(TASK_UNGHOST_BASE + id);
	g_bHasRespawnOrigin[id] = false;
	g_bTtGhost[id] = false;
	g_bFallDeath[id] = false;
}

public CSGameRules_RestartRound_Post() {
	new bool:bDmMode = is_dm_mode();

	for (new id = 1; id <= MaxClients; id++) {
		remove_task(TASK_UNGHOST_BASE + id);
		g_bHasRespawnOrigin[id] = false;
		g_bFallDeath[id] = false;

		if (bDmMode && g_bTtGhost[id]) {
			clear_tt_ghost_state(id);
		} else {
			g_bTtGhost[id] = false;
		}
	}
}

public CSGameRules_FlPlayerFallDamage_Post(id) {
	if (!is_dm_mode()) {
		return HC_CONTINUE;
	}

	if (id < 1 || id > MaxClients || !is_user_alive(id)) {
		return HC_CONTINUE;
	}

	new Float:flDamage = Float:GetHookChainReturn(ATYPE_FLOAT);
	if (flDamage <= 0.0) {
		g_bFallDeath[id] = false;
		return HC_CONTINUE;
	}

	new Float:flHealth;
	get_entvar(id, var_health, flHealth);
	g_bFallDeath[id] = (flDamage >= flHealth);

	return HC_CONTINUE;
}

public CBasePlayer_Killed_Post(victim, attacker) {
	if (!is_dm_mode()) {
		return HC_CONTINUE;
	}

	if (!is_user_connected(victim)) {
		return HC_CONTINUE;
	}

	new bool:bFallDeath = g_bFallDeath[victim];
	g_bFallDeath[victim] = false;

	new bool:bKilledByPlayer = (
		attacker >= 1
		&& attacker <= MaxClients
		&& attacker != victim
		&& is_user_connected(attacker)
	);

	if (!bFallDeath && bKilledByPlayer) {
		// Save death origin only for player kills; apply when player respawns as CT.
		get_entvar(victim, var_origin, g_flRespawnOrigin[victim]);
		g_bHasRespawnOrigin[victim] = true;
	} else {
		g_bHasRespawnOrigin[victim] = false;
	}

	if (bKilledByPlayer && is_user_alive(attacker) && rg_get_user_team(attacker) == TEAM_TERRORIST) {
		enable_tt_ghost(attacker);
	}

	return HC_CONTINUE;
}

public CBasePlayer_Spawn_Post(id) {
	if (!is_dm_mode() || !is_user_connected(id) || !is_user_alive(id)) {
		return HC_CONTINUE;
	}

	g_bFallDeath[id] = false;

	if (g_bHasRespawnOrigin[id]) {
		if (rg_get_user_team(id) == TEAM_CT && get_pcvar_num(g_pCvarTpDeathPos)) {
			new Float:flTargetOrigin[3];

			if (find_safe_respawn_origin(id, g_flRespawnOrigin[id], flTargetOrigin)) {
				set_entvar(id, var_origin, flTargetOrigin);

				static const Float:flZero[3] = {0.0, 0.0, 0.0};
				set_entvar(id, var_velocity, flZero);
			}
		}

		g_bHasRespawnOrigin[id] = false;
	}

	if (g_bTtGhost[id]) {
		clear_tt_ghost_state(id);
	}

	return HC_CONTINUE;
}

stock bool:is_dm_mode() {
	new HNS_MODES:iMode = hns_get_mode();
	return iMode == MODE_DM || iMode == MODE_DM_1TT;
}

stock enable_tt_ghost(id) {
	g_bTtGhost[id] = true;

	new Float:flAlpha = get_pcvar_float(g_pCvarTtGhostAlpha);
	new Float:flTime = get_pcvar_float(g_pCvarTtGhostTime);

	if (flAlpha < 0.0) {
		flAlpha = 0.0;
	} else if (flAlpha > 255.0) {
		flAlpha = 255.0;
	}

	if (flTime < 0.05) {
		flTime = 0.05;
	}

	new iFlags = get_entvar(id, var_flags);
	set_entvar(id, var_flags, iFlags | FL_GODMODE);
	set_entvar(id, var_takedamage, DAMAGE_NO);
	set_entvar(id, var_rendermode, kRenderTransAlpha);
	set_entvar(id, var_renderamt, flAlpha);

	remove_task(TASK_UNGHOST_BASE + id);
	set_task(flTime, "TaskDisableTTGhost", TASK_UNGHOST_BASE + id);
}

public TaskDisableTTGhost(taskid) {
	new id = taskid - TASK_UNGHOST_BASE;
	clear_tt_ghost_state(id);
}

stock clear_tt_ghost_state(id) {
	if (id < 1 || id > MaxClients) {
		return;
	}

	new bool:bWasGhost = g_bTtGhost[id];
	g_bTtGhost[id] = false;

	if (!bWasGhost) {
		return;
	}

	if (!is_user_connected(id) || !is_user_alive(id)) {
		return;
	}

	new iFlags = get_entvar(id, var_flags);
	set_entvar(id, var_flags, iFlags & ~FL_GODMODE);
	set_entvar(id, var_takedamage, DAMAGE_AIM);
	set_entvar(id, var_rendermode, kRenderNormal);
	set_entvar(id, var_renderamt, 255.0);
}

stock bool:find_safe_respawn_origin(id, const Float:flBaseOrigin[3], Float:flOutOrigin[3]) {
	if (is_position_free_for_player(id, flBaseOrigin)) {
		flOutOrigin[0] = flBaseOrigin[0];
		flOutOrigin[1] = flBaseOrigin[1];
		flOutOrigin[2] = flBaseOrigin[2];
		return true;
	}

	new Float:flCandidate[3];

	for (new iHeight = 0; iHeight < sizeof(g_flSearchHeight); iHeight++) {
		for (new iRadius = 0; iRadius < sizeof(g_flSearchRadius); iRadius++) {
			new Float:flRadius = g_flSearchRadius[iRadius];

			for (new iAngle = 0; iAngle < 360; iAngle += 45) {
				new Float:flYaw = float(iAngle);

				flCandidate[0] = flBaseOrigin[0] + floatcos(flYaw, degrees) * flRadius;
				flCandidate[1] = flBaseOrigin[1] + floatsin(flYaw, degrees) * flRadius;
				flCandidate[2] = flBaseOrigin[2] + g_flSearchHeight[iHeight];

				if (!is_position_free_for_player(id, flCandidate)) {
					continue;
				}

				flOutOrigin[0] = flCandidate[0];
				flOutOrigin[1] = flCandidate[1];
				flOutOrigin[2] = flCandidate[2];
				return true;
			}
		}
	}

	return false;
}

stock bool:is_position_free_for_player(id, const Float:flOrigin[3]) {
	new iTrace = create_tr2();
	new iHull = (get_entvar(id, var_flags) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;

	engfunc(EngFunc_TraceHull, flOrigin, flOrigin, 0, iHull, id, iTrace);

	new bool:bStartSolid = bool:get_tr2(iTrace, TR_StartSolid);
	new bool:bAllSolid = bool:get_tr2(iTrace, TR_AllSolid);
	new Float:flFraction;
	get_tr2(iTrace, TR_flFraction, flFraction);

	free_tr2(iTrace);

	return !bStartSolid && !bAllSolid && flFraction >= 1.0;
}